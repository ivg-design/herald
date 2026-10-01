import XCTest
#if canImport(DesignerCore)
@testable import DesignerCore
@testable import HeraldClient
#else
@testable import HeraldCore
#endif

// Tests for the Designer's pure model (Sources/Herald/Designer/DesignerModel.swift).
//
// This directory is not a SwiftPM target yet: DesignerModel.swift is Foundation + HeraldClient only, so to
// run these add "Designer/DesignerModel.swift" to the `sources:` of the HeraldCore target in Package.swift,
// and move this file into Tests/HeraldTests (or add a test target for this folder).
final class DesignerModelTests: XCTestCase {
    // MARK: Helpers

    private func text(_ binding: String) -> HeraldComponent { .text(HeraldTextComponent(binding: binding, style: .body)) }

    /// 3 x 4 grid with: title (0,1) spanning 2 columns, image (0,0) spanning 3 rows, time (1,3).
    private func sample() -> HeraldTemplate {
        var t = HeraldTemplate.blank(name: "t", app: "demo")
        t.cells = [
            HeraldCell(id: "image", row: 0, col: 0, rowSpan: 3, component: .image(HeraldImageComponent())),
            HeraldCell(id: "title", row: 0, col: 1, colSpan: 2, component: text("{title}")),
            HeraldCell(id: "time", row: 1, col: 3, component: .timestamp(HeraldTimestampComponent())),
        ]
        return t
    }

    private func ids(_ t: HeraldTemplate) -> [String] { t.cells.map(\.id) }

    // MARK: Payloads and rects

    func testDragPayloadRoundTrip() {
        for p in [DragPayload.component("text"), .field("extra.queue"), .action("mark-read"), .cell("c3"), .rive("bell-2")] {
            XCTAssertEqual(DragPayload(string: p.string), p)
        }
        XCTAssertNil(DragPayload(string: "hello"))
        XCTAssertNil(DragPayload(string: "herald-designer:cell:"))
        XCTAssertNil(DragPayload(string: "herald-designer:bogus:x"))
    }

    func testSlotRectGeometry() {
        let a = SlotRect(row: 0, col: 0, rowSpan: 2, colSpan: 2), b = SlotRect(row: 1, col: 1, rowSpan: 2, colSpan: 2)
        XCTAssertTrue(a.intersects(b))
        XCTAssertEqual(a.union(b), SlotRect(row: 0, col: 0, rowSpan: 3, colSpan: 3))
        XCTAssertEqual(SlotRect.bounding(GridSlot(2, 3), GridSlot(0, 1)), SlotRect(row: 0, col: 1, rowSpan: 3, colSpan: 3))
        XCTAssertEqual(a.slots.count, 4)
        XCTAssertFalse(a.intersects(SlotRect(row: 2, col: 0)))
    }

    // MARK: Place, move

    func testPlaceCreatesAndReplaces() {
        var t = sample()
        let id = GridEditing.place(.spacer, at: GridSlot(2, 2), in: &t)
        XCTAssertEqual(id, "c1")
        XCTAssertEqual(t.cell(withID: "c1")?.align, .center)
        // Dropping on an occupied slot replaces the component and keeps the cell's area.
        let again = GridEditing.place(text("{body}"), at: GridSlot(1, 1), in: &t)   // inside "title"? no: row 1 col 1 is free
        XCTAssertNotNil(again)
        let onTitle = GridEditing.place(text("{subtitle}"), at: GridSlot(0, 2), in: &t)
        XCTAssertEqual(onTitle, "title")
        XCTAssertEqual(t.cell(withID: "title")?.colSpan, 2)
        XCTAssertEqual(t.cell(withID: "title")?.component, text("{subtitle}"))
        XCTAssertNil(GridEditing.place(.spacer, at: GridSlot(3, 0), in: &t))   // outside the grid
    }

    func testMoveToFreeSlotClipsSpan() {
        var t = sample()
        XCTAssertTrue(GridEditing.move(cell: "title", to: GridSlot(2, 3), in: &t))   // colSpan 2 would run off the grid
        let c = t.cell(withID: "title")!
        XCTAssertEqual([c.row, c.col, c.rowSpan, c.colSpan], [2, 3, 1, 1])
    }

    func testMoveOntoOccupiedSwapsComponents() {
        var t = sample()
        XCTAssertTrue(GridEditing.move(cell: "title", to: GridSlot(1, 3), in: &t))
        XCTAssertEqual(t.cell(withID: "title")?.component, .timestamp(HeraldTimestampComponent()))
        XCTAssertEqual(t.cell(withID: "time")?.component, text("{title}"))
        XCTAssertEqual(t.cell(withID: "title")?.colSpan, 2)   // areas stay
        XCTAssertFalse(GridEditing.move(cell: "title", to: GridSlot(0, 1), in: &t))   // onto itself
    }

    func testMoveReducesSpanWhereItWouldOverlap() {
        var t = sample()
        // "image" is 3 rows tall in column 0; move it to column 3 where "time" sits at row 1.
        XCTAssertTrue(GridEditing.move(cell: "image", to: GridSlot(0, 3), in: &t))   // free slot (0,3)
        let c = t.cell(withID: "image")!
        XCTAssertEqual([c.row, c.col], [0, 3])
        XCTAssertEqual(c.rowSpan, 1)   // (1,3) is taken, so it shrinks to one row
    }

    // MARK: Resize

    func testResizeStopsAtNeighbours() {
        var t = sample()
        let r = GridEditing.resize(cell: "title", rowSpan: 1, colSpan: 3, in: &t)   // (0,3) is free
        XCTAssertEqual(r?.colSpan, 3)
        let r2 = GridEditing.resize(cell: "title", rowSpan: 3, colSpan: 3, in: &t)   // (1,1) and (1,2) are free, (1,3) is "time"
        XCTAssertEqual(r2?.rowSpan, 3); XCTAssertEqual(r2?.colSpan, 2)
        XCTAssertTrue(GridEditing.isFree(GridEditing.rect(ofCell: "title", in: t)!, in: t, excluding: ["title"]))
        let r3 = GridEditing.resize(cell: "title", rowSpan: 0, colSpan: 0, in: &t)   // never below 1
        XCTAssertEqual(r3?.rowSpan, 1); XCTAssertEqual(r3?.colSpan, 1)
        XCTAssertNil(GridEditing.resize(cell: "nope", rowSpan: 1, colSpan: 1, in: &t))
    }

    // MARK: Merge and split

    func testMergeKeepsFirstRealComponent() {
        var t = sample()
        let merged = GridEditing.merge(SlotRect(row: 0, col: 1, rowSpan: 2, colSpan: 2), in: &t)   // title + free slots
        XCTAssertEqual(merged, "title")
        let c = t.cell(withID: "title")!
        XCTAssertEqual([c.row, c.col, c.rowSpan, c.colSpan], [0, 1, 2, 2])
        XCTAssertEqual(ids(t).sorted(), ["image", "time", "title"])
    }

    func testMergeExpandsToWholeCells() {
        var t = sample()
        // Selecting just (1,0)-(1,1) cuts through "image" (rows 0-2 of column 0): the merge takes all of it.
        let merged = GridEditing.merge(SlotRect(row: 1, col: 0, rowSpan: 1, colSpan: 2), in: &t)
        XCTAssertEqual(merged, "image")
        let c = t.cell(withID: "image")!
        XCTAssertEqual([c.row, c.col, c.rowSpan, c.colSpan], [0, 0, 3, 3])
        XCTAssertNil(t.cell(withID: "title"), "title lay inside the merged area and was dropped")
    }

