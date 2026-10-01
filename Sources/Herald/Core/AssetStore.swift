import Foundation

/// Why an animation asset could not be installed or located. `errorDescription` is written to be shown as is
/// (the Rive component prints it in its placeholder), so it names the file and what to change.
public enum AssetError: Error, Equatable, LocalizedError, Sendable {
    /// The manifest asset's `type` is not "rive".
    case unsupportedType(String)
    /// The file name does not end in `.riv`.
    case notRiveFile(String)
    case empty(String)
    case tooLarge(name: String, bytes: Int, limit: Int)
    case missing(String)
    /// The path exists but is a folder or another kind of non-regular file.
    case notAFile(String)
    /// A relative path that leaves the app's assets folder, a remote URL, or an empty path/id.
    case badPath(String)
    /// A component names an asset that neither the manifest declares nor the store holds.
    case unknownAsset(String)
    /// The component has neither an `asset` nor a `path`.
    case noSource
    case limitReached(Int)
    case copyFailed(String)

    public var errorDescription: String? {
        switch self {
        case .unsupportedType(let t): return "asset type \u{201C}\(t)\u{201D} is not supported (only rive)"
        case .notRiveFile(let n): return "\u{201C}\(n)\u{201D} is not a .riv file"
        case .empty(let n): return "\u{201C}\(n)\u{201D} is empty"
        case .tooLarge(let n, let bytes, let limit):
            return "\u{201C}\(n)\u{201D} is \(Self.size(bytes)); Rive assets are limited to \(Self.size(limit))"
        case .missing(let p): return "file not found: \(p)"
        case .notAFile(let n): return "\u{201C}\(n)\u{201D} is not a regular file"
        case .badPath(let why): return why
        case .unknownAsset(let id): return "asset \u{201C}\(id)\u{201D} is not declared by the manifest and is not installed"
        case .noSource: return "the Rive component has no asset or path"
        case .limitReached(let n): return "an app can have at most \(n) animation assets"
        case .copyFailed(let why): return "could not copy the asset: \(why)"
        }
    }

    private static func size(_ bytes: Int) -> String {
        let mb = Double(bytes) / 1_048_576
        if mb >= 1 { return String(format: mb == mb.rounded() ? "%.0f MB" : "%.1f MB", mb) }
        return String(format: "%.0f KB", Double(bytes) / 1024)
    }
}

/// The outcome of installing one manifest asset (`AssetStore.installAll`).
public struct AssetInstallResult: Equatable, Sendable {
    public var id: String
    /// Where the stored copy is, when the install worked.
    public var url: URL?
    public var error: AssetError?
    public var ok: Bool { url != nil }

    public init(id: String, url: URL? = nil, error: AssetError? = nil) {
        self.id = id; self.url = url; self.error = error
    }
}

/// Animation (`.riv`) files the banners play, kept at `<directory>/<app>/` (normally
/// `~/Library/Application Support/Herald/assets`).
///
/// Two kinds of file live in an app's folder:
///  * copies of the assets an issuer declares in its manifest (`install`, named `<asset id>.riv`), so a
///    banner keeps playing after the issuer moves or deletes its own bundle, and
///  * files the user drops there by hand for a template to reference with a relative `path`.
///
/// A file is accepted when its name ends in `.riv` (any case), it is a regular file (symlinks are followed)
/// and it is between 1 byte and 10 MB. The Rive runtime does the real parsing and its failure is shown in the
/// component's placeholder, so a bad file never reaches a banner as anything but text.
///
/// Like the other stores, ids are mapped to one safe path component (`TemplateStore.component`), so a manifest
/// cannot make Herald write outside its folder, and nothing is cached on disk beyond the copies themselves.
public final class AssetStore: @unchecked Sendable {
    /// 10 MB.
    public static let maxBytes = 10 * 1024 * 1024
    /// Copies installed for one app (hand-dropped files do not count).
    public static let maxAssetsPerApp = 32
    public static let riveExtension = "riv"

    /// The store the app uses: `~/Library/Application Support/Herald/assets`.
    public static let shared = AssetStore(
        directory: HeraldPaths.defaultSupportDirectory.appendingPathComponent("assets", isDirectory: true))

    public let directory: URL
    private let lock = NSLock()

    public init(directory: URL) {
        self.directory = directory
    }

    // MARK: Locations

    /// `<directory>/<app>/`. Not created until something is installed.
    public func folder(for app: String) -> URL {
        directory.appendingPathComponent(TemplateStore.component(app), isDirectory: true)
    }

    /// Where the stored copy of a manifest asset lives, whether or not it has been installed yet.
    public func storedURL(app: String, assetID: String) -> URL {
        folder(for: app).appendingPathComponent(TemplateStore.component(assetID) + "." + Self.riveExtension)
    }

    /// Every `.riv` in the app's folder (copies and hand-dropped files), sorted by name.
    public func list(app: String) -> [URL] {
        riveFiles(in: folder(for: app))
    }

    // MARK: Validation

