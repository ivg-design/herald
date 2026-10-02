import XCTest
@testable import HeraldCore

private let pngHeader: [UInt8] = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]

private func pngData(_ tail: [UInt8] = [1, 2, 3]) -> Data { Data(pngHeader + tail) }

// MARK: Links

final class LinkPolicyTests: XCTestCase {
    func testWebAndMailLinksOpen() {
        for s in ["http://example.com", "https://example.com/a?b=1#c", "HTTPS://EXAMPLE.COM", "mailto:me@example.com"] {
            XCTAssertTrue(LinkPolicy.isOpenable(s), s)
        }
    }

    func testEverythingElseIsRefused() {
        for s in ["file:///Applications/Calculator.app",
                  "file:///Users/u/Library/Application%20Support/Herald/history/images/ab.terminal",
                  "smb://attacker/share", "shortcuts://run-shortcut?name=x", "x-apple.systempreferences:com.apple.preference.security",
                  "javascript:alert(1)", "ssh://host", "vnc://host", "tel:123", "data:text/html,hi", "https:///no-host", "no-scheme"] {
            XCTAssertFalse(LinkPolicy.isOpenable(s), s)
        }
    }
}

// MARK: Images

final class ImageSniffTests: XCTestCase {
    func testKnownFormats() {
        XCTAssertEqual(ImageSniffer.fileExtension(for: pngData()), "png")
        XCTAssertEqual(ImageSniffer.fileExtension(for: Data([0xFF, 0xD8, 0xFF, 0xE0, 0, 0x10])), "jpg")
        XCTAssertEqual(ImageSniffer.fileExtension(for: Data("GIF89a....".utf8)), "gif")
        XCTAssertEqual(ImageSniffer.fileExtension(for: Data("RIFF".utf8) + Data([1, 2, 3, 4]) + Data("WEBPVP8 ".utf8)), "webp")
        XCTAssertEqual(ImageSniffer.fileExtension(for: Data([0x49, 0x49, 0x2A, 0x00, 8, 0, 0, 0])), "tiff")
        XCTAssertEqual(ImageSniffer.fileExtension(for: Data([0x4D, 0x4D, 0x00, 0x2A, 0, 0, 0, 8])), "tiff")
        XCTAssertEqual(ImageSniffer.fileExtension(for: Data([0, 0, 0, 0x18]) + Data("ftypheic".utf8) + Data([0, 0, 0, 0])), "heic")
        XCTAssertEqual(ImageSniffer.fileExtension(for: Data([0, 0, 0, 0x18]) + Data("ftypavif".utf8) + Data([0, 0, 0, 0])), "avif")
        XCTAssertEqual(ImageSniffer.fileExtension(for: Data("BM".utf8) + Data(count: 20)), "bmp")
    }

    func testNonImagesAreRefused() {
        let terminal = Data("<?xml version=\"1.0\"?><plist><dict><key>CommandString</key><string>id</string></dict></plist>".utf8)
        for data in [Data(), terminal, Data("#!/bin/sh\necho hi\n".utf8), Data("PK\u{3}\u{4}".utf8), Data([0x89, 0x50, 0x4E, 0x47]),
                     Data([0, 0, 0, 0x18]) + Data("ftypM4A ".utf8)] {
            XCTAssertNil(ImageSniffer.fileExtension(for: data))
        }
    }
}

final class ImageCacheSafetyTests: XCTestCase {
    var dir: URL!
    override func setUp() { dir = FileManager.default.temporaryDirectory.appendingPathComponent("herald-img-\(UUID().uuidString)") }
    override func tearDown() { try? FileManager.default.removeItem(at: dir) }

    private func imageFiles(_ s: HistoryStore) -> [String] {
        ((try? FileManager.default.contentsOfDirectory(atPath: s.imagesDirectory.path)) ?? []).sorted()
    }

    /// The sender names the type in the MIME subtype; the file must still land with an image extension.
    func testDataURIWithAHostileMimeTypeIsStoredAsTheDetectedImageType() async throws {
        let s = HistoryStore(directory: dir)
        let path = await s.cacheImage("data:application/terminal;base64," + pngData().base64EncodedString())
        let p = try XCTUnwrap(path)
        XCTAssertEqual((p as NSString).pathExtension, "png")
        XCTAssertFalse(p.contains("terminal"))
        let perms = try FileManager.default.attributesOfItem(atPath: p)[.posixPermissions] as? NSNumber
        XCTAssertEqual(perms?.intValue, 0o600)
    }

