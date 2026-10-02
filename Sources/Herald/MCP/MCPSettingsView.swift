import SwiftUI
import AppKit

/// Settings > MCP: one-click install of the bundled herald-mcp server into agent clients.
struct MCPSettingsView: View {
    private let installer = MCPInstaller()
    @State private var statuses: [MCPClient: MCPClientStatus] = [:]
    @State private var messages: [String: MCPInstallResult] = [:]
    @State private var testResult: String?
    @State private var busy = false

    var body: some View {
        Form {
            Section {
                Text("One-click install for Claude Code, Codex and Claude Desktop. Any other MCP client can use the generic config.")
                Text("The MCP server gives an agent design templates (list, validate, preview, save), the ability to send and test notifications, speak a message, and read or set quiet hours.")
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
                    Button("Install `herald` command line tool") { run("cli") { installer.installCLI() } }.disabled(busy) .heraldHelp(.mcpInstallCLI)
                    Spacer()
                }
                result("cli")
            }
        }
        .formStyle(.grouped)
        .onAppear(perform: refresh)
    }

    @ViewBuilder private func row(_ client: MCPClient) -> some View {
        let st = statuses[client] ?? .notInstalled
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
                    Button("Copy generic config") {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(installer.genericClipboardText, forType: .string)
                        messages[client.rawValue] = .init(ok: true, message: "Copied the JSON config and the stdio command line.", touched: "pasteboard")
                    } .heraldHelp(.mcpCopyConfig)
                case .claudeCode:
                    let exists = messages[client.rawValue]?.alreadyExists == true
                    Button(st == .installed || exists ? "Reinstall" : "Install") {
                        run(client.rawValue) { installer.installClaudeCode(reinstall: st == .installed || exists) }
                    }.disabled(busy || st == .clientNotFound) .heraldHelp(.mcpInstallClient)
                case .codex:
                    Button(st == .installed ? "Reinstall" : "Install") { run(client.rawValue) { installer.installCodex() } }
                        .disabled(busy || st == .clientNotFound) .heraldHelp(.mcpInstallClient)
                case .claudeDesktop:
                    Button(st == .installed ? "Reinstall" : "Install") { run(client.rawValue) { installer.installClaudeDesktop() } }
                        .disabled(busy || st == .clientNotFound) .heraldHelp(.mcpInstallClient)
                }
            }
            result(client.rawValue)
        }
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

    private func refresh() {
        let inst = installer
        DispatchQueue.global().async {
            var s: [MCPClient: MCPClientStatus] = [:]
            for c in MCPClient.allCases { s[c] = inst.status(c) }
            DispatchQueue.main.async { statuses = s }
        }
    }

    private func run(_ key: String, _ work: @escaping () -> MCPInstallResult) {
        busy = true
        DispatchQueue.global().async {
            let r = work()
            DispatchQueue.main.async { messages[key] = r; busy = false; refresh() }
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
