import XCTest
@testable import HeraldCore

/// Where banners go and how they stack: per-app display, corner and mute (issue #28), lazy promotion of
/// deferred banners (issue #25) and the spacing of the built-in v1 grids (issue #38). The AppKit side
/// (`BannerCenter`, panels, animation) was checked live; everything it decides is here.
final class BannerStackTests: XCTestCase {
    // MARK: Displays and slots (issue #28)

    func testDisplayResolution() {
        let connected = ["3", "5", "8"]   // primary first
        XCTAssertEqual(BannerDisplay.resolve(nil, connected: connected), "3")
        XCTAssertEqual(BannerDisplay.resolve("main", connected: connected), "3")
        XCTAssertEqual(BannerDisplay.resolve("5", connected: connected), "5")
        XCTAssertEqual(BannerDisplay.resolve("8", connected: connected), "8")
        // A display that is not connected falls back to the primary one, and comes back when it is plugged in.
        XCTAssertEqual(BannerDisplay.resolve("999", connected: connected), "3")
        XCTAssertEqual(BannerDisplay.resolve("8", connected: ["3"]), "3")
        // Nothing to ask (a headless test run): the marker for the primary display.
        XCTAssertEqual(BannerDisplay.resolve("5", connected: []), "main")
    }

    func testSlotsKeepDisplayAndCornerApart() {
        let connected = ["3", "5"]
        let a = BannerSlot.resolve(screen: "5", corner: .topLeft, connected: connected)
        let b = BannerSlot.resolve(screen: "5", corner: .topRight, connected: connected)
        let c = BannerSlot.resolve(screen: "main", corner: .topLeft, connected: connected)
        XCTAssertEqual(a, BannerSlot(screen: "5", corner: .topLeft))
        XCTAssertNotEqual(a, b); XCTAssertNotEqual(a, c)
        // No corner: top right, like before any setting existed.
        XCTAssertEqual(BannerSlot.resolve(screen: nil, corner: nil, connected: connected), BannerSlot(screen: "3", corner: .topRight))
        // An app whose display is gone shares the primary display's stack for that corner.
        XCTAssertEqual(BannerSlot.resolve(screen: "999", corner: .topLeft, connected: connected), c)
    }

    func testAppRecordSlotPrefersTheUsersChoiceOverTheRegisteredCorner() {
        var reg = HeraldAppRegistration(app: "a")
        reg.defaults = HeraldAppDefaults(corner: .bottomLeft)
        var rec = AppRecord(registration: reg)
        XCTAssertEqual(rec.slot(connectedDisplays: ["3", "5"]), BannerSlot(screen: "3", corner: .bottomLeft), "the app's own corner")
        rec.corner = .topLeft; rec.screen = "5"
        XCTAssertEqual(rec.slot(connectedDisplays: ["3", "5"]), BannerSlot(screen: "5", corner: .topLeft), "the user's choice wins")
        XCTAssertEqual(rec.slot(connectedDisplays: ["3"]), BannerSlot(screen: "3", corner: .topLeft), "display unplugged")
    }

    func testEffectiveSettingsCarryDisplayCornerAndMute() {
        let n = HeraldNotification(app: "a", title: "t")
        let plain = EffectiveSettings.resolve(n, nil)
        XCTAssertEqual(plain.screen, "main"); XCTAssertEqual(plain.corner, .topRight); XCTAssertFalse(plain.mutedBanners)

        var reg = HeraldAppRegistration(app: "a")
        reg.defaults = HeraldAppDefaults(corner: .bottomRight)
        var rec = AppRecord(registration: reg)
        XCTAssertEqual(EffectiveSettings.resolve(n, rec).corner, .bottomRight, "the registered corner still counts")
        rec.corner = .topLeft; rec.screen = "5"; rec.mutedBanners = true
        let e = EffectiveSettings.resolve(n, rec)
        XCTAssertEqual(e.corner, .topLeft); XCTAssertEqual(e.screen, "5"); XCTAssertTrue(e.mutedBanners)
    }

