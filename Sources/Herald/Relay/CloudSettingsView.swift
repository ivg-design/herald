import SwiftUI
import AppKit

/// Settings > Cloud: pair this Mac with the relay, mint notify-only agent keys (shown once, with a ready-to-paste connector
/// block), see the last 20 relay items with their receipt states, and today's usage of the free plan.
struct CloudSettingsView: View {
    let controller: AppController
    @StateObject private var ticker = ChangeTicker()
    @State private var showDeploy = false
    @State private var advancedOpen = false
    @State private var confirmOff = false
    @State private var busy = false
    @State private var message: String?
    @State private var newName = ""
    @State private var newClient = "claude"
    @State private var shown: RelayKeyCreated?

    private var relay: RelayController { controller.relay }

    var body: some View {
        Form {
            Section {
                Text("Let an agent running in the cloud notify this Mac. Herald connects out to the relay; nothing listens on this Mac. A key can send notifications and read their receipts, and nothing else: no commands, callbacks, scripts or settings.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Relay") {
                Toggle("Enable relay", isOn: enableBinding).toggleStyle(.switch)
                    .disabled(relay.deployRunning || relay.relaySwitch.isBusy) .heraldHelp(.cloudEnable)
                statusRow
                if !relay.relayURL.isEmpty { connectorURLRow }
                if relay.isPaired, relay.cloudConfig.value.customDomain == nil {
                    CustomDomainBanner { advancedOpen = true }
                }
                if relay.isPaired, relay.updateAvailable {
                    HStack {
                        Text("A newer relay is bundled with this Herald (running \(relay.deployedVersion ?? "unknown"), new \(relay.bundledVersion)).").font(.caption)
                        Spacer()
                        Button("Update the relay") { run { _ = try await relay.deployRelay() } }.disabled(busy || !relay.hasCloudflareToken) .heraldHelp(.cloudUpdate)
                    }
                }
                if let e = relay.lastError ?? message { Text(e).font(.caption).foregroundStyle(.red) }
            }
            if relay.isPaired { instructionsSection }
            if relay.isPaired {
                connectorSection
                Section("Agent keys") {
                    ForEach(relay.keys.filter(\.isActive)) { k in keyRow(k) }
                    if relay.keys.allSatisfy({ !$0.isActive }) { Text("No keys yet.").font(.caption).foregroundStyle(.secondary) }
                    HStack {
                        TextField("Key name (for example build-bot)", text: $newName).textFieldStyle(.roundedBorder) .heraldHelp(.cloudKeyName)
                        Picker("Agent", selection: $newClient) {
                            Text("Claude").tag("claude"); Text("Codex").tag("codex"); Text("Other").tag("other")
                        }.frame(width: 140) .heraldHelp(.cloudKeyClient)
                        Button("Create key") { createKey() }.disabled(busy || newName.trimmingCharacters(in: .whitespaces).isEmpty) .heraldHelp(.cloudNewKey)
                    }
                    Text("Scope: notify only.").font(.caption).foregroundStyle(.secondary)
                    if let k = shown { shownKey(k) }
                }
                Section("Usage today") {
                    usageRows
                } 
                Section("Last relay items") {
                    let log = { _ = ticker.tick; return relay.store.value.log }()
                    if log.isEmpty { Text("Nothing has arrived yet.").font(.caption).foregroundStyle(.secondary) }
                    ForEach(log) { e in
                        HStack {
                            VStack(alignment: .leading) {
                                Text(e.title.isEmpty ? e.id : e.title).lineLimit(1)
                                Text("\(e.key) \u{00B7} \(e.receivedAt.formatted(date: .omitted, time: .shortened))").font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Text(e.summary).font(.caption).foregroundStyle(e.suppressed == nil ? Color.secondary : Color.orange)
                        }
                    }
                }
            }
            Section { CloudAdvancedView(controller: controller, expanded: $advancedOpen) }
        }
        .formStyle(.grouped)
        .sheet(isPresented: $showDeploy) { DeployRelaySheet(controller: controller, isPresented: $showDeploy) }
        .alert("Turn the relay off?", isPresented: $confirmOff) {
            Button("Turn off", role: .destructive) { Task { await relay.relaySwitch.turnOff() } }
            Button("Cancel", role: .cancel) {}
        } message: { Text("This unpairs this Mac and revokes every agent key and connector. The relay itself stays in your Cloudflare account.") }
        .onAppear {
            if relay.isPaired { Task { await relay.refreshKeys(); await relay.refreshConsents(); await relay.refreshHealth(); _ = try? await relay.relayUsage() } }
        }
    }

    private var enableBinding: Binding<Bool> {
        Binding(get: { relay.relaySwitch.isOn }, set: { on in
            if on {
                if relay.relayURL.isEmpty { showDeploy = true } else { Task { await relay.relaySwitch.turnOn() } }
            } else { confirmOff = true }
        })
    }

    private var statusRow: some View {
        let _ = ticker.tick
        let sw = relay.relaySwitch.state
        let online = relay.client.state == .online
        let seen = relay.store.value.lastSeenAt
        return VStack(alignment: .leading, spacing: 4) {
            HStack {
                Circle().fill(online ? Color.green : (relay.isPaired || sw == .pairing || sw == .connecting ? Color.orange : Color.gray)).frame(width: 8, height: 8)
                Text(relay.isPaired ? relay.client.state.label : sw.label)
                if let seen, relay.isPaired { Text("last seen \(seen.formatted(date: .omitted, time: .shortened))").font(.caption).foregroundStyle(.secondary) }
                if sw == .pairing || sw == .connecting { ProgressView().controlSize(.small) }
                Spacer()
                if relay.isPaired { Button("Reconnect") { relay.client.reconnectNow() } .heraldHelp(.cloudReconnect) }
            }
            if case .failed(let m) = sw {
                Text(m).font(.caption).foregroundStyle(.red).fixedSize(horizontal: false, vertical: true)
                HStack {
                    Button("Try again") { Task { await relay.relaySwitch.turnOn() } }
                    if relay.isPaired { Button("Turn off anyway") { run { try await relay.relayUnpair(force: true); relay.relaySwitch.sync() } } }
                }
            }
        }
    }

    private var connectorURLRow: some View {
        let url = ConnectorConfig.mcpURL(relay: relay.relayURL)
        return HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("Connector URL").font(.caption).foregroundStyle(.secondary)
                Text(url).font(.system(.callout, design: .monospaced)).textSelection(.enabled)
            }
            Spacer()
            Button("Copy") { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(url, forType: .string) } .heraldHelp(.cloudCopyURL)
        }
    }

