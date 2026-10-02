import SwiftUI
import AppKit

/// Settings > Cloud > Advanced: every setting of the relay, visible and editable. A value that lives in the Worker redeploys it.
struct CloudAdvancedView: View {
    let controller: AppController
    @Binding var expanded: Bool
    @State private var draft = RelayCloudConfig()
    @State private var urlText = ""
    @State private var pairingText = ""
    @State private var errors: [String: String] = [:]
    @State private var message: String?
    @State private var busy = false
    @State private var confirmDelete = false
    @State private var showToken = false

    private var relay: RelayController { controller.relay }

    private struct Field: Identifiable {
        var id: String; var title: String; var help: String; var kind: Kind
        enum Kind { case text, number }
    }
    private let fields: [Field] = [
        .init(id: "accountId", title: "Account id", help: "The Cloudflare account the relay lives in; empty finds it from the token", kind: .text),
        .init(id: "workerName", title: "Worker name", help: "The relay's name in Cloudflare; part of its address", kind: .text),
        .init(id: "subdomain", title: "workers.dev subdomain", help: "The account's workers.dev address; empty uses (or creates) the account's own", kind: .text),
        .init(id: "bucket", title: "R2 bucket", help: "The bucket that holds voice replies", kind: .text),
        .init(id: "audioRetentionDays", title: "Voice replies kept (days)", help: "How long a voice reply is kept before Cloudflare deletes it", kind: .number),
        .init(id: "queueTTLHours", title: "Undelivered kept (hours)", help: "How long a notification waits for this Mac while it is offline", kind: .number),
        .init(id: "notificationsPerDay", title: "Notifications per day", help: "The most notifications agents may send this Mac in a day", kind: .number),
        .init(id: "maxQueue", title: "Most waiting at once", help: "The most undelivered notifications the relay holds for this Mac", kind: .number),
        .init(id: "bodyLimitBytes", title: "Largest request (bytes)", help: "The size limit of one notification request", kind: .number),
        .init(id: "ratePerKey", title: "Per key, per 10 minutes", help: "The most notifications one agent key may send in 10 minutes", kind: .number),
        .init(id: "maxDevices", title: "Macs that may pair", help: "How many Macs may pair with this relay", kind: .number),
        .init(id: "deviceName", title: "This Mac's name", help: "How this Mac introduces itself to the relay; empty uses the Mac's name", kind: .text),
        .init(id: "pingSeconds", title: "Keep-alive (seconds)", help: "How often Herald pings the relay to keep the connection open", kind: .number),
    ]

    var body: some View {
        DisclosureGroup("Advanced", isExpanded: $expanded) {
            VStack(alignment: .leading, spacing: 10) {
                CloudCustomDomainView(controller: controller)
                Divider()
                if relay.isPaired { devicesSection; Divider() }
                row("Relay URL", help: "The relay this Mac connects to: yours on Cloudflare, or any other relay", error: nil) {
                    TextField("https://\u{2026}", text: $urlText).textFieldStyle(.roundedBorder)
                }
                ForEach(fields) { f in
                    row(f.title, help: f.help, error: errors[f.id]) { field(f) }
                }
                row("Pairing secret", help: "Demanded by the relay when a Mac pairs; Herald made it at the first deploy. Changing it redeploys.", error: nil) {
                    HStack {
                        TextField(relay.pairingSecretValue == nil ? "none" : "set", text: $pairingText).textFieldStyle(.roundedBorder)
                        if let s = relay.pairingSecretValue {
                            Button("Copy") { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(s, forType: .string) } .heraldHelp(.cloudPairingSecret)
                        }
                    }
                }
                if let s = relay.pairingSecretValue, showToken { Text(s).font(.system(.caption, design: .monospaced)).textSelection(.enabled) }
                if let m = message { Text(m).font(.caption).foregroundStyle(errors.isEmpty ? Color.secondary : Color.red).textSelection(.enabled) }
                HStack {
                    Button("Apply settings") { apply() }.disabled(busy) .heraldHelp(.cloudApply)
                    Button("Redeploy") { run { _ = try await relay.deployRelay(); message = "Redeployed." } }.disabled(busy || !relay.hasCloudflareToken) .heraldHelp(.cloudRedeploy)
                    Button("Test connection") { run { let r = try await relay.testRelay(); message = r.detail } }.disabled(busy || relay.relayURL.isEmpty) .heraldHelp(.cloudTest)
                    Spacer()
                    Button(showToken ? "Hide secret" : "Show secret") { showToken.toggle() }.disabled(relay.pairingSecretValue == nil) .heraldHelp(.cloudPairingSecret)
                }
                HStack {
                    Button("Pair with a code") { run { _ = try await relay.relayPair(); message = "Paired." } }.disabled(busy || relay.isPaired || relay.relayURL.isEmpty) .heraldHelp(.cloudPairCode)
                    Button("Unpair", role: .destructive) { run { try await relay.relayUnpair(force: true); message = "Unpaired." } }.disabled(busy || !relay.isPaired) .heraldHelp(.cloudUnpair)
                    Button("Forget token") { relay.forgetCloudflareToken() }.disabled(!relay.hasCloudflareToken) .heraldHelp(.cloudForgetToken)
                    Spacer()
                    Button("Delete relay from Cloudflare\u{2026}", role: .destructive) { confirmDelete = true }.disabled(busy || !relay.hasCloudflareToken || relay.cloudConfig.value.accountId.isEmpty) .heraldHelp(.cloudDelete)
                }
            }
            .padding(.top, 6)
        }
        .heraldHelp(.cloudAdvanced)
        .onAppear(perform: load)
        .alert("Delete the relay from Cloudflare?", isPresented: $confirmDelete) {
            Button("Delete", role: .destructive) { run { let r = try await relay.deleteRelay(); message = r.note ?? "The relay was deleted."; load() } }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This removes the relay, every mailbox, agent key and connector from your Cloudflare account. Agents lose access for good.")
        }
    }

