import XCTest
@testable import HeraldCore

/// A backend wired to a real ManifestStore and a ShortcutsCatalog, mirroring the manifest and shortcuts
/// parts of AppController, so the router tests cover the whole path from HTTP to disk.
final class ManifestBackend: HeraldBackend, @unchecked Sendable {
    let store: ManifestStore
    let catalog: ShortcutsCatalog
    var notified: [HeraldNotification] = []
    init(store: ManifestStore, catalog: ShortcutsCatalog) { self.store = store; self.catalog = catalog }

    func notify(_ n: HeraldNotification) async throws -> String { notified.append(n); return n.id ?? "gen" }
    func register(_ r: HeraldAppRegistration) async throws {}
    func dismiss(app: String, id: String) async throws {}
    func dismissAll(app: String?) async throws {}
    func history(app: String?, limit: Int) async throws -> [HeraldHistoryItem] { [] }
    func clearHistory(app: String?) async throws {}
    func apps() async throws -> [HeraldAppRegistration] { [] }

    func manifests() async throws -> [HeraldManifest] { store.list() }
    func manifest(app: String) async throws -> HeraldManifest? { store.get(app: app) }
    func putManifest(_ m: HeraldManifest) async throws {
        guard store.hasRoom(for: m.app) else { throw BackendError(429, "too many manifests") }
        guard store.put(m) else { throw BackendError(500, "could not save manifest") }
    }
    func deleteManifest(app: String) async throws {
        guard store.delete(app: app) else { throw BackendError(404, "manifest not found") }
    }
    func shortcuts() async throws -> [String] {
        do { return try await catalog.names() }
        catch let e as ShortcutsError {
            if case .timedOut = e { throw BackendError(504, e.localizedDescription) }
            throw BackendError(502, e.localizedDescription)
        }
    }
}

/// Counts calls from a `@Sendable` closure.
private final class ManifestTestCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var n = 0
    var value: Int { lock.lock(); defer { lock.unlock() }; return n }
    @discardableResult func bump() -> Int { lock.lock(); defer { lock.unlock() }; n += 1; return n }
}

/// A clock a test can move.
private final class ManifestTestClock: @unchecked Sendable {
    private let lock = NSLock()
    private var t = Date(timeIntervalSince1970: 1_800_000_000)
    var now: Date { lock.lock(); defer { lock.unlock() }; return t }
    func advance(_ s: TimeInterval) { lock.lock(); t = t.addingTimeInterval(s); lock.unlock() }
}

final class ManifestTests: XCTestCase {
    /// DESIGN section 7.1, verbatim apart from the icon and asset paths.
    static let designSample = """
    {"app":"webwatcher.email","appName":"WebWatcher · Email","icon":"/tmp/icon.png","version":1,
     "fields":[{"key":"title","type":"text","required":true,"sample":"2 new from Acme Billing"},
               {"key":"subject","type":"text","sample":"Invoice #4021"},{"key":"sender","type":"text","sample":"Acme Billing"},
               {"key":"count","type":"number","sample":2},{"key":"image","type":"image","sample":"/tmp/sample.png"},
               {"key":"receivedAt","type":"date","sample":"2026-10-01T14:14:00Z"},{"key":"url","type":"url"}],
     "actions":[{"id":"markRead","label":"Mark as Read","kind":"callback"},{"id":"archive","label":"Archive","kind":"callback","style":"destructive"}],
     "assets":[{"id":"bell","type":"rive","path":"/tmp/bell.riv","stateMachine":"Main","inputs":["count","hover"]}],
     "defaultTemplate":"email-accumulated"}
    """

    private func decode(_ json: String) throws -> HeraldManifest {
        try HeraldJSON.decoder().decode(HeraldManifest.self, from: Data(json.utf8))
    }

    private func decodeValue(_ json: String) throws -> HeraldFieldValue {
        try HeraldJSON.decoder().decode(HeraldFieldValue.self, from: Data(json.utf8))
    }

    // MARK: Decoding

    func testDesignSampleDecodes() throws {
        let m = try decode(Self.designSample)
        XCTAssertEqual(m.app, "webwatcher.email")
        XCTAssertEqual(m.appName, "WebWatcher · Email")
        XCTAssertEqual(m.icon, "/tmp/icon.png")
        XCTAssertEqual(m.version, 1)
        XCTAssertEqual(m.defaultTemplate, "email-accumulated")
        XCTAssertEqual(m.fields.map(\.key), ["title", "subject", "sender", "count", "image", "receivedAt", "url"])
        XCTAssertEqual(m.fields.map(\.type), [.text, .text, .text, .number, .image, .date, .url])
        XCTAssertEqual(m.fields[0].required, true)
        XCTAssertEqual(m.fields[0].sample, .text("2 new from Acme Billing"))
        XCTAssertEqual(m.fields[3].sample, .number(2))
        XCTAssertNil(m.fields[6].sample)
        XCTAssertEqual(m.field("sender")?.type, .text)
        XCTAssertNil(m.field("nope"))

        XCTAssertEqual(m.actions.map(\.label), ["Mark as Read", "Archive"])
        XCTAssertEqual(m.actionIDs, ["markRead", "archive"])
        XCTAssertEqual(m.actions[0].callback, HeraldCallback(), "kind callback without a payload still calls the issuer back")
        XCTAssertEqual(m.actions[1].style, "destructive")
        XCTAssertEqual(m.assets, [HeraldAsset(id: "bell", type: "rive", path: "/tmp/bell.riv", stateMachine: "Main", inputs: ["count", "hover"])])
        XCTAssertEqual(m.validationErrors(), [])
    }

    func testEveryFieldTypeDecodesWithItsSample() throws {
        let json = """
        {"app":"x","fields":[
          {"key":"a","type":"text","sample":"hello"},
          {"key":"b","type":"number","sample":2.5},
          {"key":"c","type":"date","sample":"2026-10-01T14:14:00Z"},
          {"key":"d","type":"url","sample":"https://example.com"},
          {"key":"e","type":"image","sample":"data:image/png;base64,AAAA"},
          {"key":"f","type":"bool","sample":true},
          {"key":"g","type":"list","sample":["x","y"]}]}
        """
        let m = try decode(json)
        XCTAssertEqual(m.fields.map(\.type), HeraldFieldType.allCases)
        XCTAssertEqual(m.fields.map(\.sample), [.text("hello"), .number(2.5), .text("2026-10-01T14:14:00Z"),
                                                .text("https://example.com"), .text("data:image/png;base64,AAAA"),
                                                .bool(true), .list(["x", "y"])])
    }

