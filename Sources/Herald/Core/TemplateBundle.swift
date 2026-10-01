import Foundation

// Template import and export for Herald.app (issue #30): the stores on one side, the `.heraldtemplate` bundle
// (`HeraldTemplateBundle`, shared with the `herald` command line tool) on the other.
//
//   export  finds the Rive files a template plays (the app's stored copy of an asset id, else the issuer's own
//           file named by its manifest; a loose path as the template has it) and packs them with the template.
//   import  unpacks and validates, puts the Rive files into the target app's assets folder without replacing a
//           different file that is already there, and saves the template under a name that is free (or replaces
//           the one with that name when asked).
//
// Everything here is synchronous file work on the caller's thread.

public final class TemplateBundleService: @unchecked Sendable {
    /// What to do when the target app already has a template with the imported name.
    public enum Conflict: Equatable, Sendable {
        /// Save under `name 2`, `name 3`, ... (the default: nothing is lost).
        case keepBoth
        /// Overwrite the existing template.
        case replace
        /// Stop with `BundleError.nameExists`; the caller shows its own prompt and tries again.
        case fail
    }

    /// What an import did.
    public struct ImportResult: Equatable, Sendable {
        /// The template as saved (name possibly changed, animation references possibly rewritten).
        public var template: HeraldTemplate
        /// The name the bundle carried, when the template was saved under another one.
        public var renamedFrom: String?
        /// True when an existing template was overwritten.
        public var replaced: Bool
        public var assets: HeraldTemplateBundle.InstallReport
        public var warnings: [String]
    }

    /// What a bundle holds, for the confirmation before it is imported.
    public struct Preview: Equatable, Sendable {
        public var name: String
        public var app: String
        public var assetFiles: [String]
        /// A template with this name already exists for `app`.
        public var nameTaken: Bool
    }

    public let templates: TemplateStore
    public let assets: AssetStore
    private let manifest: (String) -> HeraldManifest?

    public init(templates: TemplateStore, assets: AssetStore, manifest: @escaping (String) -> HeraldManifest?) {
        self.templates = templates; self.assets = assets; self.manifest = manifest
    }

    // MARK: Export

    /// Packs the saved template `name` of `app`.
    public func export(app: String, name: String) throws -> HeraldTemplateBundle.ExportResult {
        guard let t = templates.get(app: app, name: name) else {
            throw HeraldTemplateBundle.BundleError.notABundle("there is no template \u{201C}\(name)\u{201D} for \(app)")
        }
        return try export(t)
    }

    /// Packs `template` (a draft that is not saved yet works too).
    public func export(_ template: HeraldTemplate) throws -> HeraldTemplateBundle.ExportResult {
        let app = template.app
        let declared = manifest(app)
        return try HeraldTemplateBundle.export(template) { ref in
            switch ref {
            case .asset(let id):
                let stored = self.assets.storedURL(app: app, assetID: id)
                if FileManager.default.fileExists(atPath: stored.path) { return stored }
                guard let a = declared?.assets.first(where: { $0.id == id }) else { return nil }
                return try? self.assets.locate(path: a.path, app: app)
            case .path(let p):
                return try? self.assets.locate(path: p, app: app)
            }
        }
    }

    /// Packs and writes the bundle to `url`. Returns what was packed.
    @discardableResult
    public func export(_ template: HeraldTemplate, to url: URL) throws -> HeraldTemplateBundle.ExportResult {
        let r = try export(template)
        do { try r.data.write(to: url, options: .atomic) }
        catch { throw HeraldTemplateBundle.BundleError.cannotWrite(error.localizedDescription) }
        return r
    }

    // MARK: Import

    /// Reads a bundle far enough to tell the user what is in it, writing nothing. `intoApp` is where it would go.
    public func preview(_ data: Data, intoApp: String? = nil) throws -> Preview {
        let c = try HeraldTemplateBundle.unpack(data)
        let app = Self.target(intoApp, c.template.app)
        return Preview(name: c.template.name, app: app, assetFiles: c.assets.map(\.file),
                       nameTaken: templates.get(app: app, name: c.template.name) != nil)
    }

    /// Imports a bundle. `intoApp` retargets the template to another issuer (its Rive files go to that app's
    /// folder); nil keeps the bundle's own app. `save` writes the finished template (default: the template store;
    /// the app passes its controller's `putTemplate` so open windows refresh).
    @discardableResult
    public func importBundle(_ data: Data, intoApp: String? = nil, onConflict: Conflict = .keepBoth,
                             save: ((HeraldTemplate) throws -> Void)? = nil) throws -> ImportResult {
        var contents = try HeraldTemplateBundle.unpack(data)
        let app = Self.target(intoApp, contents.template.app)
        contents.template.app = app

        let taken = Set(templates.list(app: app).map(\.name))
        let bundled = contents.template.name
        var name = bundled
        var replaced = false
        if taken.contains(name) {
            switch onConflict {
            case .keepBoth: name = HeraldTemplateBundle.uniqueName(bundled, taken: taken)
            case .replace: replaced = true
            case .fail: throw HeraldTemplateBundle.BundleError.nameExists(bundled)
            }
        }

        // Installed only after the name is settled, so a refused import leaves no files behind.
        var (template, report) = try HeraldTemplateBundle.installAssets(contents, into: assets.folder(for: app),
                                                                         maxFiles: AssetStore.maxAssetsPerApp)
        template.name = name
        template.app = app
        if let save { try save(template) }
        else if !templates.put(template) { throw HeraldTemplateBundle.BundleError.cannotWrite("the template file") }

        var warnings: [String] = report.missing.map { "The animation \u{201C}\($0)\u{201D} is not in the bundle and not installed for \(app); the component shows a placeholder." }
        if template.actionRules.contains(where: { $0.add?.kind == .script }) || template.cells.contains(where: Self.hasScript) {
            warnings.append("The template runs script actions; copy the script files into the scripts folder.")
        }
        return ImportResult(template: template, renamedFrom: name == bundled ? nil : bundled, replaced: replaced,
                            assets: report, warnings: warnings)
    }

    private static func target(_ intoApp: String?, _ bundled: String) -> String {
        let t = intoApp?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return t.isEmpty ? bundled : t
    }

    private static func hasScript(_ c: HeraldCell) -> Bool {
        switch c.component {
        case .button(let b): return b.action?.kind == .script
        case .iconButton(let b): return b.action?.kind == .script
        case .rive(let r): return r.action?.kind == .script
        default: return false
        }
    }
}
