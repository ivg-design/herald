import XCTest
import HeraldClient
@testable import HeraldCore

/// Issue #63: the `openApp` action kind. Which application it opens (the order is the contract), where it can be
/// written (template rule, manifest, payload button, banner click), that an unknown application is a warning and a
/// graceful no-op with a note in History, and that the schema documents it.
final class OpenAppTests: XCTestCase {
    /// An application lookup that knows exactly these bundle ids, paths and names.
    private func lookup(bundles: [String: String] = [:], paths: [String] = [], names: [String: String] = [:]) -> HeraldAppLookup {
        HeraldAppLookup(bundleURL: { bundles[$0].map { URL(fileURLWithPath: $0) } },
                        named: { names[$0].map { URL(fileURLWithPath: $0) } },
                        pathExists: { paths.contains($0) ? URL(fileURLWithPath: $0) : nil })
    }

    private let manifest = HeraldManifest(app: "webwatcher.email", appName: "WebWatcher", appBundleId: "com.ivg.webwatcher",
                                          appPath: "/Applications/WebWatcher.app")

    // MARK: Resolution order

    func testTheOrderIsExplicitBundleIdThenPathThenManifestThenAppName() {
        let c = HeraldOpenAppResolver.candidates(bundleId: "com.example.Own", path: "/Applications/Own.app", manifest: manifest,
                                                 registeredBundleId: "com.ivg.registered", appName: "WebWatcher")
        XCTAssertEqual(c, [.bundleId("com.example.Own"), .path("/Applications/Own.app"), .bundleId("com.ivg.webwatcher"),
                           .path("/Applications/WebWatcher.app"), .bundleId("com.ivg.registered"), .appName("WebWatcher")])

        let everything = lookup(bundles: ["com.example.Own": "/own-bundle", "com.ivg.webwatcher": "/manifest-bundle", "com.ivg.registered": "/registered"],
                                paths: ["/Applications/Own.app", "/Applications/WebWatcher.app"], names: ["WebWatcher": "/by-name"])
        XCTAssertEqual(HeraldOpenAppResolver.resolve(c, lookup: everything)?.url.path, "/own-bundle", "explicit bundleId wins")
        let noBundle = lookup(bundles: ["com.ivg.webwatcher": "/manifest-bundle"], paths: ["/Applications/Own.app", "/Applications/WebWatcher.app"],
                              names: ["WebWatcher": "/by-name"])
        XCTAssertEqual(HeraldOpenAppResolver.resolve(c, lookup: noBundle)?.url.path, "/Applications/Own.app", "then the action's path")
        let manifestOnly = lookup(bundles: ["com.ivg.webwatcher": "/manifest-bundle"], paths: ["/Applications/WebWatcher.app"], names: ["WebWatcher": "/by-name"])
        XCTAssertEqual(HeraldOpenAppResolver.resolve(c, lookup: manifestOnly)?.url.path, "/manifest-bundle", "then the manifest's bundle id")
        let manifestPath = lookup(paths: ["/Applications/WebWatcher.app"], names: ["WebWatcher": "/by-name"])
        XCTAssertEqual(HeraldOpenAppResolver.resolve(c, lookup: manifestPath)?.url.path, "/Applications/WebWatcher.app", "then the manifest's path")
        let registered = lookup(bundles: ["com.ivg.registered": "/registered"], names: ["WebWatcher": "/by-name"])
        XCTAssertEqual(HeraldOpenAppResolver.resolve(c, lookup: registered)?.url.path, "/registered", "then the bundle id the issuer registered with")
        let nameOnly = lookup(names: ["WebWatcher": "/by-name"])
        XCTAssertEqual(HeraldOpenAppResolver.resolve(c, lookup: nameOnly)?.url.path, "/by-name", "and last the app whose name is appName")
        XCTAssertNil(HeraldOpenAppResolver.resolve(c, lookup: lookup()), "nothing found: nil")
    }

    func testAnActionWithNothingFallsBackToTheManifest() {
        let c = HeraldOpenAppResolver.candidates(bundleId: nil, path: "  ", manifest: manifest)
        XCTAssertEqual(c.first, .bundleId("com.ivg.webwatcher"), "blank fields are absent")
        XCTAssertTrue(HeraldOpenAppResolver.candidates(bundleId: nil, path: nil, manifest: nil).isEmpty)
    }

    // MARK: The wire