    func testFieldValueDecodesFromJSONScalarsAndArrays() throws {
        XCTAssertEqual(try decodeValue("\"hi\""), .text("hi"))
        XCTAssertEqual(try decodeValue("3"), .number(3))
        XCTAssertEqual(try decodeValue("3.25"), .number(3.25))
        XCTAssertEqual(try decodeValue("true"), .bool(true))
        XCTAssertEqual(try decodeValue("false"), .bool(false))
        XCTAssertEqual(try decodeValue("[]"), .list([]))
        XCTAssertEqual(try decodeValue("[\"a\",\"b\"]"), .list(["a", "b"]))
        // Numbers and booleans inside a list keep their text; null is dropped.
        XCTAssertEqual(try decodeValue("[\"a\",2,2.5,true,null]"), .list(["a", "2", "2.5", "true"]))
        XCTAssertThrowsError(try decodeValue("{\"a\":1}"))
        XCTAssertThrowsError(try decodeValue("[[\"a\"]]"))
        XCTAssertThrowsError(try decodeValue("[{\"a\":1}]"))
        XCTAssertThrowsError(try decodeValue("null"))
    }

    func testFieldValueEncodesAsPlainJSON() throws {
        func json(_ v: HeraldFieldValue) throws -> String {
            String(data: try HeraldJSON.encoder().encode([v]), encoding: .utf8)!
        }
        XCTAssertEqual(try json(.text("a/b")), "[\"a/b\"]")
        XCTAssertEqual(try json(.number(3)), "[3]")
        XCTAssertEqual(try json(.number(2.5)), "[2.5]")
        XCTAssertEqual(try json(.bool(true)), "[true]")
        XCTAssertEqual(try json(.list(["a", "b"])), "[[\"a\",\"b\"]]")
        // And back, for every case.
        for v in [HeraldFieldValue.text("t"), .number(7), .bool(false), .list(["x"]), .list([])] {
            let data = try HeraldJSON.encoder().encode([v])
            XCTAssertEqual(try HeraldJSON.decoder().decode([HeraldFieldValue].self, from: data), [v])
        }
    }

    func testDefaults() throws {
        let m = try decode("{\"app\":\"x\"}")
        XCTAssertEqual(m, HeraldManifest(app: "x"))
        XCTAssertEqual(m.appName, "x")
        XCTAssertEqual(m.version, 1)
        XCTAssertEqual(m.fields, [])
        XCTAssertEqual(m.actions, [])
        XCTAssertEqual(m.assets, [])
        XCTAssertNil(m.icon); XCTAssertNil(m.defaultTemplate)
        // A field declaration may be just a key.
        XCTAssertEqual(try decode("{\"app\":\"x\",\"fields\":[{\"key\":\"k\"}]}").fields, [HeraldField(key: "k")])
        XCTAssertThrowsError(try decode("{\"appName\":\"x\"}"), "app is required")
    }

    func testBadTypesAreRejected() {
        XCTAssertThrowsError(try decode("{\"app\":\"x\",\"fields\":[{\"key\":\"k\",\"type\":\"color\"}]}"))
        XCTAssertThrowsError(try decode("{\"app\":\"x\",\"fields\":[{\"type\":\"text\"}]}"))
        XCTAssertThrowsError(try decode("{\"app\":\"x\",\"fields\":[{\"key\":\"k\",\"sample\":{\"a\":1}}]}"))
        XCTAssertThrowsError(try decode("{\"app\":\"x\",\"assets\":[{\"id\":\"a\"}]}"))
        XCTAssertThrowsError(try decode("{\"app\":\"x\",\"version\":\"two\"}"))
    }

    func testIssuerActionsMapToButtons() throws {
        let m = try decode("""
        {"app":"x","actions":[
          {"id":"open","label":"Open","kind":"url","url":"https://example.com"},
          {"id":"ping","label":"Ping","kind":"callback","callback":{"url":"http://127.0.0.1:1/h","payload":{"n":1}}},
          {"id":"run","label":"Run","kind":"command","command":"echo hi"},
          {"id":"later","label":"Later","kind":"dismiss"},
          {"label":"Inferred","url":"https://example.org"}]}
        """)
        XCTAssertEqual(m.actions[0], HeraldButton(label: "Open", url: "https://example.com"))
        XCTAssertEqual(m.actions[1].callback, HeraldCallback(url: "http://127.0.0.1:1/h", payload: .object(["n": .number(1)])))
        XCTAssertEqual(m.actions[2].command, "echo hi")
        XCTAssertEqual(m.actions[3], HeraldButton(label: "Later"))
        XCTAssertEqual(m.actions[4].url, "https://example.org")
        XCTAssertEqual(m.actionIDs, ["open", "ping", "run", "later", "inferred"])
    }

