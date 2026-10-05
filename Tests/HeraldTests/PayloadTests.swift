import XCTest
@testable import HeraldCore

final class PayloadTests: XCTestCase {
    func testFullNotifyPayloadDecodes() throws {
        let json = """
        {"app":"bidbot","id":"bid-42","title":"Bid accepted","subtitle":"Acme RFP","body":"ok [Open](https://x)",
         "image":"/p.png","url":"https://x","sound":"default","persistent":true,"timeout":0,"priority":"high",
         "buttons":[{"label":"Open","url":"https://x"},{"label":"Mark done","callback":{"payload":{"bid":42}}},
                    {"label":"Archive","style":"destructive","command":"bidbot archive 42"}],
         "snooze":true,"reminder":{"title":"Follow up","due":"2026-10-02T09:00:00-04:00"},"metadata":{"any":"json"}}
        """
        let n = try HeraldJSON.decoder().decode(HeraldNotification.self, from: Data(json.utf8))
        XCTAssertEqual(n.app, "bidbot"); XCTAssertEqual(n.buttons?.count, 3)
        XCTAssertEqual(n.buttons?[1].callback?.payload, .object(["bid": .number(42)]))
        XCTAssertEqual(n.buttons?[2].style, "destructive")
        XCTAssertEqual(n.metadata, .object(["any": .string("json")]))
        XCTAssertEqual(n.snooze, true)
        let again = try HeraldJSON.decoder().decode(HeraldNotification.self, from: HeraldJSON.encoder().encode(n))
        XCTAssertEqual(again, n)
    }

    func testMinimalPayloadAndMissingTitle() throws {
        let n = try HeraldJSON.decoder().decode(HeraldNotification.self, from: Data("{\"app\":\"a\",\"title\":\"t\"}".utf8))
        XCTAssertNil(n.id); XCTAssertNil(n.buttons)
        XCTAssertThrowsError(try HeraldJSON.decoder().decode(HeraldNotification.self, from: Data("{\"app\":\"a\"}".utf8)))
    }

    func testRegistrationDecodes() throws {
        let json = """
        {"app":"bidbot","appName":"BidBot","icon":"data:image/png;base64,AAAA","bundleId":"com.x.bidbot",
         "callbackURL":"http://127.0.0.1:5123/herald","allowCommands":false,
         "defaults":{"sound":"Glass","persistent":true,"timeout":0,"corner":"topRight"}}
        """
        let r = try HeraldJSON.decoder().decode(HeraldAppRegistration.self, from: Data(json.utf8))
        XCTAssertEqual(r.defaults?.corner, .topRight); XCTAssertEqual(r.allowCommands, false)
    }

    func testISODateParsing() {
        XCTAssertNotNil(ISODate.parse("2026-10-02T09:00:00-04:00"))
        XCTAssertNotNil(ISODate.parse("2026-10-02T09:00:00.500Z"))
        XCTAssertNotNil(ISODate.parse("2026-10-02T09:00"))
        XCTAssertNotNil(ISODate.parse("2026-10-02"))
        XCTAssertNil(ISODate.parse("tomorrow"))
        XCTAssertEqual(ISODate.parse("2026-10-02T13:00:00Z"), ISODate.parse("2026-10-02T09:00:00-04:00"))
    }

    func testEffectiveSettings() {
        var reg = HeraldAppRegistration(app: "a")
        reg.defaults = HeraldAppDefaults(sound: "Ping", persistent: false, timeout: 0, corner: .bottomLeft)
        let rec = AppRecord(registration: reg)
        let e = EffectiveSettings.resolve(HeraldNotification(app: "a", title: "t"), rec)
        XCTAssertEqual(e.sound, "Ping"); XCTAssertEqual(e.timeout, 8); XCTAssertFalse(e.persistent); XCTAssertEqual(e.corner, .bottomLeft)
        let e2 = EffectiveSettings.resolve(HeraldNotification(app: "a", title: "t", sound: "none", persistent: true), rec)
        XCTAssertEqual(e2.sound, "none"); XCTAssertNil(e2.timeout); XCTAssertTrue(e2.persistent)
        let e3 = EffectiveSettings.resolve(HeraldNotification(app: "a", title: "t", timeout: 3), nil)
        XCTAssertEqual(e3.timeout, 3); XCTAssertEqual(e3.sound, "Glass"); XCTAssertEqual(e3.corner, .topRight)
    }