    /// Every Mac paired with this relay. An approval goes to the connected one, so a stale entry (an old install, a Mac that paired
    /// again under the same name) is worth removing; the relay lets this Mac remove only those.
    @ViewBuilder private var devicesSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Devices on this relay").font(.headline)
            if relay.devices.isEmpty {
                Text("Not loaded yet.").font(.caption).foregroundStyle(.secondary)
            }
            ForEach(relay.devices) { d in
                HStack {
                    Image(systemName: d.online ? "circle.fill" : "circle").font(.system(size: 7)).foregroundStyle(d.online ? Color.green : Color.secondary)
                    Text(d.title + (d.thisDevice ? " (this Mac)" : ""))
                    Text(Self.lastSeen(d)).font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    if d.removable {
                        Button("Remove") { run { try await relay.removeDevice(id: d.id); message = "Removed \(d.title)." } }
                            .disabled(busy).heraldHelp(name: "Remove", detail: "Removes this entry from the relay: it has the same name as this Mac, its credentials were replaced, or it has not connected for a week")
                    }
                }
            }
            Text("Agents without a chosen Mac reach the one that is connected right now.").font(.caption).foregroundStyle(.secondary)
        }
        .task { await relay.refreshDevices() }
    }

    static func lastSeen(_ d: RelayDeviceEntry) -> String {
        if d.online { return "connected" }
        guard let s = d.lastSeenAt, let t = ISO8601DateFormatter.fractional.date(from: s) ?? ISO8601DateFormatter().date(from: s) else { return "never connected" }
        return "last seen " + RelativeDateTimeFormatter().localizedString(for: t, relativeTo: Date())
    }

    @ViewBuilder private func field(_ f: Field) -> some View {
        switch f.kind {
        case .text: TextField("", text: textBinding(f.id)).textFieldStyle(.roundedBorder)
        case .number: TextField("", value: intBinding(f.id), format: .number.grouping(.never)).textFieldStyle(.roundedBorder)
        }
    }

    private func row<C: View>(_ title: String, help: String, error: String?, @ViewBuilder content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack { Text(title).frame(width: 190, alignment: .leading); content().heraldHelp(name: title, detail: help) }
            if let error { Text(error).font(.caption).foregroundStyle(.red).padding(.leading, 190) }
        }
    }

    // MARK: Draft <-> config

    private func textBinding(_ id: String) -> Binding<String> {
        Binding(get: { (try? JSONSerialization.jsonObject(with: JSONEncoder().encode(draft)) as? [String: Any])?[id] as? String ?? "" },
                set: { v in patch(id, .string(v)) })
    }
    private func intBinding(_ id: String) -> Binding<Int> {
        Binding(get: { (try? JSONSerialization.jsonObject(with: JSONEncoder().encode(draft)) as? [String: Any])?[id] as? Int ?? 0 },
                set: { v in patch(id, .number(Double(v))) })
    }
    private func patch(_ id: String, _ v: JSONValue) { if let c = try? draft.applying([id: v]) { draft = c; errors = draft.validate() } }

    private func load() {
        draft = relay.cloudConfig.value; urlText = relay.relayURL; pairingText = ""; errors = [:]; message = nil
    }

    private func apply() {
        errors = draft.validate()
        guard errors.isEmpty else { message = "Fix the highlighted values."; return }
        run {
            var p: [String: JSONValue] = [
                "accountId": .string(draft.accountId), "workerName": .string(draft.workerName), "subdomain": .string(draft.subdomain), "bucket": .string(draft.bucket),
                "audioRetentionDays": .number(Double(draft.audioRetentionDays)), "queueTTLHours": .number(Double(draft.queueTTLHours)),
                "notificationsPerDay": .number(Double(draft.notificationsPerDay)), "maxQueue": .number(Double(draft.maxQueue)),
                "bodyLimitBytes": .number(Double(draft.bodyLimitBytes)), "ratePerKey": .number(Double(draft.ratePerKey)),
                "maxDevices": .number(Double(draft.maxDevices)), "deviceName": .string(draft.deviceName), "pingSeconds": .number(Double(draft.pingSeconds)),
                "relayURL": .string(urlText),
            ]
            if !pairingText.isEmpty { p["pairingSecret"] = .string(pairingText) }
            let r = try await relay.updateRelaySettings(p)
            message = r.redeployed ? "Saved and redeployed." : "Saved."
            pairingText = ""
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

private extension ISO8601DateFormatter {
    static let fractional: ISO8601DateFormatter = { let f = ISO8601DateFormatter(); f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]; return f }()
}