    func testScriptAndShortcutActionsRoundTripAndSnoozeIsRejected() throws {
        let m = try decode("""
        {"app":"x","actions":[{"id":"fwd","label":"Forward","kind":"shortcut","shortcut":"Forward to phone","input":"{title}"},
          {"id":"log","label":"Log","kind":"script","script":"log.sh"},{"label":"Inferred","shortcut":"S"}]}
        """)
        XCTAssertEqual(m.actions[0], HeraldButton(label: "Forward", shortcut: "Forward to phone", input: "{title}"))
        XCTAssertEqual(m.actions[1], HeraldButton(label: "Log", script: "log.sh"))
        XCTAssertEqual(m.actions[2].shortcut, "S")
        let again = try HeraldJSON.decoder().decode(HeraldManifest.self, from: HeraldJSON.encoder().encode(m))
        XCTAssertEqual(again, m)
        let wire = String(decoding: try HeraldJSON.encoder().encode(m), as: UTF8.self)
        XCTAssertTrue(wire.contains("\"kind\":\"shortcut\"") && wire.contains("\"kind\":\"script\""), wire)
        XCTAssertEqual(HeraldAction(button: m.actions[0], id: "fwd").kind, .shortcut)
        XCTAssertEqual(HeraldAction(button: m.actions[0]).input, "{title}")
        XCTAssertEqual(HeraldAction(button: m.actions[1]).kind, .script)
        // A script or Shortcut action names what it runs; a script is a plain file name in the scripts folder.
        for kind in ["shortcut", "script"] {
            XCTAssertThrowsError(try decode("{\"app\":\"x\",\"actions\":[{\"label\":\"A\",\"kind\":\"\(kind)\"}]}")) { error in
                guard case DecodingError.dataCorrupted(let c) = error else { return XCTFail("\(error)") }
                XCTAssertEqual(c.codingPath.last?.stringValue, kind)
            }
        }
        let path = try decode(#"{"app":"x","actions":[{"label":"A","kind":"script","script":"../evil.sh"}]}"#)
        XCTAssertTrue(path.validationErrors().contains { $0.contains("actions[0].script") && $0.contains("plain file name") }, "\(path.validationErrors())")
    }

    func testSnoozeAndUnknownActionKindsAreRejectedWithAReason() {
        for kind in ["snooze"] {
            XCTAssertThrowsError(try decode("{\"app\":\"x\",\"actions\":[{\"label\":\"A\",\"kind\":\"\(kind)\"}]}")) { error in
                guard case DecodingError.dataCorrupted(let c) = error else { return XCTFail("\(error)") }
                XCTAssertTrue(c.debugDescription.contains("authored in templates"), c.debugDescription)
                XCTAssertEqual(c.codingPath.last?.stringValue, "kind")
            }
        }
        XCTAssertThrowsError(try decode("{\"app\":\"x\",\"actions\":[{\"label\":\"A\",\"kind\":\"teleport\"}]}"))
        XCTAssertThrowsError(try decode("{\"app\":\"x\",\"actions\":[{\"id\":\"a\",\"label\":\"A\"},{\"id\":\"a\",\"label\":\"B\"}]}"),
                             "an id may be declared once")
    }

    func testLabelDerivedActionIDsAreUnique() throws {
        let m = try decode("""
        {"app":"x","actions":[{"label":"Mark as Read"},{"label":"Open"},{"label":"Open"},{"id":"open-2","label":"Open"},{"label":"!!!"}]}
        """)
        XCTAssertEqual(m.actionIDs, ["mark-as-read", "open", "open-3", "open-2", "action"])
        XCTAssertEqual(Set(m.actionIDs).count, m.actionIDs.count)
        // Built in code, the ids follow the same rule.
        let built = HeraldManifest(app: "x", actions: [HeraldButton(label: "Go"), HeraldButton(label: "Go")])
        XCTAssertEqual(built.actionIDs, ["go", "go-2"])
        // An action appended by hand still has an id.
        var edited = built
        edited.actions.append(HeraldButton(label: "New One"))
        XCTAssertEqual(edited.actionID(at: 2), "new-one")
    }

    func testManifestRoundTripKeepsEverything() throws {
        let m = try decode(Self.designSample)
        let data = try HeraldJSON.encoder().encode(m)
        XCTAssertEqual(try HeraldJSON.decoder().decode(HeraldManifest.self, from: data), m)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let actions = try XCTUnwrap(object["actions"] as? [[String: Any]])
        XCTAssertEqual(actions.first?["id"] as? String, "markRead")
        XCTAssertEqual(actions.first?["kind"] as? String, "callback")
        XCTAssertNil(actions.first?["callback"], "an empty callback is written as just its kind")

        var rich = HeraldManifest(app: "r", appName: "R", fields: [HeraldField(key: "n", type: .list, required: false, sample: .list(["a"]))],
                                  actions: [HeraldButton(label: "Open", url: "https://x.test"),
                                            HeraldButton(label: "Call", callback: HeraldCallback(url: "http://127.0.0.1:9/x", payload: .string("p"))),
                                            HeraldButton(label: "Run", style: "destructive", command: "true"),
                                            HeraldButton(label: "Skip")],
                                  assets: [HeraldAsset(id: "a", type: "rive", path: "/a.riv")], defaultTemplate: "t")
        rich.version = 3
        let again = try HeraldJSON.decoder().decode(HeraldManifest.self, from: try HeraldJSON.encoder().encode(rich))
        XCTAssertEqual(again, rich)
    }

    func testHistoryItemFieldsRoundTripAndOldRecordsStillDecode() throws {
        let n = HeraldNotification(app: "a", id: "i", title: "T")
        let item = HeraldHistoryItem(id: "i", app: "a", notification: n, deliveredAt: Date(timeIntervalSince1970: 1_700_000_000),
                                     fields: ["title": .text("T"), "count": .number(2), "seen": .bool(false), "tags": .list(["x"])])
        let data = try HeraldJSON.encoder().encode(item)
        XCTAssertEqual(try HeraldJSON.decoder().decode(HeraldHistoryItem.self, from: data), item)

        let plain = HeraldHistoryItem(id: "i", app: "a", notification: n, deliveredAt: Date(timeIntervalSince1970: 1_700_000_000))
        let plainData = try HeraldJSON.encoder().encode(plain)
        XCTAssertFalse(String(decoding: plainData, as: UTF8.self).contains("\"fields\""), "nil fields are not written")
        XCTAssertNil(try HeraldJSON.decoder().decode(HeraldHistoryItem.self, from: plainData).fields)
    }

    // MARK: Validation

    func testValidationReportsEveryProblem() {
        var m = HeraldManifest(app: "x")
        XCTAssertEqual(m.validationErrors(), [])

        m = HeraldManifest(app: "")
        XCTAssertTrue(m.validationErrors().contains("app is required"))

        m = HeraldManifest(app: "x", fields: [HeraldField(key: "ok"), HeraldField(key: "ok"), HeraldField(key: "has space"),
                                              HeraldField(key: ""), HeraldField(key: "{brace}")],
                           actions: [HeraldButton(label: ""), HeraldButton(label: "S", style: "loud")],
                           assets: [HeraldAsset(id: "a b", type: "", path: ""), HeraldAsset(id: "d", type: "rive", path: "/p"),
                                    HeraldAsset(id: "d", type: "rive", path: "/p")])
        m.version = 0
        let errors = m.validationErrors().joined(separator: "\n")
        for expected in ["version must be", "fields[1].key 'ok' is declared twice", "fields[2].key 'has space'", "fields[3].key ''",
                         "fields[4].key '{brace}'", "actions[0].label is required", "actions[1].style 'loud'",
                         "assets[0].id 'a b'", "assets[0].type is required", "assets[0].path is required",
                         "assets[2].id 'd' is declared twice"] {
            XCTAssertTrue(errors.contains(expected), "missing: \(expected)\n\(errors)")
        }
    }

    func testValidationLimits() {
        var m = HeraldManifest(app: String(repeating: "a", count: HeraldManifest.Limits.maxAppBytes + 1))
        XCTAssertTrue(m.validationErrors().joined().contains("app is too large"))

        m = HeraldManifest(app: "x", icon: String(repeating: "i", count: HeraldManifest.Limits.maxIconBytes + 1))
        XCTAssertTrue(m.validationErrors().joined().contains("icon is too large"))

        m = HeraldManifest(app: "x", fields: (0...HeraldManifest.Limits.maxFields).map { HeraldField(key: "k\($0)") })
        XCTAssertTrue(m.validationErrors().joined().contains("too many fields"))

        m = HeraldManifest(app: "x", actions: (0...HeraldManifest.Limits.maxActions).map { HeraldButton(label: "a\($0)") })
        XCTAssertTrue(m.validationErrors().joined().contains("too many actions"))

        m = HeraldManifest(app: "x", fields: [HeraldField(key: "big", sample: .text(String(repeating: "s", count: HeraldManifest.Limits.maxSampleBytes + 1))),
                                              HeraldField(key: "long", type: .list, sample: .list(Array(repeating: "x", count: HeraldManifest.Limits.maxSampleListItems + 1)))])
        let errors = m.validationErrors().joined(separator: "\n")
        XCTAssertTrue(errors.contains("fields[0].sample is too large"), errors)
        XCTAssertTrue(errors.contains("fields[1].sample has too many items"), errors)
    }

    // MARK: Store

    private func tempDir() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("herald-manifest-\(UUID().uuidString)")
    }

