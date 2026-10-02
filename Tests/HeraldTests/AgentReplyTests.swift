import XCTest
@testable import HeraldClient
@testable import HeraldCore
@testable import herald_mcp

/// The agent default's buttons (Open, Reply, Open link) and what they do: no two controls with one effect, "Open" is the host
/// application and never a URL, the host is detected from the environment the install ran in, and Reply works without a
/// callback server (inline field, History record, reply queue, `get_replies`, `wait_for_reply`).
final class AgentReplyTests: XCTestCase {
    var root: URL!
    var registry: AppRegistry!
    var manifests: ManifestStore!
    var templates: TemplateStore!
    var history: HistoryStore!
    var queue: ReplyQueue!
    var service: ParityService!

    final class Host: ParityHost, @unchecked Sendable {}

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("herald-reply-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        registry = AppRegistry(file: root.appendingPathComponent("apps.json"))
        manifests = ManifestStore(directory: root.appendingPathComponent("manifests"))
        templates = TemplateStore(directory: root.appendingPathComponent("templates"))
        history = HistoryStore(directory: root.appendingPathComponent("history"))
        queue = ReplyQueue(file: root.appendingPathComponent("replies.json"))
        service = ParityService(templates: templates, manifests: manifests, history: history, registry: registry,
                                assets: AssetStore(directory: root.appendingPathComponent("assets")),
                                approvals: TemplateCommandApprovals(file: root.appendingPathComponent("approvals.json")),
                                host: Host(), replies: queue)
    }

    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: root) }

    private func register(_ agent: AgentIdentity, opens: HeraldHostApp.Target? = nil, detectedHost: String? = nil) throws -> AgentIssuer.Report {
        try AgentIssuer.register(agent, iconPNG: nil, opens: opens, detectedHost: detectedHost, supportDirectory: root,
                                 registry: registry, manifests: manifests, templates: templates)
    }

    private func get(_ path: String, _ query: [String: String] = [:]) async -> [String: Any] {
        let r = await service.handle(HTTPRequest(method: "GET", path: path, query: query, headers: [:], body: Data()))
        XCTAssertEqual(r.status, 200, String(decoding: r.body, as: UTF8.self))
        return (try? JSONSerialization.jsonObject(with: r.body)) as? [String: Any] ?? [:]
    }

    private func deliver(_ app: String, _ id: String, title: String = "Question?") {
        history.upsert(HeraldHistoryItem(id: id, app: app, notification: HeraldNotification(app: app, id: id, title: title), deliveredAt: Date()))
    }

    // MARK: No duplicate effects

    func testAgentTemplateHasNoDuplicateEffectActions() throws {
        for kind in AgentIdentity.Kind.allCases {
            let agent = try XCTUnwrap(AgentIdentity(kind: kind, genericName: "Some Client"))
            let m = agent.manifest(), t = agent.template()
            XCTAssertEqual(agent.duplicateEffects(manifest: m, template: t), [], agent.appID)
            // No Done, no Dismiss anywhere: the close button is the one dismiss.
            let labels = m.actions.map { $0.label.lowercased() }
            XCTAssertFalse(labels.contains("dismiss") || labels.contains("done"), "\(labels)")
            XCTAssertEqual(m.actions.map(\.label), ["Open", "Reply", "Open link"])
            XCTAssertEqual(t.cells.compactMap { c -> HeraldAction? in c.component.inlineActions.first }.filter { $0.kind == .dismiss }.count, 1,
                           "exactly one dismiss control: the close button")
            XCTAssertTrue(t.actionRules.compactMap(\.add).isEmpty)
            // Layout: icon | title and body | status badge, then the buttons.
            XCTAssertEqual(t.cells.first { $0.id == "icon" }.map { ($0.row, $0.col) }.map { [$0.0, $0.1] }, [0, 0])
            XCTAssertEqual(t.cells.first { $0.id == "title" }?.col, 1)
            XCTAssertEqual(t.cells.first { $0.id == "status" }?.col, 2)
            XCTAssertEqual(t.cells.first { $0.id == "body" }?.row, 1)
            guard case .actions(let a)? = t.cells.first(where: { $0.id == "actions" })?.component else { return XCTFail("an actions row") }
            XCTAssertEqual(a.source, .merged)
        }
    }

    func testTheDuplicateCheckCatchesTheSameEffectTwice() throws {
        let agent = try XCTUnwrap(AgentIdentity(kind: .codex))
        var m = agent.manifest()
        m.actions.append(HeraldButton(label: "Done"))      // a second dismiss next to the close button
        XCTAssertEqual(agent.duplicateEffects(manifest: m, template: agent.template()), ["dismiss"])
        var m2 = agent.manifest()
        m2.actions.append(HeraldButton(label: "Open again", openApp: HeraldOpenApp()))
        XCTAssertEqual(agent.duplicateEffects(manifest: m2, template: agent.template()), ["openApp:"])
    }

    // MARK: Open

    func testOpenResolvesToTheConfiguredHostAppBundleId() throws {
        let desktop = try XCTUnwrap(AgentIdentity(kind: .claudeDesktop))
        XCTAssertEqual(desktop.manifest().appBundleId, "com.anthropic.claudefordesktop", "Claude Desktop opens Claude.app")
        let code = try XCTUnwrap(AgentIdentity(kind: .claudeCode)), codex = try XCTUnwrap(AgentIdentity(kind: .codex))
        XCTAssertEqual(code.manifest().appBundleId, "com.apple.Terminal", "no host detected: Terminal")
        _ = try register(code, detectedHost: "dev.warp.Warp-Stable")
        _ = try register(codex, detectedHost: "com.googlecode.iterm2")
        let m = try XCTUnwrap(manifests.get(app: code.appID))
        XCTAssertEqual(m.appBundleId, "dev.warp.Warp-Stable")
        XCTAssertEqual(manifests.get(app: codex.appID)?.appBundleId, "com.googlecode.iterm2")

        // The openApp action takes that id from the manifest: the first candidate, ahead of the registered id and the name.
        let open = ActionResolver.resolve(issuer: [m.actions[0]], ids: ["open"], rules: [])[0]
        XCTAssertEqual(open.kind, .openApp); XCTAssertNil(open.url, "Open never opens a URL")
        let cands = HeraldOpenAppResolver.candidates(bundleId: open.bundleId, path: open.path, manifest: m, registeredBundleId: nil, appName: nil)
        XCTAssertEqual(cands.first, .bundleId("dev.warp.Warp-Stable"))
        let found = HeraldOpenAppResolver.resolve(cands, lookup: HeraldAppLookup(bundleURL: { URL(fileURLWithPath: "/Applications/\($0).app") },
                                                                                  named: { _ in nil }, pathExists: { _ in nil }))
        XCTAssertEqual(found?.via, .bundleId("dev.warp.Warp-Stable"))
    }

    func testTheUsersChosenAppSurvivesReinstallAndAnExplicitChoiceWins() throws {
        let agent = try XCTUnwrap(AgentIdentity(kind: .claudeCode))
        _ = try register(agent, detectedHost: "com.googlecode.iterm2")
        // The user picks Ghostty in Settings > MCP.
        let picked = AgentIssuer.manifest(settingOpens: .bundleId("com.mitchellh.ghostty"), app: agent.appID, appName: agent.name,
                                          current: manifests.get(app: agent.appID))
        XCTAssertTrue(manifests.put(picked))
        _ = try register(agent, detectedHost: "dev.warp.Warp-Stable")
        XCTAssertEqual(manifests.get(app: agent.appID)?.appBundleId, "com.mitchellh.ghostty", "a reinstall keeps the user's app")
        let r = try register(agent, opens: .path("/Applications/Cursor.app"), detectedHost: "dev.warp.Warp-Stable")
        XCTAssertEqual(r.opens, .path("/Applications/Cursor.app"))
        XCTAssertEqual(manifests.get(app: agent.appID)?.appPath, "/Applications/Cursor.app")
        XCTAssertNil(manifests.get(app: agent.appID)?.appBundleId)
        XCTAssertEqual(AgentIdentity.opens(of: manifests.get(app: agent.appID)), .path("/Applications/Cursor.app"))
        XCTAssertEqual(HeraldHostApp.parseTarget("com.apple.Terminal"), .bundleId("com.apple.Terminal"))
        XCTAssertEqual(HeraldHostApp.parseTarget("/Applications/iTerm.app"), .path("/Applications/iTerm.app"))
        XCTAssertNil(HeraldHostApp.parseTarget("not a bundle"))
        XCTAssertNil(HeraldHostApp.parseTarget(""))
    }

    func testOpensIsAnAppSettingThatWritesTheManifest() async throws {
        let agent = try XCTUnwrap(AgentIdentity(kind: .codex))
        _ = try register(agent)
        let put = { (body: [String: Any]) async -> HTTPResponse in
            await self.service.handle(HTTPRequest(method: "PUT", path: "/v1/apps/settings", query: [:], headers: [:],
                                                  body: try! JSONSerialization.data(withJSONObject: body)))
        }
        let ok = await put(["app": agent.appID, "opens": "/Applications/Warp.app"])
        XCTAssertEqual(ok.status, 200, String(decoding: ok.body, as: UTF8.self))
        XCTAssertEqual(manifests.get(app: agent.appID)?.appPath, "/Applications/Warp.app")
        let bad = await put(["app": agent.appID, "opens": "https://example.com"])
        XCTAssertEqual(bad.status, 400)
        let listed = await get("/v1/apps/settings", ["app": agent.appID])
        let settings = ((listed["apps"] as? [[String: Any]])?.first?["settings"]) as? [String: Any]
        XCTAssertEqual(settings?["opens"] as? String, "/Applications/Warp.app")
    }

    // MARK: Detecting the terminal

    func testHostIsDetectedFromTheEnvironment() {
        let none: (String) -> String? = { _ in nil }
        func d(_ env: [String: String], ancestors: [String] = [], at: @escaping (String) -> String? = { _ in nil }) -> String {
            HeraldHostApp.detect(environment: env, ancestors: ancestors, bundleIDAt: at)
        }
        XCTAssertEqual(d(["TERM_PROGRAM": "iTerm.app"]), "com.googlecode.iterm2")
        XCTAssertEqual(d(["TERM_PROGRAM": "Apple_Terminal"]), "com.apple.Terminal")
        XCTAssertEqual(d(["TERM_PROGRAM": "WarpTerminal"]), "dev.warp.Warp-Stable")
        XCTAssertEqual(d(["TERM_PROGRAM": "ghostty"]), "com.mitchellh.ghostty")
        XCTAssertEqual(d(["TERM_PROGRAM": "vscode"]), "com.microsoft.VSCode")
        // Cursor also says vscode; its bundle id tells them apart, and it wins over TERM_PROGRAM.
        XCTAssertEqual(d(["TERM_PROGRAM": "vscode", "__CFBundleIdentifier": "com.todesktop.230313mzl4w4u92"]), "com.todesktop.230313mzl4w4u92")
        XCTAssertEqual(d(["TERM_PROGRAM": "iTerm.app", "__CFBundleIdentifier": "dev.warp.Warp-Stable"]), "dev.warp.Warp-Stable")
        // Herald's own bundle id is never "where the agent runs".
        XCTAssertEqual(d(["__CFBundleIdentifier": "com.ivg.herald", "TERM_PROGRAM": "ghostty"]), "com.mitchellh.ghostty")
        XCTAssertEqual(d(["__CFBundleIdentifier": "com.ivg.herald.mcp"]), "com.apple.Terminal")
        // Parent processes: the first one inside an .app names its bundle.
        let ids = ["/Applications/Warp.app": "dev.warp.Warp-Stable", "/Applications/iTerm.app": "com.googlecode.iterm2"]
        XCTAssertEqual(d([:], ancestors: ["/usr/bin/login", "/bin/zsh", "/Applications/iTerm.app/Contents/MacOS/iTerm2", "/sbin/launchd"],
                         at: { ids[$0] }), "com.googlecode.iterm2")
        XCTAssertEqual(HeraldHostApp.appBundlePath(inExecutable: "/Applications/Warp.app/Contents/MacOS/stable"), "/Applications/Warp.app")
        XCTAssertNil(HeraldHostApp.appBundlePath(inExecutable: "/bin/zsh"))
        // Nothing found: Terminal.app.
        XCTAssertEqual(d([:], ancestors: ["/bin/zsh"], at: none), "com.apple.Terminal")
        XCTAssertEqual(d(["TERM_PROGRAM": "SomethingNew"]), "com.apple.Terminal")
    }

    func testAnAncestorAppBundleIsReadFromItsInfoPlist() throws {
        let app = root.appendingPathComponent("Fake Term.app/Contents")
        try FileManager.default.createDirectory(at: app.appendingPathComponent("MacOS"), withIntermediateDirectories: true)
        try (["CFBundleIdentifier": "com.example.faketerm"] as NSDictionary).write(to: app.appendingPathComponent("Info.plist"))
        let exe = app.appendingPathComponent("MacOS/fake").path
        XCTAssertEqual(HeraldHostApp.detect(environment: [:], ancestors: ["/bin/zsh", exe]), "com.example.faketerm")
    }

    // MARK: Open link and the actions an agent offers

    func testOpenLinkAppearsOnlyWhenTheNotificationHasALink() throws {
        let agent = try XCTUnwrap(AgentIdentity(kind: .claudeCode))
        let m = agent.manifest()
        var n = HeraldNotification(app: agent.appID, title: "Done")
        n.actionIds = ["open", "reply", "open-link"]
        let without = ActionResolver.issuerSource(for: n, manifest: m)
        XCTAssertEqual(without.ids, ["open", "reply"], "no link: Open link collapses")
        n.metadata = .object(["link": .string("https://example.com/s/1")])
        let with = ActionResolver.issuerSource(for: n, manifest: m)
        XCTAssertEqual(with.ids, ["open", "reply", "open-link"])
        XCTAssertEqual(with.buttons[2].url, "https://example.com/s/1")
        // A sample preview has a sample link, so all three show.
        XCTAssertEqual(ActionResolver.sampleSource(manifest: m).ids, ["open", "reply", "open-link"])
        // Open never carries a URL.
        XCTAssertNil(with.buttons[0].url); XCTAssertNotNil(with.buttons[0].openApp)
    }

    // MARK: Reply action for any app

    func testAnIssuerManifestCanDeclareAReplyActionWithACallback() throws {
        let json = #"{"app":"acme.chat","actions":[{"id":"answer","label":"Answer","kind":"reply","placeholder":"Type an answer","callback":{"url":"http://127.0.0.1:9/cb"}}]}"#
        let m = try HeraldJSON.decoder().decode(HeraldManifest.self, from: Data(json.utf8))
        XCTAssertEqual(m.validationErrors(), [])
        let b = try XCTUnwrap(m.actions.first)
        XCTAssertEqual(b.reply?.placeholder, "Type an answer"); XCTAssertEqual(b.reply?.callback?.url, "http://127.0.0.1:9/cb")
        XCTAssertNil(b.callback, "the callback belongs to the reply")
        let again = try HeraldJSON.decoder().decode(HeraldManifest.self, from: try HeraldJSON.encoder().encode(m))
        XCTAssertEqual(again, m)
        let a = HeraldAction(button: b, id: "answer")
        XCTAssertEqual(a.kind, .reply)
        XCTAssertEqual(a.legacyButton?.reply, b.reply)
        // A bare action `{"kind":"reply"}` needs nothing else.
        let bare = try HeraldJSON.decoder().decode(HeraldAction.self, from: Data(#"{"label":"Reply","kind":"reply"}"#.utf8))
        XCTAssertEqual(bare.kind, .reply)
        let inferred = try HeraldJSON.decoder().decode(HeraldAction.self, from: Data(#"{"label":"Reply","reply":{"placeholder":"x"}}"#.utf8))
        XCTAssertEqual(inferred.kind, .reply)
        // The runner plans it as the inline field, and it needs no permission.
        let plan = ActionRunner().plan(a, origin: .issuer, invocation: ActionInvocation(notification: HeraldNotification(app: "acme.chat", title: "t"),
                                                                                        fields: [:], extra: [:], template: nil, imagePath: nil))
        XCTAssertEqual(try plan.get(), .reply(HeraldReply(placeholder: "Type an answer", callback: HeraldCallback(url: "http://127.0.0.1:9/cb"))))
        XCTAssertEqual(ActionRunner.gate(for: a, origin: .issuer), .open)
        // Declared in a template rule it validates too.
        var t = BuiltinTemplates.template(layout: .compact, app: "acme.chat")
        t.actionRules = [HeraldActionRule(add: HeraldAction(id: "r", label: "Reply", kind: .reply))]
        XCTAssertTrue(t.validate().filter(\.isError).isEmpty)
    }

    // MARK: Inline reply: History, the queue, wait_for_reply

    func testReplyIsStoredOnTheHistoryRecordAndInTheQueue() throws {
        deliver("agent.claude-code", "q1", title: "Ship it?")
        let at = Date(timeIntervalSince1970: 1_800_000_000)
        let r = try XCTUnwrap(ReplyRecorder.record(app: "agent.claude-code", id: "q1", text: "  yes, ship it  ", history: history, queue: queue, now: at))
        XCTAssertEqual(r.text, "yes, ship it"); XCTAssertEqual(r.title, "Ship it?")
        let item = try XCTUnwrap(history.item(app: "agent.claude-code", id: "q1"))
        XCTAssertEqual(item.reply, "yes, ship it"); XCTAssertEqual(item.repliedAt, at)
        XCTAssertEqual(queue.list(app: "agent.claude-code"), [r])
        // The record survives a reload of the store and of the queue.
        XCTAssertEqual(ReplyQueue(file: root.appendingPathComponent("replies.json")).list(), [r])
        // Nothing is stored for empty text or a notification that does not exist.
        XCTAssertNil(ReplyRecorder.record(app: "agent.claude-code", id: "q1", text: "   ", history: history, queue: queue))
        XCTAssertNil(ReplyRecorder.record(app: "agent.claude-code", id: "nope", text: "hi", history: history, queue: queue))
        XCTAssertEqual(queue.count, 1)
    }

    func testWaitForReplyReturnsTheReplyTypedLater() async throws {
        deliver("agent.codex", "q2")
        let history = self.history!, queue = self.queue!
        Task {
            try? await Task.sleep(nanoseconds: 400_000_000)
            ReplyRecorder.record(app: "agent.codex", id: "q2", text: "use the second option", history: history, queue: queue)
        }
        let started = Date()
        let o = await get("/v1/replies/wait", ["id": "q2", "app": "agent.codex", "timeout": "10"])
        XCTAssertEqual(o["replied"] as? Bool, true)
        XCTAssertEqual((o["reply"] as? [String: Any])?["text"] as? String, "use the second option")
        XCTAssertLessThan(Date().timeIntervalSince(started), 5, "returns when the reply arrives, not at the timeout")
        XCTAssertEqual(queue.count, 0, "wait_for_reply takes the reply out of the queue")
        // Asking again still answers (History keeps it).
        let again = await get("/v1/replies/wait", ["id": "q2", "app": "agent.codex", "timeout": "1"])
        XCTAssertEqual(again["replied"] as? Bool, true)
    }

    func testWaitForReplyTimesOutAndKeepsTheReplyWithConsumeFalse() async throws {
        deliver("agent.codex", "q3")
        let t = await get("/v1/replies/wait", ["id": "q3", "app": "agent.codex", "timeout": "1"])
        XCTAssertEqual(t["replied"] as? Bool, false); XCTAssertEqual(t["timedOut"] as? Bool, true)
        ReplyRecorder.record(app: "agent.codex", id: "q3", text: "later", history: history, queue: queue)
        let peek = await get("/v1/replies/wait", ["id": "q3", "app": "agent.codex", "consume": "false"])
        XCTAssertEqual(peek["replied"] as? Bool, true)
        XCTAssertEqual(queue.count, 1, "consume=false leaves it queued")
        let bad = await service.handle(HTTPRequest(method: "GET", path: "/v1/replies/wait", query: [:], headers: [:], body: Data()))
        XCTAssertEqual(bad.status, 400, "id is required")
    }

    func testGetRepliesFiltersAndConsumes() async throws {
        for (app, id) in [("agent.codex", "a"), ("agent.codex", "b"), ("agent.claude-code", "c")] { deliver(app, id) }
        let t0 = Date(timeIntervalSince1970: 1_800_000_000)
        ReplyRecorder.record(app: "agent.codex", id: "a", text: "one", history: history, queue: queue, now: t0)
        ReplyRecorder.record(app: "agent.codex", id: "b", text: "two", history: history, queue: queue, now: t0.addingTimeInterval(60))
        ReplyRecorder.record(app: "agent.claude-code", id: "c", text: "three", history: history, queue: queue, now: t0.addingTimeInterval(120))
        func texts(_ q: [String: String] = [:]) async -> [String] {
            let o = await get("/v1/replies", q)
            return (o["replies"] as? [[String: Any]])?.compactMap { $0["text"] as? String } ?? []
        }

        let r289 = await texts()
        XCTAssertEqual(r289, ["one", "two", "three"], "oldest first, every app")
        let r291 = await texts(["app": "agent.codex"])
        XCTAssertEqual(r291, ["one", "two"])
        let r293 = await texts()
        XCTAssertEqual(r293, ["one", "two", "three"], "reading does not consume")
        let r295 = await texts(["since": ISODate.string(from: t0.addingTimeInterval(30))])
        XCTAssertEqual(r295, ["two", "three"])
        let r297 = await texts(["since": String(t0.addingTimeInterval(90).timeIntervalSince1970)])
        XCTAssertEqual(r297, ["three"])
        // Consume takes exactly what it returned.
        let r300 = await texts(["app": "agent.codex", "consume": "true"])
        XCTAssertEqual(r300, ["one", "two"])
        let r302 = await texts(["app": "agent.codex"])
        XCTAssertEqual(r302, [])
        let r304 = await texts()
        XCTAssertEqual(r304, ["three"], "other apps keep theirs")
        XCTAssertEqual(history.item(app: "agent.codex", id: "a")?.reply, "one", "History still has it")
        let o = await get("/v1/replies", ["consume": "true"])
        XCTAssertEqual(o["count"] as? Int, 1)
        XCTAssertEqual(queue.count, 0)
        let bad = await service.handle(HTTPRequest(method: "GET", path: "/v1/replies", query: ["since": "yesterday-ish"], headers: [:], body: Data()))
        XCTAssertEqual(bad.status, 400)
    }

    func testTheQueueKeepsAtMostTwoHundredPerApp() {
        for i in 0..<(ReplyQueue.capPerApp + 5) {
            queue.add(HeraldReplyRecord(notificationId: "n\(i)", app: "a", text: "t\(i)", repliedAt: Date(timeIntervalSince1970: Double(i))))
        }
        queue.add(HeraldReplyRecord(notificationId: "x", app: "b", text: "other", repliedAt: Date()))
        XCTAssertEqual(queue.list(app: "a").count, ReplyQueue.capPerApp)
        XCTAssertEqual(queue.list(app: "a").first?.notificationId, "n5", "the oldest were dropped")
        XCTAssertEqual(queue.list(app: "b").count, 1)
        XCTAssertEqual(ReplyQueue.clean(String(repeating: "é", count: 5000))?.utf8.count ?? 0, ReplyQueue.maxTextBytes)
    }

    // MARK: Upgrading an installed agent

    func testAnUntouchedOldTemplateIsUpgradedAndAnEditedOneIsNot() throws {
        let agent = try XCTUnwrap(AgentIdentity(kind: .claudeCode))
        _ = try register(agent)
        XCTAssertTrue(templates.put(agent.previousTemplate()), "an install made before the fix")
        var oldManifest = agent.manifest()
        oldManifest.actions = [HeraldButton(label: "Open", url: agent.homepage), HeraldButton(label: "Reply", callback: HeraldCallback()), HeraldButton(label: "Dismiss")]
        oldManifest.actionIDs = ["open", "reply", "dismiss"]; oldManifest.appBundleId = nil
        XCTAssertTrue(manifests.put(oldManifest))
        let changed = AgentIssuer.refreshInstalled(supportDirectory: root, registry: registry, manifests: manifests, templates: templates,
                                                   detectedHost: "dev.warp.Warp-Stable")
        XCTAssertEqual(changed, [agent.appID])
        XCTAssertEqual(templates.get(app: agent.appID, name: "agent"), agent.template())
        let m = try XCTUnwrap(manifests.get(app: agent.appID))
        XCTAssertEqual(m.actions.map(\.label), ["Open", "Reply", "Open link"])
        XCTAssertEqual(m.appBundleId, "dev.warp.Warp-Stable")

        var mine = agent.template(); mine.accentColor = "#FF8800"
        XCTAssertTrue(templates.put(mine))
        XCTAssertEqual(AgentIssuer.refreshInstalled(supportDirectory: root, registry: registry, manifests: manifests, templates: templates), [])
        XCTAssertEqual(templates.get(app: agent.appID, name: "agent"), mine)
        // An app that is not an agent is never touched.
        XCTAssertTrue(manifests.put(HeraldManifest(app: "agent.rogue", family: "other")))
        XCTAssertEqual(AgentIssuer.refreshInstalled(supportDirectory: root, registry: registry, manifests: manifests, templates: templates), [])
    }

    // MARK: herald-mcp

    func testAnAgentNotificationWithoutButtonsGetsOpenReplyAndOpenLink() async throws {
        let rec = try ParityToolTests.Recorder()
        defer { rec.stop() }
        let tools = MCPTools(client: HeraldClient(supportDirectory: rec.directory), previewDirectory: rec.directory, defaultApp: "agent.codex")
        _ = try await tools.call("send_notification", arguments: .object(["title": .string("Which branch?"), "persistent": .bool(true)]))
        XCTAssertEqual(rec.calls.last?.body?["actionIds"]?.arrayValue?.compactMap(\.stringValue), ["open", "reply", "open-link"])
        // Its own buttons are left alone, and other apps get nothing added.
        _ = try await tools.call("send_notification", arguments: .object(["title": .string("x"), "buttons": .array([.object(["label": .string("Go"), "url": .string("https://example.com")])])]))
        XCTAssertNil(rec.calls.last?.body?["actionIds"])
        _ = try await tools.call("send_notification", arguments: .object(["app": .string("webwatcher.web"), "title": .string("x")]))
        XCTAssertNil(rec.calls.last?.body?["actionIds"])
    }

    func testInstallMcpPassesTheDetectedHostAndTheChosenApp() async throws {
        let rec = try ParityToolTests.Recorder()
        defer { rec.stop() }
        let tools = MCPTools(client: HeraldClient(supportDirectory: rec.directory), previewDirectory: rec.directory,
                             hostDetector: { "com.googlecode.iterm2" })
        _ = try await tools.call("install_mcp", arguments: .object(["client": .string("claudeCode"), "opens": .string("com.apple.Terminal")]))
        let body = try XCTUnwrap(rec.calls.last?.body)
        XCTAssertEqual(body["detectedHost"]?.stringValue, "com.googlecode.iterm2")
        XCTAssertEqual(body["opens"]?.stringValue, "com.apple.Terminal")
        _ = try await tools.call("install_mcp", arguments: .object([:]))
        XCTAssertEqual(rec.calls.last?.method, "GET", "the status call carries no hint")
    }

    func testGetRepliesAndWaitForReplyToolsAskForTheRoutes() async throws {
        let rec = try ParityToolTests.Recorder()
        defer { rec.stop() }
        let tools = MCPTools(client: HeraldClient(supportDirectory: rec.directory), previewDirectory: rec.directory, defaultApp: "agent.codex")
        _ = try await tools.call("get_replies", arguments: .object(["since": .string("2026-10-02T10:00:00Z"), "consume": .bool(true)]))
        var c = try XCTUnwrap(rec.calls.last)
        XCTAssertEqual(c.path, "/v1/replies"); XCTAssertEqual(c.query["app"], "agent.codex"); XCTAssertEqual(c.query["consume"], "true")
        XCTAssertEqual(c.query["since"], "2026-10-02T10:00:00Z")
        _ = try await tools.call("wait_for_reply", arguments: .object(["notificationId": .string("n1"), "timeoutSeconds": .number(900)]))
        c = try XCTUnwrap(rec.calls.last)
        XCTAssertEqual(c.path, "/v1/replies/wait"); XCTAssertEqual(c.query["id"], "n1"); XCTAssertEqual(c.query["timeout"], "300", "at most 300 s")
        XCTAssertEqual(c.query["app"], "agent.codex")
        let missing = try await tools.call("wait_for_reply", arguments: .object([:]))
        XCTAssertTrue(missing.isError)
    }
}

/// Issue: the actions row honours its alignment (its own `align`, else the cell's horizontal alignment).
final class ActionsAlignmentTests: XCTestCase {
    func testCellAlignmentIsTheDefaultAndTheComponentsOwnWins() {
        var a = HeraldActionsComponent()
        XCTAssertEqual(a.effectiveAlign(in: .topTrailing), .trailing)
        XCTAssertEqual(a.effectiveAlign(in: .bottom), .center)
        XCTAssertEqual(a.effectiveAlign(in: .leading), .leading)
        a.align = .spaceBetween
        XCTAssertEqual(a.effectiveAlign(in: .trailing), .spaceBetween)
        a.align = .leading
        XCTAssertEqual(a.effectiveAlign(in: .trailing), .leading)
    }

    func testTrailingButtonsEndAtTheCellsRightEdge() {
        // A merged cell 332 pt wide (380 - 2 x 12 padding - gaps already removed): Open, Reply, Open link.
        let sizes = [CGSize(width: 62, height: 24), CGSize(width: 58, height: 24), CGSize(width: 84, height: 24)]
        for wrap in [true, false] {
            let r = ActionRowMath.arrange(sizes: sizes, width: 332, spacing: 6, lineSpacing: 6, wrap: wrap, align: .trailing)
            XCTAssertEqual(r.frames.last?.maxX, 332, "wrap \(wrap): the last button's right edge is the cell's")
            XCTAssertEqual(r.size.width, 332)
            let c = ActionRowMath.arrange(sizes: sizes, width: 332, spacing: 6, lineSpacing: 6, wrap: wrap, align: .center)
            XCTAssertEqual((c.frames.first!.minX + c.frames.last!.maxX) / 2, 166, accuracy: 0.01)
            let sb = ActionRowMath.arrange(sizes: sizes, width: 332, spacing: 6, lineSpacing: 6, wrap: wrap, align: .spaceBetween)
            XCTAssertEqual(sb.frames.first?.minX, 0); XCTAssertEqual(sb.frames.last?.maxX, 332)
        }
    }
}