    /// The two ready-made blocks: OAuth connectors (ChatGPT / OpenAI cloud agents) and a static key (Claude Code / Codex CLI).
    @ViewBuilder private var instructionsSection: some View {
        let url = ConnectorConfig.mcpURL(relay: relay.relayURL)
        Section("Connect an agent") {
            instructionBlock(RelayInstructions.oauth(mcpURL: url))
            instructionBlock(RelayInstructions.staticKey(mcpURL: url), extra: AnyView(
                Button("Create a key and copy the config") { makeStaticKey() }.disabled(busy)
                    .heraldHelp(name: "Create a key and copy the config", detail: "Makes a notify-only key named after the agent and copies the ready-to-paste connector block")))
        }
    }

    private func instructionBlock(_ text: String, extra: AnyView? = nil) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(text).font(.system(size: 11, design: .monospaced)).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
            HStack {
                Button("Copy instructions") { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(text, forType: .string) } .heraldHelp(.cloudCopyInstructions)
                if let extra { extra }
            }
        }
        .padding(8).background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 8))
    }

    private func makeStaticKey() {
        busy = true
        Task {
            defer { busy = false }
            let taken = Set(relay.keys.filter(\.isActive).map(\.name))
            var name = "claude-code", n = 2
            while taken.contains(name) { name = "claude-code-\(n)"; n += 1 }
            do {
                let k = try await relay.relayCreateKey(name: name, client: "claude")
                shown = k
                NSPasteboard.general.clearContents(); NSPasteboard.general.setString(k.connectorConfig, forType: .string)
                message = nil
            } catch { message = error.localizedDescription }
        }
    }

    @ViewBuilder private func keyRow(_ k: RelayKeyInfo) -> some View {
        HStack {
            VStack(alignment: .leading) {
                Text(k.title)
                Text("cloud.\(HeraldAgent.slug(k.name)) \u{00B7} \(k.isOAuth ? "connector (oauth)" : k.client) \u{00B7} notify").font(.system(.caption, design: .monospaced)).foregroundStyle(.secondary)
            }
            Spacer()
            Button("Design\u{2026}") { DesignerWindow.show(controller: controller, app: "cloud." + HeraldAgent.slug(k.name), template: AgentIdentity.templateName) }
                .heraldHelp(.cloudDesign)
            Button("Revoke", role: .destructive) { run { try await relay.relayRevokeKey(id: k.id) } } .heraldHelp(.cloudRevoke)
        }
    }

    /// ChatGPT and other connectors that sign in with OAuth: the requests waiting for a decision (with the 6-digit code to type
    /// on the consent page when the banner was missed) and the connectors that are connected.
    @ViewBuilder private var connectorSection: some View {
        let _ = ticker.tick
        Section("Connector approvals") {
            Text("A connector such as ChatGPT asks to connect from its own settings; the request shows up here and as a banner. Approve it there, or type the code on the page that opened in your browser. An agent with no browser prints a code like BDFG-HJKM: approve only if it matches what the agent showed you.")
                .font(.caption).foregroundStyle(.secondary)
            ForEach(relay.pendingConsents) { c in
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(c.isDevice ? "\(c.clientName) wants to send you notifications" : "\(c.clientName) wants to connect")
                        Text(c.isDevice ? "agent without a browser \u{00B7} approval code \(c.spacedCode) for the /activate page"
                                        : "returns to \(c.redirectHost ?? "its own site")").font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text(c.isDevice ? (c.userCode ?? c.code) : c.spacedCode).font(.system(size: 22, weight: .semibold, design: .monospaced)).textSelection(.enabled)
                        .accessibilityLabel(c.isDevice ? "Code the agent printed \(c.userCode ?? "")" : "Approval code \(c.code)")
                    Button("Approve") { Task { await relay.decideConsent(id: c.id, approve: true) } }
                        .heraldHelp(name: "Approve connector", detail: "lets this connector send notifications to this Mac")
                    Button("Deny", role: .destructive) { Task { await relay.decideConsent(id: c.id, approve: false) } }
                        .heraldHelp(name: "Deny connector", detail: "refuses this connection request")
                }
            }
            if relay.pendingConsents.isEmpty { Text("Nothing is waiting for approval.").font(.caption).foregroundStyle(.secondary) }
            ForEach(relay.connectors) { k in
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(k.title)
                        Text("connected \u{00B7} notify only").font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("Revoke", role: .destructive) { run { try await relay.relayRevokeKey(id: k.id) } } .heraldHelp(.cloudRevoke)
                }
            }
        }
    }

    private func shownKey(_ k: RelayKeyCreated) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Key \"\(k.name)\" \u{2014} copy it now, it is not shown again").font(.headline)
            Text(k.key).font(.system(.caption, design: .monospaced)).textSelection(.enabled)
            ScrollView { Text(k.connectorConfig).font(.system(size: 10.5, design: .monospaced)).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading) }
                .frame(height: 150)
            HStack {
                Button("Copy connector config") {
                    NSPasteboard.general.clearContents(); NSPasteboard.general.setString(k.connectorConfig, forType: .string)
                } .heraldHelp(.cloudCopyConfig)
                Button("Done") { shown = nil }
            }
        }
        .padding(8).background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 8))
    }

    @ViewBuilder private var usageRows: some View {
        if let u = relay.usage {
            Text("\(u.requests) requests (\(u.requestsPercent)% of the relay's daily budget) \u{00B7} \(u.notifications) notifications \u{00B7} \(u.queued) queued \u{00B7} \(ByteCountFormatter.string(fromByteCount: Int64(u.storageBytes), countStyle: .file)) stored")
                .font(.caption) .heraldHelp(.cloudUsage)
            if u.budgetExhausted { Text("Daily budget used up; agents get 503 until midnight UTC. Nothing queued is lost.").font(.caption).foregroundStyle(.orange) }
        } else { Text("Not loaded yet.").font(.caption).foregroundStyle(.secondary) }
        Button("Refresh") { run { _ = try await relay.relayUsage() } } .heraldHelp(.cloudUsage)
    }

    private func createKey() {
        busy = true
        let name = newName.trimmingCharacters(in: .whitespaces), kind = newClient
        Task {
            defer { busy = false }
            do { shown = try await relay.relayCreateKey(name: name, client: kind); newName = ""; message = nil }
            catch { message = error.localizedDescription }
        }
    }

    private func run(_ work: @escaping () async throws -> Void) {
        busy = true; message = nil
        Task {
            defer { busy = false }
            do { try await work() } catch { message = error.localizedDescription }
        }
    }
}