    func testStoreRoundTrip() throws {
        let dir = tempDir(); defer { try? FileManager.default.removeItem(at: dir) }
        let store = ManifestStore(directory: dir)
        XCTAssertEqual(store.list(), [])
        XCTAssertNil(store.get(app: "webwatcher.email"))

        let email = try decode(Self.designSample)
        let web = HeraldManifest(app: "webwatcher.web", appName: "WebWatcher · Web",
                                 fields: [HeraldField(key: "title", required: true, sample: .text("Price dropped"))])
        let other = HeraldManifest(app: "Aardvark")
        XCTAssertTrue(store.put(email)); XCTAssertTrue(store.put(web)); XCTAssertTrue(store.put(other))

        XCTAssertEqual(store.list().map(\.app), ["Aardvark", "webwatcher.email", "webwatcher.web"], "sorted by app, case-insensitively")
        XCTAssertEqual(store.get(app: "webwatcher.email"), email)
        XCTAssertEqual(store.get(app: "webwatcher.web"), web)
        XCTAssertNil(store.get(app: "nope"))
        XCTAssertNil(store.get(app: ""))

        // A second store on the same folder sees the same data (it is on disk, not in memory).
        XCTAssertEqual(ManifestStore(directory: dir).get(app: "webwatcher.email"), email)

        // Put replaces.
        var changed = email
        changed.version = 2; changed.defaultTemplate = "other"
        XCTAssertTrue(store.put(changed))
        XCTAssertEqual(store.list().count, 3)
        XCTAssertEqual(store.get(app: "webwatcher.email")?.version, 2)

        XCTAssertTrue(store.delete(app: "webwatcher.web"))
        XCTAssertFalse(store.delete(app: "webwatcher.web"))
        XCTAssertNil(store.get(app: "webwatcher.web"))
        XCTAssertEqual(store.list().map(\.app), ["Aardvark", "webwatcher.email"])
    }

    func testStoreFilesAreReadableJSONNamedAfterTheApp() throws {
        let dir = tempDir(); defer { try? FileManager.default.removeItem(at: dir) }
        let store = ManifestStore(directory: dir)
        XCTAssertTrue(store.put(HeraldManifest(app: "webwatcher.email")))
        let file = dir.appendingPathComponent("webwatcher.email.json")
        let text = try String(contentsOf: file, encoding: .utf8)
        XCTAssertTrue(text.contains("\n"), "pretty printed for hand editing")
        XCTAssertTrue(text.contains("\"app\" : \"webwatcher.email\""))
    }

    func testStoreRejectsEmptyAppAndNeutralisesPaths() throws {
        let dir = tempDir(); defer { try? FileManager.default.removeItem(at: dir) }
        let store = ManifestStore(directory: dir)
        XCTAssertFalse(store.put(HeraldManifest(app: "")))
        XCTAssertFalse(store.delete(app: ""))

        for app in ["../evil", "a/b", "..", ".hidden", "x\u{0}y", "ünï"] {
            XCTAssertTrue(store.put(HeraldManifest(app: app)), app)
            XCTAssertNotNil(store.get(app: app), app)
        }
        let escaped = dir.deletingLastPathComponent().appendingPathComponent("evil.json")
        XCTAssertFalse(FileManager.default.fileExists(atPath: escaped.path))
        let names = try FileManager.default.contentsOfDirectory(atPath: dir.path)
        XCTAssertEqual(names.count, 6, "no two apps share a file: \(names)")
        XCTAssertTrue(names.allSatisfy { !$0.contains("/") && !$0.hasPrefix(".") })
        // "a/b" and "a_b" are different apps.
        XCTAssertTrue(store.put(HeraldManifest(app: "a_b", appName: "underscore")))
        XCTAssertEqual(store.get(app: "a/b")?.appName, "a/b")
        XCTAssertEqual(store.get(app: "a_b")?.appName, "underscore")
    }

