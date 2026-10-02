import XCTest
@testable import HeraldCore

/// DESIGN section 9: stacking keys at every level, and the fold / replace / count / dismiss / snooze rules of a
/// live stack. All pure: `StackPlanner.swift` has no AppKit.
final class StackPlannerTests: XCTestCase {
    // MARK: Keys

    func testFamilyIsTheManifestsElseThePrefixBeforeTheFirstDot() {
        XCTAssertEqual(StackKeying.family(app: "webwatcher.email", manifestFamily: nil), "webwatcher")
        XCTAssertEqual(StackKeying.family(app: "webwatcher.email.gmail", manifestFamily: nil), "webwatcher")
        XCTAssertEqual(StackKeying.family(app: "bidbot", manifestFamily: nil), "bidbot")
        XCTAssertEqual(StackKeying.family(app: "webwatcher.email", manifestFamily: "suite"), "suite")
        XCTAssertEqual(StackKeying.family(app: "webwatcher.email", manifestFamily: "  "), "webwatcher", "a blank family is none")
        XCTAssertEqual(StackKeying.family(app: ".hidden", manifestFamily: nil), ".hidden", "a leading dot is not a prefix")
    }

    func testByAppKeySharesAFamilyAcrossIssuers() {
        let web = StackKeying.key(level: .byApp, app: "webwatcher.web", manifestFamily: nil, group: "rive")
        let mail = StackKeying.key(level: .byApp, app: "webwatcher.email", manifestFamily: nil, group: "alice")
        let other = StackKeying.key(level: .byApp, app: "bidbot", manifestFamily: nil, group: nil)
        XCTAssertNotNil(web)
        XCTAssertEqual(web, mail)
        XCTAssertNotEqual(web, other)
        // A manifest family beats the prefix: two issuers with unrelated ids can share a stack, and a prefix can be split.
        XCTAssertEqual(StackKeying.key(level: .byApp, app: "gmail", manifestFamily: "mail", group: nil),
                       StackKeying.key(level: .byApp, app: "outlook", manifestFamily: "mail", group: nil))
        XCTAssertNotEqual(StackKeying.key(level: .byApp, app: "webwatcher.web", manifestFamily: "web", group: nil),
                          StackKeying.key(level: .byApp, app: "webwatcher.email", manifestFamily: "mail", group: nil))
    }

    func testByIssuerKeyIsOnePerIssuerWhateverTheGroup() {
        let a = StackKeying.key(level: .byIssuer, app: "gmail", manifestFamily: "mail", group: "alice")
        XCTAssertEqual(a, StackKeying.key(level: .byIssuer, app: "gmail", manifestFamily: nil, group: "bob"))
        XCTAssertEqual(a, StackKeying.key(level: .byIssuer, app: "gmail", manifestFamily: nil, group: nil))
        XCTAssertNotEqual(a, StackKeying.key(level: .byIssuer, app: "webwatcher.web", manifestFamily: "mail", group: nil))
        // webwatcher.web and webwatcher.email are different issuers even though they share a family.
        XCTAssertNotEqual(StackKeying.key(level: .byIssuer, app: "webwatcher.web", manifestFamily: nil, group: nil),
                          StackKeying.key(level: .byIssuer, app: "webwatcher.email", manifestFamily: nil, group: nil))
    }