    func testMergeOfEmptySlotsMakesASpacer() {
        var t = sample()
        let merged = GridEditing.merge(SlotRect(row: 2, col: 1, rowSpan: 1, colSpan: 3), in: &t)
        XCTAssertNotNil(merged)
        let c = t.cell(withID: merged!)!
        XCTAssertEqual(c.component, .spacer)
        XCTAssertEqual(c.colSpan, 3)
        XCTAssertNil(GridEditing.merge(SlotRect(row: 0, col: 3), in: &t), "one slot is nothing to merge")
    }

    func testSingleSlotCannotMerge() {
        let t = sample()
        XCTAssertFalse(GridEditing.canMerge(SlotRect(row: 2, col: 3), in: t))
        XCTAssertTrue(GridEditing.canMerge(SlotRect(row: 2, col: 2, rowSpan: 1, colSpan: 2), in: t))
    }

    func testSplitKeepsComponentAtOrigin() {
        var t = sample()
        XCTAssertTrue(GridEditing.split(cell: "title", in: &t))
        let c = t.cell(withID: "title")!
        XCTAssertEqual([c.rowSpan, c.colSpan], [1, 1])
        XCTAssertEqual(c.component, text("{title}"))
        XCTAssertFalse(GridEditing.split(cell: "title", in: &t))   // already one slot
        // A spacer placeholder just disappears when split.
        let sp = GridEditing.merge(SlotRect(row: 2, col: 1, rowSpan: 1, colSpan: 2), in: &t)!
        XCTAssertTrue(GridEditing.split(cell: sp, in: &t))
        XCTAssertNil(t.cell(withID: sp))
    }

    // MARK: Delete, duplicate

    func testDeleteKeepsAMergeAsSpacer() {
        var t = sample()
        XCTAssertEqual(GridEditing.remove(cell: "title", in: &t), .replacedWithSpacer)
        XCTAssertEqual(t.cell(withID: "title")?.component, .spacer)
        XCTAssertEqual(GridEditing.remove(cell: "title", in: &t), .removed)
        XCTAssertEqual(GridEditing.remove(cell: "time", in: &t), .removed)
        XCTAssertEqual(GridEditing.remove(cell: "time", in: &t), .notFound)
    }

    func testDuplicateFindsFreeSlotThenAddsARow() {
        var t = sample()
        let copy = GridEditing.duplicate(cell: "time", in: &t)!
        XCTAssertNotEqual(copy, "time")
        XCTAssertEqual(t.cell(withID: copy)?.component, .timestamp(HeraldTimestampComponent()))
        // Fill every free slot, then duplicate again: a row is added.
        for r in 0..<3 { for c in 0..<4 where GridEditing.cell(at: GridSlot(r, c), in: t) == nil { GridEditing.place(.spacer, at: GridSlot(r, c), in: &t) } }
        let rowsBefore = t.grid!.rows
        let more = GridEditing.duplicate(cell: "time", in: &t)
        XCTAssertNotNil(more)
        XCTAssertEqual(t.grid!.rows, rowsBefore + 1)
        XCTAssertEqual(t.cell(withID: more!)?.row, rowsBefore)
        XCTAssertTrue(t.validate().filter(\.isError).isEmpty)
    }

    // MARK: Tracks

    func testInsertAndRemoveRowsKeepCellsConsistent() {
        var t = sample()
        XCTAssertTrue(GridEditing.insertRow(at: 1, in: &t))      // splits "image" (rows 0-2) across the new row
        XCTAssertEqual(t.grid!.rows, 4)
        XCTAssertEqual(t.grid!.rowSizes.count, 4)
        XCTAssertEqual(t.cell(withID: "image")?.rowSpan, 4)
        XCTAssertEqual(t.cell(withID: "time")?.row, 2)
        XCTAssertTrue(GridEditing.removeRow(at: 1, in: &t))
        XCTAssertEqual(t.cell(withID: "image")?.rowSpan, 3)
        XCTAssertEqual(t.cell(withID: "time")?.row, 1)
        XCTAssertTrue(GridEditing.removeColumn(at: 3, in: &t))   // "time" lived only there
        XCTAssertNil(t.cell(withID: "time"))
        XCTAssertEqual(t.grid!.cols, 3)
        XCTAssertTrue(t.validate().filter(\.isError).isEmpty)
        while GridEditing.removeRow(at: 0, in: &t) {}
        XCTAssertEqual(t.grid!.rows, 1)   // never below one
    }

    func testTrackLimits() {
        var t = HeraldTemplate.blank(name: "t", app: "a")
        while GridEditing.insertColumn(at: t.grid!.cols, in: &t) {}
        XCTAssertEqual(t.grid!.cols, HeraldTemplate.maxGridTracks)
    }

    // MARK: Binding and defaults

    func testBindTokenRules() {
        XCTAssertEqual(DesignerPalette.bind(token: "sender", into: text("{title}")), text("{sender}"))
        XCTAssertEqual(DesignerPalette.bind(token: "sender", into: text("")), text("{sender}"))
        XCTAssertEqual(DesignerPalette.bind(token: "sender", into: text("{title} - {count}")), text("{title} - {count} {sender}"))
        XCTAssertEqual(DesignerPalette.bind(token: "title", into: text("{title} - {count}")), text("{title} - {count}"))
        if case .image(let p)? = DesignerPalette.bind(token: "photo", into: .image(HeraldImageComponent())) { XCTAssertEqual(p.binding, "{photo}") } else { XCTFail() }
        XCTAssertNil(DesignerPalette.bind(token: "x", into: .spacer))
        XCTAssertNil(DesignerPalette.bind(token: "x", into: .actions(HeraldActionsComponent())))
    }

    func testFieldBecomesFittingComponent() {
        if case .image = DesignerPalette.component(forField: "image", type: nil) {} else { XCTFail() }
        if case .timestamp(let p) = DesignerPalette.component(forField: "receivedAt", type: .date) { XCTAssertEqual(p.binding, "{receivedAt}") } else { XCTFail() }
        if case .badge = DesignerPalette.component(forField: "count", type: .number) {} else { XCTFail() }
        if case .text(let p) = DesignerPalette.component(forField: "subtitle", type: nil) { XCTAssertEqual(p.style, .subtitle) } else { XCTFail() }
    }

    func testEveryPaletteComponentIsValid() {
        let m = HeraldManifest(app: "demo", fields: [HeraldField(key: "count", type: .number)],
                               actions: [HeraldButton(label: "Open", url: "https://x.example")],
                               assets: [HeraldAsset(id: "bell", type: "rive", path: "/tmp/bell.riv", stateMachine: "Main")])
        var t = HeraldTemplate.blank(name: "all", app: "demo")
        let actions = ActionResolver.resolveDetailed(issuer: m.actions, rules: [])
        for (i, entry) in DesignerPalette.components.enumerated() {
            t.cells.append(HeraldCell(id: "c\(i)", row: i % 3, col: i / 3, component: DesignerPalette.makeComponent(type: entry.type, manifest: m, actions: actions)))
        }
        XCTAssertEqual(DesignerPalette.components.count, HeraldComponent.typeNames.count)
        XCTAssertEqual(DesignerPalette.components.map(\.type), HeraldComponent.typeNames)
        let errors = t.validate(manifest: m).filter(\.isError)
        XCTAssertTrue(errors.isEmpty, "\(errors)")
    }

    // MARK: Action rules

    private let issuer = [HeraldButton(label: "Mark as Read", callback: HeraldCallback()),
                          HeraldButton(label: "Archive", style: "destructive", callback: HeraldCallback())]