    func testStoreFindsHandRenamedFileAndSkipsCorruptOnes() throws {
        let dir = tempDir(); defer { try? FileManager.default.removeItem(at: dir) }
        let store = ManifestStore(directory: dir)
        XCTAssertTrue(store.put(HeraldManifest(app: "mine", appName: "Mine")))
        try FileManager.default.moveItem(at: dir.appendingPathComponent("mine.json"), to: dir.appendingPathComponent("renamed-by-hand.json"))
        try Data("not json".utf8).write(to: dir.appendingPathComponent("broken.json"))
        try Data("ignored".utf8).write(to: dir.appendingPathComponent("notes.txt"))

        XCTAssertEqual(store.list().map(\.app), ["mine"])
        XCTAssertEqual(store.get(app: "mine")?.appName, "Mine")
        // Replacing it leaves one file for that app, not two.
        XCTAssertTrue(store.put(HeraldManifest(app: "mine", appName: "Mine 2")))
        XCTAssertEqual(store.list().count, 1)
        XCTAssertEqual(store.get(app: "mine")?.appName, "Mine 2")
        XCTAssertFalse(FileManager.default.fileExists(atPath: dir.appendingPathComponent("renamed-by-hand.json").path))
        // Deleting works for a renamed file too.
        try FileManager.default.moveItem(at: dir.appendingPathComponent("mine.json"), to: dir.appendingPathComponent("again.json"))
        XCTAssertTrue(store.delete(app: "mine"))
        XCTAssertNil(store.get(app: "mine"))
    }

    func testStoreHasRoomUntilFull() throws {
        let dir = tempDir(); defer { try? FileManager.default.removeItem(at: dir) }
        let store = ManifestStore(directory: dir)
        for i in 0..<ManifestStore.maxManifests { XCTAssertTrue(store.put(HeraldManifest(app: "app\(i)"))) }
        XCTAssertFalse(store.hasRoom(for: "one-more"))
        XCTAssertTrue(store.hasRoom(for: "app7"), "replacing an existing manifest needs no room")
        XCTAssertTrue(store.delete(app: "app7"))
        XCTAssertTrue(store.hasRoom(for: "one-more"))
    }

    // MARK: Router

    private func routerAndBackend(runner: ShortcutsCatalog.Runner? = nil)
        -> (Router, ManifestBackend, URL) {
        let dir = tempDir()
        let catalog = runner.map { ShortcutsCatalog(runner: $0) }
            ?? ShortcutsCatalog(runner: { _, _, _ in ShortcutsProcessResult(stdout: "Follow up\nArchive mail\n") })
        let backend = ManifestBackend(store: ManifestStore(directory: dir), catalog: catalog)
        return (Router(token: "secret-token", backend: backend, version: "1.1.0", pid: 1), backend, dir)
    }

    private func req(_ method: String, _ path: String, token: String? = "secret-token", body: String = "",
                     query: [String: String] = [:]) -> HTTPRequest {
        var h: [String: String] = [:]
        if let token { h["authorization"] = "Bearer \(token)" }
        return HTTPRequest(method: method, path: path, query: query, headers: h, body: Data(body.utf8))
    }

    private func text(_ r: HTTPResponse) -> String { String(data: r.body, encoding: .utf8) ?? "" }

    func testManifestRoutesNeedAuth() async {
        let (router, _, dir) = routerAndBackend(); defer { try? FileManager.default.removeItem(at: dir) }
        let calls: [(String, String)] = [("GET", "/v1/manifests"), ("GET", "/v1/manifest"), ("PUT", "/v1/manifest"),
                                         ("DELETE", "/v1/manifest"), ("GET", "/v1/components"), ("GET", "/v1/shortcuts")]
        for (method, path) in calls {
            for t in [nil, "wrong", "secret-token-x"] as [String?] {
                let r = await router.handle(req(method, path, token: t, body: Self.designSample, query: ["app": "webwatcher.email"]))
                XCTAssertEqual(r.status, 401, "\(method) \(path) token \(t ?? "none")")
                XCTAssertEqual(text(r), "{\"error\":\"unauthorized\"}")
            }
        }
    }

    func testManifestCRUDOverHTTP() async throws {
        let (router, backend, dir) = routerAndBackend(); defer { try? FileManager.default.removeItem(at: dir) }

        var r = await router.handle(req("GET", "/v1/manifests"))
        XCTAssertEqual(r.status, 200)
        XCTAssertEqual(text(r), "{\"items\":[]}")

        r = await router.handle(req("PUT", "/v1/manifest", body: Self.designSample))
        XCTAssertEqual(r.status, 200, text(r))
        XCTAssertEqual(text(r), "{\"ok\":true}")
        r = await router.handle(req("PUT", "/v1/manifest", body: "{\"app\":\"webwatcher.web\",\"appName\":\"Web\"}"))
        XCTAssertEqual(r.status, 200)
        XCTAssertEqual(backend.store.list().count, 2)

        r = await router.handle(req("GET", "/v1/manifests"))
        struct Items: Decodable { var items: [HeraldManifest] }
        let all = try HeraldJSON.decoder().decode(Items.self, from: r.body).items
        XCTAssertEqual(all.map(\.app), ["webwatcher.email", "webwatcher.web"])

        r = await router.handle(req("GET", "/v1/manifest", query: ["app": "webwatcher.email"]))
        XCTAssertEqual(r.status, 200)
        let got = try HeraldJSON.decoder().decode(HeraldManifest.self, from: r.body)
        XCTAssertEqual(got, try decode(Self.designSample), "GET returns exactly what PUT stored, including action ids")
        XCTAssertEqual(got.actionIDs, ["markRead", "archive"])

        // PUT is an upsert.
        r = await router.handle(req("PUT", "/v1/manifest", body: "{\"app\":\"webwatcher.web\",\"appName\":\"Web 2\",\"version\":2}"))
        XCTAssertEqual(r.status, 200)
        XCTAssertEqual(backend.store.get(app: "webwatcher.web")?.version, 2)
        XCTAssertEqual(backend.store.list().count, 2)

        r = await router.handle(req("GET", "/v1/manifest", query: ["app": "unknown"]))
        XCTAssertEqual(r.status, 404)
        XCTAssertEqual(text(r), "{\"error\":\"manifest not found\"}")

        r = await router.handle(req("DELETE", "/v1/manifest", query: ["app": "webwatcher.web"]))
        XCTAssertEqual(r.status, 200)
        XCTAssertNil(backend.store.get(app: "webwatcher.web"))
        r = await router.handle(req("DELETE", "/v1/manifest", query: ["app": "webwatcher.web"]))
        XCTAssertEqual(r.status, 404)
        r = await router.handle(req("GET", "/v1/manifest", query: ["app": "webwatcher.web"]))
        XCTAssertEqual(r.status, 404)
        XCTAssertEqual(backend.store.list().map(\.app), ["webwatcher.email"])
    }