    func testBySenderKeyIsThePayloadGroupFallingBackToTheIssuerId() {
        let rive = StackKeying.key(level: .bySender, app: "webwatcher.web", manifestFamily: nil, group: "rive.app")
        XCTAssertEqual(rive, StackKeying.key(level: .bySender, app: "webwatcher.web", manifestFamily: "x", group: " rive.app "))
        XCTAssertNotEqual(rive, StackKeying.key(level: .bySender, app: "webwatcher.web", manifestFamily: nil, group: "other.site"))
        // No group, or a blank one: the issuer id is the group.
        let none = StackKeying.key(level: .bySender, app: "bidbot", manifestFamily: nil, group: nil)
        XCTAssertEqual(none, StackKeying.key(level: .bySender, app: "bidbot", manifestFamily: nil, group: ""))
        XCTAssertEqual(none, StackKeying.key(level: .bySender, app: "bidbot", manifestFamily: nil, group: "   "))
        XCTAssertEqual(none, StackKeying.key(level: .bySender, app: "bidbot", manifestFamily: nil, group: "bidbot"))
        XCTAssertNotEqual(none, StackKeying.key(level: .bySender, app: "bidbot", manifestFamily: nil, group: "bid-42"))
        // The same group from two issuers is two stacks.
        XCTAssertNotEqual(StackKeying.key(level: .bySender, app: "a", manifestFamily: nil, group: "g"),
                          StackKeying.key(level: .bySender, app: "b", manifestFamily: nil, group: "g"))
        XCTAssertEqual(StackKeying.effectiveGroup(app: "bidbot", group: nil), "bidbot")
        XCTAssertEqual(StackKeying.effectiveGroup(app: "bidbot", group: "bid-42"), "bid-42")
    }

    func testNeverHasNoKeyAndLevelsDoNotCollide() {
        XCTAssertNil(StackKeying.key(level: .never, app: "a", manifestFamily: nil, group: "g"))
        // An issuer named like its own family and group: the three levels still have three different keys.
        let keys = [StackingLevel.byApp, .byIssuer, .bySender].map { StackKeying.key(level: $0, app: "x", manifestFamily: nil, group: nil) }
        XCTAssertEqual(Set(keys.compactMap { $0 }).count, 3)
    }

    func testDefaultLevelOverrideAndDescribe() {
        XCTAssertEqual(StackingLevel.defaultLevel, .bySender)
        XCTAssertEqual(StackKeying.level(override: nil, default: .bySender), .bySender)
        XCTAssertEqual(StackKeying.level(override: .byIssuer, default: .bySender), .byIssuer)
        XCTAssertEqual(StackKeying.level(override: .never, default: .byApp), .never)
        let d = StackKeying.describe(StackKeying.key(level: .bySender, app: "bidbot", manifestFamily: nil, group: "bid-42")!)
        XCTAssertEqual(d?.level, .bySender); XCTAssertEqual(d?.app, "bidbot"); XCTAssertEqual(d?.group, "bid-42")
        let f = StackKeying.describe(StackKeying.key(level: .byApp, app: "webwatcher.web", manifestFamily: nil, group: nil)!)
        XCTAssertEqual(f?.level, .byApp); XCTAssertEqual(f?.app, "webwatcher"); XCTAssertNil(f?.group)
        XCTAssertNil(StackKeying.describe("nonsense"))
        XCTAssertEqual(StackingLevel.allCases.map(\.rawValue), ["byApp", "byIssuer", "bySender", "never"])
    }

    func testTheSettingRoundTripsAsItsRawValue() throws {
        let data = try JSONEncoder().encode(["l": StackingLevel.byIssuer])
        XCTAssertEqual(String(data: data, encoding: .utf8), "{\"l\":\"byIssuer\"}")
        XCTAssertEqual(try JSONDecoder().decode([String: StackingLevel].self, from: data)["l"], .byIssuer)
    }

    // MARK: Fold, replace, count

    private let k = "sender\u{1}a\u{1}g"

    func testTheFirstBannerOfAKeyIsAloneAndTheNextFoldsOnTop() {
        var b = StackBook()
        XCTAssertEqual(b.deliver("1", stackKey: k), .alone)
        XCTAssertEqual(b.deliver("2", stackKey: k), .folded(count: 2, isTop: true))
        XCTAssertEqual(b.deliver("3", stackKey: k), .folded(count: 3, isTop: true))
        let plan = b.plan()
        XCTAssertEqual(plan.stacks.count, 1)
        XCTAssertEqual(plan.stacks[0].members, ["3", "2", "1"], "newest first")
        XCTAssertEqual(plan.stacks[0].top, "3")
        XCTAssertEqual(plan.count(of: "1"), 3)
        XCTAssertTrue(plan.isTop("3"))
        XCTAssertFalse(plan.isTop("2"))
        XCTAssertTrue(plan.isFolded("2")); XCTAssertTrue(plan.isFolded("1")); XCTAssertFalse(plan.isFolded("3"))
        XCTAssertEqual(plan.top(of: "1"), "3")
    }

