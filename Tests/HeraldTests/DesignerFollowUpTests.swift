import XCTest
#if canImport(DesignerCore)
@testable import DesignerCore
@testable import HeraldClient
#else
@testable import HeraldCore
#endif

// The Designer's follow-up logic (DesignerModel): delay units, the run menu, the inline action, the issuer's
// declaration and its switch, and what the History line says.
@MainActor
final class DesignerFollowUpTests: XCTestCase {
    private func manifest(followUp: String = "") throws -> HeraldManifest {
        let json = """
        {"app":"demo","appName":"Demo","fields":[{"key":"title","type":"text"}],
         "actions":[{"id":"forward","label":"Forward","kind":"shortcut","shortcut":"Forward to phone"},
                    {"id":"open","label":"Open","kind":"url","url":"https://example.com"},
                    {"id":"log","label":"Log","kind":"script","script":"log.sh"}]\(followUp)}
        """
        return try HeraldJSON.decoder().decode(HeraldManifest.self, from: Data(json.utf8))
    }

    private func model(_ m: HeraldManifest?) -> DesignerModel {
        var b = DesignerBackend()
        b.issuers = { [DesignerIssuer(id: "demo", name: "Demo", hasManifest: m != nil)] }
        b.manifest = { _ in m }
        return DesignerModel(backend: b, app: "demo")
    }

    func testSecondsFromUnitsAreClamped() {
        XCTAssertEqual(DesignerModel.followUpSeconds(10, .minutes), 600)
        XCTAssertEqual(DesignerModel.followUpSeconds(2, .hours), 7200)
        XCTAssertEqual(DesignerModel.followUpSeconds(1, .seconds), 5)
        XCTAssertEqual(DesignerModel.followUpSeconds(200, .hours), 604_800)
    }

    func testSwitchOnPicksTheFirstRunnableActionAndAfterUsesUnits() throws {
        let m = model(try manifest())
        XCTAssertFalse(m.followUpIsOn)
        m.setFollowUpOn(true)
        XCTAssertTrue(m.followUpIsOn)
        XCTAssertEqual(m.draft.followUp?.after, 600)
        XCTAssertEqual(m.draft.followUp?.actionRef, "forward")
        XCTAssertEqual(m.followUpAfterDisplay.value, 10)
        XCTAssertEqual(m.followUpAfterDisplay.unit, .minutes)
        m.setFollowUpAfter(2, unit: .hours)
        XCTAssertEqual(m.draft.followUp?.after, 7200)
        XCTAssertEqual(m.followUpAfterDisplay.unit, .hours)
        m.setFollowUpAfter(90, unit: .seconds)
        XCTAssertEqual(m.draft.followUp?.after, 90)
        XCTAssertEqual(m.followUpAfterDisplay.unit, .seconds)
        m.setFollowUpOn(false)
        XCTAssertNil(m.draft.followUp)
    }

    func testChoicesListOnlyAllowedKindsAndSayWhoseTheyAre() throws {
        let m = model(try manifest())
        m.setFollowUpOn(true)
        m.commitActionEditor(ActionEditorRequest(mode: .addToTemplate,
            action: HeraldAction(id: "mine", label: "Mine", kind: .command, command: "echo hi")))
        m.commitActionEditor(ActionEditorRequest(mode: .addToTemplate,
            action: HeraldAction(id: "later", label: "Later", kind: .snooze)))
        let kinds = Set(m.followUpChoices.map(\.action.kind))
        XCTAssertTrue(kinds.isSubset(of: Set(HeraldFollowUp.allowedKinds)))
        XCTAssertEqual(Set(m.followUpChoices.map(\.id)), ["forward", "log", "mine"])
        XCTAssertEqual(m.followUpChoices.first { $0.id == "forward" }?.title, "Forward")
        XCTAssertEqual(m.followUpChoices.first { $0.id == "mine" }?.title, "Mine")
    }

    func testChoosingAnActionRefReplacesAnInlineAction() throws {
        let m = model(try manifest())
        m.setFollowUpOn(true)
        m.setFollowUpInlineAction(HeraldAction(id: "fwd", label: "Fwd", kind: .shortcut, shortcut: "S"))
        XCTAssertNil(m.draft.followUp?.actionRef)
        XCTAssertEqual(m.draft.followUp?.action?.id, "fwd")
        m.setFollowUpAction(ref: "log")
        XCTAssertEqual(m.draft.followUp?.actionRef, "log")
        XCTAssertNil(m.draft.followUp?.action)
        XCTAssertEqual(m.followUpRunSelection, "log")
    }

    func testNewActionFormStoresAnInlineFollowUpActionNotAButton() throws {
        let m = model(try manifest())
        m.setFollowUpOn(true)
        var req = m.newFollowUpActionRequest()
        XCTAssertEqual(req.mode, .followUp)
        XCTAssertEqual(req.action.kind, .shortcut)
        req.action.label = "Forward it"; req.action.id = "forward-it"; req.action.shortcut = "Forward to phone"
        let rulesBefore = m.draft.actionRules
        m.commitActionEditor(req)
        XCTAssertEqual(m.draft.followUp?.action?.shortcut, "Forward to phone")
        XCTAssertNil(m.draft.followUp?.actionRef)
        XCTAssertEqual(m.draft.actionRules, rulesBefore, "no button is added")
        XCTAssertNil(m.actionEditor)
        XCTAssertFalse(m.issues.contains { $0.isError && $0.path.hasPrefix("followUp") })
    }

