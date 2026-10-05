#if DEBUG
import SwiftUI
import AppKit
import HeraldClient

/// Sample data for the documentation screenshots. Placeholder names and hosts only: nothing here comes from a real history,
/// account or relay.
@MainActor
extension ScreenshotMode {
    static let ciApp = "ci"
    static let ciTemplate = "Build status"

    static func seed(_ c: AppController) {
        _ = try? AgentIssuer.register(AgentIdentity(kind: .claudeCode)!, iconPNG: nil, supportDirectory: c.supportDirectory,
                                      registry: c.registry, manifests: c.manifests, templates: c.templates)
        _ = try? AgentIssuer.register(AgentIdentity(kind: .codex)!, iconPNG: nil, supportDirectory: c.supportDirectory,
                                      registry: c.registry, manifests: c.manifests, templates: c.templates)
        _ = try? AgentIssuer.register(AgentIdentity(cloudKeyName: "build-bot", client: "claude", clientName: "Claude (build-bot)")!, iconPNG: nil,
                                      supportDirectory: c.supportDirectory, registry: c.registry, manifests: c.manifests, templates: c.templates)
        for (app, name) in [("vercel", "Vercel"), ("calendar", "Calendar"), ("web-watcher", "Web Watcher"), (ciApp, "GitHub Actions")] {
            c.registry.register(HeraldAppRegistration(app: app, appName: name))
        }
        _ = AutoIcon.applyToIconless(registry: c.registry, supportDirectory: c.supportDirectory)
        AppIcons.invalidate()

        // The "ci" issuer: fields, three issuer actions and a template with several cells.
        let manifest = HeraldManifest(
            app: ciApp, appName: "GitHub Actions",
            fields: [HeraldField(key: "title", type: .text, sample: .text("Build failed")),
                     HeraldField(key: "subtitle", type: .text, sample: .text("herald-relay \u{00B7} main")),
                     HeraldField(key: "body", type: .text, sample: .text("Step 'lint' exited with code 1 after 3 min 12 s.")),
                     HeraldField(key: "branch", type: .text, sample: .text("main")),
                     HeraldField(key: "commit", type: .text, sample: .text("a1f94c2")),
                     HeraldField(key: "duration", type: .number, sample: .number(192)),
                     HeraldField(key: "url", type: .url, sample: .text("https://ci.example.com/runs/4821"))],
            actions: [HeraldButton(label: "Open log", url: "{url}"),
                      HeraldButton(label: "Deploy", style: "destructive", callback: HeraldCallback(url: "https://ci.example.com/hooks/deploy")),
                      HeraldButton(label: "Dismiss", style: "cancel")],
            actionIDs: ["open-log", "deploy", "dismiss"], defaultTemplate: ciTemplate)
        _ = try? c.putManifest(manifest)
        var t = BuiltinTemplates.template(layout: .imageLeft, app: ciApp, accentColor: "#2F7DF6", hasImage: false)
        t.name = ciTemplate
        _ = try? c.putTemplate(t)

        // Two sample scripts for Settings > Actions.
        let dir = c.actionRunner.scriptsDirectory
        c.actionRunner.ensureScriptsDirectory()
        for (name, body) in [("archive-logs.sh", "#!/bin/zsh\n# Reads the notification JSON on stdin.\ntar czf ~/Archive/logs.tgz ~/Logs\n"),
                             ("post-to-channel.py", "#!/usr/bin/env python3\nimport json, sys\nn = json.load(sys.stdin)\nprint(n[\"title\"])\n")] {
            let f = dir.appendingPathComponent(name)
            try? body.write(to: f, atomically: true, encoding: .utf8)
            try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: f.path)
        }