    func testBytesThatAreNotAnImageAreNeverWritten() async throws {
        let s = HistoryStore(directory: dir)
        let plist = Data("<?xml version=\"1.0\"?><plist><dict/></plist>".utf8)
        let viaData = await s.cacheImage("data:application/terminal;base64," + plist.base64EncodedString())
        XCTAssertNil(viaData)
        XCTAssertNil(s.storeImage(plist))
        let src = dir.appendingPathComponent("evil.terminal"); try plist.write(to: src)
        let viaPath = await s.cacheImage(src.path)
        XCTAssertNil(viaPath)
        XCTAssertEqual(imageFiles(s), [])
    }

    func testALocalImageKeepsItsTypeNotItsName() async throws {
        let s = HistoryStore(directory: dir)
        let src = dir.appendingPathComponent("looks-like.terminal"); try pngData().write(to: src)
        let path = await s.cacheImage(src.path)
        XCTAssertEqual((try XCTUnwrap(path) as NSString).pathExtension, "png")
    }

    func testOversizedImagesAreRefused() async throws {
        let s = HistoryStore(directory: dir)
        let big = Data(pngHeader + [UInt8](repeating: 0, count: HistoryStore.maxImageBytes))
        XCTAssertNil(s.storeImage(big))
        let src = dir.appendingPathComponent("big.png"); try big.write(to: src)
        let viaPath = await s.cacheImage(src.path)
        XCTAssertNil(viaPath)
        XCTAssertEqual(imageFiles(s), [])
    }
}

// MARK: History growth

final class HistoryGrowthTests: XCTestCase {
    var dir: URL!
    override func setUp() { dir = FileManager.default.temporaryDirectory.appendingPathComponent("herald-grow-\(UUID().uuidString)") }
    override func tearDown() { try? FileManager.default.removeItem(at: dir) }

    private func item(_ app: String, _ id: String, _ t: TimeInterval = 0, image: String? = nil) -> HeraldHistoryItem {
        HeraldHistoryItem(id: id, app: app, notification: HeraldNotification(app: app, id: id, title: "t"),
                          deliveredAt: Date(timeIntervalSince1970: 1_700_000_000 + t), imagePath: image)
    }

    private func exists(_ path: String) -> Bool { FileManager.default.fileExists(atPath: path) }

    func testDeletingTheLastReferenceRemovesTheCachedImage() throws {
        let s = HistoryStore(directory: dir)
        let shared = try XCTUnwrap(s.storeImage(pngData([1])))
        let solo = try XCTUnwrap(s.storeImage(pngData([2])))
        s.upsert(item("a", "1", 0, image: shared)); s.upsert(item("b", "2", 1, image: shared)); s.upsert(item("a", "3", 2, image: solo))
        s.delete(app: "a", id: "1")
        XCTAssertTrue(exists(shared), "still used by b/2")
        s.delete(app: "b", ids: ["2"])
        XCTAssertFalse(exists(shared))
        XCTAssertTrue(exists(solo))
        s.clear(app: "a")
        XCTAssertFalse(exists(solo))
    }

    func testReplacingAnItemFreesItsOldImageAndKeepsASharedOne() throws {
        let s = HistoryStore(directory: dir)
        let old = try XCTUnwrap(s.storeImage(pngData([1])))
        let new = try XCTUnwrap(s.storeImage(pngData([2])))
        s.upsert(item("a", "1", 0, image: old))
        s.upsert(item("a", "1", 1, image: old))     // same image again: must survive
        XCTAssertTrue(exists(old))
        s.upsert(item("a", "1", 2, image: new))
        XCTAssertFalse(exists(old))
        XCTAssertTrue(exists(new))
    }

    func testEvictionPastTheCapRemovesTheEvictedImage() throws {
        let s = HistoryStore(directory: dir)
        let first = try XCTUnwrap(s.storeImage(pngData([9])))
        s.upsert(item("a", "first", 0, image: first))
        for i in 1...HistoryStore.cap { s.upsert(item("a", "n\(i)", TimeInterval(i))) }
        XCTAssertEqual(s.items(app: "a").count, HistoryStore.cap)
        XCTAssertNil(s.item(app: "a", id: "first"))
        XCTAssertFalse(exists(first))
    }