    func testManifestRouteValidationAndMethods() async {
        let (router, backend, dir) = routerAndBackend(); defer { try? FileManager.default.removeItem(at: dir) }

        var r = await router.handle(req("GET", "/v1/manifest"))
        XCTAssertEqual(r.status, 400); XCTAssertTrue(text(r).contains("app is required"))
        r = await router.handle(req("DELETE", "/v1/manifest"))
        XCTAssertEqual(r.status, 400)

        r = await router.handle(req("PUT", "/v1/manifest", body: "not json"))
        XCTAssertEqual(r.status, 400)
        r = await router.handle(req("PUT", "/v1/manifest", body: "{\"appName\":\"x\"}"))
        XCTAssertEqual(r.status, 400); XCTAssertTrue(text(r).contains("app"), text(r))
        r = await router.handle(req("PUT", "/v1/manifest", body: "{\"app\":\"\"}"))
        XCTAssertEqual(r.status, 400); XCTAssertTrue(text(r).contains("app is required"), text(r))

        // The reason names the exact place.
        r = await router.handle(req("PUT", "/v1/manifest", body: "{\"app\":\"x\",\"fields\":[{\"key\":\"a\"},{\"key\":\"b\",\"type\":\"colour\"}]}"))
        XCTAssertEqual(r.status, 400); XCTAssertTrue(text(r).contains("fields[1].type"), text(r))
        r = await router.handle(req("PUT", "/v1/manifest", body: "{\"app\":\"x\",\"actions\":[{\"label\":\"A\",\"kind\":\"url\",\"url\":\"https://x.test\"},{\"label\":\"F\",\"kind\":\"shortcut\"}]}"))
        XCTAssertEqual(r.status, 400)
        XCTAssertTrue(text(r).contains("actions[1].shortcut"), text(r))
        XCTAssertTrue(text(r).contains("name of an installed Shortcut"), text(r))

        // Semantic problems are all reported at once.
        r = await router.handle(req("PUT", "/v1/manifest", body: "{\"app\":\"x\",\"fields\":[{\"key\":\"a\"},{\"key\":\"a\"},{\"key\":\"b c\"}]}"))
        XCTAssertEqual(r.status, 400)
        XCTAssertTrue(text(r).contains("declared twice") && text(r).contains("'b c'"), text(r))
        XCTAssertEqual(backend.store.list(), [], "nothing invalid is stored")

        for (method, path) in [("POST", "/v1/manifest"), ("PATCH", "/v1/manifest"), ("POST", "/v1/manifests"), ("DELETE", "/v1/manifests"),
                               ("POST", "/v1/components"), ("PUT", "/v1/components"), ("POST", "/v1/shortcuts"), ("DELETE", "/v1/shortcuts")] {
            r = await router.handle(req(method, path))
            XCTAssertEqual(r.status, 405, "\(method) \(path)")
        }
    }

    func testBackendWithoutManifestSupportAnswers501() async {
        let router = Router(token: "secret-token", backend: MockBackend(), version: "1.1.0", pid: 1)
        for (method, path, body) in [("GET", "/v1/manifests", ""), ("GET", "/v1/manifest", ""), ("PUT", "/v1/manifest", "{\"app\":\"x\"}"),
                                     ("DELETE", "/v1/manifest", ""), ("GET", "/v1/shortcuts", "")] {
            let r = await router.handle(req(method, path, body: body, query: ["app": "x"]))
            XCTAssertEqual(r.status, 501, "\(method) \(path)")
        }
        // The component schema needs no backend.
        let c = await router.handle(req("GET", "/v1/components"))
        XCTAssertEqual(c.status, 200)
    }

    func testComponentsRouteServesTheSchemaDocument() async throws {
        let (router, _, dir) = routerAndBackend(); defer { try? FileManager.default.removeItem(at: dir) }
        let r = await router.handle(req("GET", "/v1/components"))
        XCTAssertEqual(r.status, 200)
        let object = try JSONSerialization.jsonObject(with: r.body)
        XCTAssertTrue(object is [String: Any], "a JSON object: \(text(r).prefix(80))")
        XCTAssertGreaterThan(r.body.count, 100)
    }

    // MARK: Shortcuts route

    func testShortcutsRouteListsNamesSorted() async {
        let (router, _, dir) = routerAndBackend(); defer { try? FileManager.default.removeItem(at: dir) }
        let r = await router.handle(req("GET", "/v1/shortcuts"))
        XCTAssertEqual(r.status, 200)
        XCTAssertEqual(text(r), "{\"items\":[\"Archive mail\",\"Follow up\"]}")
    }

    func testShortcutsRouteMapsFailuresToGatewayErrors() async {
        var (router, _, dir) = routerAndBackend(runner: { _, _, _ in ShortcutsProcessResult(status: 1, stderr: "Error: nope\nmore") })
        var r = await router.handle(req("GET", "/v1/shortcuts"))
        XCTAssertEqual(r.status, 502)
        XCTAssertTrue(text(r).contains("exit 1") && text(r).contains("nope"), text(r))
        try? FileManager.default.removeItem(at: dir)

        (router, _, dir) = routerAndBackend(runner: { _, _, _ in ShortcutsProcessResult(status: -1, timedOut: true) })
        r = await router.handle(req("GET", "/v1/shortcuts"))
        XCTAssertEqual(r.status, 504)
        try? FileManager.default.removeItem(at: dir)

        (router, _, dir) = routerAndBackend(runner: { _, _, _ in ShortcutsProcessResult(status: -1, launchError: "no such file") })
        r = await router.handle(req("GET", "/v1/shortcuts"))
        XCTAssertEqual(r.status, 502)
        XCTAssertTrue(text(r).contains("no such file"))
        try? FileManager.default.removeItem(at: dir)
    }

    // MARK: Notify keeps working, and fields at the top level reach metadata