    private func resolved(_ rules: [HeraldActionRule]) -> [HeraldAction] { ActionResolver.resolve(issuer: issuer, rules: rules) }

    func testOverrideRulesHideRelabelRestyleAndClean() {
        var rules: [HeraldActionRule] = []
        ActionRules.override("archive", in: &rules) { $0.relabel = "Archive it" }
        ActionRules.override("archive", in: &rules) { $0.style = "default" }
        XCTAssertEqual(rules.count, 1, "one override rule per issuer action")
        XCTAssertEqual(resolved(rules).map(\.label), ["Mark as Read", "Archive it"])
        XCTAssertEqual(resolved(rules).last?.style, "default")
        ActionRules.override("mark-as-read", in: &rules) { $0.hide = true }
        XCTAssertEqual(resolved(rules).map(\.id), ["archive"])
        ActionRules.override("mark-as-read", in: &rules) { $0.hide = false }
        XCTAssertEqual(resolved(rules).count, 2)
        ActionRules.override("archive", in: &rules) { $0.relabel = ""; $0.style = nil }
        XCTAssertTrue(rules.isEmpty, "an override that changes nothing is removed")
    }

    func testOrderRulesProduceExactOrderAndVanishWhenNatural() {
        var rules: [HeraldActionRule] = []
        let natural = resolved([]).map(\.id)
        ActionRules.applyOrder(["archive", "mark-as-read"], natural: natural, in: &rules)
        XCTAssertEqual(resolved(rules).map(\.id), ["archive", "mark-as-read"])
        ActionRules.applyOrder(natural, natural: natural, in: &rules)
        XCTAssertTrue(rules.isEmpty)
        // A hand-written rule survives reordering.
        rules = [HeraldActionRule(match: "archive", relabel: "Done")]
        ActionRules.applyOrder(["archive", "mark-as-read"], natural: natural, in: &rules)
        XCTAssertEqual(rules.first?.relabel, "Done")
        XCTAssertEqual(resolved(rules).first?.label, "Done")
    }

    func testMergeOrderKeepsTheUsersOrderAcrossMembershipChanges() {
        XCTAssertEqual(ActionRules.mergeOrder(previous: ["c", "a", "b"], natural: ["a", "b"]), ["a", "b"])
        XCTAssertEqual(ActionRules.mergeOrder(previous: ["b", "a"], natural: ["a", "b", "x"]), ["b", "a", "x"])
        XCTAssertEqual(ActionRules.mergeOrder(previous: ["b"], natural: ["a", "b"]), ["a", "b"])
    }

    func testAddReplaceRemoveTemplateActions() {
        var rules: [HeraldActionRule] = []
        let follow = HeraldAction(id: "follow-up", label: "Follow up", kind: .shortcut, shortcut: "Create follow-up", input: "{title}")
        ActionRules.addAction(follow, in: &rules)
        ActionRules.applyOrder(["follow-up", "mark-as-read", "archive"], natural: resolved(rules).map(\.id), in: &rules)
        XCTAssertEqual(resolved(rules).map(\.id), ["follow-up", "mark-as-read", "archive"])
        // A new override goes before the order rules so they keep the last word.
        ActionRules.override("archive", in: &rules) { $0.hide = true }
        XCTAssertTrue(ActionRules.isOrderRule(rules.last!))
        XCTAssertEqual(resolved(rules).map(\.id), ["follow-up", "mark-as-read"])
        var renamed = follow; renamed.id = "followup"; renamed.label = "Follow-up"
        ActionRules.replaceAction(oldID: "follow-up", with: renamed, in: &rules)
        XCTAssertEqual(resolved(rules).first?.id, "followup")
        XCTAssertEqual(resolved(rules).first?.shortcut, "Create follow-up")
        ActionRules.removeAction("followup", in: &rules)
        XCTAssertEqual(resolved(rules).map(\.id), ["mark-as-read"])
        XCTAssertEqual(ActionRules.uniqueID("open", taken: ["open", "open-2"]), "open-3")
    }

    // MARK: Empty behaviour

    func testEmptyBehaviourOnEveryComponent() {
        for entry in DesignerPalette.components {
            let c = DesignerPalette.makeComponent(type: entry.type, manifest: nil, actions: [])
            let on = c.settingEmptyBehavior(.keep)
            if entry.type == "spacer" { XCTAssertEqual(on.emptyBehavior, nil) } else { XCTAssertEqual(on.emptyBehavior, .keep, entry.type) }
            XCTAssertNil(on.settingEmptyBehavior(nil).emptyBehavior)
        }
        XCTAssertFalse(HeraldComponent.issuerIcon(HeraldIssuerIconComponent()).canBeEmpty)
        XCTAssertFalse(HeraldComponent.timestamp(HeraldTimestampComponent()).canBeEmpty, "a blank binding shows the delivery time")
        XCTAssertTrue(HeraldComponent.timestamp(HeraldTimestampComponent(binding: "{x}")).canBeEmpty)
        XCTAssertTrue(text("{x}").canBeEmpty)
    }
}

// MARK: - Model

@MainActor
final class DesignerModelStateTests: XCTestCase {
    final class Store {
        var templates: [HeraldTemplate] = []
        var manifest = HeraldManifest(
            app: "demo", appName: "Demo",
            fields: [HeraldField(key: "title", type: .text, sample: .text("2 new from Acme")),
                     HeraldField(key: "count", type: .number, sample: .number(2)),
                     HeraldField(key: "image", type: .image)],
            actions: [HeraldButton(label: "Mark as Read", callback: HeraldCallback()),
                      HeraldButton(label: "Archive", style: "destructive", callback: HeraldCallback())])
        var sent: [HeraldNotification] = []
        var last: HeraldHistoryItem?
    }

    private func make(_ store: Store = Store()) -> (DesignerModel, Store) {
        var b = DesignerBackend()
        b.issuers = { [DesignerIssuer(id: "demo", name: "Demo", hasManifest: true)] }
        b.manifest = { _ in store.manifest }
        b.templates = { app in store.templates.filter { $0.app == app } }
        b.saveTemplate = { t in store.templates.removeAll { $0.name == t.name && $0.app == t.app }; store.templates.append(t); return true }
        b.deleteTemplate = { app, name in store.templates.removeAll { $0.name == name && $0.app == app }; return true }
        b.setDefaultTemplate = { _, name in store.manifest.defaultTemplate = name; return true }
        b.lastItem = { _ in store.last }
        b.sendTest = { n in store.sent.append(n); return n.id ?? "" }
        return (DesignerModel(backend: b), store)
    }

    func testStartsOnANewBlankTemplate() {
        let (m, _) = make()
        XCTAssertEqual(m.app, "demo")
        XCTAssertTrue(m.isNew)
        XCTAssertFalse(m.isDirty, "a pristine new template has no edits to lose")
        XCTAssertEqual(m.draft.name, "template-1")
        XCTAssertEqual(m.grid.rows, 3); XCTAssertEqual(m.grid.cols, 4)
    }

