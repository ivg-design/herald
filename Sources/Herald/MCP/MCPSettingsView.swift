import SwiftUI
import AppKit
import UniformTypeIdentifiers

/// Settings > MCP: one-click install of the bundled herald-mcp server into agent clients. Installing a client also
/// makes the agent an issuer of its own (`agent.claude-code`, ...): its notifications arrive under their own name and
/// icon, and "Design notifications..." opens the Designer on it (issue #62).
struct MCPSettingsView: View {
    let controller: AppController
    private let installer = MCPInstaller()
    @StateObject private var ticker = ChangeTicker()
    @State private var statuses: [MCPClient: MCPClientStatus] = [:]
    @State private var messages: [String: MCPInstallResult] = [:]
    @State private var testResult: String?
    @State private var busy = false
    @State private var genericName = ""
    @State private var genericIcon: URL?

    var body: some View {
        Form {
            Section {
                Text("One-click install for Claude Code, Codex and Claude Desktop. Any other MCP client can use the generic config.")
                Text("Each installed client becomes a notification app of its own (for example agent.claude-code) with its own icon, sound and banner design. The MCP server gives an agent design templates (list, validate, preview, save), the ability to send and test notifications, speak a message, and read or set quiet hours.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Server") {
                HStack {
                    Text(installer.serverPath).font(.system(.caption, design: .monospaced)).textSelection(.enabled)
                        .lineLimit(2).truncationMode(.middle)
                    Spacer()
                    Button("Reveal in Finder") {
                        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: installer.serverPath)])
                    } .heraldHelp(.mcpReveal)
                }
                HStack {
                    Button("Test connection") { runTest() }.disabled(busy) .heraldHelp(.mcpTest)
                    if let t = testResult { Text(t).font(.caption).foregroundStyle(t.hasPrefix("OK") ? Color.green : Color.red) }
                }
            }
            Section("Clients") {
                ForEach(MCPClient.allCases) { client in row(client) }
            }
            Section("Command line tool") {
                HStack {
                    Button("Install `herald` command line tool") { runCLI() }.disabled(busy) .heraldHelp(.mcpInstallCLI)
                    Spacer()
                }
                result("cli")
            }
        }
        .formStyle(.grouped)
        .onAppear(perform: refresh)
    }

    private static func key(_ c: MCPClient) -> String {
        switch c {
        case .claudeCode: return "claudeCode"
        case .codex: return "codex"
        case .claudeDesktop: return "claudeDesktop"
        case .generic: return "generic"
        }
    }

    private func identity(_ client: MCPClient) -> AgentIdentity? {
        AgentIdentity.client(Self.key(client), genericName: client == .generic ? genericName : nil)
    }

    private func record(_ id: AgentIdentity?) -> AppRecord? {
        _ = ticker.tick
        return id.flatMap { controller.registry.record(for: $0.appID) }
    }

    @ViewBuilder private func row(_ client: MCPClient) -> some View {
        let st = statuses[client] ?? .notInstalled
        let agent = identity(client)
        let rec = client == .generic ? nil : record(agent)
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(client.rawValue)
                Spacer()
                if client != .generic {
                    Text(st.label).font(.caption)
                        .foregroundStyle(st == .installed ? Color.green : .secondary)
                }
                switch client {
                case .generic:
                    EmptyView()
                case .claudeCode:
                    let exists = messages[client.rawValue]?.alreadyExists == true
                    Button(st == .installed || exists ? "Reinstall" : "Install") {
                        install(client, reinstall: st == .installed || exists)
                    }.disabled(busy || st == .clientNotFound) .heraldHelp(.mcpInstallClient)
                case .codex, .claudeDesktop:
                    Button(st == .installed ? "Reinstall" : "Install") { install(client, reinstall: st == .installed) }
                        .disabled(busy || st == .clientNotFound) .heraldHelp(.mcpInstallClient)
                }
            }
            if client == .generic { genericControls(client) }
            else if let rec, let agent { issuerLine(agent, rec) }
            result(client.rawValue)
        }
    }

    /// The agent's app: its id, a button into the Designer, and the icon state.
    @ViewBuilder private func issuerLine(_ agent: AgentIdentity, _ rec: AppRecord) -> some View {
        HStack(spacing: 8) {
            Text(agent.appID).font(.system(.caption, design: .monospaced)).foregroundStyle(.secondary).textSelection(.enabled)
            Spacer()
            if rec.registration.icon == nil {
                Text("No icon found").font(.caption).foregroundStyle(.orange)
                Button("Choose\u{2026}") { chooseIcon(for: agent) }
                    .heraldHelp(name: "Choose icon", detail: "pick an image to use as this agent's icon")
            }
            Button("Design notifications\u{2026}") {
                DesignerWindow.show(controller: controller, app: agent.appID, template: AgentIdentity.templateName)
            }
            .heraldHelp(name: "Design notifications", detail: "open the Designer on this agent's banner")
        }
    }

    @ViewBuilder private func genericControls(_ client: MCPClient) -> some View {
        let agent = identity(client)
        HStack {
            TextField("Client name", text: $genericName, prompt: Text("My Bot"))
                .heraldHelp(name: "Client name", detail: "the name of the MCP client; its notifications arrive as agent.<name>")
            Button(genericIcon.map { $0.lastPathComponent } ?? "Choose icon\u{2026}") { genericIcon = pickImage(title: "Choose an icon") }
                .heraldHelp(name: "Choose icon", detail: "an image for this client's notifications; without one a symbol is used")
            Button("Add and copy config") { install(client, reinstall: false) }
                .disabled(busy || agent == nil)
                .heraldHelp(name: "Add client", detail: "register this client as a notification app and copy its MCP config")
        }
        if let agent, let rec = record(agent) { issuerLine(agent, rec) }
        if let agent { Text("Uses \(agent.appID). Config: \(installer.genericCommandLine(agent: agent.slug))")
            .font(.system(.caption2, design: .monospaced)).foregroundStyle(.secondary).textSelection(.enabled).lineLimit(2).truncationMode(.middle) }
    }

    @ViewBuilder private func result(_ key: String) -> some View {
        if let r = messages[key] {
            VStack(alignment: .leading, spacing: 1) {
                Text(r.message).font(.caption).foregroundStyle(r.ok ? Color.green : Color.red)
                Text(r.touched).font(.system(.caption2, design: .monospaced)).foregroundStyle(.secondary)
                    .textSelection(.enabled).lineLimit(2).truncationMode(.middle)
            }
        }
    }

    private func pickImage(title: String) -> URL? {
        let p = NSOpenPanel()
        p.title = title
        p.allowedContentTypes = [.png, .jpeg, .tiff, .icns, .heic]
        p.allowsMultipleSelection = false
        p.canChooseDirectories = false
        return p.runModal() == .OK ? p.url : nil
    }

    private func environment() -> AgentInstall.Environment {
        AgentInstall.Environment(registry: controller.registry, manifests: controller.manifests, templates: controller.templates,
                                 support: controller.supportDirectory)
    }

    private func install(_ client: MCPClient, reinstall: Bool) {
        busy = true
        let env = environment(), name = client == .generic ? genericName : nil, icon = client == .generic ? genericIcon : nil
        Task {
            let outcome = await AgentInstall.run(client: Self.key(client), genericName: name, iconFile: icon, reinstall: reinstall, env: env)
            var shown = outcome.install
            if let e = outcome.registrationError { shown.message += " The notification app could not be set up: \(e)" }
            if client == .generic, outcome.install.ok, let slug = outcome.identity?.slug {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString("\(installer.genericJSON(agent: slug))\n\n\(installer.genericCommandLine(agent: slug))\n", forType: .string)
                shown.message += " The JSON config and the command line are on the clipboard."
            }
            messages[client.rawValue] = shown
            busy = false
            controller.changed()
            refresh()
        }
    }

    /// An icon picked afterwards for an agent whose product has none on this Mac.
    private func chooseIcon(for agent: AgentIdentity) {
        guard let url = pickImage(title: "Choose an icon for \(agent.name)"), let png = IconExtractor.png(from: url) else { return }
        do {
            try AgentIssuer.register(agent, iconPNG: png, supportDirectory: controller.supportDirectory, registry: controller.registry,
                                     manifests: controller.manifests, templates: controller.templates)
            AppIcons.invalidate()
            controller.changed()
        } catch { messages[Self.key(.claudeCode)] = MCPInstallResult(ok: false, message: "\(error)", touched: url.path) }
    }

    private func runCLI() {
        busy = true
        let inst = installer
        DispatchQueue.global().async {
            let r = inst.installCLI()
            DispatchQueue.main.async { messages["cli"] = r; busy = false }
        }
    }

    private func refresh() {
        let inst = installer
        DispatchQueue.global().async {
            var s: [MCPClient: MCPClientStatus] = [:]
            for c in MCPClient.allCases { s[c] = inst.status(c) }
            DispatchQueue.main.async { statuses = s }
        }
    }

    private func runTest() {
        busy = true; testResult = "Testing..."
        let inst = installer
        DispatchQueue.global().async {
            let r = inst.testConnection()
            DispatchQueue.main.async {
                busy = false
                switch r {
                case .success(let n): testResult = "OK: \(n) tools"
                case .failure(let e): testResult = "Failed: \(e.message)"
                }
            }
        }
    }
}