        // A Kokoro voice that looks installed (empty stand-in files in the sandboxed support folder; nothing is ever run).
        let tts = KokoroLayout(supportDirectory: c.supportDirectory)
        try? FileManager.default.createDirectory(at: tts.python.deletingLastPathComponent(), withIntermediateDirectories: true)
        for f in [tts.model, tts.voices, tts.environmentMarker] { try? Data().write(to: f) }
        try? "#!/bin/sh\nexit 1\n".write(to: tts.python, atomically: true, encoding: .utf8)
        try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: tts.python.path)

        seedHistory(c)
        // Quiet hours (the real Herald shares these defaults while the run lasts; Mon-Fri nights only, restored at the end).
        AppSettings.shared.quiet.windows = [QuietWindow(days: ["mon", "tue", "wed", "thu", "fri"], start: "22:30", end: "07:30",
                                                        speech: true, sounds: true, banners: false, speakSummary: true)]
    }

    /// The sample History (also put back after the banner shots, which add notifications of their own).
    static func seedHistory(_ c: AppController) {
        for app in c.history.apps() { c.history.clear(app: app) }
        let now = Date()
        func item(_ app: String, _ title: String, _ sub: String?, _ body: String?, _ minutesAgo: Double) -> HeraldHistoryItem {
            let id = UUID().uuidString
            let n = HeraldNotification(app: app, id: id, title: title, subtitle: sub, body: body)
            return HeraldHistoryItem(id: id, app: app, notification: n, deliveredAt: now.addingTimeInterval(-minutesAgo * 60))
        }
        c.history.upsert(contentsOf: [
            item("vercel", "Deploy finished", "herald-web \u{00B7} production", "Built in 42 s, no warnings.", 3),
            item("agent.claude-code", "Tests pass", "herald", "All 412 tests passed after the banner refactor. Ready for review.", 9),
            item("web-watcher", "Price dropped", "Studio monitor", "Now $289, was $329.", 21),
            item("calendar", "Design review in 10 minutes", "Room 4B", nil, 34),
            item(ciApp, "Build failed", "herald-relay \u{00B7} main", "Step 'lint' exited with code 1.", 58),
            item("agent.codex", "Refactor done", "relay", "Moved the socket handling into its own module. 3 files changed.", 95),
            item("cloud.build-bot", "Migration finished", nil, "All 14 tables migrated. Want me to open the pull request?", 130),
            item("vercel", "Preview ready", "herald-web \u{00B7} gmail-section", "https://example.com/preview", 190),
            item("web-watcher", "Page changed", "Release notes", "A new section was added: 'Known issues'.", 260),
            item(ciApp, "Build passed", "herald \u{00B7} main", "Finished in 3 min 12 s.", 400),
            item("calendar", "Standup", "Starts at 9:30", nil, 1_300),
            item("agent.claude-code", "Needs your input", "herald", "Should the relay keep receipts for 7 or 30 days?", 1_500),
        ])
        c.changed()
    }

    /// Designer edits that give the Actions tab its look; saved, so the window shows no unsaved mark.
    static func styleCiTemplate(_ m: DesignerModel) {
        m.setActionShows("open-log", .iconAndText)
        var s = HeraldSymbol(name: "arrow.up.circle"); s.placement = .only
        m.setActionSymbol("deploy", symbol: s)
        var req = m.newActionRequest(kind: .shortcut)
        req.action.label = "Post to Slack"
        req.action.shortcut = "Post build status"
        m.commitActionEditor(req)
        _ = m.save()
    }

    static func sampleRelay(_ c: AppController) {
        let iso = ISO8601DateFormatter()
        let keys = [
            RelayKeyInfo(id: "key_1", name: "build-bot", client: "claude", scope: "notify", kind: "static", displayName: nil,
                         createdAt: iso.string(from: Date().addingTimeInterval(-86_400 * 9)), lastUsedAt: iso.string(from: Date().addingTimeInterval(-600)), revokedAt: nil),
            RelayKeyInfo(id: "key_2", name: "chatgpt", client: "codex", scope: "notify", kind: "oauth", displayName: "ChatGPT",
                         createdAt: iso.string(from: Date().addingTimeInterval(-86_400 * 3)), lastUsedAt: iso.string(from: Date().addingTimeInterval(-3_600)), revokedAt: nil),
        ]
        let usage = RelayUsage(day: "2026-10-04", requests: 1_284, wsMessages: 310, notifications: 42, pollSeconds: 0, audioUploads: 3,
                               audioBytes: 412_000, queued: 0, storageBytes: 1_380_000, requestsPercent: 1, budgetExhausted: false)
        let events = RelayEvents(subscriptions: [
            .init(id: "sub_1", event: "reply", host: "connectors.api.openai.com", key: .init(id: "key_2", name: "chatgpt", displayName: "ChatGPT"),
                  createdAt: iso.string(from: Date().addingTimeInterval(-7_200)), pending: 0)])
        let pending = RelayConsent(id: "consent_1", clientId: "client_1", clientName: "Claude Desktop", redirectHost: "claude.ai", code: "482915",
                                   status: "pending", createdAt: iso.string(from: Date()), expiresAt: iso.string(from: Date().addingTimeInterval(600)), flow: "code")
        func entry(_ id: String, _ key: String, _ title: String, _ minutes: Double, displayed: Bool = true, spoken: Bool = false, replied: Bool = false) -> RelayLogEntry {
            RelayLogEntry(id: id, key: key, title: title, receivedAt: Date().addingTimeInterval(-minutes * 60), displayed: displayed, spoken: spoken, replied: replied, suppressed: nil, duplicate: false)
        }
        c.relay.debugInstallSample(url: "https://herald-relay.example.workers.dev", keys: keys, usage: usage, events: events, consents: [pending],
                                   log: [entry("d5", "build-bot", "Tests pass on main", 4, spoken: true), entry("d4", "chatgpt", "Summary is ready", 22, replied: true),
                                         entry("d3", "build-bot", "Migration finished", 71), entry("d2", "chatgpt", "Reminder: review the draft", 130),
                                         entry("d1", "build-bot", "Deploy needs approval", 190)])
    }
}
#endif
