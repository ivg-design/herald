import Foundation

// The content half of ParityService: assets, template duplicate / rename / default / export / import, History
// search, re-show, delete and export, and the SF Symbol listing.

extension ParityService {
    // MARK: Assets

    static let imageExtensions: Set<String> = ["png", "jpg", "jpeg", "gif", "webp", "heic", "heif", "tif", "tiff", "bmp", "avif"]

    /// Which image format the bytes are, by signature; nil when they are not an image Herald draws.
    static func imageKind(_ d: Data) -> String? {
        let b = [UInt8](d.prefix(16))
        guard b.count >= 4 else { return nil }
        if b.starts(with: [0x89, 0x50, 0x4E, 0x47]) { return "png" }
        if b.starts(with: [0xFF, 0xD8, 0xFF]) { return "jpeg" }
        if b.starts(with: Array("GIF8".utf8)) { return "gif" }
        if b.starts(with: Array("BM".utf8)) { return "bmp" }
        if b.starts(with: [0x49, 0x49, 0x2A, 0x00]) || b.starts(with: [0x4D, 0x4D, 0x00, 0x2A]) { return "tiff" }
        if b.count >= 12, Array(b[0..<4]) == Array("RIFF".utf8), Array(b[8..<12]) == Array("WEBP".utf8) { return "webp" }
        if b.count >= 12, Array(b[4..<8]) == Array("ftyp".utf8) { return "heic" }
        return nil
    }

    func imagesFolder(_ app: String) -> URL { assets.folder(for: app).appendingPathComponent("images", isDirectory: true) }

    /// A file name that stays inside the folder: one path component, no dots at the start.
    static func safeFileName(_ raw: String) throws -> String {
        let base = (raw as NSString).lastPathComponent
        let cleaned = TemplateStore.component(base)
        guard !cleaned.isEmpty, !cleaned.hasPrefix("."), raw == base else {
            throw BackendError(400, "invalid file name: use a plain name without folders, for example logo.png")
        }
        return cleaned
    }

    func listAssets(_ req: HTTPRequest) throws -> HTTPResponse {
        let app = try requiredQuery(req, "app")
        let users = templates.list(app: app)
        let declared = Set((manifests.get(app: app)?.assets ?? []).filter { $0.type.lowercased() == "rive" }
            .map { HeraldTemplateBundle.safeFile(stem: $0.id).lowercased() })
        var items: [[String: Any]] = []
        for url in assets.list(app: app) {
            let file = url.lastPathComponent
            let usedBy = users.filter { t in
                HeraldTemplateBundle.riveRefs(in: t).contains { HeraldTemplateBundle.fileName(for: $0).lowercased() == file.lowercased() }
            }.map(\.name)
            items.append(["kind": "rive", "id": String(file.dropLast(4)), "file": file, "path": url.path,
                          "bytes": Self.size(of: url), "declared": declared.contains(file.lowercased()), "usedBy": usedBy,
                          "component": ["type": "rive", "path": file]])
        }
        let images = (try? FileManager.default.contentsOfDirectory(at: imagesFolder(app), includingPropertiesForKeys: nil)) ?? []
        for url in images.sorted(by: { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending })
        where Self.imageExtensions.contains(url.pathExtension.lowercased()) {
            items.append(["kind": "image", "file": url.lastPathComponent, "path": url.path, "bytes": Self.size(of: url)])
        }
        return Self.reply(["app": app, "assets": items, "folder": assets.folder(for: app).path,
                           "limits": ["bytes": AssetStore.maxBytes, "riveFiles": AssetStore.maxAssetsPerApp]])
    }

    static func size(of url: URL) -> Int {
        (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? NSNumber)?.intValue ?? 0
    }