    func testOnlyFilesInsideTheImagesDirectoryAreEverDeleted() throws {
        let s = HistoryStore(directory: dir)
        let outside = dir.appendingPathComponent("precious.txt")
        try "keep".write(to: outside, atomically: true, encoding: .utf8)
        s.upsert(item("a", "1", 0, image: outside.path))
        s.delete(app: "a", id: "1")
        XCTAssertTrue(exists(outside.path))
    }

    func testUpdateThatDropsTheImageFreesIt() throws {
        let s = HistoryStore(directory: dir)
        let p = try XCTUnwrap(s.storeImage(pngData([5])))
        s.upsert(item("a", "1", 0, image: p))
        s.update(app: "a", id: "1") { $0.dismissedAt = Date() }
        XCTAssertTrue(exists(p))
        s.update(app: "a", id: "1") { $0.imagePath = nil }
        XCTAssertFalse(exists(p))
    }

    /// After the first call the list of apps and the unread count come from memory: a history file that
    /// appears behind the store's back is not found by re-reading the directory.
    func testAppListAndUnreadCountAreServedFromMemory() throws {
        let s = HistoryStore(directory: dir)
        s.upsert(item("a", "1", 0)); s.upsert(item("a", "2", 1)); s.upsert(item("b", "3", 2))
        s.update(app: "a", id: "1") { $0.dismissedAt = Date() }
        XCTAssertEqual(s.apps(), ["a", "b"])
        XCTAssertEqual(s.unreadCount(), 2)
        XCTAssertEqual(s.unreadCount(), s.undismissed().count)

        let other = HistoryStore(directory: dir)   // writes a third app's file behind `s`'s back
        other.upsert(item("c", "9", 3))
        XCTAssertEqual(s.apps(), ["a", "b"])

        let reopened = HistoryStore(directory: dir)   // a fresh store seeds from disk once
        XCTAssertEqual(reopened.apps(), ["a", "b", "c"])
        XCTAssertEqual(reopened.unreadCount(), 3)
    }

    func testAppLeavesTheListWhenItsHistoryEmpties() {
        let s = HistoryStore(directory: dir)
        s.upsert(item("a", "1", 0)); s.upsert(item("b", "2", 1))
        XCTAssertEqual(s.apps(), ["a", "b"])
        s.delete(app: "a", id: "1")
        XCTAssertEqual(s.apps(), ["b"])
        s.clear(app: "b")
        XCTAssertEqual(s.apps(), [])
        XCTAssertEqual(s.unreadCount(), 0)
        XCTAssertEqual(HistoryStore(directory: dir).apps(), [], "no empty history files are left behind")
    }
}

// MARK: Limits

final class PayloadLimitTests: XCTestCase {
    private func tooLarge(_ n: HeraldNotification, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertThrowsError(try PayloadLimits.validate(n), file: file, line: line) {
            XCTAssertEqual(($0 as? BackendError)?.status, 413, file: file, line: line)
        }
    }

    func testAnOrdinaryPayloadPasses() throws {
        var n = HeraldNotification(app: "bidbot", id: "x", title: String(repeating: "t", count: PayloadLimits.maxTitleBytes),
                                   subtitle: String(repeating: "s", count: PayloadLimits.maxSubtitleBytes),
                                   body: String(repeating: "b", count: PayloadLimits.maxBodyBytes))
        n.buttons = (0..<PayloadLimits.maxButtons).map { HeraldButton(label: "B\($0)", url: "https://example.com/\($0)") }
        n.metadata = .object(["k": .string("v")])
        XCTAssertNoThrow(try PayloadLimits.validate(n))
    }