    func testAddMergeSplitDeleteDuplicateAndUndo() {
        let (m, _) = make()
        m.addComponent(type: "text", at: GridSlot(0, 1))
        XCTAssertEqual(m.draft.cells.count, 1)
        XCTAssertEqual(m.selectedCellID, "c1")
        XCTAssertTrue(m.isDirty)

        m.select(slot: GridSlot(0, 1))
        m.select(slot: GridSlot(0, 2), extend: true)
        XCTAssertEqual(m.selection, SlotRect(row: 0, col: 1, rowSpan: 1, colSpan: 2))
        XCTAssertTrue(m.canMerge)
        m.mergeSelection()
        XCTAssertEqual(m.draft.cell(withID: "c1")?.colSpan, 2)
        XCTAssertTrue(m.canSplit)

        m.duplicateSelection()
        XCTAssertEqual(m.draft.cells.count, 2)

        m.select(cell: "c1")
        m.deleteSelection()                        // merged: becomes a spacer
        XCTAssertEqual(m.draft.cell(withID: "c1")?.component, .spacer)
        m.deleteSelection()                        // spacer: removed
        XCTAssertNil(m.draft.cell(withID: "c1"))

        m.undo(); m.undo()
        XCTAssertEqual(m.draft.cell(withID: "c1")?.colSpan, 2)
        XCTAssertNotEqual(m.draft.cell(withID: "c1")?.component, .spacer)
        m.redo()
        XCTAssertEqual(m.draft.cell(withID: "c1")?.component, .spacer)
        XCTAssertTrue(m.canUndo)
    }

    func testPropertyEditsCoalesceIntoOneUndoStep() {
        let (m, _) = make()
        m.addComponent(type: "text", at: GridSlot(0, 0))
        let before = m.draft
        for s in ["{t", "{ti", "{tit", "{title}"] {
            m.edit { t in if case .text(var p) = t.cells[0].component { p.binding = s; t.cells[0].component = .text(p) } }
        }
        m.undo()
        XCTAssertEqual(m.draft, before)
    }

    func testDropFieldOntoOccupiedAndEmptySlots() {
        let (m, _) = make()
        m.handle(.field("count"), at: GridSlot(0, 3))                 // number -> badge on an empty slot
        if case .badge(let p)? = m.draft.cell(withID: "c1")?.component { XCTAssertEqual(p.binding, "{count}") } else { XCTFail() }
        m.handle(.component("text"), at: GridSlot(1, 1))
        m.handle(.field("title"), at: GridSlot(1, 1))                  // text cell: token replaces the lone token
        m.handle(.cell("c2"), at: GridSlot(2, 1))                      // move
        XCTAssertEqual(m.draft.cell(withID: "c2")?.row, 2)
        m.handle(.action("mark-as-read"), at: GridSlot(2, 2))
        if case .button(let p)? = m.draft.cell(withID: "c3")?.component { XCTAssertEqual(p.actionRef, "mark-as-read") } else { XCTFail() }
        m.handle(.field("title"), at: GridSlot(2, 2))                  // a button takes no binding
        XCTAssertEqual(m.status?.kind, .error)
    }

    func testSaveRenameDeleteAndDefault() {
        let (m, s) = make()
        m.addComponent(type: "text", at: GridSlot(0, 0))
        m.draft.name = "email"
        XCTAssertTrue(m.save())
        XCTAssertEqual(s.templates.map(\.name), ["email"])
        XCTAssertEqual(m.savedName, "email"); XCTAssertFalse(m.isDirty); XCTAssertFalse(m.isNew)

        m.setAsDefault()
        XCTAssertEqual(s.manifest.defaultTemplate, "email")
        m.draft.name = "email v2"
        XCTAssertTrue(m.save())
        XCTAssertEqual(s.templates.map(\.name), ["email v2"], "a rename removes the old file")
        XCTAssertEqual(s.manifest.defaultTemplate, "email v2", "the default follows a rename")

        m.draft.name = "../x"
        XCTAssertFalse(m.save())
        m.draft.name = "_hidden"
        XCTAssertFalse(m.save())
        m.draft.name = "email v2"

        m.duplicate()
        XCTAssertEqual(Set(s.templates.map(\.name)), ["email v2", "email v2 copy"])
        XCTAssertEqual(m.savedName, "email v2 copy")
        m.deleteSaved()
        XCTAssertEqual(s.templates.map(\.name), ["email v2"])
        XCTAssertEqual(m.savedName, "email v2")
    }

    func testRefusesToSaveAnInvalidTemplate() {
        let (m, s) = make()
        m.addComponent(type: "text", at: GridSlot(0, 0))
        m.edit { t in if case .text(var p) = t.cells[0].component { p.binding = ""; t.cells[0].component = .text(p) } }
        XCTAssertTrue(m.hasErrors)
        XCTAssertFalse(m.save())
        XCTAssertTrue(s.templates.isEmpty)
    }

    func testV1TemplateIsConvertedToAGrid() {
        let (m, s) = make()
        var v1 = HeraldTemplate(name: "old", app: "demo", layout: .hero)
        v1.title = "Hello"
        s.templates = [v1]
        m.refreshFromDisk()
        m.select(template: "old")
        XCTAssertTrue(m.draft.usesGrid)
        XCTAssertTrue(m.convertedFromV1)
        XCTAssertTrue(m.isDirty)
        XCTAssertEqual(m.draft.title, "Hello")
        XCTAssertTrue(m.save())
        XCTAssertTrue(s.templates.first { $0.name == "old" }!.usesGrid)
    }

    func testPreviewFieldsAndAbsentTokens() {
        let (m, _) = make()
        m.draft.extra = ["queue": "inbox", "blank": " "]
        XCTAssertEqual(m.previewFields["title"], .text("2 new from Acme"))
        XCTAssertEqual(m.previewFields["count"], .number(2))
        XCTAssertEqual(m.previewFields["image"], .text(DesignerModel.sampleImage), "a declared image field gets the stock picture")
        XCTAssertEqual(m.previewFields["extra.queue"], .text("inbox"))
        XCTAssertNil(m.previewFields["extra.blank"])
        m.absentTokens = ["count"]
        XCTAssertNil(m.previewFields["count"])
        // The empty-field behaviour follows: a badge bound to {count} is empty now.
        let badge = HeraldComponent.badge(HeraldBadgeComponent(binding: "{count}"))
        XCTAssertFalse(badge.hasContent(fields: m.previewFields, actions: []))
    }

    func testLastRealUsesTheNewestNotification() {
        let (m, s) = make()
        var n = HeraldNotification(app: "demo", id: "x", title: "Real one")
        n.buttons = [HeraldButton(label: "Archive", callback: HeraldCallback())]
        s.last = HeraldHistoryItem(id: "x", app: "demo", notification: n, deliveredAt: Date(), fields: ["title": .text("Real one")])
        m.refreshFromDisk()
        m.previewSource = .lastReal
        XCTAssertEqual(m.previewFields["title"], .text("Real one"))
        XCTAssertNil(m.previewFields["count"])
        XCTAssertEqual(m.previewActions.map(\.id), ["archive"])
    }

    func testActionEditingThroughTheModel() {
        let (m, _) = make()
        XCTAssertEqual(m.actionRows.map(\.id), ["mark-as-read", "archive"])
        m.setActionHidden("archive", true)
        XCTAssertEqual(m.actionRows.map(\.hidden), [false, true])
        m.setActionHidden("archive", false)
        m.setActionLabel("archive", label: "Archive it", original: "Archive")
        XCTAssertEqual(m.actionRows.last?.action.label, "Archive it")
        XCTAssertTrue(m.actionRows.last?.isRelabeled ?? false)
        m.resetAction("archive")
        XCTAssertTrue(m.draft.actionRules.isEmpty)

        var req = m.newActionRequest(kind: .shortcut)
        req.action.id = "follow-up"; req.action.label = "Follow up"; req.action.shortcut = "Create follow-up"; req.action.input = "{title}\n{url}"
        m.commitActionEditor(req)
        XCTAssertEqual(m.actionRows.map(\.origin), [.issuer, .issuer, .template])
        m.moveAction("follow-up", by: -2)
        XCTAssertEqual(m.actionRows.map(\.id), ["follow-up", "mark-as-read", "archive"])
        XCTAssertEqual(m.previewActions.map(\.id), ["follow-up", "mark-as-read", "archive"])
        m.moveAction("follow-up", by: -1)                                // already first: nothing happens
        XCTAssertEqual(m.actionRows.first?.id, "follow-up")

        m.editTemplateAction("follow-up")
        guard var edit = m.actionEditor else { return XCTFail() }
        edit.action.id = "followup"
        m.commitActionEditor(edit)
        XCTAssertEqual(m.actionRows.first?.id, "followup")
        m.removeTemplateAction("followup")
        XCTAssertEqual(m.actionRows.map(\.id), ["mark-as-read", "archive"])
    }

