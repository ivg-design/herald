import SwiftUI
import AppKit

/// The relay's custom domain (Settings > Cloud > Advanced). Cloud agents such as ChatGPT are blocked by Cloudflare's Browser
/// Integrity Check on workers.dev (Error 1010), which cannot be switched off there; a hostname in the user's own zone can.
struct CloudCustomDomainView: View {
    let controller: AppController
    @State private var zones: [RelayZone] = []
    @State private var zone = ""
    @State private var hostname = ""
    @State private var message: String?
    @State private var warnings: [String] = []
    @State private var busy = false

    private var relay: RelayController { controller.relay }
    private var current: RelayCloudConfig.CustomDomain? { relay.cloudConfig.value.customDomain }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Custom domain").font(.headline)
            Text("Optional. Cloudflare\u{2019}s Browser Integrity Check rejects Python\u{2019}s default User-Agent (Python-urllib/3.x, Error 1010) on workers.dev; agents that send their own User-Agent are fine. A hostname in a domain you own on Cloudflare turns the check off, so even default library User-Agents work, and gives the relay a stable, branded address. Herald attaches it, switches Browser Integrity Check off for that hostname only, and points this Mac at it. Connectors already added to an agent must be re-added with the new URL.")
                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            if let w = relay.cloudConfig.value.workerURL { addressRow("workers.dev address", w, canonical: relay.cloudConfig.value.customURL == nil) }
            if let c = relay.cloudConfig.value.customURL { addressRow("Custom address (canonical)", c, canonical: true) }
            HStack {
                Picker("Zone", selection: $zone) {
                    Text(zones.isEmpty ? "Load your zones\u{2026}" : "Choose a zone").tag("")
                    ForEach(zones, id: \.name) { Text($0.name).tag($0.name) }
                }
                .onChange(of: zone) { _, z in if !z.isEmpty, hostname.isEmpty || !hostname.hasSuffix(z) { hostname = RelayCloudConfig.CustomDomain.suggestedHostname(zone: z) } }
                Button("Load zones") { run { zones = try await relay.relayZones().zones; if zones.isEmpty { message = "The token sees no zones." } } }
                    .disabled(busy || !relay.hasCloudflareToken)
            }
            TextField("Hostname, for example herald.example.com", text: $hostname).textFieldStyle(.roundedBorder)
            HStack {
                Button(current == nil ? "Set up custom domain" : "Apply again") {
                    run {
                        let r = try await relay.updateRelaySettings(["customDomain": .object(["zone": .string(zone), "hostname": .string(hostname)])])
                        message = r.redeployed ? "Done. The relay now answers on \(hostname) and this Mac uses it." : "Saved. Deploy the relay to apply it."
                        warnings = relay.lastDeployWarnings
                    }
                }.disabled(busy || zone.isEmpty || hostname.isEmpty || !relay.hasCloudflareToken)
                if current != nil {
                    Button("Use workers.dev again", role: .destructive) {
                        run { _ = try await relay.updateRelaySettings(["customDomain": .null]); message = "Back on the workers.dev address." }
                    }.disabled(busy)
                }
                if busy { ProgressView().controlSize(.small) }
            }
            ForEach(warnings, id: \.self) { Text($0).font(.caption).foregroundStyle(.orange).fixedSize(horizontal: false, vertical: true) }
            if let m = message { Text(m).font(.caption).foregroundStyle(.secondary).textSelection(.enabled) }
            Text("Needs a token with the Zone permissions (Zone: Read, DNS: Edit, Workers Routes: Edit, Zone Settings: Edit, Config Settings: Edit, Zone WAF: Edit): create one from the pre-filled token page.")
                .font(.caption2).foregroundStyle(.secondary)
        }
        .onAppear { zone = current?.zone ?? ""; hostname = current?.hostname ?? "" }
    }

    private func addressRow(_ title: String, _ url: String, canonical: Bool) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.caption).foregroundStyle(.secondary)
                Text(url).font(.system(.callout, design: .monospaced)).fontWeight(canonical ? .semibold : .regular).textSelection(.enabled)
            }
            Spacer()
            Button("Copy") { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(url, forType: .string) }
        }
    }

    private func run(_ work: @escaping () async throws -> Void) {
        busy = true; message = nil; warnings = []
        Task { defer { busy = false }; do { try await work() } catch { message = error.localizedDescription } }
    }
}

/// The banner row shown when the relay is paired but has no custom domain.
struct CustomDomainBanner: View {
    let setUp: () -> Void
    var body: some View {
        HStack {
            Image(systemName: "exclamationmark.triangle").foregroundStyle(.orange)
            Text("Cloud agents: send a custom User-Agent; or set up a custom domain to skip Cloudflare\u{2019}s browser check.").font(.caption)
            Spacer()
            Button("Set up\u{2026}", action: setUp)
        }
    }
}