    func uploadAsset(_ req: HTTPRequest) throws -> HTTPResponse {
        let o = try body(req)
        let app = try requiredString(o, "app")
        let b64 = try optionalString(o, "base64"), path = try optionalString(o, "path")
        guard (b64 == nil) != (path == nil) else { throw BackendError(400, "give exactly one of base64 (small files, the request body is limited to 1 MB) or path (a file on this Mac)") }
        var name = try optionalString(o, "name")
        var data: Data?
        var source: URL?
        if let b64 {
            guard let d = Data(base64Encoded: b64, options: .ignoreUnknownCharacters), !d.isEmpty else { throw BackendError(400, "invalid field: base64") }
            data = d
            guard name != nil else { throw BackendError(400, "missing field: name (the file name, for example logo.png or confetti.riv)") }
        } else if let path {
            let url = URL(fileURLWithPath: (path as NSString).expandingTildeInPath)
            var isDir: ObjCBool = false
            guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir), !isDir.boolValue else { throw BackendError(400, "no such file: \(path)") }
            source = url
            if name == nil { name = url.lastPathComponent }
        }
        guard let fileName = name else { throw BackendError(400, "missing field: name") }
        let ext = (fileName as NSString).pathExtension.lowercased()
        var kind = try optionalString(o, "kind")
        if kind == nil { kind = ext == AssetStore.riveExtension ? "rive" : (Self.imageExtensions.contains(ext) ? "image" : nil) }
        switch kind {
        case "rive": return try uploadRive(app: app, fileName: fileName, data: data, source: source)
        case "image": return try uploadImage(app: app, fileName: fileName, data: data, source: source)
        case nil: throw BackendError(400, "cannot tell the kind from the name; give kind: rive or image (or a name ending in .riv, .png, .jpg, ...)")
        default: throw BackendError(400, "kind must be rive or image")
        }
    }

    func uploadRive(app: String, fileName: String, data: Data?, source: URL?) throws -> HTTPResponse {
        let safe = try Self.safeFileName(fileName)
        let id = String(HeraldTemplateBundle.safeFile(stem: safe).dropLast(4))
        var temp: URL?
        defer { if let temp { try? FileManager.default.removeItem(at: temp) } }
        let from: URL
        if let data {
            guard data.count <= AssetStore.maxBytes else { throw BackendError(413, "the animation is larger than \(AssetStore.maxBytes / 1_048_576) MB") }
            let t = FileManager.default.temporaryDirectory.appendingPathComponent("herald-upload-\(UUID().uuidString).riv")
            try data.write(to: t)
            temp = t; from = t
        } else if let source { from = source } else { throw BackendError(400, "missing file") }
        let existed = FileManager.default.fileExists(atPath: assets.storedURL(app: app, assetID: id).path)
        do {
            let stored = try assets.install(HeraldAsset(id: id, type: "rive", path: from.path), app: app)
            return Self.reply(["ok": true, "kind": "rive", "app": app, "id": id, "file": stored.lastPathComponent, "path": stored.path,
                               "bytes": Self.size(of: stored), "replaced": existed,
                               "component": ["type": "rive", "path": stored.lastPathComponent]])
        } catch let e as AssetError {
            throw BackendError(400, e.localizedDescription)
        }
    }

    func uploadImage(app: String, fileName: String, data: Data?, source: URL?) throws -> HTTPResponse {
        let safe = try Self.safeFileName(fileName)
        let bytes: Data
        if let data { bytes = data } else if let source {
            let size = Self.size(of: source)
            guard size > 0 else { throw BackendError(400, "the file is empty") }
            guard size <= HistoryStore.maxImageBytes else { throw BackendError(413, "the image is larger than \(HistoryStore.maxImageBytes / 1_048_576) MB") }
            guard let d = try? Data(contentsOf: source) else { throw BackendError(400, "cannot read \(source.path)") }
            bytes = d
        } else { throw BackendError(400, "missing file") }
        guard bytes.count <= HistoryStore.maxImageBytes else { throw BackendError(413, "the image is larger than \(HistoryStore.maxImageBytes / 1_048_576) MB") }
        guard let format = Self.imageKind(bytes) else { throw BackendError(400, "not an image Herald can draw (PNG, JPEG, GIF, WebP, HEIC, TIFF or BMP)") }
        guard Self.imageExtensions.contains((safe as NSString).pathExtension.lowercased()) else {
            throw BackendError(400, "the file name must end in an image extension such as .png")
        }
        let folder = imagesFolder(app)
        let dest = folder.appendingPathComponent(safe)
        let existed = FileManager.default.fileExists(atPath: dest.path)
        let count = ((try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []).count
        guard existed || count < 100 else { throw BackendError(429, "an app can hold at most 100 images") }
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try bytes.write(to: dest, options: .atomic)
        } catch { throw BackendError(500, "could not write the image: \(error.localizedDescription)") }
        return Self.reply(["ok": true, "kind": "image", "app": app, "file": safe, "path": dest.path, "format": format,
                           "bytes": bytes.count, "replaced": existed,
                           "usage": "Use the path as an image field's value or as a fixed image source."])
    }

    func deleteAsset(_ req: HTTPRequest) throws -> HTTPResponse {
        let app = try requiredQuery(req, "app")
        let file = try Self.safeFileName(try requiredQuery(req, "file"))
        let ext = (file as NSString).pathExtension.lowercased()
        let url: URL
        if ext == AssetStore.riveExtension { url = assets.folder(for: app).appendingPathComponent(file) }
        else if Self.imageExtensions.contains(ext) { url = imagesFolder(app).appendingPathComponent(file) }
        else { throw BackendError(400, "file must be a .riv or an image file name (see GET /v1/assets)") }
        guard FileManager.default.fileExists(atPath: url.path) else { throw BackendError(404, "no such asset: \(file)") }
        do { try FileManager.default.removeItem(at: url) } catch { throw BackendError(500, "could not remove \(file): \(error.localizedDescription)") }
        let users = ext == AssetStore.riveExtension ? templates.list(app: app).filter { t in
            HeraldTemplateBundle.riveRefs(in: t).contains { HeraldTemplateBundle.fileName(for: $0).lowercased() == file.lowercased() }
        }.map(\.name) : []
        return Self.reply(["ok": true, "deleted": file, "stillReferencedBy": users])
    }

    // MARK: Template duplicate, rename, default

    static func validTemplateName(_ n: String) -> String? { HeraldTemplateName.problem(n) }

    func sourceTemplate(app: String, name: String) throws -> HeraldTemplate {
        if let t = templates.get(app: app, name: name) { return t }
        if let b = BuiltinTemplates.named(name, app: app) { return b }
        throw BackendError(404, "template not found")
    }

    func duplicateTemplate(_ req: HTTPRequest) throws -> HTTPResponse {
        let o = try body(req)
        let app = try requiredString(o, "app"), name = try requiredString(o, "name")
        var t = try sourceTemplate(app: app, name: name)
        let target = try optionalString(o, "toApp") ?? app
        let taken = Set(templates.list(app: target).map(\.name))
        let wanted = try optionalString(o, "newName")
        let newName: String
        if let wanted {
            if let problem = Self.validTemplateName(wanted) { throw BackendError(400, "invalid newName: \(problem)") }
            guard !taken.contains(wanted) else { throw BackendError(409, "a template named \(wanted) already exists for \(target)") }
            newName = wanted
        } else {
            let base = name.hasPrefix(BuiltinTemplates.prefix) ? String(name.dropFirst(BuiltinTemplates.prefix.count)) : name
            newName = HeraldTemplateBundle.uniqueName("\(base) copy", taken: taken)
        }
        t.name = newName; t.app = target
        try saveTemplate(t)
        return Self.reply(["ok": true, "app": target, "name": newName, "copiedFrom": ["app": app, "name": name]])
    }

    func renameTemplate(_ req: HTTPRequest) throws -> HTTPResponse {
        let o = try body(req)
        let app = try requiredString(o, "app"), name = try requiredString(o, "name"), newName = try requiredString(o, "newName")
        // A built-in layout cannot be renamed; a stored template that happens to carry a builtin. name can.
        guard templates.get(app: app, name: name) != nil || !name.hasPrefix(BuiltinTemplates.prefix) else {
            throw BackendError(400, "a built-in template cannot be renamed; duplicate it instead")
        }
        if let problem = Self.validTemplateName(newName) { throw BackendError(400, "invalid newName: \(problem)") }
        guard var t = templates.get(app: app, name: name) else { throw BackendError(404, "template not found") }
        guard newName != name else { return Self.reply(["ok": true, "app": app, "name": name, "unchanged": true]) }
        guard templates.get(app: app, name: newName) == nil else { throw BackendError(409, "a template named \(newName) already exists for \(app)") }
        t.name = newName
        try saveTemplate(t)
        try removeTemplate(app, name)
        var wasDefault = false
        if var m = manifests.get(app: app), m.defaultTemplate == name {
            m.defaultTemplate = newName
            try saveManifest(m)
            wasDefault = true
        }
        return Self.reply(["ok": true, "app": app, "name": newName, "renamedFrom": name, "isDefault": wasDefault,
                           "note": "Command, script and Shortcut approvals belong to the old name; the user is asked again the first time they run."])
    }

    func setDefaultTemplate(_ req: HTTPRequest) throws -> HTTPResponse {
        let o = try body(req)
        let app = try requiredString(o, "app")
        guard var m = manifests.get(app: app) else { throw BackendError(400, "\(app) has no manifest; put_manifest first (the default template is a field of the manifest)") }
        if let name = try optionalString(o, "name") {
            _ = try sourceTemplate(app: app, name: name)
            m.defaultTemplate = name
        } else {
            m.defaultTemplate = nil
        }
        try saveManifest(m)
        return Self.reply(["ok": true, "app": app, "defaultTemplate": m.defaultTemplate ?? NSNull()])
    }

    // MARK: Bundles

    func exportBundle(_ req: HTTPRequest) throws -> HTTPResponse {
        let app = try requiredQuery(req, "app"), name = try requiredQuery(req, "name")
        guard let t = templates.get(app: app, name: name) else {
            // Built-in layouts are exported too (a bundle of the generated template), like the Designer's draft.
            if let b = BuiltinTemplates.named(name, app: app) { return try packed(b, req) }
            throw BackendError(404, "template not found")
        }
        return try packed(t, req)
    }

    func packed(_ t: HeraldTemplate, _ req: HTTPRequest) throws -> HTTPResponse {
        let result: HeraldTemplateBundle.ExportResult
        do { result = try bundles.export(t) } catch { throw BackendError(400, error.localizedDescription) }
        let file = TemplateStore.component(t.name) + "." + HeraldTemplateBundle.fileExtension
        var out: [String: Any] = ["ok": true, "app": t.app, "name": t.name, "file": file, "bytes": result.data.count,
                                  "assets": result.assetFiles, "warnings": result.warnings]
        if let path = query(req, "path") {
            let url = URL(fileURLWithPath: (path as NSString).expandingTildeInPath)
            guard url.pathExtension.lowercased() == HeraldTemplateBundle.fileExtension else { throw BackendError(400, "path must end in .\(HeraldTemplateBundle.fileExtension)") }
            guard FileManager.default.fileExists(atPath: url.deletingLastPathComponent().path) else { throw BackendError(400, "the folder does not exist") }
            do { try result.data.write(to: url, options: .atomic) } catch { throw BackendError(500, "could not write: \(error.localizedDescription)") }
            out["path"] = url.path
        } else {
            out["base64"] = result.data.base64EncodedString()
        }
        return Self.reply(out)
    }

    func importBundle(_ req: HTTPRequest) throws -> HTTPResponse {
        let o = try body(req)
        let b64 = try optionalString(o, "base64"), path = try optionalString(o, "path")
        guard (b64 == nil) != (path == nil) else { throw BackendError(400, "give exactly one of base64 or path (a .\(HeraldTemplateBundle.fileExtension) file on this Mac)") }
        let data: Data
        if let b64 {
            guard let d = Data(base64Encoded: b64, options: .ignoreUnknownCharacters), !d.isEmpty else { throw BackendError(400, "invalid field: base64") }
            data = d
        } else if let path {
            let url = URL(fileURLWithPath: (path as NSString).expandingTildeInPath)
            guard url.pathExtension.lowercased() == HeraldTemplateBundle.fileExtension else { throw BackendError(400, "path must end in .\(HeraldTemplateBundle.fileExtension)") }
            guard Self.size(of: url) <= HeraldTemplateBundle.maxTotalBytes else { throw BackendError(413, "the bundle is too large") }
            guard let d = try? Data(contentsOf: url) else { throw BackendError(400, "cannot read \(path)") }
            data = d
        } else { throw BackendError(400, "missing bundle") }
        let conflict: TemplateBundleService.Conflict
        switch try optionalString(o, "onConflict") ?? "keepBoth" {
        case "keepBoth": conflict = .keepBoth
        case "replace": conflict = .replace
        case "fail": conflict = .fail
        default: throw BackendError(400, "onConflict must be keepBoth, replace or fail")
        }
        do {
            let r = try bundles.importBundle(data, intoApp: try optionalString(o, "app"), onConflict: conflict, save: saveTemplate)
            var out: [String: Any] = ["ok": true, "app": r.template.app, "name": r.template.name, "replaced": r.replaced,
                                      "installedAssets": r.assets.installed, "reusedAssets": r.assets.reused,
                                      "missingAssets": r.assets.missing, "warnings": r.warnings]
            if let from = r.renamedFrom { out["renamedFrom"] = from }
            return Self.reply(out)
        } catch let e as HeraldTemplateBundle.BundleError {
            if case .nameExists = e { throw BackendError(409, e.localizedDescription) }
            throw BackendError(400, e.localizedDescription)
        }
    }

    // MARK: History

    func historyLimit(_ req: HTTPRequest, default d: Int = 50) throws -> Int {
        guard let raw = query(req, "limit") else { return d }
        guard let n = Int(raw), n >= 0 else { throw BackendError(400, "invalid limit") }
        return min(n, 1000)
    }

    func searchHistory(_ req: HTTPRequest) throws -> HTTPResponse {
        let q = req.query["q"] ?? ""
        let limit = try historyLimit(req)
        let items = history.search(q, app: query(req, "app"), limit: limit) { self.registry.record(for: $0)?.displayName }
        return Self.reply(["query": q, "count": items.count, "items": Self.jsonObject(items)])
    }

    func exportHistory(_ req: HTTPRequest) throws -> HTTPResponse {
        let items = try history.exportJSON(app: query(req, "app"))
        let arr = (try? JSONSerialization.jsonObject(with: items)) ?? []
        let count = (arr as? [Any])?.count ?? 0
        if let path = query(req, "path") {
            let url = URL(fileURLWithPath: (path as NSString).expandingTildeInPath)
            guard url.pathExtension.lowercased() == "json" else { throw BackendError(400, "path must end in .json") }
            guard FileManager.default.fileExists(atPath: url.deletingLastPathComponent().path) else { throw BackendError(400, "the folder does not exist") }
            do { try items.write(to: url, options: .atomic) } catch { throw BackendError(500, "could not write: \(error.localizedDescription)") }
            return Self.reply(["count": count, "path": url.path, "bytes": items.count])
        }
        return Self.reply(["count": count, "items": arr])
    }

    func reshow(_ req: HTTPRequest) async throws -> HTTPResponse {
        let o = try body(req)
        let app = try requiredString(o, "app"), id = try requiredString(o, "id")
        guard let item = history.item(app: app, id: id) else { throw BackendError(404, "no such notification in History") }
        let newId = try await host.reshow(item.notification)
        return Self.reply(["ok": true, "id": newId])
    }

    func deleteHistoryItem(_ req: HTTPRequest) async throws -> HTTPResponse {
        let app = try requiredQuery(req, "app"), id = try requiredQuery(req, "id")
        guard history.item(app: app, id: id) != nil else { throw BackendError(404, "no such notification in History") }
        await host.closeBanner(app: app, id: id)
        history.delete(app: app, id: id)
        await host.changed()
        return Self.reply(["ok": true])
    }

    // MARK: Symbols

    func listSymbols(_ req: HTTPRequest) throws -> HTTPResponse {
        guard let listing = symbols() else { throw BackendError(501, "this Mac has no SF Symbols list") }
        let limit = min(max(Int(query(req, "limit") ?? "") ?? 100, 0), 1000)
        let offset = max(Int(query(req, "offset") ?? "") ?? 0, 0)
        let category = query(req, "category")
        if let category, !listing.categories.contains(where: { $0.key == category }) {
            throw BackendError(400, "unknown category: \(category) (known: \(listing.categories.map(\.key).joined(separator: ", ")))")
        }
        let r = listing.search(req.query["q"] ?? "", category: category, limit: limit, offset: offset)
        return Self.reply([
            "total": r.total, "offset": offset, "limit": limit,
            "symbols": r.names.map { ["name": $0, "categories": listing.categories(of: $0)] as [String: Any] },
            "categories": listing.categories.map { ["key": $0.key, "title": $0.title, "icon": $0.icon, "count": $0.count] as [String: Any] },
        ])
    }
}
