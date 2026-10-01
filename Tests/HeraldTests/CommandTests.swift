import XCTest
@testable import HeraldCore

final class CommandTests: XCTestCase {
    private var logURL: URL!

    override func setUp() {
        logURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("herald-cmdlog-\(UUID().uuidString)", isDirectory: true)
            .appendingPathComponent("commands.log")
    }

    override func tearDown() { try? FileManager.default.removeItem(at: logURL.deletingLastPathComponent()) }

    private let ctx = CommandContext(app: "bidbot", notificationId: "bid-42", action: "Archive")

    /// `-c` (no login profile) keeps the tests independent of the machine's zsh startup files.
    private func runner(timeout: TimeInterval = 10, outputLimit: Int = 64 * 1024, shell: String = "/bin/zsh") -> CommandRunner {
        CommandRunner(shell: shell, shellArguments: ["-c"], timeout: timeout, outputLimit: outputLimit,
                      log: CommandLog(url: logURL))
    }

    // Permission

    func testPermissionNeedsBothHalves() {
        func record(allow: Bool?, confirmed: Bool) -> AppRecord {
            AppRecord(registration: HeraldAppRegistration(app: "a", allowCommands: allow), commandsConfirmed: confirmed)
        }
        XCTAssertEqual(CommandPermission.evaluate(nil), .denied("this app has not registered with allowCommands"))
        XCTAssertEqual(CommandPermission.evaluate(record(allow: nil, confirmed: false)),
                       .denied("this app has not registered with allowCommands"))
        XCTAssertEqual(CommandPermission.evaluate(record(allow: false, confirmed: true)),
                       .denied("this app has not registered with allowCommands"))
        XCTAssertEqual(CommandPermission.evaluate(record(allow: true, confirmed: false)), .needsConfirmation)
        XCTAssertEqual(CommandPermission.evaluate(record(allow: true, confirmed: true)), .allowed)
    }