    func testDifferentKeysAndUnstackedBannersAreSeparate() {
        var b = StackBook()
        b.deliver("1", stackKey: k)
        XCTAssertEqual(b.deliver("2", stackKey: "sender\u{1}a\u{1}other"), .alone)
        XCTAssertEqual(b.deliver("3", stackKey: nil), .alone)
        XCTAssertEqual(b.deliver("4", stackKey: nil), .alone, "banners with no key never fold together")
        let plan = b.plan()
        XCTAssertEqual(plan.stacks.count, 2, "the two unkeyed banners are not stacks")
        XCTAssertFalse(plan.isFolded("3")); XCTAssertFalse(plan.isFolded("4"))
        XCTAssertEqual(plan.count(of: "3"), 1)
        XCTAssertTrue(plan.isTop("3"))
        XCTAssertEqual(b.count, 4)
    }

    func testABlankKeyIsNoKey() {
        var b = StackBook()
        XCTAssertEqual(b.deliver("1", stackKey: ""), .alone)
        XCTAssertEqual(b.deliver("2", stackKey: "  "), .alone)
        XCTAssertNil(b.stackKey(of: "1"))
    }

    func testReplacingByIdDoesNotRaiseTheCount() {
        var b = StackBook()
        b.deliver("1", stackKey: k)
        // Alone: replaced in place, keeps its order.
        let order = b.order(of: "1")
        XCTAssertEqual(b.deliver("1", stackKey: k), .replaced(count: 1, promoted: false))
        XCTAssertEqual(b.order(of: "1"), order)

        b.deliver("2", stackKey: k); b.deliver("3", stackKey: k)
        // The top again: nothing moves, count stays 3.
        XCTAssertEqual(b.deliver("3", stackKey: k), .replaced(count: 3, promoted: false))
        // An older member: the update becomes the top card, the count still 3.
        XCTAssertEqual(b.deliver("1", stackKey: k), .replaced(count: 3, promoted: true))
        XCTAssertEqual(b.members(ofStack: k), ["1", "3", "2"])
        XCTAssertEqual(b.plan().stacks[0].count, 3)
        XCTAssertEqual(b.count, 3)
    }

    func testARedrawKeepsItsPlaceInTheStack() {
        var b = StackBook()
        for id in ["1", "2", "3"] { b.deliver(id, stackKey: k) }
        XCTAssertEqual(b.deliver("1", stackKey: k, keepPlace: true), .replaced(count: 3, promoted: false))
        XCTAssertEqual(b.members(ofStack: k), ["3", "2", "1"])
    }

    func testAReplacementThatChangesTheKeyMovesToTheOtherStack() {
        var b = StackBook()
        b.deliver("1", stackKey: k); b.deliver("2", stackKey: k)
        let other = "sender\u{1}a\u{1}other"
        b.deliver("9", stackKey: other)
        XCTAssertEqual(b.deliver("1", stackKey: other), .folded(count: 2, isTop: true))
        XCTAssertEqual(b.members(ofStack: k), ["2"])
        XCTAssertEqual(b.members(ofStack: other), ["1", "9"])
        XCTAssertEqual(b.count, 3)
    }

    func testAPromotedBannerIsOlderThanEverythingOnScreen() {
        var b = StackBook()
        b.deliver("new1", stackKey: k)
        b.deliver("new2", stackKey: k)
        XCTAssertEqual(b.deliver("old", stackKey: k, promoted: true), .folded(count: 3, isTop: false))
        XCTAssertEqual(b.members(ofStack: k), ["new2", "new1", "old"])
        XCTAssertEqual(b.plan().stacks[0].top, "new2")
        XCTAssertLessThan(b.order(of: "old")!, b.order(of: "new1")!)
    }

    // MARK: Dismiss