    func testEachFieldHasALimit() {
        tooLarge(HeraldNotification(app: "a", title: String(repeating: "t", count: PayloadLimits.maxTitleBytes + 1)))
        tooLarge(HeraldNotification(app: "a", title: "t", subtitle: String(repeating: "s", count: PayloadLimits.maxSubtitleBytes + 1)))
        tooLarge(HeraldNotification(app: "a", title: "t", body: String(repeating: "b", count: PayloadLimits.maxBodyBytes + 1)))
        tooLarge(HeraldNotification(app: "a", title: "t", image: "data:image/png;base64," + String(repeating: "A", count: PayloadLimits.maxImageSpecBytes)))
        tooLarge(HeraldNotification(app: "a", title: "t", url: "https://x/" + String(repeating: "u", count: PayloadLimits.maxSmallFieldBytes)))
        tooLarge(HeraldNotification(app: String(repeating: "a", count: PayloadLimits.maxAppBytes + 1), title: "t"))
        tooLarge(HeraldNotification(app: "a", id: String(repeating: "i", count: PayloadLimits.maxIdBytes + 1), title: "t"))
        tooLarge(HeraldNotification(app: "a", title: "t", buttons: (0...PayloadLimits.maxButtons).map { HeraldButton(label: "B\($0)") }))
        tooLarge(HeraldNotification(app: "a", title: "t",
                                    buttons: [HeraldButton(label: "B", command: String(repeating: "c", count: PayloadLimits.maxButtonsBytes))]))
        var big = HeraldNotification(app: "a", title: "t")
        big.metadata = .object(["k": .string(String(repeating: "m", count: PayloadLimits.maxMetadataBytes))])
        tooLarge(big)
    }

    func testRegistrationLimits() {
        XCTAssertNoThrow(try PayloadLimits.validate(HeraldAppRegistration(app: "a", icon: "/path/icon.png")))
        XCTAssertThrowsError(try PayloadLimits.validate(
            HeraldAppRegistration(app: "a", icon: "data:image/png;base64," + String(repeating: "A", count: PayloadLimits.maxImageSpecBytes))))
        XCTAssertThrowsError(try PayloadLimits.validate(HeraldAppRegistration(app: String(repeating: "a", count: 500))))
    }

    func testTheRegistryIsBounded() {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("herald-reg-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }
        let reg = AppRegistry(file: dir.appendingPathComponent("apps.json"))
        for i in 0..<AppRegistry.maxApps { reg.ensure("app\(i)") }
        XCTAssertFalse(reg.hasRoom(for: "one-too-many"))
        XCTAssertTrue(reg.hasRoom(for: "app0"), "a known app can always be updated")
    }
}

// MARK: Ordering of suspended notifies

final class SupersedeTrackerTests: XCTestCase {
    func testALaterRequestSupersedesAnEarlierOne() {
        var t = SupersedeTracker()
        let first = t.begin("a\u{1}1")
        let second = t.begin("a\u{1}1")
        XCTAssertFalse(t.isCurrent("a\u{1}1", first))
        XCTAssertTrue(t.isCurrent("a\u{1}1", second))
        t.finish("a\u{1}1", first)             // a stale finish does not clear the newer ticket
        XCTAssertTrue(t.isCurrent("a\u{1}1", second))
        t.finish("a\u{1}1", second)
        XCTAssertEqual(t.pendingCount, 0)
    }

    func testDismissInvalidatesWhatIsInFlight() {
        var t = SupersedeTracker()
        let ticket = t.begin("a\u{1}1")
        t.invalidate("a\u{1}1")
        XCTAssertFalse(t.isCurrent("a\u{1}1", ticket))
        t.invalidate("a\u{1}never-started")    // nothing in flight: nothing is remembered
        XCTAssertEqual(t.pendingCount, 0)
    }

    func testKeysAreIndependentAndPrefixInvalidationIsScoped() {
        var t = SupersedeTracker()
        let a1 = t.begin("a\u{1}1"), a2 = t.begin("a\u{1}2"), b1 = t.begin("b\u{1}1")
        t.invalidateAll(prefix: "a\u{1}")
        XCTAssertFalse(t.isCurrent("a\u{1}1", a1)); XCTAssertFalse(t.isCurrent("a\u{1}2", a2))
        XCTAssertTrue(t.isCurrent("b\u{1}1", b1))
        t.invalidateAll()
        XCTAssertFalse(t.isCurrent("b\u{1}1", b1))
    }
}

// MARK: Banner stack

final class BannerStackPlanTests: XCTestCase {
    private func plan(_ n: Int, height: CGFloat = 137, available: CGFloat = 876, forceStub: Bool = false) -> BannerStackPlan {
        BannerStackPlan.make(heights: Array(repeating: height, count: n), available: available, gap: 8, stubHeight: 26, forceStub: forceStub)
    }