    func testRecordsWrittenBeforeTheDisplaySettingsStillLoad() throws {
        // What 1.1 wrote: no screen, corner or mutedBanners.
        let old = #"{"registration":{"app":"a","appName":"A"},"commandsConfirmed":true}"#
        let rec = try JSONDecoder().decode(AppRecord.self, from: Data(old.utf8))
        XCTAssertTrue(rec.commandsConfirmed)
        XCTAssertNil(rec.screen); XCTAssertNil(rec.corner); XCTAssertFalse(rec.mutedBanners)
        // And a registry file with such a record opens.
        let f = FileManager.default.temporaryDirectory.appendingPathComponent("apps-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: f) }
        try Data(#"{"a":\#(old)}"#.utf8).write(to: f)
        XCTAssertEqual(AppRegistry(file: f).record(for: "a")?.registration.appName, "A")
    }

    func testDisplaySettingsSurviveReregistrationAndRelaunch() {
        let f = FileManager.default.temporaryDirectory.appendingPathComponent("apps-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: f) }
        let reg = AppRegistry(file: f)
        reg.register(HeraldAppRegistration(app: "a", defaults: HeraldAppDefaults(corner: .topRight)))
        reg.update("a") { $0.screen = "5"; $0.corner = .bottomLeft; $0.mutedBanners = true }
        // The app registers again (every launch does) and names its own corner: the user's choices stay.
        reg.register(HeraldAppRegistration(app: "a", appName: "A", defaults: HeraldAppDefaults(corner: .topLeft)))
        var r = reg.record(for: "a")!
        XCTAssertEqual(r.screen, "5"); XCTAssertEqual(r.corner, .bottomLeft); XCTAssertTrue(r.mutedBanners)
        XCTAssertEqual(r.registration.defaults?.corner, .topLeft, "the app's own default is kept as well")
        // They are on disk.
        r = AppRegistry(file: f).record(for: "a")!
        XCTAssertEqual(r.screen, "5"); XCTAssertEqual(r.corner, .bottomLeft); XCTAssertTrue(r.mutedBanners)
        // Back to defaults.
        reg.update("a") { $0.screen = nil; $0.corner = nil; $0.mutedBanners = false }
        let back = EffectiveSettings.resolve(HeraldNotification(app: "a", title: "t"), reg.record(for: "a"))
        XCTAssertEqual(back.corner, .topLeft); XCTAssertEqual(back.screen, "main"); XCTAssertFalse(back.mutedBanners)
    }

    // MARK: Deferred banners (issue #25)

    private let tl = BannerSlot(screen: "3", corner: .topLeft)
    private let tr = BannerSlot(screen: "3", corner: .topRight)

    func testDeferredBannersComeBackOldestFirstPerStack() {
        var d = DeferredBanners()
        d.add("a\u{1}1", slot: tr); d.add("a\u{1}2", slot: tl); d.add("a\u{1}3", slot: tr)
        XCTAssertEqual(d.count, 3); XCTAssertEqual(d.count(in: tr), 2); XCTAssertEqual(d.count(in: tl), 1)
        XCTAssertEqual(d.oldest(in: tr)?.key, "a\u{1}1")
        XCTAssertEqual(d.oldest(in: tl)?.key, "a\u{1}2")
        XCTAssertEqual(d.keys, ["a\u{1}1", "a\u{1}2", "a\u{1}3"])
        XCTAssertEqual(d.slots, [tl, tr])
        XCTAssertTrue(d.remove("a\u{1}1"))
        XCTAssertFalse(d.remove("a\u{1}1"))
        XCTAssertEqual(d.oldest(in: tr)?.key, "a\u{1}3")
        XCTAssertNil(DeferredBanners().oldest(in: tr))
    }

    func testReAddingAKeepsItsAgeAndMovesIt() {
        var d = DeferredBanners()
        d.add("k1", slot: tr); d.add("k2", slot: tr)
        d.add("k1", slot: tl)                 // the app's corner changed
        XCTAssertEqual(d.count(in: tr), 1); XCTAssertEqual(d.oldest(in: tl)?.key, "k1")
        d.add("k1", slot: tr)
        XCTAssertEqual(d.oldest(in: tr)?.key, "k1", "still older than k2")
    }

    func testReslotFollowsTheAppsSettings() {
        var d = DeferredBanners()
        d.add(["a\u{1}1", "b\u{1}1"], slot: { _ in self.tr })
        let moved = d.reslot { $0.hasPrefix("a") ? self.tl : self.tr }
        XCTAssertTrue(moved)
        XCTAssertEqual(d.count(in: tl), 1); XCTAssertEqual(d.count(in: tr), 1)
        XCTAssertFalse(d.reslot { $0.hasPrefix("a") ? self.tl : self.tr }, "nothing left to move")
    }

    func testPromotionDecisionTable() {
        typealias P = BannerPromotion
        // Something was freed, something waits, the stack is measured and has room.
        XCTAssertEqual(P.decide(freed: 1, deferred: 3, unmeasured: 0, overflow: 0), .promote)
        // Nothing freed (a banner arrived or the stack grew by itself) or nothing deferred: leave things alone.
        XCTAssertEqual(P.decide(freed: 0, deferred: 3, unmeasured: 0, overflow: 0), .stop)
        XCTAssertEqual(P.decide(freed: 2, deferred: 0, unmeasured: 0, overflow: 0), .stop)
        // A banner on the stack has no height yet (the one just promoted, a burst): decide when it is known.
        XCTAssertEqual(P.decide(freed: 1, deferred: 3, unmeasured: 1, overflow: 0), .wait)
        // Banners that did not fit are older than anything deferred and take the room first.
        XCTAssertEqual(P.decide(freed: 1, deferred: 3, unmeasured: 0, overflow: 1), .stop)
    }

    /// The whole loop without a window server: a stack that holds six banners, three more deferred, banners
    /// dismissed one at a time or all at once. The pill count is `plan.overflow + deferred`.
    func testDismissingBannersPromotesTheOldestDeferredOnes() {
        let h: CGFloat = 66, available: CGFloat = 6 * 66 + 5 * 8 + 8 + 26 + 4   // room for exactly six and the pill
        var deferred = DeferredBanners()
        for i in 1...3 { deferred.add("item\(i)", slot: tr) }
        var onScreen = (4...9).map { "item\($0)" }          // newest last
        var freed = 0

        func plan() -> BannerStackPlan {
            BannerStackPlan.make(heights: Array(repeating: h, count: onScreen.count), available: available, gap: 8,
                                 stubHeight: 26, forceStub: deferred.count(in: tr) > 0)
        }
        func settle() {
            while true {
                let p = plan()
                switch BannerPromotion.decide(freed: freed, deferred: deferred.count(in: tr), unmeasured: 0, overflow: p.overflow) {
                case .promote:
                    freed -= 1
                    let next = deferred.oldest(in: tr)!
                    deferred.remove(next.key)
                    onScreen.insert(next.key, at: 0)       // below the banners that are on screen
                case .wait: return
                case .stop: freed = 0; return
                }
            }
        }
        func dismiss(_ key: String) {
            if deferred.remove(key) { return }
            onScreen.removeAll { $0 == key }
            if deferred.count(in: tr) > 0 { freed += 1 }
        }

        XCTAssertEqual(plan().overflow + deferred.count(in: tr), 3, "the pill says +3")
        dismiss("item9"); settle()
        XCTAssertEqual(onScreen.first, "item1", "the oldest deferred banner took the place, at the old end")
        XCTAssertEqual(onScreen.count, 6)
        XCTAssertEqual(plan().overflow + deferred.count(in: tr), 2, "the pill says +2")
        // A deferred banner dismissed in History is simply gone; it is not promoted later.
        dismiss("item2"); settle()
        XCTAssertEqual(deferred.count, 1)
        dismiss("item8"); dismiss("item7"); settle()      // two places freed, one banner waiting
        XCTAssertEqual(onScreen.count, 5)
        XCTAssertEqual(onScreen.first, "item3")
        XCTAssertTrue(deferred.isEmpty)
        XCTAssertEqual(plan().overflow, 0, "no pill any more")
    }

    func testAFullStackKeepsDeferredBannersWaiting() {
        // A banner so tall that the stack is full again as soon as it is shown: nothing more is promoted.
        let p = BannerStackPlan.make(heights: [500, 400], available: 600, gap: 8, stubHeight: 26, forceStub: true)
        XCTAssertGreaterThan(p.overflow, 0)
        XCTAssertEqual(BannerPromotion.decide(freed: 3, deferred: 2, unmeasured: 0, overflow: p.overflow), .stop)
    }

    // MARK: Built-in grids (issue #38)

    /// Heights of the pieces of a v1 banner, as measured live in 1.0 (13 pt semibold title, 12 pt subtitle and
    /// body, 12 pt capsule buttons).
    private let metrics: [String: Double] = ["title": 16, "subtitle": 14, "body": 30, "close": 16, "icon": 22, "time": 12,
                                              "actions": 23, "image": 72]
    private let widths: [String: Double] = ["close": 16, "icon": 22, "time": 28, "image": 72]

    private func solve(_ t: HeraldTemplate, empty: Set<String> = [], metrics m: [String: Double]? = nil) -> GridSolution {
        let m = m ?? metrics
        let plan = t.plan(emptyCells: empty)
        let cells = t.cells
        let measure = GridMeasure(idealWidth: { self.widths[cells[$0].id] ?? 0 },
                                  height: { i, _ in m[cells[i].id] ?? 0 })
        return GridSolver.solve(grid: t.grid!, cells: cells, plan: plan, measure: measure)
    }

    /// What 1.0 drew for the same content: padding 12, the text column (2 pt between lines, body 1 pt lower) or
    /// the meta column (close 18, icon 22, time 12, 6 apart) beside the image, whichever is taller, then the
    /// action row 10 pt below.
    private func v1Height(image: Bool, buttons: Bool) -> Double {
        let text = 16 + 2 + 14 + 2 + 1 + 30.0
        let meta = 18 + 6 + 22 + 6 + 12.0
        var top = max(text, meta)
        if image { top = max(top, 72) }
        return 12 + top + (buttons ? 10 + 23 : 0) + 12
    }

    func testBuiltinCardsAreAsTallAsV1() {
        for layout in [HeraldLayout.imageLeft, .imageRight] {
            for image in [false, true] {
                for buttons in [false, true] {
                    let t = BuiltinTemplates.template(layout: layout, hasImage: image)
                    var empty: Set<String> = []
                    if !buttons { empty.insert("actions") }
                    let got = solve(t, empty: empty).height
                    let want = v1Height(image: image, buttons: buttons)
                    // 1.0 pinned a 64 pt meta column under a one-line title; the grid does not, so only banners with
                    // text (the usual ones) are compared. Within 3 pt; live they were within 2 (see the issue).
                    XCTAssertEqual(got, want, accuracy: 3, "\(layout) image=\(image) buttons=\(buttons): \(got) vs v1 \(want)")
                }
            }
        }
    }

    func testMetaCellsNoLongerStretchTheTextRows() {
        // 1.1.0 put the app icon (22) on the subtitle row and the close button (18) on the title row, which made
        // those rows 22 and 18 tall for 14 and 16 pt of text.
        let t = BuiltinTemplates.template(layout: .imageLeft, hasImage: false)
        let s = solve(t)
        XCTAssertEqual(s.rowHeights[0], 16, "title row = the title")
        XCTAssertEqual(s.rowHeights[1], 14, "subtitle row = the subtitle, not the 22 pt icon")
        XCTAssertEqual(s.rowHeights[2], 30, "body row = the body")
        // The icon sits under the close button, spanning the subtitle and body rows.
        let cells = t.cells
        let iconFrame = s.frames[cells.firstIndex { $0.id == "icon" }!]!
        let closeFrame = s.frames[cells.firstIndex { $0.id == "close" }!]!
        XCTAssertGreaterThan(iconFrame.y, closeFrame.y)
        XCTAssertEqual(iconFrame.maxX, closeFrame.maxX, accuracy: 0.01, "same right edge")
        // The time is on the title row, left of the close button.
        let timeFrame = s.frames[cells.firstIndex { $0.id == "time" }!]!
        XCTAssertEqual(timeFrame.y, closeFrame.y, accuracy: 0.01)
        XCTAssertLessThan(timeFrame.maxX, closeFrame.x)
    }

    func testNoImageNoBlankColumn() throws {
        // The action row spans every column, so an image column kept alive by it pushed the text 78 pt right
        // of where v1 drew it. Without an image there is no such column.
        for layout in [HeraldLayout.imageLeft, .imageRight] {
            let t = BuiltinTemplates.template(layout: layout, hasImage: false)
            XCTAssertNil(t.cell(withID: "image"))
            XCTAssertEqual(t.grid?.cols, 3)
            XCTAssertFalse((t.grid?.colSizes ?? []).contains(.points(72)))
            let s = solve(t)
            let title = try XCTUnwrap(s.frames[t.cells.firstIndex { $0.id == "title" }!])
            let actions = try XCTUnwrap(s.frames[t.cells.firstIndex { $0.id == "actions" }!])
            XCTAssertEqual(title.x, 12, accuracy: 0.01, "\(layout): the title starts at the card padding")
            XCTAssertEqual(actions.x, 12, accuracy: 0.01, "\(layout): and so does the action row")
        }
        // With an image, the columns are the ones the Designer shows.
        let withImage = BuiltinTemplates.template(layout: .imageLeft)
        XCTAssertEqual(withImage.grid?.cols, 4)
        XCTAssertEqual(withImage.grid?.colSizes.first, .points(72))
    }

    func testNotificationDrivenGridFollowsTheImage() {
        let plain = HeraldNotification(app: "a", title: "t")
        XCTAssertNil(BuiltinTemplates.gridTemplate(for: plain).cell(withID: "image"))
        let pic = HeraldNotification(app: "a", title: "t", image: "/tmp/p.png")
        XCTAssertNotNil(BuiltinTemplates.gridTemplate(for: pic).cell(withID: "image"))
        // A picture the caller holds (a composer preview) counts even when the notification names none.
        XCTAssertNotNil(BuiltinTemplates.gridTemplate(for: plain, hasImage: true).cell(withID: "image"))
        XCTAssertNil(BuiltinTemplates.gridTemplate(for: pic, hasImage: false).cell(withID: "image"))
        // The named built-ins are the static ones, with the image column.
        for name in BuiltinTemplates.names {
            XCTAssertEqual(BuiltinTemplates.named(name), BuiltinTemplates.template(layout: BuiltinTemplates.layout(forName: name)!))
        }
    }

    func testEveryBuiltinVariantValidates() {
        for layout in HeraldLayout.allCases {
            for image in [false, true] {
                let t = BuiltinTemplates.template(layout: layout, app: "a", hasImage: image)
                XCTAssertEqual(t.validate(), [], "\(layout) image=\(image)")
            }
        }
    }

    // MARK: Open stack list height (DESIGN section 9)

    func testListCapLeavesRoomForTheFooter() {
        // A ~780 pt visible height less 12 pt margins either side leaves 756 pt for the panel.
        XCTAssertEqual(StackListLayout.cap(available: 756),
                       756 - StackListLayout.footerHeight - StackListLayout.gap)
        XCTAssertEqual(StackListLayout.cap(available: 10), 0)
        XCTAssertEqual(StackListLayout.cap(available: 0), 0)
    }

    func testListHeightIsTheFirstSixRowsWhenTheyFit() {
        let gap = StackListLayout.gap
        let rows = [CGFloat](repeating: 60, count: 9)
        let r = StackListLayout.height(rows: rows, cap: .infinity)
        XCTAssertEqual(r.height, 6 * 60 + 5 * gap)
        XCTAssertFalse(r.capped)
        let two = StackListLayout.height(rows: [50, 70], cap: 1000)
        XCTAssertEqual(two.height, 50 + 70 + gap)
        XCTAssertFalse(two.capped)
        XCTAssertEqual(StackListLayout.height(rows: [], cap: 100).height, 0)
        XCTAssertFalse(StackListLayout.height(rows: [], cap: 100).capped)
    }

    func testTallRowsAreCappedSoTheFooterStaysOnScreen() {
        // Six ~110 pt rows with one of them open on an inline question (+225 pt), on a 756 pt panel budget.
        let available: CGFloat = 756
        let cap = StackListLayout.cap(available: available)
        let rows: [CGFloat] = [335, 110, 110, 110, 110, 110]
        let r = StackListLayout.height(rows: rows, cap: cap)
        XCTAssertTrue(r.capped)
        XCTAssertEqual(r.height, cap)
        // List, gap and footer together stay inside the panel budget.
        XCTAssertLessThanOrEqual(r.height + StackListLayout.gap + StackListLayout.footerHeight, available)
        // Tall templates (builtin.hero ~260 pt a row) cap too, whatever the row count.
        let hero = StackListLayout.height(rows: [CGFloat](repeating: 260, count: 4), cap: cap)
        XCTAssertTrue(hero.capped)
        XCTAssertEqual(hero.height, cap)
    }

    func testTheCapNeverCutsBelowTheNewestRow() {
        // A short screen: the newest banner stays usable, the list scrolls for the rest.
        let r = StackListLayout.height(rows: [400, 90, 90], cap: 120)
        XCTAssertEqual(r.height, 400)
        XCTAssertTrue(r.capped)
        // An exactly fitting list is not "capped".
        let exact = StackListLayout.height(rows: [100, 100], cap: 100 + 100 + StackListLayout.gap)
        XCTAssertEqual(exact.height, 208)
        XCTAssertFalse(exact.capped)
    }
}