    func testDismissingAMemberLeavesTheStackAndTheNextCardComesUp() {
        var b = StackBook()
        for id in ["1", "2", "3"] { b.deliver(id, stackKey: k) }
        // The middle one leaves: the top stays, the count drops.
        XCTAssertEqual(b.remove("2"), StackBook.Removal(stackKey: k, remaining: 2, newTop: "3"))
        XCTAssertEqual(b.plan().count(of: "3"), 2)
        // The top leaves: the card under it is the top now.
        XCTAssertEqual(b.remove("3"), StackBook.Removal(stackKey: k, remaining: 1, newTop: "1"))
        XCTAssertEqual(b.plan().count(of: "1"), 1, "a stack of one is just a banner")
        XCTAssertFalse(b.plan().isFolded("1"))
        XCTAssertTrue(b.plan().isTop("1"))
        XCTAssertEqual(b.remove("1"), StackBook.Removal(stackKey: k, remaining: 0, newTop: nil))
        XCTAssertTrue(b.plan().stacks.isEmpty)
        XCTAssertNil(b.remove("1"), "removing what is not there does nothing")
    }

    func testDismissingTheGroupRemovesEveryMemberAndOnlyThose() {
        var b = StackBook()
        for id in ["1", "2", "3"] { b.deliver(id, stackKey: k) }
        b.deliver("x", stackKey: "sender\u{1}a\u{1}other")
        b.deliver("y", stackKey: nil)
        XCTAssertEqual(b.removeStack(k), ["3", "2", "1"], "newest first, for History")
        XCTAssertEqual(Set(b.ids), ["x", "y"])
        XCTAssertEqual(b.removeStack(k), [])
    }

    // MARK: Expand

    func testAStackOpensOnlyWithTwoMembersAndClosesWhenItShrinks() {
        var b = StackBook()
        b.deliver("1", stackKey: k)
        b.setExpanded(k, true)
        XCTAssertFalse(b.isExpanded(k), "a lone banner has nothing to expand")
        b.deliver("2", stackKey: k)
        XCTAssertFalse(b.isExpanded(k), "and asking early did not stick")
        b.setExpanded(k, true)
        XCTAssertTrue(b.isExpanded(k))
        XCTAssertEqual(b.expandedStacks, [k])
        b.deliver("3", stackKey: k)
        XCTAssertTrue(b.isExpanded(k), "a new member joins the open list")
        b.remove("3")
        XCTAssertTrue(b.isExpanded(k))
        b.remove("2")
        XCTAssertFalse(b.isExpanded(k), "down to one: back to a plain card")
        b.deliver("4", stackKey: k)
        XCTAssertFalse(b.isExpanded(k), "and it does not reopen by itself when the stack grows again")
        b.setExpanded(k, true); b.setExpanded(k, false)
        XCTAssertFalse(b.isExpanded(k))
    }

    func testDismissingTheOpenGroupForgetsItsExpansion() {
        var b = StackBook()
        b.deliver("1", stackKey: k); b.deliver("2", stackKey: k)
        b.setExpanded(k, true)
        b.removeStack(k)
        b.deliver("3", stackKey: k); b.deliver("4", stackKey: k)
        XCTAssertFalse(b.isExpanded(k))
    }

    // MARK: Snooze

    func testASnoozedStackComesBackAsAStackWithTheSameTopCard() {
        var b = StackBook()
        for id in ["1", "2", "3"] { b.deliver(id, stackKey: k) }
        let order = b.restoreOrder(ofStack: k)
        XCTAssertEqual(order, ["1", "2", "3"], "oldest first")
        // Snooze: the group's banners go away...
        b.removeStack(k)
        XCTAssertTrue(b.plan().stacks.isEmpty)
        // ...and come back one by one in that order, folding as they arrive.
        XCTAssertEqual(b.deliver(order[0], stackKey: k), .alone)
        XCTAssertEqual(b.deliver(order[1], stackKey: k), .folded(count: 2, isTop: true))
        XCTAssertEqual(b.deliver(order[2], stackKey: k), .folded(count: 3, isTop: true))
        XCTAssertEqual(b.members(ofStack: k), ["3", "2", "1"])
        XCTAssertEqual(b.plan().stacks[0].top, "3")
    }