    /// Throws unless `url` is an existing regular `.riv` file of 1 byte to `maxBytes`; returns its size.
    @discardableResult
    public static func validate(_ url: URL) throws -> Int {
        let resolved = url.resolvingSymlinksInPath()
        let name = resolved.lastPathComponent
        // Both the name given and what a symlink points at must be `.riv`, so a link cannot smuggle in another file.
        guard url.pathExtension.lowercased() == riveExtension, resolved.pathExtension.lowercased() == riveExtension else {
            throw AssetError.notRiveFile(url.lastPathComponent)
        }
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: resolved.path, isDirectory: &isDir) else {
            throw AssetError.missing(url.path)
        }
        guard !isDir.boolValue else { throw AssetError.notAFile(name) }
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: resolved.path),
              (attrs[.type] as? FileAttributeType) == .typeRegular,
              let size = (attrs[.size] as? NSNumber)?.intValue else { throw AssetError.notAFile(name) }
        guard size > 0 else { throw AssetError.empty(name) }
        guard size <= maxBytes else { throw AssetError.tooLarge(name: name, bytes: size, limit: maxBytes) }
        return size
    }

    // MARK: Install

    /// Copies the file a manifest asset points at into the app's folder as `<asset id>.riv` and returns the
    /// copy. `asset.path` is an absolute path, a `~/` path or a `file://` URL; a relative path is looked up in
    /// the app's own folder. Installing again refreshes the copy only when the content changed.
    @discardableResult
    public func install(_ asset: HeraldAsset, app: String) throws -> URL {
        guard asset.type.lowercased() == "rive" else { throw AssetError.unsupportedType(asset.type) }
        guard !asset.id.trimmingCharacters(in: .whitespaces).isEmpty else { throw AssetError.badPath("an asset needs an id") }
        let source = try locate(path: asset.path, app: app)
        let size = try Self.validate(source)
        let dest = storedURL(app: app, assetID: asset.id)

        lock.lock(); defer { lock.unlock() }
        let fm = FileManager.default
        let src = source.resolvingSymlinksInPath()
        // The path already names the stored copy (a hand-edited manifest, or an install repeated from it).
        if src.path == dest.resolvingSymlinksInPath().path { return dest }
        if fm.fileExists(atPath: dest.path), Self.sizeOf(dest) == size, fm.contentsEqual(atPath: src.path, andPath: dest.path) {
            return dest
        }
        if !fm.fileExists(atPath: dest.path), riveFiles(in: folder(for: app)).count >= Self.maxAssetsPerApp {
            throw AssetError.limitReached(Self.maxAssetsPerApp)
        }
        let folder = folder(for: app)
        let temp = folder.appendingPathComponent(".\(UUID().uuidString).tmp")
        do {
            try fm.createDirectory(at: folder, withIntermediateDirectories: true)
            try fm.copyItem(at: src, to: temp)
            // The source may have been swapped for a bigger file between the check and the copy.
            guard let copied = Self.sizeOf(temp), copied > 0, copied <= Self.maxBytes else {
                try? fm.removeItem(at: temp)
                throw AssetError.tooLarge(name: src.lastPathComponent, bytes: Self.sizeOf(temp) ?? 0, limit: Self.maxBytes)
            }
            if fm.fileExists(atPath: dest.path) {
                _ = try fm.replaceItemAt(dest, withItemAt: temp)
            } else {
                try fm.moveItem(at: temp, to: dest)
            }
        } catch let e as AssetError {
            try? fm.removeItem(at: temp)
            throw e
        } catch {
            try? fm.removeItem(at: temp)
            throw AssetError.copyFailed(error.localizedDescription)
        }
        return dest
    }

    /// Installs every asset of `manifest`; one bad asset does not stop the others.
    @discardableResult
    public func installAll(_ manifest: HeraldManifest) -> [AssetInstallResult] {
        manifest.assets.map { asset in
            do { return AssetInstallResult(id: asset.id, url: try install(asset, app: manifest.app)) }
            catch let e as AssetError { return AssetInstallResult(id: asset.id, error: e) }
            catch { return AssetInstallResult(id: asset.id, error: .copyFailed(error.localizedDescription)) }
        }
    }

    // MARK: Resolve

    /// The file a Rive component should play.
    ///
    /// With an `asset` id: the manifest asset of that id is (re)installed, so a changed or new file is picked up,
    /// and the stored copy is returned; when the install fails but an earlier copy is still valid, that copy is
    /// used. Without a `manifest` only a stored copy can answer. With a `path`: the file itself, validated, not
    /// copied (see `locate`).
    public func resolve(_ component: HeraldRiveComponent, app: String, manifest: HeraldManifest?) throws -> URL {
        if let id = component.asset?.trimmingCharacters(in: .whitespacesAndNewlines), !id.isEmpty {
            let stored = storedURL(app: app, assetID: id)
            if let asset = manifest?.assets.first(where: { $0.id == id }) {
                do { return try install(asset, app: app) }
                catch {
                    if (try? Self.validate(stored)) != nil { return stored }
                    throw error
                }
            }
            guard FileManager.default.fileExists(atPath: stored.path) else { throw AssetError.unknownAsset(id) }
            try Self.validate(stored)
            return stored
        }
        if let path = component.path?.trimmingCharacters(in: .whitespacesAndNewlines), !path.isEmpty {
            let url = try locate(path: path, app: app)
            try Self.validate(url)
            return url
        }
        throw AssetError.noSource
    }

    /// Turns a manifest or template path into a file URL. Absolute paths, `~/` paths and `file://` URLs stand
    /// for themselves; any other relative path is read inside the app's assets folder and may not climb out of
    /// it. Remote URLs are refused. Existence and size are checked by `validate`, not here.
    public func locate(path raw: String, app: String) throws -> URL {
        let path = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !path.isEmpty else { throw AssetError.badPath("the asset path is empty") }
        if path.lowercased().hasPrefix("file:") {
            guard let url = URL(string: path), url.isFileURL else { throw AssetError.badPath("not a valid file URL: \(path)") }
            return url
        }
        guard !path.contains("://") else { throw AssetError.badPath("remote assets are not supported: \(path)") }
        if path.hasPrefix("~") { return URL(fileURLWithPath: (path as NSString).expandingTildeInPath) }
        if path.hasPrefix("/") { return URL(fileURLWithPath: path) }
        let parts = path.split(separator: "/", omittingEmptySubsequences: true)
        guard !parts.contains(where: { $0 == ".." }) else {
            throw AssetError.badPath("a relative asset path cannot leave the app's assets folder: \(path)")
        }
        return parts.reduce(folder(for: app)) { $0.appendingPathComponent(String($1)) }
    }

    // MARK: Remove

    /// Deletes the stored copy of one manifest asset. False when there was none.
    @discardableResult
    public func remove(app: String, assetID: String) -> Bool {
        lock.lock(); defer { lock.unlock() }
        return (try? FileManager.default.removeItem(at: storedURL(app: app, assetID: assetID))) != nil
    }

    /// Deletes the stored copies of every asset the manifest declares (hand-dropped files stay). Returns how
    /// many were removed.
    @discardableResult
    public func remove(manifest: HeraldManifest) -> Int {
        manifest.assets.filter { remove(app: manifest.app, assetID: $0.id) }.count
    }

    // MARK: Files

    private func riveFiles(in folder: URL) -> [URL] {
        ((try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? [])
            .filter { $0.pathExtension.lowercased() == Self.riveExtension && !$0.lastPathComponent.hasPrefix(".") }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
    }

    private static func sizeOf(_ url: URL) -> Int? {
        (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? NSNumber)?.intValue
    }
}