    func testTopLevelFieldsAreCarriedInMetadata() async throws {
        let (router, backend, dir) = routerAndBackend(); defer { try? FileManager.default.removeItem(at: dir) }
        let body = """
        {"app":"webwatcher.email","id":"m1","title":"2 new","subject":"Invoice #4021","count":2,"unread":true,"tags":["a","b"],
         "metadata":{"count":9,"extra":"kept"}}
        """
        let r = await router.handle(req("POST", "/v1/notify", body: body))
        XCTAssertEqual(r.status, 200, text(r))
        let n = try XCTUnwrap(backend.notified.first)
        XCTAssertEqual(n.title, "2 new")
        guard case .object(let meta)? = n.metadata else { return XCTFail("metadata: \(String(describing: n.metadata))") }
        XCTAssertEqual(meta["subject"], .string("Invoice #4021"))
        XCTAssertEqual(meta["count"], .number(2), "the top-level key wins over the same key in metadata")
        XCTAssertEqual(meta["unread"], .bool(true))
        XCTAssertEqual(meta["tags"], .array([.string("a"), .string("b")]))
        XCTAssertEqual(meta["extra"], .string("kept"))
        XCTAssertNil(meta["title"], "notification properties are not copied into metadata")
        XCTAssertNil(meta["metadata"])
    }

    /// The whole path a manifest field takes: top-level key in the payload, through the router, into the
    /// resolved fields a grid template binds to, typed by the manifest.
    func testManifestFieldsSentAtTheTopLevelResolveToTemplateFields() async throws {
        let (router, backend, dir) = routerAndBackend(); defer { try? FileManager.default.removeItem(at: dir) }
        _ = await router.handle(req("PUT", "/v1/manifest", body: Self.designSample))
        let body = "{\"app\":\"webwatcher.email\",\"title\":\"2 new from Acme\",\"subject\":\"Invoice #4021\",\"count\":\"2\",\"tags\":[\"a\",\"b\"]}"
        let r = await router.handle(req("POST", "/v1/notify", body: body))
        XCTAssertEqual(r.status, 200, text(r))
        let n = try XCTUnwrap(backend.notified.first)
        let manifest = try XCTUnwrap(backend.store.get(app: "webwatcher.email"))
        let fields = TemplateResolver.fields(for: n, manifest: manifest)
        XCTAssertEqual(fields["title"], .text("2 new from Acme"))
        XCTAssertEqual(fields["subject"], .text("Invoice #4021"))
        XCTAssertEqual(fields["count"], .number(2), "the manifest declares count as a number")
        XCTAssertEqual(fields["tags"], .list(["a", "b"]))
        XCTAssertNil(fields["sender"], "samples are for the designer, never for a real notification")
        XCTAssertNil(fields["url"])
    }

    func testPayloadWithOnlyKnownKeysIsLeftAsSent() async throws {
        let (router, backend, dir) = routerAndBackend(); defer { try? FileManager.default.removeItem(at: dir) }
        var r = await router.handle(req("POST", "/v1/notify", body: "{\"app\":\"a\",\"id\":\"i\",\"title\":\"T\",\"body\":\"B\",\"buttons\":[{\"label\":\"Go\",\"url\":\"https://x.test\"}]}"))
        XCTAssertEqual(r.status, 200)
        XCTAssertNil(backend.notified.last?.metadata)
        XCTAssertEqual(backend.notified.last?.buttons?.first?.label, "Go")

        r = await router.handle(req("POST", "/v1/notify", body: "{\"app\":\"a\",\"title\":\"T\",\"metadata\":{\"k\":1}}"))
        XCTAssertEqual(backend.notified.last?.metadata, .object(["k": .number(1)]))
    }

    func testTopLevelFieldsWorkWithATemplateAndWithoutATitle() async throws {
        let (router, backend, dir) = routerAndBackend(); defer { try? FileManager.default.removeItem(at: dir) }
        let r = await router.handle(req("POST", "/v1/notify", body: "{\"app\":\"a\",\"template\":\"t\",\"sender\":\"Acme\"}"))
        XCTAssertEqual(r.status, 200, text(r))
        XCTAssertEqual(backend.notified.last?.title, "")
        XCTAssertEqual(backend.notified.last?.template, "t")
        XCTAssertEqual(backend.notified.last?.metadata, .object(["sender": .string("Acme")]))

        // Still no title and no template: the usual error.
        let bad = await router.handle(req("POST", "/v1/notify", body: "{\"app\":\"a\",\"sender\":\"Acme\"}"))
        XCTAssertEqual(bad.status, 400)
        XCTAssertTrue(text(bad).contains("title"))
    }

    func testMetadataThatIsNotAnObjectIsNotTouched() async {
        let (router, backend, dir) = routerAndBackend(); defer { try? FileManager.default.removeItem(at: dir) }
        let r = await router.handle(req("POST", "/v1/notify", body: "{\"app\":\"a\",\"title\":\"T\",\"metadata\":[1,2],\"extra\":1}"))
        XCTAssertEqual(r.status, 200)
        XCTAssertEqual(backend.notified.last?.metadata, .array([.number(1), .number(2)]))
    }

    // MARK: ShortcutsCatalog

    func testParseCannedOutput() {
        let canned = "Zebra\nalpha\n\n  Beta  \r\nalpha\n\t\nÉclair\nWith\u{7}Bell\n   \n"
        XCTAssertEqual(ShortcutsCatalog.parse(canned), ["alpha", "Beta", "Éclair", "WithBell", "Zebra"])
        XCTAssertEqual(ShortcutsCatalog.parse(""), [])
        XCTAssertEqual(ShortcutsCatalog.parse("\n\n"), [])
        XCTAssertEqual(ShortcutsCatalog.parse("Only one"), ["Only one"])
        XCTAssertEqual(ShortcutsCatalog.parse("Morning routine\nMorning Routine"), ["Morning routine", "Morning Routine"],
                       "names that differ only in case are both kept (they are different shortcuts)")
    }

    func testParseBoundsWhatOneListingContributes() {
        let many = (0..<(ShortcutsCatalog.maxNames + 50)).map { "Shortcut \($0)" }.joined(separator: "\n")
        XCTAssertEqual(ShortcutsCatalog.parse(many).count, ShortcutsCatalog.maxNames)
        let long = String(repeating: "x", count: ShortcutsCatalog.maxNameBytes + 1)
        XCTAssertEqual(ShortcutsCatalog.parse("ok\n\(long)"), ["ok"])
    }