    func testASnoozedStackRestoresIntoABannerThatArrivedMeanwhile() {
        var b = StackBook()
        b.deliver("1", stackKey: k); b.deliver("2", stackKey: k)
        let order = b.restoreOrder(ofStack: k)
        b.removeStack(k)
        b.deliver("fresh", stackKey: k)   // a notification of the group arrived during the snooze
        for id in order { b.deliver(id, stackKey: k) }
        XCTAssertEqual(b.plan().stacks[0].count, 3)
        XCTAssertEqual(b.members(ofStack: k).last, "fresh")
    }

    // MARK: Level changes

    func testChangingTheLevelRegroupsTheLiveBanners() {
        var b = StackBook()
        let senderA = "sender\u{1}a\u{1}x", senderB = "sender\u{1}a\u{1}y"
        b.deliver("1", stackKey: senderA); b.deliver("2", stackKey: senderB); b.deliver("3", stackKey: senderA)
        XCTAssertEqual(b.plan().stacks.count, 2)
        b.setExpanded(senderA, true)
        // By issuer: one stack for the app.
        let issuer = "issuer\u{1}a"
        XCTAssertTrue(b.rekey { _ in issuer })
        XCTAssertEqual(b.plan().stacks.count, 1)
        XCTAssertEqual(b.members(ofStack: issuer), ["3", "2", "1"], "arrival order is kept")
        XCTAssertFalse(b.isExpanded(senderA), "the old stack's expansion went with it")
        XCTAssertFalse(b.rekey { _ in issuer }, "nothing moved")
        // Never: three banners of their own.
        XCTAssertTrue(b.rekey { _ in nil })
        XCTAssertTrue(b.plan().stacks.isEmpty)
        XCTAssertEqual(b.count, 3)
        XCTAssertFalse(b.plan().isFolded("1"))
    }

    // MARK: Position

    func testAStackSitsWhereItsTopCardWouldAndNewestStacksComeFirst() {
        var b = StackBook()
        b.deliver("a1", stackKey: "sender\u{1}a\u{1}x")
        b.deliver("b1", stackKey: "sender\u{1}b\u{1}x")
        b.deliver("a2", stackKey: "sender\u{1}a\u{1}x")
        XCTAssertEqual(b.plan().stacks.map(\.top), ["a2", "b1"], "a2 arrived after b1, so its stack is on top")
        b.deliver("b2", stackKey: "sender\u{1}b\u{1}x")
        XCTAssertEqual(b.plan().stacks.map(\.top), ["b2", "a2"])
        XCTAssertGreaterThan(b.order(of: "b2")!, b.order(of: "a2")!)
    }

    // MARK: Report

    private func item(_ app: String, _ id: String, group: String? = nil, title: String = "t", at: TimeInterval = 0) -> HeraldHistoryItem {
        var n = HeraldNotification(app: app, id: id, title: title)
        n.group = group
        return HeraldHistoryItem(id: id, app: app, notification: n, deliveredAt: Date(timeIntervalSince1970: 1_700_000_000 + at))
    }

    func testReportListsStacksNewestFirstWithTheirMembers() {
        var b = StackBook()
        let items = [item("a", "1", group: "rive", at: 1), item("a", "2", group: "rive", at: 2), item("a", "3", group: "rive", at: 3),
                     item("b", "9", at: 4)]
        for i in items {
            let key = StackKeying.key(level: .bySender, app: i.app, manifestFamily: nil, group: i.notification.group)
            b.deliver(BannerKey.make(i.app, i.id), stackKey: key)
        }
        b.setExpanded(StackKeying.key(level: .bySender, app: "a", manifestFamily: nil, group: "rive")!, true)
        let infos = StackReport.infos(book: b) { id in items.first { BannerKey.make($0.app, $0.id) == id } }
        XCTAssertEqual(infos.count, 2)
        XCTAssertEqual(infos[0].app, "b"); XCTAssertEqual(infos[0].count, 1); XCTAssertEqual(infos[0].group, "b")
        let stack = infos[1]
        XCTAssertEqual(stack.level, "bySender"); XCTAssertEqual(stack.app, "a"); XCTAssertEqual(stack.group, "rive")
        XCTAssertEqual(stack.count, 3); XCTAssertTrue(stack.expanded)
        XCTAssertEqual(stack.members.map(\.id), ["3", "2", "1"])
        XCTAssertEqual(stack.members.first?.group, "rive")
        // A filter by app keeps only the stacks that hold that app.
        XCTAssertEqual(StackReport.infos(book: b, app: "b") { id in items.first { BannerKey.make($0.app, $0.id) == id } }.count, 1)
        XCTAssertTrue(StackReport.infos(book: b, app: "zzz") { _ in nil }.isEmpty)
    }

