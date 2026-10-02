import XCTest
import HeraldClient
@testable import HeraldCore

/// Issue #60: a button's `style` is normal, prominent or destructive (and the quiet cancel). Destructive draws the
/// label in red and asks for confirmation before running; the old `destructive: true` still decodes.
final class ButtonStyleTests: XCTestCase {
    private func component(_ json: String) throws -> HeraldComponent {
        try HeraldJSON.decoder().decode(HeraldComponent.self, from: Data(json.utf8))
    }

    func testTheOldDestructiveFlagDecodesAsTheDestructiveStyle() throws {
        guard case .button(let b) = try component(#"{"type":"button","actionRef":"archive","destructive":true}"#) else { return XCTFail() }
        XCTAssertEqual(b.style, "destructive")
        guard case .button(let plain) = try component(#"{"type":"button","actionRef":"archive","destructive":false}"#) else { return XCTFail() }
        XCTAssertNil(plain.style, "false says nothing")
        guard case .button(let both) = try component(#"{"type":"button","actionRef":"x","style":"prominent","destructive":true}"#) else { return XCTFail() }
        XCTAssertEqual(both.style, "prominent", "an explicit style wins over the old flag")
        // It is written back as a style, never as the flag.
        let text = String(decoding: try HeraldJSON.encoder().encode(HeraldComponent.button(b)), as: UTF8.self)
        XCTAssertTrue(text.contains("\"style\":\"destructive\""), text)
        XCTAssertFalse(text.contains("\"destructive\":"), text)
    }

    func testStylesParseAndDefaultMeansNormal() {
        XCTAssertEqual(HeraldActionStyle.parse(nil), .normal)
        XCTAssertEqual(HeraldActionStyle.parse("default"), .normal)
        XCTAssertEqual(HeraldActionStyle.parse("normal"), .normal)
        XCTAssertEqual(HeraldActionStyle.parse("prominent"), .prominent)
        XCTAssertEqual(HeraldActionStyle.parse("destructive"), .destructive)
        XCTAssertEqual(HeraldActionStyle.parse("cancel"), .cancel)
        XCTAssertEqual(HeraldActionStyle.parse("whatever"), .normal)
    }

    func testValidationAcceptsTheNewNamesAndRejectsOthers() throws {
        func issues(_ style: String) throws -> [HeraldTemplateIssue] {
            let t = try HeraldJSON.decoder().decode(HeraldTemplate.self, from: Data("""
            {"name":"s","app":"a","layoutVersion":2,"grid":{"rows":1,"cols":1,"rowSizes":["auto"],"colSizes":["fill"],"gap":8,"padding":10,"width":300},
             "cells":[{"id":"b","row":0,"col":0,"component":{"type":"button","actionRef":"x","style":"\(style)"}}]}
            """.utf8))
            return t.validate().filter { $0.isError }
        }
        for ok in ["normal", "prominent", "destructive", "cancel", "default"] { XCTAssertEqual(try issues(ok).count, 0, ok) }
        let bad = try issues("loud")
        XCTAssertEqual(bad.count, 1)
        XCTAssertTrue(bad[0].message.contains("normal, prominent, destructive or cancel"), bad[0].message)
    }

    func testOnlyDestructiveAsksBeforeRunning() {
        func action(_ style: String?) -> HeraldAction { HeraldAction(id: "a", label: "A", kind: .callback, style: style) }
        XCTAssertTrue(ActionRunner.confirmsBeforeRunning(action("destructive")))
        for s in [nil, "default", "normal", "prominent", "cancel"] { XCTAssertFalse(ActionRunner.confirmsBeforeRunning(action(s)), s ?? "nil") }
    }

    // MARK: The inline question

    func testTheQuestionNamesTheButtonAndOffersItInRed() {
        let c = BannerConfirmation.destructiveAction(label: "Delete", name: "Acme")
        XCTAssertEqual(c.kind, .destructiveAction)
        XCTAssertTrue(c.title.contains("Delete"))
        XCTAssertEqual(c.buttons.map(\.choice), [.once, .cancel])
        XCTAssertEqual(c.buttons.first?.title, "Delete")
        XCTAssertEqual(c.buttons.first?.role, .danger)
        XCTAssertEqual(BannerConfirmationButton.Role.danger.buttonStyleKind, "destructive")
        XCTAssertFalse(c.offers(.always), "a destructive action is asked about every time")
    }

    @MainActor func testOnceRunsAndCancelDoesNot() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("herald-style-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }
        let flow = ConfirmationFlow(registry: AppRegistry(file: dir.appendingPathComponent("apps.json")),
                                    approvals: TemplateCommandApprovals(file: dir.appendingPathComponent("a.json")))
        let surface = FakeSurface()
        flow.surface = surface
        let runner = FakeRunner()
        flow.askDestructive(app: "acme", id: "1", label: "Delete", name: "Acme") { runner.run() }
        XCTAssertEqual(surface.presented.map(\.kind), [.destructiveAction])
        XCTAssertEqual(runner.runs, 0, "nothing runs before the answer")
        XCTAssertTrue(flow.answer(app: "acme", id: "1", .cancel))
        XCTAssertEqual(runner.runs, 0)
        flow.askDestructive(app: "acme", id: "1", label: "Delete", name: "Acme") { runner.run() }
        XCTAssertTrue(flow.answer(app: "acme", id: "1", .once))
        XCTAssertEqual(runner.runs, 1)
        // The banner is gone: the answer is cancel and nothing runs.
        surface.up = []
        flow.askDestructive(app: "acme", id: "1", label: "Delete", name: "Acme") { runner.run() }
        XCTAssertEqual(runner.runs, 1)
    }

    func testThePreviewCanShowTheQuestion() throws {
        let c = try BannerConfirmation.fromPreview(#"destructiveAction"#, defaultName: "Acme")
        XCTAssertEqual(c.kind, .destructiveAction)
        let named = try BannerConfirmation.fromPreview(["kind": "destructive-action", "label": "Spam"], defaultName: "Acme")
        XCTAssertTrue(named.title.contains("Spam"))
    }
}