    func testRenamingATemplateActionFollowsButtonCells() {
        let (m, _) = make()
        var req = m.newActionRequest(kind: .command)
        req.action.id = "run"; req.action.command = "echo hi"
        m.commitActionEditor(req)
        m.handle(.action("run"), at: GridSlot(0, 0))
        m.editTemplateAction("run")
        var edit = m.actionEditor!
        edit.action.id = "run-it"
        m.commitActionEditor(edit)
        if case .button(let p)? = m.draft.cells.first?.component { XCTAssertEqual(p.actionRef, "run-it") } else { XCTFail() }
    }

    func testInlineActionEditing() {
        let (m, _) = make()
        m.addComponent(type: "iconButton", at: GridSlot(0, 3))
        m.editInlineAction(cell: "c1")
        var req = m.actionEditor!
        XCTAssertEqual(req.action.kind, .dismiss)
        req.action = HeraldAction(id: "snooze-1h", label: "Snooze", kind: .snooze, snoozeMinutes: 60)
        m.commitActionEditor(req)
        if case .iconButton(let p)? = m.draft.cell(withID: "c1")?.component {
            XCTAssertEqual(p.action?.snoozeMinutes, 60); XCTAssertNil(p.actionRef)
        } else { XCTFail() }
        XCTAssertNil(m.actionEditor)
    }

    func testTestNotificationCarriesPreviewDataAndTemplate() async {
        let (m, s) = make()
        m.addComponent(type: "text", at: GridSlot(0, 0))
        m.draft.name = "email"
        m.draft.extra = ["queue": "inbox"]
        XCTAssertTrue(m.save())
        await m.sendTest()
        let n = s.sent.last!
        XCTAssertEqual(n.title, "2 new from Acme")
        XCTAssertEqual(n.template, "email", "a saved, unchanged template is used as it is")
        XCTAssertNil(n.image, "the stock picture is not a real image")
        XCTAssertEqual(n.buttons?.map(\.label), ["Mark as Read", "Archive"])
        if case .object(let o)? = n.metadata { XCTAssertEqual(o["count"], .number(2)); XCTAssertNil(o["extra.queue"]) } else { XCTFail() }

        m.addComponent(type: "badge", at: GridSlot(0, 3))                   // now the draft differs from disk
        await m.sendTest()
        XCTAssertEqual(s.sent.last?.template, DesignerModel.testTemplateName)
        XCTAssertTrue(s.templates.contains { $0.name == DesignerModel.testTemplateName })
        m.refreshFromDisk()
        XCTAssertFalse(m.templates.contains { $0.name == DesignerModel.testTemplateName }, "the scratch template is never listed")
        XCTAssertEqual(s.templates.first { $0.name == "email" }?.cells.count, 1, "the saved template was not touched")
    }

    func testExternalChangeReloadsACleanDraftAndFlagsADirtyOne() {
        let (m, s) = make()
        m.addComponent(type: "text", at: GridSlot(0, 0))
        m.draft.name = "email"
        XCTAssertTrue(m.save())
        // An agent saves a new version while the draft is clean: the designer follows it.
        var agent = s.templates[0]
        agent.cells.append(HeraldCell(id: "agent", row: 2, col: 0, component: .spacer))
        s.templates = [agent]
        m.refreshFromDisk()
        XCTAssertNotNil(m.draft.cell(withID: "agent"))
        XCTAssertFalse(m.diskChanged)
        // ...but never over unsaved edits.
        m.addComponent(type: "badge", at: GridSlot(0, 3))
        var agent2 = s.templates[0]
        agent2.cells.removeAll { $0.id == "agent" }
        s.templates = [agent2]
        m.refreshFromDisk()
        XCTAssertTrue(m.diskChanged)
        XCTAssertNotNil(m.draft.cell(withID: "c2"))
        m.reloadFromDisk()
        XCTAssertNil(m.draft.cell(withID: "c2"))
        XCTAssertFalse(m.diskChanged)
    }

    func testDiscardIsConfirmedBeforeEditsAreLost() {
        let (m, s) = make()
        s.templates = [HeraldTemplate.blank(name: "other", app: "demo")]
        m.refreshFromDisk()
        m.addComponent(type: "text", at: GridSlot(0, 0))
        var asked = 0
        m.confirmDiscard = { asked += 1; return false }
        m.select(template: "other")
        XCTAssertEqual(asked, 1)
        XCTAssertNil(m.savedName, "declined: still on the draft")
        m.confirmDiscard = { asked += 1; return true }
        m.select(template: "other")
        XCTAssertEqual(m.savedName, "other")
    }

    func testTokenSuggestionsGroupFieldsStandardExtraAndCustom() {
        let (m, _) = make()
        m.draft.extra = ["queue": "inbox"]
        m.addCustomToken("{weird.key}")
        m.addCustomToken("not valid!")
        let keys = m.tokenSuggestions.map(\.key)
        XCTAssertEqual(keys.prefix(3), ["title", "count", "image"])
        XCTAssertTrue(keys.contains("subtitle")); XCTAssertTrue(keys.contains("extra.queue")); XCTAssertTrue(keys.contains("weird.key"))
        XCTAssertFalse(keys.contains("not valid!"))
        XCTAssertEqual(keys.count, Set(keys).count, "no duplicates")
        XCTAssertEqual(m.tokenSuggestions.first { $0.key == "count" }?.sample, "2")
    }

    func testEmptyBehaviourFollowsTheTemplateUnlessTheComponentSaysOtherwise() {
        let (m, _) = make()
        m.addComponent(type: "text", at: GridSlot(0, 0))
        m.edit { t in if case .text(var p) = t.cells[0].component { p.binding = "{nothing}"; t.cells[0].component = .text(p) } }
        let cell = m.draft.cells[0]
        XCTAssertTrue(m.isEmpty(cell))
        XCTAssertEqual(m.draft.behavior(for: cell.component), .collapse)
        m.edit { $0.collapseEmpty = false }
        XCTAssertEqual(m.draft.behavior(for: m.draft.cells[0].component), .keep)
        m.setEmptyBehavior(cell: "c1", .collapse)
        XCTAssertEqual(m.draft.behavior(for: m.draft.cells[0].component), .collapse, "the component's own choice wins")
        m.setEmptyBehavior(cell: "c1", nil)
        XCTAssertEqual(m.draft.behavior(for: m.draft.cells[0].component), .keep)
    }

    func testHidingAnActionKeepsTheOthersInTheirOrder() {
        let (m, _) = make()
        var req = m.newActionRequest(kind: .url)
        req.action.id = "site"; req.action.label = "Site"; req.action.url = "https://example.com"
        m.commitActionEditor(req)
        m.moveAction("site", by: -2)
        XCTAssertEqual(m.actionRows.map(\.id), ["site", "mark-as-read", "archive"])
        m.setActionHidden("mark-as-read", true)
        XCTAssertEqual(m.previewActions.map(\.id), ["site", "archive"])
        m.setActionHidden("site", true)
        XCTAssertEqual(m.previewActions.map(\.id), ["archive"])
        m.setActionHidden("mark-as-read", false)
        XCTAssertEqual(m.previewActions.map(\.id), ["mark-as-read", "archive"])
        m.resetAction("site")
        XCTAssertEqual(m.previewActions.map(\.id), ["mark-as-read", "archive", "site"], "an action that comes back takes its natural place")
    }