    func testReportRoundTripsAsJSON() throws {
        let info = HeraldStackInfo(level: "byApp", app: "webwatcher", count: 2, expanded: false, members: [
            .init(app: "webwatcher.web", id: "x", title: "T", group: nil, deliveredAt: Date(timeIntervalSince1970: 1_700_000_000))])
        let data = try HeraldJSON.encoder().encode(info)
        XCTAssertEqual(try HeraldJSON.decoder().decode(HeraldStackInfo.self, from: data), info)
    }

    // MARK: History

    func testHistoryFoldsAGroupUnderOneRowAtItsNewestMember() {
        let items = [item("a", "5", group: "rive", at: 5), item("b", "4", at: 4), item("a", "3", group: "rive", at: 3),
                     item("a", "2", group: "solo", at: 2), item("a", "1", group: "rive", at: 1)]
        let rows = HistoryGrouping.rows(items)
        XCTAssertEqual(rows.count, 3)
        guard case .group(let g) = rows[0] else { return XCTFail("the newest item of the group leads its row") }
        XCTAssertEqual(g.app, "a"); XCTAssertEqual(g.group, "rive")
        XCTAssertEqual(g.items.map(\.id), ["5", "3", "1"], "newest first")
        XCTAssertEqual(g.unread, 3)
        guard case .item(let b) = rows[1], case .item(let solo) = rows[2] else { return XCTFail("the rest stay plain rows") }
        XCTAssertEqual(b.id, "4")
        XCTAssertEqual(solo.id, "2", "a group of one is not folded")
    }

    func testHistoryGroupsAreKeptPerApp() {
        let rows = HistoryGrouping.rows([item("a", "1", group: "g"), item("b", "2", group: "g")])
        XCTAssertEqual(rows.count, 2, "the same group from two apps is two groups of one")
        for r in rows { if case .group = r { XCTFail() } }
        XCTAssertEqual(HistoryGrouping.rows([]).count, 0)
        XCTAssertEqual(Set(rows.map(\.id)).count, 2)
    }

    func testHistoryItemsWithoutAGroupAreNeverFolded() {
        let rows = HistoryGrouping.rows([item("a", "1"), item("a", "2"), item("a", "3", group: " ")])
        XCTAssertEqual(rows.count, 3)
        for r in rows { if case .group = r { XCTFail() } }
    }

    func testHistoryCountsUnreadInAGroup() {
        var done = item("a", "2", group: "g", at: 2)
        done.dismissedAt = Date()
        let rows = HistoryGrouping.rows([item("a", "3", group: "g", at: 3), done])
        guard case .group(let g) = rows[0] else { return XCTFail() }
        XCTAssertEqual(g.items.count, 2); XCTAssertEqual(g.unread, 1)
    }

    // MARK: The group travels with the notification