    func testIssuerFollowUpSummaryAndSwitch() throws {
        let m = model(try manifest(followUp: #","followUp":{"after":"10m","actionRef":"forward"}"#))
        XCTAssertEqual(m.issuerFollowUp?.label, "Forward")
        XCTAssertEqual(m.issuerFollowUp?.after, 600)
        XCTAssertTrue(m.issuerFollowUpIsOn)
        XCTAssertEqual(DesignerModel.declaredFollowUpLine(manifest: m.manifest), "Declares a follow-up: Forward after 10 minutes")
        m.setIssuerFollowUpOn(false)
        XCTAssertEqual(m.draft.followUp, HeraldFollowUp(enabled: false))
        XCTAssertFalse(m.issuerFollowUpIsOn)
        XCTAssertFalse(m.followUpIsOn)
        XCTAssertNotNil(m.issuerFollowUp, "still shown so it can be turned back on")
        m.setIssuerFollowUpOn(true)
        XCTAssertNil(m.draft.followUp)
        // Your own follow-up replaces the issuer's: its line goes.
        m.setFollowUpOn(true)
        XCTAssertNil(m.issuerFollowUp)
    }

    func testIssuerLineFallsBackToTheRefAndSkipsDisabledOrAbsent() throws {
        let inline = try manifest(followUp: #","followUp":{"after":90,"action":{"id":"x","label":"Ping me","kind":"command","command":"say hi"}}"#)
        XCTAssertEqual(DesignerModel.declaredFollowUpLine(manifest: inline), "Declares a follow-up: Ping me after 90 seconds")
        let off = try manifest(followUp: #","followUp":{"enabled":false}"#)
        XCTAssertNil(DesignerModel.declaredFollowUpLine(manifest: off))
        XCTAssertNil(DesignerModel.declaredFollowUpLine(manifest: try manifest()))
        XCTAssertNil(DesignerModel.declaredFollowUpLine(manifest: nil))
    }

    func testFollowUpEditsGoThroughUndo() throws {
        let m = model(try manifest())
        m.setFollowUpOn(true)
        m.setFollowUpAfter(30, unit: .minutes)
        XCTAssertEqual(m.draft.followUp?.after, 1800)
        m.undo()
        XCTAssertEqual(m.draft.followUp?.after, 600)
    }

    private func storedJSON(_ m: DesignerModel) throws -> String {
        let t = try HeraldJSON.decoder().decode(HeraldTemplate.self, from: HeraldJSON.encoder().encode(m.draft))
        XCTAssertEqual(t.followUp, m.draft.followUp, "round-trips through the stored template JSON")
        let d = try HeraldJSON.encoder().encode(t.followUp)
        return String(decoding: d, as: UTF8.self)
    }

    func testTheChoiceMapsToTheStoredTemplateWhenTheIssuerDeclaresAFollowUp() throws {
        let m = model(try manifest(followUp: #","followUp":{"after":"15m","actionRef":"forward"}"#))
        XCTAssertEqual(m.followUpModes, [.off, .issuer, .own])
        XCTAssertEqual(m.followUpMode, .issuer)
        XCTAssertNil(m.draft.followUp)
        XCTAssertEqual(m.followUpModeTitle(.issuer), "The issuer\u{2019}s: Forward after 15 minutes")
        XCTAssertEqual(m.followUpExplanation, "Runs the issuer\u{2019}s Forward once if the banner is still up after 15 minutes. The banner stays.")

        m.setFollowUpMode(.off)
        XCTAssertEqual(m.followUpMode, .off)
        XCTAssertEqual(m.draft.followUp, HeraldFollowUp(enabled: false))
        XCTAssertTrue(try storedJSON(m).contains("\"enabled\":false"))
        XCTAssertTrue(m.followUpExplanation.hasPrefix("No follow-up"))
        XCTAssertNil(FollowUpResolver.declaration(manifest: m.manifest, notification: nil, template: m.draft))

        m.setFollowUpMode(.own)
        XCTAssertEqual(m.followUpMode, .own)
        XCTAssertEqual(m.draft.followUp?.after, 600)
        XCTAssertEqual(m.draft.followUp?.actionRef, "forward")
        XCTAssertNil(m.draft.followUp?.enabled)
        _ = try storedJSON(m)
        XCTAssertEqual(FollowUpResolver.declaration(manifest: m.manifest, notification: nil, template: m.draft)?.1, .template)
        XCTAssertTrue(m.followUpExplanation.contains("It replaces the issuer\u{2019}s."))

        m.setFollowUpMode(.issuer)
        XCTAssertEqual(m.followUpMode, .issuer)
        XCTAssertNil(m.draft.followUp)
        XCTAssertEqual(FollowUpResolver.declaration(manifest: m.manifest, notification: nil, template: m.draft)?.1, .manifest)

        // Off, then straight to my own: the disabled marker is replaced, not kept.
        m.setFollowUpMode(.off)
        m.setFollowUpMode(.own)
        XCTAssertEqual(m.followUpMode, .own)
        XCTAssertNil(m.draft.followUp?.enabled)
    }

    func testWithoutAnIssuerFollowUpTheChoicesAreOffAndMyOwn() throws {
        let m = model(try manifest())
        XCTAssertEqual(m.followUpModes, [.off, .own])
        XCTAssertEqual(m.followUpMode, .off)
        m.setFollowUpMode(.own)
        XCTAssertEqual(m.followUpMode, .own)
        XCTAssertNotNil(m.draft.followUp)
        XCTAssertFalse(m.followUpExplanation.contains("replaces"))
        m.setFollowUpMode(.off)
        XCTAssertNil(m.draft.followUp, "nothing to switch off: no marker is stored")
        XCTAssertEqual(m.followUpMode, .off)
    }
}