    func testTrackEditsKeepSelectionInBounds() {
        let (m, _) = make()
        m.addComponent(type: "text", at: GridSlot(2, 3))
        m.select(cell: "c1")
        m.removeRow(at: 2)
        XCTAssertNil(m.draft.cell(withID: "c1"))
        XCTAssertNil(m.selection)
        m.insertRow(at: 2)
        XCTAssertEqual(m.grid.rows, 3)
        XCTAssertEqual(m.draft.grid?.rowSizes.count, 3)
    }
}


// MARK: - Track sizes, drop previews, modes, animations, bundles (Herald 1.2 designer work)

final class DesignerTrackTests: XCTestCase {
    func testClampedPointsAreWholeAndBounded() {
        let g = HeraldGrid.standard   // 400 wide
        XCTAssertEqual(GridEditing.clampedPoints(96.4, columns: true, in: g), 96)
        XCTAssertEqual(GridEditing.clampedPoints(-20, columns: true, in: g), GridEditing.minTrackPoints)
        XCTAssertEqual(GridEditing.clampedPoints(2000, columns: true, in: g), 400)
        XCTAssertEqual(GridEditing.clampedPoints(2000, columns: false, in: g), 800)
        XCTAssertEqual(GridEditing.clampedPoints(.nan, columns: false, in: g), GridEditing.minTrackPoints)
    }

    func testSetTrackWritesOneTrackAndKeepsTheRest() {
        var t = HeraldTemplate.blank(name: "t", app: "demo")
        XCTAssertTrue(GridEditing.setTrack(columns: true, index: 1, size: .points(120.6), in: &t))
        XCTAssertEqual(t.grid?.colSizes, [.points(72), .points(121), .fill, .points(56)])
        XCTAssertTrue(GridEditing.setTrack(columns: false, index: 2, size: .points(3), in: &t))
        XCTAssertEqual(t.grid?.rowSizes, [.auto, .auto, .points(GridEditing.minTrackPoints)])
        XCTAssertTrue(GridEditing.setTrack(columns: true, index: 1, size: .fill, in: &t))
        XCTAssertEqual(t.grid?.colSizes[1], .fill)
        XCTAssertFalse(GridEditing.setTrack(columns: true, index: 4, size: .fill, in: &t))
        XCTAssertFalse(GridEditing.setTrack(columns: false, index: -1, size: .auto, in: &t))
        XCTAssertTrue(t.validate().filter(\.isError).isEmpty)
    }

    func testSetTrackRepairsShortSizeLists() {
        var t = HeraldTemplate.blank(name: "t", app: "demo")
        t.grid?.colSizes = [.fill]       // a hand-written template with fewer sizes than columns
        XCTAssertTrue(GridEditing.setTrack(columns: true, index: 3, size: .points(40), in: &t))
        XCTAssertEqual(t.grid?.colSizes.count, 4)
        XCTAssertEqual(t.grid?.colSizes[3], .points(40))
    }
}