    func testTheActionDecodesInferenceAndRoundTrip() throws {
        let a = try HeraldJSON.decoder().decode(HeraldAction.self, from: Data(#"{"id":"open","label":"Open WebWatcher","kind":"openApp","bundleId":"com.ivg.webwatcher"}"#.utf8))
        XCTAssertEqual(a.kind, .openApp); XCTAssertEqual(a.bundleId, "com.ivg.webwatcher")
        let inferred = try HeraldJSON.decoder().decode(HeraldAction.self, from: Data(#"{"label":"Open","path":"/Applications/WebWatcher.app"}"#.utf8))
        XCTAssertEqual(inferred.kind, .openApp, "a path or a bundleId alone says what it is")
        XCTAssertEqual(try HeraldJSON.decoder().decode(HeraldAction.self, from: try HeraldJSON.encoder().encode(a)), a)
        XCTAssertTrue(HeraldActionKind.allCases.contains(.openApp))
    }

    func testAnIssuerCanDeclareItInAManifestAndTheKeysRoundTrip() throws {
        let m = try HeraldJSON.decoder().decode(HeraldManifest.self, from: Data("""
        {"app":"webwatcher.email","appName":"WebWatcher","appBundleId":"com.ivg.webwatcher","appPath":"/Applications/WebWatcher.app",
         "actions":[{"id":"open","label":"Open WebWatcher","kind":"openApp"},
                    {"id":"mail","label":"Open Mail","kind":"openApp","bundleId":"com.apple.mail"},
                    {"id":"archive","label":"Archive","kind":"callback"}]}
        """.utf8))
        XCTAssertEqual(m.appBundleId, "com.ivg.webwatcher"); XCTAssertEqual(m.appPath, "/Applications/WebWatcher.app")
        XCTAssertEqual(m.actions[0].openApp, HeraldOpenApp())
        XCTAssertEqual(m.actions[1].openApp?.bundleId, "com.apple.mail")
        XCTAssertNil(m.actions[2].openApp)
        XCTAssertEqual(m.validationErrors(), [])
        XCTAssertEqual(try HeraldJSON.decoder().decode(HeraldManifest.self, from: try HeraldJSON.encoder().encode(m)), m)
        let action = HeraldAction(button: m.actions[1], id: "mail")
        XCTAssertEqual(action.kind, .openApp); XCTAssertEqual(action.bundleId, "com.apple.mail")
        XCTAssertEqual(action.legacyButton?.openApp?.bundleId, "com.apple.mail")
        // Shape errors are reported with the field.
        var bad = m; bad.appBundleId = "not a bundle"; bad.appPath = "/Applications/Thing"
        XCTAssertEqual(bad.validationErrors().count, 2, "\(bad.validationErrors())")
        // A payload button can carry it too.
        let b = try HeraldJSON.decoder().decode(HeraldButton.self, from: Data(#"{"label":"Open","openApp":{"bundleId":"com.apple.mail"}}"#.utf8))
        XCTAssertEqual(HeraldAction(button: b).kind, .openApp)
    }

    func testTheBannerClickOptionRoundTrips() throws {
        let t = try HeraldJSON.decoder().decode(HeraldTemplate.self, from: Data(#"{"name":"n","app":"a","onClick":"openApp"}"#.utf8))
        XCTAssertEqual(t.onClick, .openApp)
        XCTAssertEqual(try HeraldJSON.decoder().decode(HeraldTemplate.self, from: try HeraldJSON.encoder().encode(t)).onClick, .openApp)
        XCTAssertNil(try HeraldJSON.decoder().decode(HeraldTemplate.self, from: Data(#"{"name":"n","app":"a"}"#.utf8)).onClick)
    }

    // MARK: Validation

    private func withLookup<T>(_ l: HeraldAppLookup, _ body: () throws -> T) rethrows -> T {
        let saved = HeraldAppLookup.current
        HeraldAppLookup.current = l
        defer { HeraldAppLookup.current = saved }
        return try body()
    }

    private func template(_ extra: String) throws -> HeraldTemplate {
        try HeraldJSON.decoder().decode(HeraldTemplate.self, from: Data("""
        {"name":"t","app":"webwatcher.email","layoutVersion":2,"grid":{"rows":1,"cols":1,"rowSizes":["auto"],"colSizes":["fill"],"gap":8,"padding":10,"width":300},
         "cells":[{"id":"b","row":0,"col":0,"component":{"type":"button","action":{"id":"o","label":"Open","kind":"openApp","bundleId":"com.nobody.Nothing"}}}]\(extra)}
        """.utf8))
    }

    func testAnUnknownApplicationIsAWarningNeverAnError() throws {
        let t = try template(#","actionRules":[{"add":{"id":"open-ww","label":"Open WebWatcher","kind":"openApp"}}],"onClick":"openApp""#)
        let issues = withLookup(lookup()) { t.validate(manifest: manifest) }
        XCTAssertEqual(issues.filter { $0.isError }.map(\.message), [], "the template is valid")
        let warnings = issues.filter { !$0.isError && $0.message.contains("no installed application") }
        XCTAssertEqual(Set(warnings.map(\.path)), ["cells[0].component.action", "actionRules[0].add", "onClick"])
        XCTAssertTrue(warnings.allSatisfy { $0.message.contains("note in History") })
        XCTAssertEqual(warnings.first { $0.path.hasPrefix("cells") }?.cellId, "b")
    }

    func testAKnownApplicationHasNoWarningAndNoManifestMeansNothingToResolveFrom() throws {
        let t = try template(#","onClick":"openApp""#)
        let known = lookup(bundles: ["com.nobody.Nothing": "/x", "com.ivg.webwatcher": "/y"])
        XCTAssertEqual(withLookup(known) { t.validate(manifest: manifest) }.filter { $0.message.contains("application") }.map(\.message), [])
        let noManifest = withLookup(known) { t.validate(manifest: nil) }
        XCTAssertTrue(noManifest.contains { $0.path == "onClick" && $0.message.contains("names none") }, "onClick with no manifest has no app to open")
    }

    func testBadShapesAreErrors() throws {
        let t = try HeraldJSON.decoder().decode(HeraldTemplate.self, from: Data("""
        {"name":"t","app":"a","actionRules":[{"add":{"id":"x","label":"X","kind":"openApp","bundleId":"nope","path":"/Applications/Thing"}}]}
        """.utf8))
        let errors = t.validate().filter { $0.isError }.map(\.path)
        XCTAssertTrue(errors.contains { $0.hasSuffix(".bundleId") }); XCTAssertTrue(errors.contains { $0.hasSuffix(".path") })
    }

    // MARK: Running it

    func testThePlanCarriesTheActionsOwnTargetAndNeedsNoApproval() throws {
        let runner = ActionRunner()
        let inv = ActionInvocation(notification: HeraldNotification(app: "a", title: "t"), fields: [:], extra: [:], template: nil, imagePath: nil)
        func plan(_ a: HeraldAction, _ origin: HeraldActionOrigin) -> Result<ActionPlan, ActionError> { runner.plan(a, origin: origin, invocation: inv) }
        XCTAssertEqual(try plan(HeraldAction(id: "o", label: "Open", kind: .openApp, bundleId: " com.apple.mail "), .template).get(),
                       .openApp(bundleId: "com.apple.mail", path: nil))
        XCTAssertEqual(try plan(HeraldAction(id: "o", label: "Open", kind: .openApp), .issuer).get(), .openApp(bundleId: nil, path: nil), "none: the issuing app")
        XCTAssertEqual(try plan(HeraldAction(id: "o", label: "Open", kind: .openApp, path: "~/Applications/X.app"), .issuer).get(),
                       .openApp(bundleId: nil, path: "~/Applications/X.app"))
        XCTAssertThrowsError(try plan(HeraldAction(id: "o", label: "Open", kind: .openApp, bundleId: "nope"), .issuer).get())
        XCTAssertThrowsError(try plan(HeraldAction(id: "o", label: "Open", kind: .openApp, path: "/bin/zsh"), .issuer).get(), "only applications")
        for origin in [HeraldActionOrigin.issuer, .template] {
            XCTAssertEqual(ActionRunner.gate(for: HeraldAction(id: "o", label: "O", kind: .openApp), origin: origin), .open,
                           "bringing an app forward runs no code, so there is nothing to confirm")
        }
        XCTAssertNil(runner.approvalKey(for: HeraldAction(id: "o", label: "O", kind: .openApp)))
        XCTAssertEqual(ActionRunner.describe(HeraldAction(id: "o", label: "O", kind: .openApp, bundleId: "com.apple.mail")), "open app: com.apple.mail")
    }

    func testAnUnknownApplicationLeavesANoteInHistoryAndNothingElse() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("herald-openapp-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = HistoryStore(directory: dir)
        store.upsert(HeraldHistoryItem(id: "1", app: "a", notification: HeraldNotification(app: "a", id: "1", title: "t"),
                                       deliveredAt: Date(timeIntervalSince1970: 1_700_000_000)))
        // What the controller does when nothing resolves: record the note, leave the item alone.
        let candidates = HeraldOpenAppResolver.candidates(bundleId: "com.nobody.Nothing", path: nil, manifest: nil)
        XCTAssertNil(HeraldOpenAppResolver.resolve(candidates, lookup: lookup()))
        store.update(app: "a", id: "1") { $0.actionNote = HeraldOpenAppResolver.notFoundNote(label: "Open WebWatcher") }
        let item = try XCTUnwrap(HistoryStore(directory: dir).item(app: "a", id: "1"))
        XCTAssertEqual(item.actionNote, "Open WebWatcher: no installed application found", "the note survives a restart")
        XCTAssertNil(item.dismissedAt, "the banner stays")
        XCTAssertNil(item.actionUsed)
    }

    // MARK: Schema

    func testTheSchemaDocumentsTheKindAndTheKeys() throws {
        let doc = String(decoding: try HeraldJSON.encoder().encode(ComponentSchema.document()), as: UTF8.self)
        for needle in ["openApp", "bundleId", "onClick"] { XCTAssertTrue(doc.contains(needle), needle) }
    }
}
