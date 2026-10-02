import SwiftUI
import AppKit

/// "Create your relay on Cloudflare (free)": open Cloudflare's pre-filled token page, paste the token, Deploy. Herald does the rest
/// through the Cloudflare API and shows each step; a failure shows Cloudflare's own message and Retry.
struct DeployRelaySheet: View {
    let controller: AppController
    @Binding var isPresented: Bool
    @StateObject private var ticker = ChangeTicker()
    @State private var token = ""
    @State private var error: String?
    @State private var finished = false

    private var relay: RelayController { controller.relay }

    var body: some View {
        let _ = ticker.tick
        VStack(alignment: .leading, spacing: 14) {
            Text("Create your relay on Cloudflare (free)").font(.title3.bold())
            Text("Herald puts a small relay in your own Cloudflare account, so a cloud agent such as ChatGPT can notify this Mac. Nobody else's server is involved, and nothing listens on this Mac.")
                .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)

            if relay.hasCloudflareToken && !relay.deployRunning && !finished && relay.deployEvents.isEmpty {
                Label("A Cloudflare token is saved on this Mac.", systemImage: "checkmark.seal").font(.callout)
            } else if !relay.deployRunning && !finished {
                VStack(alignment: .leading, spacing: 8) {
                    Text("1. Create a token").font(.headline)
                    Text("Cloudflare opens with the permissions already filled in (Workers Scripts: Edit, Workers R2 Storage: Edit, Account Settings: Read) and the name \u{201C}Herald relay\u{201D}. Press Continue to summary, then Create Token, and copy it.")
                        .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    HStack {
                        Button("Open Cloudflare\u{2026}") { NSWorkspace.shared.open(CloudflareLinks.prefilledTokenURL()) } .heraldHelp(.cloudOpenToken)
                        Button("I need a free Cloudflare account\u{2026}") { NSWorkspace.shared.open(CloudflareLinks.signUp) } .heraldHelp(.cloudSignUp)
                    }
                    Text("2. Paste it here").font(.headline)
                    SecureField("Cloudflare API token", text: $token).textFieldStyle(.roundedBorder) .heraldHelp(.cloudToken)
                    Text("It is kept in this Mac's Keychain and only ever sent to api.cloudflare.com.").font(.caption).foregroundStyle(.secondary)
                }
            }

            if !relay.deployEvents.isEmpty { stepsList }
            if let e = error ?? relay.deployFailure, !finished {
                Text(e).font(.callout).foregroundStyle(.red).textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
            }
            if finished {
                Label("Your relay is online. Close this to connect an agent.", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
            }

            HStack {
                Spacer()
                if finished {
                    Button("Done") { isPresented = false }.keyboardShortcut(.defaultAction)
                } else {
                    Button("Cancel") { isPresented = false }.disabled(relay.deployRunning)
                    Button(error != nil || relay.deployFailure != nil ? "Retry" : "Deploy") { deploy() }
                        .keyboardShortcut(.defaultAction)
                        .disabled(relay.deployRunning || (token.trimmingCharacters(in: .whitespaces).isEmpty && !relay.hasCloudflareToken))
                        .heraldHelp(.cloudDeploy)
                }
            }
        }
        .padding(20).frame(width: 520)
    }

    private var stepsList: some View {
        VStack(alignment: .leading, spacing: 5) {
            ForEach(Array(relay.deployEvents.enumerated()), id: \.offset) { _, e in
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    switch e.phase {
                    case .started: ProgressView().controlSize(.small)
                    case .done: Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                    case .failed: Image(systemName: "xmark.octagon.fill").foregroundStyle(.red)
                    }
                    VStack(alignment: .leading, spacing: 1) {
                        Text(e.step.title)
                        if !e.detail.isEmpty { Text(e.detail).font(.caption).foregroundStyle(.secondary).textSelection(.enabled) }
                    }
                }
            }
            if relay.deployRunning && relay.deployEvents.last?.phase == .done {
                HStack(spacing: 8) { ProgressView().controlSize(.small); Text("Working\u{2026}").foregroundStyle(.secondary) }
            }
        }
        .padding(10).frame(maxWidth: .infinity, alignment: .leading).background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 8))
    }

    private func deploy() {
        error = nil
        Task {
            do {
                let t = token.trimmingCharacters(in: .whitespacesAndNewlines)
                if !t.isEmpty { try await relay.setCloudflareToken(t); token = "" }
                _ = try await relay.deployRelay()
                finished = true
            } catch { self.error = error.localizedDescription }
        }
    }
}
