import AppKit

/// Installing an MCP client from Settings > MCP or `POST /v1/mcp/install` (issue #62): the client's configuration gets
/// the server with `--agent <slug>`, and Herald registers the agent as an issuer (app, manifest, default template, the
/// product's icon). Running it again is safe; see `AgentIssuer`.
enum AgentInstall {
    struct Environment {
        let registry: AppRegistry
        let manifests: ManifestStore
        let templates: TemplateStore
        let support: URL
        var installer = MCPInstaller()
    }

    struct Outcome {
        var install: MCPInstallResult
        var identity: AgentIdentity?
        var report: AgentIssuer.Report?
        /// The issuer could not be registered (the client install itself may have worked).
        var registrationError: String?

        var json: JSONValue {
            var o: [String: JSONValue] = ["ok": .bool(install.ok), "message": .string(install.message), "touched": .string(install.touched),
                                          "alreadyExists": .bool(install.alreadyExists)]
            if let id = identity { o["agent"] = .object(["app": .string(id.appID), "name": .string(id.name), "server": .string("--agent \(id.slug)")]) }
            if let r = report {
                o["issuer"] = .object(["app": .string(r.appID), "manifestWritten": .bool(r.manifestWritten), "templateCreated": .bool(r.templateCreated),
                                       "template": .string(AgentIdentity.templateName), "templateUpgraded": .bool(r.templateUpgraded),
                                       "opens": r.opens.map { AgentInstall.targetJSON($0) } ?? .null, "icon": r.iconPath.map { .string($0) } ?? .null,
                                       "iconMissing": .bool(r.iconMissing)])
            }
            if let e = registrationError { o["registrationError"] = .string(e) }
            return .object(o)
        }
    }

    static func targetJSON(_ t: HeraldHostApp.Target) -> JSONValue {
        switch t {
        case .bundleId(let b): return .string(b)
        case .path(let p): return .string(p)
        }
    }

    /// Finder's own picture of an application's icon (it reads asset catalogs too), as 512 px PNG.
    @MainActor
    static func finderIconPNG(of app: URL) -> Data? {
        guard let info = NSDictionary(contentsOf: app.appendingPathComponent("Contents/Info.plist")),
              info["CFBundleIconFile"] != nil || info["CFBundleIconName"] != nil else { return nil }
        let image = NSWorkspace.shared.icon(forFile: app.path)
        let size = 512
        guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size, bitsPerSample: 8, samplesPerPixel: 4,
                                         hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0) else { return nil }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        image.draw(in: NSRect(x: 0, y: 0, width: size, height: size), from: .zero, operation: .copy, fraction: 1)
        NSGraphicsContext.restoreGraphicsState()
        return rep.representation(using: .png, properties: [:])
    }

    /// The agent's icon: the picked file; else Finder's picture of its application; else a file in its command line
    /// package. nil when this Mac has none.
    static func iconPNG(for identity: AgentIdentity, picked: URL?) async -> Data? {
        if let picked { return IconExtractor.png(from: picked) }
        let roots = AgentIconSources.Roots.standard()
        for bundle in AgentIconSources.appBundles(for: identity.kind, in: roots) {
            if let png = await MainActor.run(body: { finderIconPNG(of: bundle) }) { return png }
        }
        return await Task.detached { AgentIconSources.png(for: identity.kind, roots: roots)?.data }.value
    }

    /// `opens` is the application the user chose for "Open" (a bundle id or an `.app` path); `detectedHost` is the
    /// terminal or editor the install was asked from, used only when nothing was chosen and none is set yet.
    static func run(client: String, genericName: String?, iconFile: URL?, reinstall: Bool, opens: String? = nil,
                    detectedHost: String? = nil, env: Environment) async -> Outcome {
        guard let identity = AgentIdentity.client(client, genericName: genericName) else {
            let why = client == "generic" ? "Give a name for the client (for example \"My Bot\")." : "Unknown client \(client)."
            return Outcome(install: MCPInstallResult(ok: false, message: why, touched: ""))
        }
        let installer = env.installer
        let slug = identity.slug
        let install: MCPInstallResult = await Task.detached {
            switch identity.kind {
            case .claudeCode: return installer.installClaudeCode(reinstall: reinstall, agent: slug)
            case .codex: return installer.installCodex(agent: slug)
            case .claudeDesktop: return installer.installClaudeDesktop(agent: slug)
            case .generic:
                return MCPInstallResult(ok: true, message: "Added \(identity.name) as \(identity.appID). Use this config in the client.",
                                        touched: installer.genericCommandLine(agent: slug))
            }
        }.value
        guard install.ok else { return Outcome(install: install, identity: identity) }

        let png = await iconPNG(for: identity, picked: iconFile)
        do {
            let host = detectedHost.flatMap { HeraldHostApp.parseTarget($0) }.flatMap { t -> String? in
                if case .bundleId(let b) = t { return b } else { return nil }
            } ?? HeraldHostApp.detectCurrent()
            let report = try AgentIssuer.register(identity, iconPNG: png, opens: opens.flatMap { HeraldHostApp.parseTarget($0) },
                                                  detectedHost: host, supportDirectory: env.support, registry: env.registry,
                                                  manifests: env.manifests, templates: env.templates)
            return Outcome(install: install, identity: identity, report: report)
        } catch {
            return Outcome(install: install, identity: identity, registrationError: (error as? BackendError)?.message ?? "\(error)")
        }
    }
}
