import XCTest
@testable import HeraldCore

/// Approval of a callback host is per host: an app that registers a different `callbackURL` host loses the
/// approval it had, so the user is asked again (#27).
final class CallbackApprovalResetTests: XCTestCase {
    var dir: URL!
    var file: URL { dir.appendingPathComponent("apps.json") }
    override func setUp() { dir = FileManager.default.temporaryDirectory.appendingPathComponent("herald-cb-\(UUID().uuidString)") }
    override func tearDown() { try? FileManager.default.removeItem(at: dir) }

    private func approvedApp(host: String = "hooks.example") -> AppRegistry {
        let reg = AppRegistry(file: file)
        reg.register(HeraldAppRegistration(app: "a", callbackURL: "https://\(host)/cb"))
        reg.update("a") { $0.callbackHostApproved = host }
        return reg
    }

    func testRegisteringADifferentHostClearsTheApproval() {
        let reg = approvedApp()
        let rec = reg.register(HeraldAppRegistration(app: "a", callbackURL: "https://other.example/cb"))
        XCTAssertNil(rec.callbackHostApproved)
        XCTAssertEqual(rec.registeredCallbackHost, "other.example")
        XCTAssertNil(reg.record(for: "a")?.callbackHostApproved)
        XCTAssertNil(AppRegistry(file: file).record(for: "a")?.callbackHostApproved, "and it stays cleared after a relaunch")
    }

    func testTheSameHostKeepsTheApprovalWhateverThePathPortSchemeOrCase() {
        let reg = approvedApp()
        for url in ["https://hooks.example/cb", "https://hooks.example/another/path", "http://hooks.example:9000/x", "https://HOOKS.Example/cb"] {
            let rec = reg.register(HeraldAppRegistration(app: "a", callbackURL: url))
            XCTAssertEqual(rec.callbackHostApproved, "hooks.example", url)
        }
        XCTAssertEqual(AppRegistry(file: file).record(for: "a")?.callbackHostApproved, "hooks.example")
    }

    func testARegistrationWithoutACallbackURLKeepsTheApproval() {
        let reg = approvedApp()
        let rec = reg.register(HeraldAppRegistration(app: "a", appName: "Renamed", allowCommands: true))
        XCTAssertEqual(rec.callbackHostApproved, "hooks.example")
        XCTAssertEqual(rec.registeredCallbackHost, "hooks.example")
    }

    func testMovingTheCallbackToLoopbackDropsTheStaleApproval() {
        let reg = approvedApp()
        let rec = reg.register(HeraldAppRegistration(app: "a", callbackURL: "http://127.0.0.1:8080/cb"))
        XCTAssertNil(rec.callbackHostApproved)
    }

    func testClearingTheCallbackURLDropsTheApproval() {
        let reg = approvedApp()
        let rec = reg.register(HeraldAppRegistration(app: "a", callbackURL: ""))
        XCTAssertNil(rec.registeredCallbackHost)
        XCTAssertNil(rec.callbackHostApproved)
    }

    func testAnApprovalThatAlreadyNamesTheNewHostIsKept() {
        // Approved earlier for a button that names its own URL; now the app registers the same host.
        let reg = AppRegistry(file: file)
        reg.register(HeraldAppRegistration(app: "a", callbackURL: "https://first.example/cb"))
        reg.update("a") { $0.callbackHostApproved = "second.example" }
        let rec = reg.register(HeraldAppRegistration(app: "a", callbackURL: "https://second.example/cb"))
        XCTAssertEqual(rec.callbackHostApproved, "second.example")
    }

    func testFirstRegistrationOfAHostDoesNotInventAnApproval() {
        let reg = AppRegistry(file: file)
        let rec = reg.register(HeraldAppRegistration(app: "new", callbackURL: "https://hooks.example/cb"))
        XCTAssertNil(rec.callbackHostApproved)
    }

    func testOtherAppsAndOtherApprovalsAreUntouched() {
        let reg = approvedApp()
        reg.register(HeraldAppRegistration(app: "b", callbackURL: "https://hooks.example/cb"))
        reg.update("b") { $0.callbackHostApproved = "hooks.example"; $0.commandsConfirmed = true }
        reg.register(HeraldAppRegistration(app: "a", callbackURL: "https://other.example/cb"))
        XCTAssertEqual(reg.record(for: "b")?.callbackHostApproved, "hooks.example")
        XCTAssertTrue(reg.record(for: "b")?.commandsConfirmed ?? false)
    }

    func testReRegisteringWithDefaultsOnlyChangesNothingAboutApproval() {
        let reg = approvedApp()
        let rec = reg.register(HeraldAppRegistration(app: "a", defaults: HeraldAppDefaults(sound: "Ping")))
        XCTAssertEqual(rec.callbackHostApproved, "hooks.example")
        XCTAssertEqual(rec.registration.defaults?.sound, "Ping")
    }
}