    func testRegistrationWithoutAllowCommandsRevokesTheConfirmation() {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("herald-reg-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }
        let reg = AppRegistry(file: dir.appendingPathComponent("apps.json"))
        reg.register(HeraldAppRegistration(app: "a", allowCommands: true))
        reg.update("a") { $0.commandsConfirmed = true }
        XCTAssertEqual(CommandPermission.evaluate(reg.record(for: "a")), .allowed)
        reg.register(HeraldAppRegistration(app: "a", allowCommands: false))
        XCTAssertEqual(CommandPermission.evaluate(reg.record(for: "a")), .denied("this app has not registered with allowCommands"))
    }

    // Running

    func testRunsAndCapturesOutput() async {
        let r = await runner().run("printf hello", context: ctx)
        XCTAssertTrue(r.succeeded)
        XCTAssertEqual(r.exitCode, 0)
        XCTAssertEqual(r.output, "hello")
        XCTAssertEqual(r.summary, "exit 0")
    }

    func testStderrIsCaptured() async {
        let r = await runner().run("echo oops 1>&2; exit 0", context: ctx)
        XCTAssertTrue(r.succeeded)
        XCTAssertEqual(r.output, "oops\n")
    }

    func testNonZeroExitIsAFailure() async {
        let r = await runner().run("echo nope; exit 3", context: ctx)
        XCTAssertFalse(r.succeeded)
        XCTAssertEqual(r.exitCode, 3)
        XCTAssertEqual(r.summary, "exit 3")
        XCTAssertEqual(r.output, "nope\n")
    }

    func testContextIsPassedInTheEnvironment() async {
        let r = await runner().run("printf '%s|%s|%s' \"$HERALD_APP\" \"$HERALD_NOTIFICATION_ID\" \"$HERALD_ACTION\"", context: ctx)
        XCTAssertEqual(r.output, "bidbot|bid-42|Archive")
    }

    func testRunsInTheUsersHomeDirectory() async {
        let r = await runner().run("pwd -P", context: ctx)
        let home = FileManager.default.homeDirectoryForCurrentUser.resolvingSymlinksInPath().path
        XCTAssertEqual(r.output.trimmingCharacters(in: .whitespacesAndNewlines), home)
    }

    func testTimeoutKillsTheCommand() async {
        let started = Date()
        let r = await runner(timeout: 0.5).run("sleep 20", context: ctx)
        XCTAssertTrue(r.timedOut)
        XCTAssertFalse(r.succeeded)
        XCTAssertEqual(r.summary, "timed out")
        XCTAssertLessThan(Date().timeIntervalSince(started), 8)
    }

    func testBackgroundedChildDoesNotHoldTheResultHostage() async {
        let started = Date()
        let r = await runner().run("(sleep 5 &) ; printf done", context: ctx)
        XCTAssertTrue(r.succeeded)
        XCTAssertEqual(r.output, "done")
        XCTAssertLessThan(Date().timeIntervalSince(started), 3, "must not wait for the background sleep")
    }

    func testOutputIsCapped() async {
        let r = await runner(outputLimit: 100).run("yes x | head -c 5000", context: ctx)
        XCTAssertTrue(r.truncated)
        XCTAssertEqual(r.output.utf8.count, 100)
    }

    func testMissingShellIsALaunchErrorNotACrash() async {
        let r = await runner(shell: "/nonexistent/zsh").run("true", context: ctx)
        XCTAssertFalse(r.succeeded)
        XCTAssertNotNil(r.launchError)
        XCTAssertTrue(r.summary.hasPrefix("could not start"))
    }

    func testDefaultShellIsAZshLoginShell() async {
        XCTAssertEqual(CommandRunner.defaultShell, "/bin/zsh")
        XCTAssertEqual(CommandRunner.defaultShellArguments, ["-lc"])
        let r = await CommandRunner(log: CommandLog(url: logURL)).run("printf ok", context: ctx)
        XCTAssertTrue(r.succeeded)
        XCTAssertTrue(r.output.hasSuffix("ok"), r.output)
    }

    // Log

    func testEveryRunIsLogged() async throws {
        let run = runner()
        _ = await run.run("printf first", context: ctx)
        _ = await run.run("echo boom; exit 2", context: CommandContext(app: "bidbot", notificationId: "bid-43", action: "Fail"))
        let text = try String(contentsOf: logURL, encoding: .utf8)
        XCTAssertTrue(text.contains("app=bidbot id=bid-42 action=\"Archive\" result=\"exit 0\""), text)
        XCTAssertTrue(text.contains("$ printf first"))
        XCTAssertTrue(text.contains("first\n---"))
        XCTAssertTrue(text.contains("id=bid-43 action=\"Fail\" result=\"exit 2\""))
        XCTAssertTrue(text.contains("boom"))
        XCTAssertEqual(text.components(separatedBy: "---\n").count - 1, 2)
    }

    func testEntryFormat() {
        let r = CommandResult(exitCode: 1, signaled: false, timedOut: false, launchError: nil,
                              output: "line", truncated: true, duration: 1.234)
        let e = CommandLog.entry(command: "do thing", context: ctx, result: r, at: Date(timeIntervalSince1970: 0))
        XCTAssertTrue(e.hasPrefix("1970-01-01T00:00:00.000Z app=bidbot id=bid-42 action=\"Archive\" result=\"exit 1\" duration=1.23s\n"), e)
        XCTAssertTrue(e.hasSuffix("$ do thing\nline\n[output truncated]\n---\n"), e)
    }

    func testLogRotatesToOneBackup() throws {
        let log = CommandLog(url: logURL, maxBytes: 200)
        let chunk = String(repeating: "x", count: 150) + "\n"
        log.append(chunk); log.append(chunk)   // 302 bytes: over the limit
        log.append("fresh\n")                  // rotates first
        let backup = logURL.appendingPathExtension("1")
        XCTAssertEqual(try String(contentsOf: logURL, encoding: .utf8), "fresh\n")
        XCTAssertEqual(try String(contentsOf: backup, encoding: .utf8), chunk + chunk)
        log.append(chunk); log.append(chunk); log.append("again\n")
        XCTAssertEqual(try String(contentsOf: logURL, encoding: .utf8), "again\n")
        XCTAssertTrue(FileManager.default.fileExists(atPath: backup.path))
    }

    func testDefaultLogLocation() {
        XCTAssertTrue(CommandLog.defaultURL.path.hasSuffix("/Library/Logs/Herald/commands.log"))
    }
}