@MainActor
final class DesignerWorkflowTests: XCTestCase {
    var root: URL!
    /// The "assets folder": file names to bytes, shared with the backend closures.
    var folder: [String: Data] = [:]
    var saved: [HeraldTemplate] = []
    var manifest = HeraldManifest(app: "demo", appName: "Demo",
                                  fields: [HeraldField(key: "title", type: .text, sample: .text("Hello")),
                                           HeraldField(key: "count", type: .number, sample: .number(3))],
                                  assets: [HeraldAsset(id: "bell", type: "rive", path: "/nowhere/bell.riv", stateMachine: "Main", inputs: ["count"])])
    var infoLoads = 0

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("herald-designer-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        folder = ["bell.riv": Data(repeating: 1, count: 40), "hero.riv": Data(repeating: 2, count: 90)]
    }

    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: root) }

    private func fileURL(_ name: String) -> URL {
        let u = root.appendingPathComponent("assets").appendingPathComponent(name)
        try? FileManager.default.createDirectory(at: u.deletingLastPathComponent(), withIntermediateDirectories: true)
        if !FileManager.default.fileExists(atPath: u.path) { try? folder[name]?.write(to: u) }
        return u
    }

    private func make() -> DesignerModel {
        var b = DesignerBackend()
        b.issuers = { [DesignerIssuer(id: "demo", name: "Demo", hasManifest: true), DesignerIssuer(id: "other", name: "Other", hasManifest: false)] }
        b.manifest = { [unowned self] app in app == "demo" ? self.manifest : nil }
        b.templates = { [unowned self] app in self.saved.filter { $0.app == app } }
        b.saveTemplate = { [unowned self] t in self.saved.removeAll { $0.name == t.name && $0.app == t.app }; self.saved.append(t); return true }
        b.assetFiles = { [unowned self] _ in self.folder.keys.sorted().map { self.fileURL($0) } }
        b.installAsset = { [unowned self] _, a in
            guard let d = try? Data(contentsOf: URL(fileURLWithPath: a.path)) else { throw AssetError.missing(a.path) }
            self.folder[a.id + ".riv"] = d
        }
        b.removeAssetFile = { [unowned self] _, url in self.folder[url.lastPathComponent] = nil; return true }
        b.riveFile = { [unowned self] _, c in
            let name = c.asset.map { $0 + ".riv" } ?? c.path
            return name.flatMap { self.folder[$0] != nil ? self.fileURL($0) : nil }
        }
        b.riveInfo = { [unowned self] _ in
            self.infoLoads += 1
            return RiveFileInfo(artboards: [.init(name: "Main", width: 200, height: 100, defaultMachine: "Main",
                machines: [.init(name: "Main", inputs: [.init(name: "count", kind: .number), .init(name: "hover", kind: .bool)]),
                           .init(name: "Alt", inputs: [.init(name: "go", kind: .trigger)])], animations: ["Idle"])])
        }
        return DesignerModel(backend: b, app: "demo")
    }

    // MARK: Drop previews

    func testDropPreviewDescribesEachPayloadKind() {
        let m = make()
        m.addComponent(type: "text", at: GridSlot(0, 1))
        m.addComponent(type: "image", at: GridSlot(0, 2))
        // An empty slot.
        XCTAssertEqual(m.dropPreview(for: .component("badge"), at: GridSlot(2, 2)),
                       DropPreview(rect: SlotRect(row: 2, col: 2), verb: "Add badge", allowed: true))
        // An occupied one: the whole cell lights up.
        XCTAssertEqual(m.dropPreview(for: .component("badge"), at: GridSlot(0, 1))?.verb, "Replace text with badge")
        XCTAssertEqual(m.dropPreview(for: .field("count"), at: GridSlot(0, 1)), DropPreview(rect: SlotRect(row: 0, col: 1), verb: "Bind {count}", allowed: true))
        XCTAssertEqual(m.dropPreview(for: .field("count"), at: GridSlot(1, 1))?.verb, "Add {count}")
        // A button cannot bind a field.
        m.addComponent(type: "iconButton", at: GridSlot(1, 3))
        let refused = m.dropPreview(for: .field("count"), at: GridSlot(1, 3))
        XCTAssertEqual(refused?.allowed, false)
        XCTAssertEqual(refused?.verb, "A icon btn cannot bind {count}")
        // Moving: onto itself, onto another cell (swap), onto free space.
        XCTAssertEqual(m.dropPreview(for: .cell("c1"), at: GridSlot(0, 1))?.allowed, false)
        XCTAssertEqual(m.dropPreview(for: .cell("c1"), at: GridSlot(0, 2))?.verb, "Swap with image")
        XCTAssertEqual(m.dropPreview(for: .cell("c1"), at: GridSlot(2, 0)), DropPreview(rect: SlotRect(row: 2, col: 0), verb: "Move here", allowed: true))
        XCTAssertNil(m.dropPreview(for: .cell("gone"), at: GridSlot(2, 0)))
        XCTAssertNil(m.dropPreview(for: .component("text"), at: GridSlot(3, 0)), "outside the grid")
    }

    func testDropPreviewForAMovedSpanShowsWhereItWouldLand() {
        let m = make()
        m.addComponent(type: "text", at: GridSlot(0, 0))
        m.setSpan(cell: "c1", rowSpan: 1, colSpan: 3)
        // Moving a 3-wide cell to column 2 is cut to what fits: only 2 columns remain.
        XCTAssertEqual(m.dropPreview(for: .cell("c1"), at: GridSlot(1, 2))?.rect, SlotRect(row: 1, col: 2, rowSpan: 1, colSpan: 2))
    }

    func testHoverDropTracksTheSlotAndClearsOnHandle() {
        let m = make()
        m.addComponent(type: "text", at: GridSlot(0, 1))
        m.dragging = .field("count")
        m.hoverDrop(at: GridSlot(0, 1))
        XCTAssertEqual(m.dropTarget?.verb, "Bind {count}")
        m.hoverDrop(at: GridSlot(2, 2))
        XCTAssertEqual(m.dropTarget?.verb, "Add {count}")
        m.hoverDrop(at: nil)
        XCTAssertNil(m.dropTarget)
        // A drag from elsewhere (nothing known about it) still shows the target.
        m.dragging = nil
        m.hoverDrop(at: GridSlot(0, 1))
        XCTAssertEqual(m.dropTarget, DropPreview(rect: SlotRect(row: 0, col: 1), verb: "Drop here", allowed: true))
        m.dragging = .component("badge")
        m.hoverDrop(at: GridSlot(2, 2))
        m.handle(.component("badge"), at: GridSlot(2, 2))
        XCTAssertNil(m.dropTarget)
        XCTAssertNil(m.dragging)
        XCTAssertNotNil(GridEditing.cell(at: GridSlot(2, 2), in: m.draft))
    }

    func testTrackResizeIsOneUndoStep() {
        let m = make()
        let before = m.draft
        m.beginGesture()
        for v in [90.0, 100, 110.4] { m.resizeTrackLive(columns: true, index: 0, points: v) }
        XCTAssertEqual(m.draft.grid?.colSizes[0], .points(110))
        m.undo()
        XCTAssertEqual(m.draft, before)
        m.resizeTrackLive(columns: false, index: 1, points: 60)
        XCTAssertEqual(m.draft.grid?.rowSizes[1], .points(60))
        m.resetTrack(columns: false, index: 1)
        XCTAssertEqual(m.draft.grid?.rowSizes[1], .auto)
        m.resetTrack(columns: true, index: 0)
        XCTAssertEqual(m.draft.grid?.colSizes[0], .fill)
    }

    // MARK: Modes (issue 31)

    func testQuickSendSeedsItsAppFromTheIssuerOnce() {
        let m = make()
        XCTAssertEqual(m.mode, .design)
        XCTAssertEqual(m.quickSend.app, "")
        m.showQuickSend()
        XCTAssertEqual(m.mode, .quickSend)
        XCTAssertEqual(m.quickSend.app, "demo")
        m.quickSend.title = "Half-written"
        m.quickSend.app = "other"
        m.showDesign()
        m.showQuickSend()
        XCTAssertEqual(m.quickSend.app, "other", "an app the user chose is kept")
        XCTAssertEqual(m.quickSend.title, "Half-written", "the form survives a look at the designer")
        m.showQuickSend(app: "demo")
        XCTAssertEqual(m.quickSend.app, "demo")
    }

    func testShowDesignCanSwitchIssuerAndTemplate() {
        let m = make()
        var t = HeraldTemplate.blank(name: "mine", app: "other")
        t.title = "x"
        saved.append(t)
        m.showQuickSend()
        m.showDesign(app: "other", template: "mine")
        XCTAssertEqual(m.mode, .design)
        XCTAssertEqual(m.app, "other")
        XCTAssertEqual(m.savedName, "mine")
        XCTAssertEqual(DesignerMode.quickSend.windowTitle, "Quick Send")
    }

    // MARK: Animations (issue 33)

    func testAssetsListFilesWithDeclaredFlagAndUsage() {
        let m = make()
        XCTAssertEqual(m.assets.map(\.id), ["bell", "hero"])
        XCTAssertEqual(m.assets.map(\.declared), [true, false])
        XCTAssertEqual(m.assets.map(\.bytes), [40, 90])
        XCTAssertTrue(m.assets.allSatisfy { $0.usedBy.isEmpty })

        m.addComponent(type: "rive", at: GridSlot(0, 0))   // the manifest's bell
        var other = HeraldTemplate.blank(name: "other-template", app: "demo")
        other.cells = [HeraldCell(id: "r", row: 0, col: 0, component: .rive(HeraldRiveComponent(path: "hero.riv")))]
        saved.append(other)
        m.reloadAssets()
        m.refreshFromDisk()
        XCTAssertEqual(m.assets.first { $0.id == "bell" }?.usedBy, [m.draft.name])
        XCTAssertEqual(m.assets.first { $0.id == "hero" }?.usedBy, ["other-template"])
    }

    func testAddAndRemoveAnAsset() throws {
        let m = make()
        let src = root.appendingPathComponent("My Hero.riv")
        try Data(repeating: 9, count: 20).write(to: src)
        m.addAsset(from: src)
        XCTAssertEqual(m.status?.kind, .info)
        XCTAssertEqual(m.assets.count, 3)
        let added = try XCTUnwrap(m.assets.first { $0.id.hasPrefix("My_Hero") })
        XCTAssertFalse(added.declared)
        // The same file again takes a free id instead of replacing the first.
        m.addAsset(from: src)
        XCTAssertEqual(m.assets.count, 4)
        XCTAssertEqual(Set(m.assets.map(\.id)).count, 4)

        m.removeAsset(added)
        XCTAssertEqual(m.assets.count, 3)
        XCTAssertFalse(m.assets.contains(added))

        m.addAsset(from: root.appendingPathComponent("missing.riv"))
        XCTAssertEqual(m.status?.kind, .error)
    }

    func testRiveComponentForAnAssetUsesTheIdWhenDeclaredAndTheFileOtherwise() throws {
        let m = make()
        let bell = try XCTUnwrap(m.assets.first { $0.id == "bell" }), hero = try XCTUnwrap(m.assets.first { $0.id == "hero" })
        let a = m.riveComponent(for: bell)
        XCTAssertEqual(a.asset, "bell"); XCTAssertNil(a.path)
        XCTAssertEqual(a.stateMachine, "Main", "the manifest's state machine wins")
        XCTAssertEqual(a.aspectRatio, 2, "from the artboard's size")
        let b = m.riveComponent(for: hero)
        XCTAssertNil(b.asset); XCTAssertEqual(b.path, "hero.riv")
        XCTAssertEqual(b.stateMachine, "Main", "the file's default machine")
    }

    func testDroppingAnAssetPlacesARiveCell() {
        let m = make()
        m.dragging = .rive("hero")
        XCTAssertEqual(m.dropPreview(for: .rive("hero"), at: GridSlot(1, 1))?.verb, "Add animation")
        XCTAssertEqual(m.dropPreview(for: .rive("nope"), at: GridSlot(1, 1))?.allowed, false)
        m.handle(.rive("hero"), at: GridSlot(1, 1))
        guard case .rive(let r)? = GridEditing.cell(at: GridSlot(1, 1), in: m.draft)?.component else { return XCTFail("no rive cell") }
        XCTAssertEqual(r.path, "hero.riv")
        XCTAssertEqual(m.assets.first { $0.id == "hero" }?.usedBy, [m.draft.name])
        // Clicking an asset puts it in the first free slot.
        m.clearSelection()
        m.insertAsset(id: "bell")
        XCTAssertTrue(m.draft.cells.contains { if case .rive(let r) = $0.component { return r.asset == "bell" }; return false })
        m.insertAsset(id: "missing")
        XCTAssertEqual(m.status?.kind, .error)
    }

    func testFileInfoIsReadOncePerFileVersion() throws {
        let m = make()
        let c = HeraldRiveComponent(path: "bell.riv")
        let a = m.riveFileInfo(for: c)
        _ = m.riveFileInfo(for: c)
        _ = m.riveFileInfo(for: c)
        XCTAssertEqual(infoLoads, 1)
        XCTAssertEqual(a?.machine(nil, artboard: nil)?.name, "Main")
        XCTAssertEqual(a?.machine("Alt", artboard: nil)?.inputs, [.init(name: "go", kind: .trigger)])
        XCTAssertNil(a?.machine("Nope", artboard: nil))
        XCTAssertEqual(a?.artboard(named: "missing")?.name, "Main", "an unknown artboard falls back like the player does")
        XCTAssertNil(m.riveFileInfo(for: HeraldRiveComponent(path: "absent.riv")))
        // A changed file is read again.
        try Data(repeating: 5, count: 41).write(to: fileURL("bell.riv"))
        try FileManager.default.setAttributes([.modificationDate: Date().addingTimeInterval(60)], ofItemAtPath: fileURL("bell.riv").path)
        _ = m.riveFileInfo(for: c)
        XCTAssertEqual(infoLoads, 2)
    }

    // MARK: Bundles (issue 30)

    private func service() -> TemplateBundleService {
        let templates = TemplateStore(directory: root.appendingPathComponent("templates"))
        let assets = AssetStore(directory: root.appendingPathComponent("store"))
        return TemplateBundleService(templates: templates, assets: assets) { [unowned self] a in a == "demo" ? self.manifest : nil }
    }

    func testExportDraftWritesABundleAndReportsWarnings() throws {
        var b = DesignerBackend()
        let svc = service()
        b.exportBundle = { try svc.export($0) }
        let m = DesignerModel(backend: { var x = b; x.issuers = { [DesignerIssuer(id: "demo", name: "Demo", hasManifest: false)] }; return x }(), app: "demo")
        m.draft.cells = [HeraldCell(id: "r", row: 0, col: 0, component: .rive(HeraldRiveComponent(path: "gone.riv")))]   // nobody can find it
        m.edit { $0.name = "Exported one" }
        XCTAssertEqual(m.suggestedBundleName, "Exported one.heraldtemplate")
        let url = root.appendingPathComponent("out.heraldtemplate")
        m.exportDraft(to: url)
        let c = try HeraldTemplateBundle.unpack(Data(contentsOf: url))
        XCTAssertEqual(c.template.name, "Exported one")
        XCTAssertEqual(c.template.app, "demo")
        XCTAssertEqual(m.status?.kind, .error, "a missing animation is worth a second look")
        XCTAssertTrue(m.status?.text.contains("Exported") == true)

        // A draft the API would refuse is not exported (a bundle that cannot be read back is no use).
        m.draft.cells = [HeraldCell(id: "r", row: 0, col: 0, component: .rive(HeraldRiveComponent()))]
        let bad = root.appendingPathComponent("bad.heraldtemplate")
        m.exportDraft(to: bad)
        XCTAssertEqual(m.status?.kind, .error)
        XCTAssertTrue(m.status?.text.contains("rive component needs") == true, m.status?.text ?? "")
        XCTAssertFalse(FileManager.default.fileExists(atPath: bad.path))
    }

    func testImportBundleLoadsTheTemplateAndHandlesNameConflicts() throws {
        let svc = service()
        var t = HeraldTemplate.blank(name: "Shared", app: "demo")
        t.cells = [HeraldCell(id: "c1", row: 0, col: 1, component: .text(HeraldTextComponent(binding: "{title}")))]
        let data = try HeraldTemplateBundle.export(t) { _ in nil }.data

        var b = DesignerBackend()
        b.issuers = { [DesignerIssuer(id: "demo", name: "Demo", hasManifest: true)] }
        b.templates = { app in svc.templates.list(app: app) }
        b.previewBundle = { try svc.preview($0, intoApp: $1) }
        b.importBundle = { d, app, c in try svc.importBundle(d, intoApp: app, onConflict: c) }
        let m = DesignerModel(backend: b, app: "demo")

        m.importBundle(data)
        XCTAssertEqual(m.savedName, "Shared")
        XCTAssertEqual(m.draft.cells.count, 1)
        XCTAssertEqual(m.status?.kind, .info)

        // Again: the name is taken, the chooser decides.
        var asked = 0
        m.chooseConflict = { preview in asked += 1; XCTAssertTrue(preview.nameTaken); return .keepBoth }
        m.importBundle(data)
        XCTAssertEqual(asked, 1)
        XCTAssertEqual(m.savedName, "Shared 2")
        XCTAssertEqual(m.templates.count, 2)

        m.chooseConflict = { _ in nil }
        m.importBundle(data)
        XCTAssertEqual(m.savedName, "Shared 2", "cancelled: nothing changes")
        XCTAssertEqual(svc.templates.list(app: "demo").count, 2)

        m.chooseConflict = { _ in .replace }
        m.importBundle(data)
        XCTAssertEqual(m.savedName, "Shared")
        XCTAssertEqual(svc.templates.list(app: "demo").count, 2)

        m.importBundle(Data("not a bundle".utf8))
        XCTAssertEqual(m.status?.kind, .error)
    }

    func testImportForAnotherIssuerSwitchesToIt() throws {
        let svc = service()
        let t = HeraldTemplate.blank(name: "Elsewhere", app: "other")
        let data = try HeraldTemplateBundle.export(t) { _ in nil }.data
        var b = DesignerBackend()
        b.issuers = { [DesignerIssuer(id: "demo", name: "Demo", hasManifest: true), DesignerIssuer(id: "other", name: "Other", hasManifest: false)] }
        b.templates = { app in svc.templates.list(app: app) }
        b.previewBundle = { try svc.preview($0, intoApp: $1) }
        b.importBundle = { d, app, c in try svc.importBundle(d, intoApp: app, onConflict: c) }
        let m = DesignerModel(backend: b, app: "demo")
        m.importBundle(data)
        XCTAssertEqual(m.app, "other")
        XCTAssertEqual(m.savedName, "Elsewhere")
        // Importing it for the current issuer instead retargets it.
        m.switchIssuer("demo", force: true)
        m.importBundle(data, intoApp: "demo")
        XCTAssertEqual(m.app, "demo")
        XCTAssertEqual(svc.templates.get(app: "demo", name: "Elsewhere")?.app, "demo")
    }
}