    func testCacheServesFor30SecondsThenRefreshes() async throws {
        let calls = ManifestTestCounter(), clock = ManifestTestClock()
        let catalog = ShortcutsCatalog(now: { clock.now }, runner: { _, _, _ in
            ShortcutsProcessResult(stdout: "Run \(calls.bump())\n")
        })
        var names = try await catalog.names()
        XCTAssertEqual(names, ["Run 1"])
        clock.advance(29)
        names = try await catalog.names()
        XCTAssertEqual(names, ["Run 1"], "still cached after 29 s")
        XCTAssertEqual(calls.value, 1)
        clock.advance(2)
        names = try await catalog.names()
        XCTAssertEqual(names, ["Run 2"], "refreshed after 31 s")

        names = try await catalog.names(refresh: true)
        XCTAssertEqual(names, ["Run 3"])
        await catalog.invalidate()
        names = try await catalog.names()
        XCTAssertEqual(names, ["Run 4"])
        XCTAssertEqual(calls.value, 4)
    }

    func testConcurrentCallersShareOneRun() async throws {
        let calls = ManifestTestCounter()
        let catalog = ShortcutsCatalog(runner: { _, _, _ in
            calls.bump()
            try? await Task.sleep(nanoseconds: 150_000_000)
            return ShortcutsProcessResult(stdout: "A\nB\n")
        })
        async let a = catalog.names()
        async let b = catalog.names()
        async let c = catalog.names()
        let results = try await [a, b, c]
        XCTAssertEqual(results, [["A", "B"], ["A", "B"], ["A", "B"]])
        XCTAssertEqual(calls.value, 1)
    }

    func testFailuresAreNotCachedAndAreClassified() async throws {
        let calls = ManifestTestCounter()
        let catalog = ShortcutsCatalog(runner: { _, _, _ in
            switch calls.bump() {
            case 1: return ShortcutsProcessResult(status: 3, stderr: "boom\nsecond line")
            case 2: return ShortcutsProcessResult(status: -1, timedOut: true)
            case 3: return ShortcutsProcessResult(status: -1, launchError: "missing")
            default: return ShortcutsProcessResult(stdout: "Fine\n")
            }
        })
        do { _ = try await catalog.names(); XCTFail("expected failure") }
        catch { XCTAssertEqual(error as? ShortcutsError, .failed(status: 3, message: "boom")) }
        do { _ = try await catalog.names(); XCTFail("expected timeout") }
        catch { XCTAssertEqual(error as? ShortcutsError, .timedOut(ShortcutsCatalog.defaultTimeout)) }
        do { _ = try await catalog.names(); XCTFail("expected unavailable") }
        catch { XCTAssertEqual(error as? ShortcutsError, .unavailable("missing")) }
        let names = try await catalog.names()
        XCTAssertEqual(names, ["Fine"])
        XCTAssertEqual(calls.value, 4)
    }

    func testRunnerReceivesTheConfiguredCommand() async throws {
        let seen = ManifestTestCounter()
        let catalog = ShortcutsCatalog(executable: "/x/shortcuts", arguments: ["list"], timeout: 7, runner: { exe, args, timeout in
            XCTAssertEqual(exe, "/x/shortcuts"); XCTAssertEqual(args, ["list"]); XCTAssertEqual(timeout, 7)
            seen.bump()
            return ShortcutsProcessResult()
        })
        _ = try await catalog.names()
        XCTAssertEqual(seen.value, 1)
        XCTAssertEqual(ShortcutsCatalog.defaultExecutable, "/usr/bin/shortcuts")
        XCTAssertEqual(ShortcutsCatalog.defaultTimeout, 5)
        XCTAssertEqual(ShortcutsCatalog.defaultCacheTTL, 30)
    }

    // The real process runner, against programs every Mac has.

    func testRealProcessOutputIsParsed() async throws {
        let catalog = ShortcutsCatalog(executable: "/usr/bin/printf", arguments: ["Beta\\nAlpha\\nBeta\\n"])
        let names = try await catalog.names()
        XCTAssertEqual(names, ["Alpha", "Beta"])
    }

    func testRealProcessWithLargeOutputDoesNotStall() async throws {
        // About 280 KB: far beyond a pipe buffer, so the output must be read while the program runs.
        let catalog = ShortcutsCatalog(executable: "/usr/bin/seq", arguments: ["1", "40000"], timeout: 10)
        let names = try await catalog.names()
        XCTAssertEqual(names.count, ShortcutsCatalog.maxNames)
    }

    func testRealProcessThatNeverAnswersTimesOut() async {
        let catalog = ShortcutsCatalog(executable: "/bin/sleep", arguments: ["30"], timeout: 0.4)
        let started = Date()
        do { _ = try await catalog.names(); XCTFail("expected a timeout") }
        catch { XCTAssertEqual(error as? ShortcutsError, .timedOut(0.4)) }
        XCTAssertLessThan(Date().timeIntervalSince(started), 5)
    }

    /// Against the real Shortcuts tool. Off by default (it needs a logged-in session and the user's own
    /// shortcuts); run with HERALD_LIVE_SHORTCUTS=1.
    func testLiveShortcutsList() async throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["HERALD_LIVE_SHORTCUTS"] == "1", "set HERALD_LIVE_SHORTCUTS=1")
        let names = try await ShortcutsCatalog().names()
        print("live shortcuts: \(names)")
        XCTAssertEqual(names, ShortcutsCatalog.parse(names.joined(separator: "\n")), "already clean and sorted")
    }

    func testRealProcessFailureAndMissingExecutable() async {
        let failing = ShortcutsCatalog(executable: "/usr/bin/false", arguments: [])
        do { _ = try await failing.names(); XCTFail("expected failure") }
        catch { XCTAssertEqual(error as? ShortcutsError, .failed(status: 1, message: "")) }

        let missing = ShortcutsCatalog(executable: "/nonexistent/shortcuts")
        do { _ = try await missing.names(); XCTFail("expected failure") }
        catch {
            guard case .unavailable? = error as? ShortcutsError else { return XCTFail("\(error)") }
        }
    }
}