    func testGroupIsAPayloadKeyAndIsRecordedWithTheHistoryItem() throws {
        let n = try HeraldJSON.decoder().decode(HeraldNotification.self, from: Data(#"{"app":"a","title":"t","group":"rive.app"}"#.utf8))
        XCTAssertEqual(n.group, "rive.app")
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("herald-stack-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = HistoryStore(directory: dir)
        store.upsert(HeraldHistoryItem(id: "1", app: "a", notification: n, deliveredAt: Date()))
        XCTAssertEqual(store.item(app: "a", id: "1")?.group, "rive.app")
        let reopened = HistoryStore(directory: dir)
        XCTAssertEqual(reopened.item(app: "a", id: "1")?.notification.group, "rive.app", "survives the database")
        XCTAssertNil(try HeraldJSON.decoder().decode(HeraldNotification.self, from: Data(#"{"app":"a","title":"t"}"#.utf8)).group)
    }

    func testGroupIsABindingToken() {
        var n = HeraldNotification(app: "a", id: "1", title: "t")
        XCTAssertNil(TemplateResolver.fields(for: n)["group"])
        n.group = "rive.app"
        XCTAssertEqual(TemplateResolver.fields(for: n)["group"], .text("rive.app"))
        XCTAssertTrue(TemplateResolver.standardTokens.contains("group"))
        var t = HeraldTemplate(name: "x", app: "a"); t.title = "{group} changed"
        XCTAssertEqual(TemplateResolver.resolve(HeraldNotification(app: "a", title: "", group: "rive.app"), with: t).title, "rive.app changed")
    }

    func testAnIssuersStackingOverrideRoundTripsAndAnUnknownOneIsIgnored() throws {
        let rec = AppRecord(registration: HeraldAppRegistration(app: "a"), stacking: .byIssuer)
        let back = try HeraldJSON.decoder().decode(AppRecord.self, from: try HeraldJSON.encoder().encode(rec))
        XCTAssertEqual(back.stacking, .byIssuer)
        XCTAssertNil(try HeraldJSON.decoder().decode(AppRecord.self, from: Data(#"{"registration":{"app":"a"}}"#.utf8)).stacking,
                     "records from before stacking have no override")
        XCTAssertNil(try HeraldJSON.decoder().decode(AppRecord.self, from: Data(#"{"registration":{"app":"a"},"stacking":"sideways"}"#.utf8)).stacking)
    }

    func testManifestFamilyRoundTripsAndIsOptional() throws {
        let m = try HeraldJSON.decoder().decode(HeraldManifest.self, from: Data(#"{"app":"webwatcher.email","family":"webwatcher"}"#.utf8))
        XCTAssertEqual(m.family, "webwatcher")
        XCTAssertEqual(try HeraldJSON.decoder().decode(HeraldManifest.self, from: try HeraldJSON.encoder().encode(m)).family, "webwatcher")
        XCTAssertNil(try HeraldJSON.decoder().decode(HeraldManifest.self, from: Data(#"{"app":"x"}"#.utf8)).family)
    }

    func testTheStackBadgeComponentAndToken() throws {
        let c = try HeraldJSON.decoder().decode(HeraldComponent.self, from: Data(##"{"type":"stackBadge","color":"#FF3B30"}"##.utf8))
        guard case .stackBadge(let b) = c else { return XCTFail() }
        XCTAssertEqual(b.color, "#FF3B30")
        XCTAssertEqual(c.typeName, "stackBadge")
        XCTAssertTrue(HeraldComponent.typeNames.contains("stackBadge"))
        XCTAssertEqual(c.referencedTokens, ["stack.count"])
        // Empty while the banner is alone, present from a stack of two.
        XCTAssertFalse(c.hasContent(fields: [:], actions: []))
        XCTAssertTrue(c.hasContent(fields: ["stack.count": .number(3)], actions: []))
        XCTAssertEqual(TemplateResolver.bind("{stack.count}", fields: ["stack.count": .number(3)]), "3")
        XCTAssertNil(TemplateResolver.bind("{stack.count}", fields: [:]))
        XCTAssertEqual(String(data: try HeraldJSON.encoder().encode(HeraldComponent.stackBadge(.init())), encoding: .utf8), "{\"type\":\"stackBadge\"}")
        XCTAssertTrue(TemplateResolver.standardTokens.contains("stack.count"))
    }

    func testStackCountIsASetFieldOnlyAboveOne() {
        let n = HeraldNotification(app: "a", id: "1", title: "t")
        func fields(_ count: Int) -> [String: HeraldFieldValue] {
            BannerData.fields(for: n, stored: nil, override: nil, manifest: nil, extra: [:], deliveredAt: Date(), hasPicture: false, stackCount: count)
        }
        XCTAssertNil(fields(1)["stack.count"], "empty when the count is 1")
        XCTAssertNil(fields(0)["stack.count"])
        XCTAssertEqual(fields(3)["stack.count"], .number(3))
        XCTAssertEqual(TemplateResolver.bind("{stack.count} new", fields: fields(3)), "3 new")
        XCTAssertNil(TemplateResolver.bind("{stack.count}", fields: fields(1)))
    }
}