// MARK: - Rive input binding (pure)

/// How a Rive component's `inputBindings` turn a notification's fields into state machine input values.
/// Kept free of the Rive runtime so the rules are unit tested; `RiveComponentView` applies the result.
///
/// A binding is the keyword `hover` or `pressed` (driven by the pointer, never by data), a single `{token}`
/// (the field's own value, so a number stays a number) or any other text (`"3"`, `"{count} new"`), which binds
/// as the substituted text.
public enum RiveInputBinding {
    public static let pointerKeywords = HeraldRiveComponent.pointerKeywords

    /// "hover" or "pressed" when the binding is one of the pointer keywords (any case), else nil.
    public static func pointerKeyword(_ binding: String) -> String? {
        let k = binding.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return pointerKeywords.contains(k) ? k : nil
    }

    /// The value `binding` yields from `fields`, or nil when it has tokens and every one is absent or blank (the
    /// input then keeps whatever the animation set).
    public static func value(for binding: String, fields: [String: HeraldFieldValue]) -> HeraldFieldValue? {
        guard pointerKeyword(binding) == nil else { return nil }
        guard let text = TemplateResolver.bind(binding, fields: fields) else { return nil }
        if let token = singleToken(binding), let v = fields[token] { return v }
        return .text(text)
    }

    /// The token name when the whole binding is exactly one `{token}`.
    static func singleToken(_ binding: String) -> String? {
        let s = binding.trimmingCharacters(in: .whitespacesAndNewlines)
        guard s.count > 2, s.hasPrefix("{"), s.hasSuffix("}") else { return nil }
        let name = s.dropFirst().dropLast()
        guard name.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "_" || $0 == "." || $0 == "-" }) else { return nil }
        return String(name)
    }

    /// A number input's value: numbers as they are, booleans as 1/0, text when it parses, a list as its length.
    public static func number(from value: HeraldFieldValue) -> Double? {
        switch value {
        case .number(let d): return d.isFinite ? d : nil
        case .bool(let b): return b ? 1 : 0
        case .text(let s):
            guard let d = Double(s.trimmingCharacters(in: .whitespacesAndNewlines)), d.isFinite else { return nil }
            return d
        case .list(let l): return Double(l.count)
        }
    }

    /// A boolean input's value, and whether a trigger fires: true booleans, non-zero numbers, non-empty lists, and
    /// text other than "", "false", "no", "off" and "0".
    public static func truthy(_ value: HeraldFieldValue) -> Bool {
        switch value {
        case .bool(let b): return b
        case .number(let d): return d != 0
        case .list(let l): return !l.isEmpty
        case .text(let s):
            return !["", "false", "no", "off", "0"].contains(s.trimmingCharacters(in: .whitespacesAndNewlines).lowercased())
        }
    }
}