    func testRegistryMergeAndCommandGate() {
        let f = FileManager.default.temporaryDirectory.appendingPathComponent("apps-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: f) }
        let reg = AppRegistry(file: f)
        reg.register(HeraldAppRegistration(app: "a", appName: "A", allowCommands: true, defaults: HeraldAppDefaults(sound: "Ping")))
        reg.register(HeraldAppRegistration(app: "a", defaults: HeraldAppDefaults(timeout: 5)))
        var r = reg.record(for: "a")!
        XCTAssertEqual(r.registration.appName, "A"); XCTAssertEqual(r.registration.defaults?.sound, "Ping")
        XCTAssertEqual(r.registration.defaults?.timeout, 5)
        XCTAssertFalse(r.commandsAllowed)               // requested but not confirmed
        reg.update("a") { $0.commandsConfirmed = true }
        XCTAssertTrue(reg.record(for: "a")!.commandsAllowed)
        reg.register(HeraldAppRegistration(app: "a", allowCommands: false))
        r = reg.record(for: "a")!
        XCTAssertFalse(r.commandsAllowed); XCTAssertFalse(r.commandsConfirmed)
        XCTAssertEqual(AppRegistry(file: f).record(for: "a")?.registration.appName, "A")  // persisted
    }

    // MARK: Follow-up and script / shortcut buttons

    func testNotifyDecodesAFollowUpAndScriptAndShortcutButtons() throws {
        let json = """
        {"app":"a","title":"t","buttons":[{"label":"Log","script":"log.sh"},{"label":"Fwd","shortcut":"Forward","input":"{title}"}],
         "followUp":{"after":"10m","action":{"id":"f","label":"Forward","kind":"shortcut","shortcut":"Forward to phone"}}}
        """
        let n = try HeraldJSON.decoder().decode(HeraldNotification.self, from: Data(json.utf8))
        XCTAssertEqual(n.buttons?[0].script, "log.sh")
        XCTAssertEqual(n.buttons?[1].shortcut, "Forward"); XCTAssertEqual(n.buttons?[1].input, "{title}")
        XCTAssertEqual(n.followUp?.after, 600)
        XCTAssertNoThrow(try PayloadLimits.validate(n))
    }

    func testAFollowUpThatIsInvalidIsRefusedWith400() throws {
        func status(_ followUp: String) -> Int? {
            let n = try? HeraldJSON.decoder().decode(HeraldNotification.self, from: Data("{\"app\":\"a\",\"title\":\"t\",\"followUp\":\(followUp)}".utf8))
            guard let n else { return -1 }
            do { try PayloadLimits.validate(n); return 200 } catch let e as BackendError { return e.status } catch { return nil }
        }
        XCTAssertEqual(status("{\"after\":2,\"actionRef\":\"x\"}"), 400, "after below the minimum")
        XCTAssertEqual(status("{\"after\":60}"), 400, "no action")
        XCTAssertEqual(status("{\"after\":60,\"action\":{\"id\":\"u\",\"label\":\"Open\",\"kind\":\"url\",\"url\":\"https://x\"}}"), 400, "a url cannot follow up")
        XCTAssertEqual(status("{\"after\":60,\"action\":{\"id\":\"s\",\"label\":\"S\",\"kind\":\"script\",\"script\":\"../x.sh\"}}"), 400, "not a plain script name")
        XCTAssertEqual(status("{\"after\":60,\"actionRef\":\"x\"}"), 200)
        XCTAssertEqual(status("{\"enabled\":false}"), 200)
        XCTAssertThrowsError(try PayloadLimits.validate(HeraldNotification(app: "a", title: "t", followUp: HeraldFollowUp(after: 60, actionRef: "a",
            action: HeraldAction(id: "f", label: "F", kind: .callback))))) { error in
            XCTAssertEqual((error as? BackendError)?.status, 400)
            XCTAssertTrue((error as? BackendError)?.message.hasPrefix("followUp") == true)
        }
    }

    func testAButtonScriptMustBeAPlainFileName() throws {
        func validate(script: String) throws {
            var n = HeraldNotification(app: "a", title: "t")
            n.buttons = [HeraldButton(label: "L", script: script)]
            try PayloadLimits.validate(n)
        }
        XCTAssertNoThrow(try validate(script: "log.sh"))
        for bad in ["../log.sh", "/usr/bin/x", "a/b.sh"] {
            XCTAssertThrowsError(try validate(script: bad), bad) { XCTAssertEqual(($0 as? BackendError)?.status, 400) }
        }
    }

    func testScriptShortcutAndInputCountTowardTheSizeLimits() throws {
        let big = String(repeating: "x", count: PayloadLimits.maxSmallFieldBytes + 1)
        for button in [HeraldButton(label: "L", shortcut: big), HeraldButton(label: "L", shortcut: "S", input: big)] {
            var n = HeraldNotification(app: "a", title: "t")
            n.buttons = [button]
            XCTAssertThrowsError(try PayloadLimits.validate(n)) { XCTAssertEqual(($0 as? BackendError)?.status, 413) }
        }
    }
}
