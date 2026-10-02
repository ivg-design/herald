import SwiftUI
import AppKit

/// Settings > Cloud: pair this Mac with the relay, mint notify-only agent keys (shown once, with a ready-to-paste connector
/// block), see the last 20 relay items with their receipt states, and today's usage of the free plan.
struct CloudSettingsView: View {
    let controller: AppController
    @StateObject private var ticker = ChangeTicker()
    @State private var urlText = ""
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
                HStack {
                    TextField("Relay URL", text: $urlText).textFieldStyle(.roundedBorder)
                        .onSubmit { relay.relayURL = urlText } .heraldHelp(.cloudRelayURL)
                    Button("Save") { relay.relayURL = urlText; relay.client.start() } .heraldHelp(name: "Save relay URL", detail: "use this relay and reconnect")
                }
                statusRow
                HStack {
                    if relay.isPaired {
                        Button("Reconnect") { relay.client.reconnectNow() } .heraldHelp(.cloudReconnect)
                        Button("Unpair\u{2026}", role: .destructive) { run { try await relay.relayUnpair() } } .heraldHelp(.cloudUnpair)
                    } else {
                        Button("Pair\u{2026}") { run { _ = try await relay.relayPair() } }.disabled(busy) .heraldHelp(.cloudPair)
                    }
                    if let code = relay.pairingCode {
                        Text("Pairing code \(code)").font(.system(.body, design: .monospaced)).textSelection(.enabled)
                    }
                }
                if let e = relay.lastError ?? message { Text(e).font(.caption).foregroundStyle(.red) }
            }
            if relay.isPaired {
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
        }
        .formStyle(.grouped)
        .onAppear {
            urlText = relay.relayURL
            if relay.isPaired { Task { await relay.refreshKeys(); _ = try? await relay.relayUsage() } }
        }
    }

    private var statusRow: some View {
        let _ = ticker.tick
        let st = relay.client.state
        let seen = relay.store.value.lastSeenAt
        return HStack {
            Circle().fill(st == .online ? Color.green : (relay.isPaired ? Color.orange : Color.gray)).frame(width: 8, height: 8)
            Text(st.label)
            if let seen, relay.isPaired { Text("last seen \(seen.formatted(date: .omitted, time: .shortened))").font(.caption).foregroundStyle(.secondary) }
            Spacer()
        }
    }

    @ViewBuilder private func keyRow(_ k: RelayKeyInfo) -> some View {
        HStack {
            VStack(alignment: .leading) {
                Text(k.name)
                Text("cloud.\(HeraldAgent.slug(k.name)) \u{00B7} \(k.client) \u{00B7} notify").font(.system(.caption, design: .monospaced)).foregroundStyle(.secondary)
            }
            Spacer()
            Button("Design\u{2026}") { DesignerWindow.show(controller: controller, app: "cloud." + HeraldAgent.slug(k.name), template: AgentIdentity.templateName) }
                .heraldHelp(.cloudDesign)
            Button("Revoke", role: .destructive) { run { try await relay.relayRevokeKey(id: k.id) } } .heraldHelp(.cloudRevoke)
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
