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
}