    func testEverythingThatFitsIsStackedWithGaps() {
        let p = plan(3)
        XCTAssertEqual(p.offsets, [0, 145, 290])
        XCTAssertEqual(p.overflow, 0)
        XCTAssertNil(p.stubOffset)
        XCTAssertEqual(plan(6).visibleCount, 6)      // 6 x 137 + 5 x 8 = 862 <= 876
    }

    func testTheSeventhBannerOverflowsAndAPillTakesItsPlace() {
        let p = plan(7)
        XCTAssertEqual(p.visibleCount, 5, "one banner is given up so the pill fits")
        XCTAssertEqual(p.overflow, 2)
        XCTAssertEqual(p.stubOffset, 725)
        XCTAssertLessThanOrEqual(p.stubOffset! + 26, 876)
        for (i, off) in p.offsets.enumerated() { XCTAssertLessThanOrEqual(off + 137, 876, "banner \(i) is on screen") }
    }

    func testTheNewestBannerIsAlwaysVisibleEvenWhenTallerThanTheScreen() {
        let p = BannerStackPlan.make(heights: [500, 200], available: 300, gap: 8, stubHeight: 26)
        XCTAssertEqual(p.offsets, [0])
        XCTAssertEqual(p.overflow, 1)
        XCTAssertEqual(p.stubOffset, 508)
    }

    func testOlderSmallerBannersDoNotJumpTheQueue() {
        let p = BannerStackPlan.make(heights: [100, 400, 50], available: 300, gap: 8, stubHeight: 26)
        XCTAssertEqual(p.visibleCount, 1)
        XCTAssertEqual(p.overflow, 2)
    }

    func testDeferredBannersReserveAPillEvenWhenAllFit() {
        let p = plan(2, forceStub: true)
        XCTAssertEqual(p.visibleCount, 2)
        XCTAssertEqual(p.overflow, 0)
        XCTAssertEqual(p.stubOffset, 145 + 137 + 8)
        XCTAssertEqual(plan(0, forceStub: true).stubOffset, 0)
        XCTAssertNil(plan(0).stubOffset)
    }
}

// MARK: Bearer check on the head

final class HeadCheckTests: XCTestCase {
    private func head(_ method: String, _ target: String, auth: String? = nil) -> HTTPHead {
        HTTPHead(method: method, target: target, headers: auth.map { ["authorization": $0] } ?? [:], contentLength: 5_000, bodyStart: 0)
    }

    func testOnlyHealthIsOpen() {
        let check = BearerAuth.headCheck(token: "tok")
        XCTAssertNil(check(head("GET", "/v1/health")))
        XCTAssertEqual(check(head("POST", "/v1/health"))?.status, 401)
        XCTAssertEqual(check(head("POST", "/v1/notify"))?.status, 401)
        XCTAssertEqual(check(head("GET", "/v1/history?limit=5", auth: "Bearer nope"))?.status, 401)
        XCTAssertNil(check(head("POST", "/v1/notify", auth: "Bearer tok")))
        XCTAssertNil(check(head("POST", "/v1/snooze", auth: "bearer tok")))
    }
}

// MARK: Link click vs banner tap (issue #24)

final class LinkClickGuardTests: XCTestCase {
    func testTapRightAfterLinkClickIsSwallowed() {
        let g = LinkClickGuard(); let t = Date()
        g.record(at: t)
        XCTAssertTrue(g.swallowsBannerTap(at: t.addingTimeInterval(0.01)))
    }
    func testPlainTapWithNoLinkClickOpensBanner() {
        XCTAssertFalse(LinkClickGuard().swallowsBannerTap())
    }
    func testOldLinkClickDoesNotSwallowLaterTap() {
        let g = LinkClickGuard(); let t = Date()
        g.record(at: t)
        XCTAssertFalse(g.swallowsBannerTap(at: t.addingTimeInterval(LinkClickGuard.window + 0.1)))
    }
    func testCopiesShareTheRecord() {
        // The openURL closure and the tap closure capture copies of the same @State value.
        let a = LinkClickGuard(); let b = a
        a.record()
        XCTAssertTrue(b.swallowsBannerTap())
    }
}
