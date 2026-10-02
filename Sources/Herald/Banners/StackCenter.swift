import AppKit

/// Stacking for the banners that are up (DESIGN section 9). It owns the `StackBook` (which live banner is in which
/// stack, who is on top, what is open: the pure rules in `StackPlanner.swift`) and works out the key a notification
/// stacks under from the stacking level that applies to its issuer. `BannerCenter` calls it whenever a banner comes
/// or goes and draws what the plan says; this class never touches a panel, so it cannot take focus (DESIGN section 8).
@MainActor
final class StackCenter {
    private(set) var book = StackBook()
    /// The level that applies to an issuer: its own override, else the global default.
    private let level: (String) -> StackingLevel
    /// The product family the issuer's manifest names, if it does. Reading a manifest is a file read, and the stacks
    /// are re-keyed on every change, so an answer is kept for a few seconds.
    private let familyLookup: (String) -> String?
    private var familyCache: [String: (value: String?, at: Date)] = [:]
    private static let familyTTL: TimeInterval = 5
    private var escapeMonitor: Any?

    init(level: @escaping (String) -> StackingLevel, family: @escaping (String) -> String?) {
        self.level = level
        self.familyLookup = family
    }

    private func family(of app: String) -> String? {
        if let hit = familyCache[app], Date().timeIntervalSince(hit.at) < Self.familyTTL { return hit.value }
        let value = familyLookup(app)
        familyCache[app] = (value, Date())
        return value
    }

    deinit { if let m = escapeMonitor { NSEvent.removeMonitor(m) } }

    // MARK: Keys

    /// The stack a notification belongs to; nil when its issuer does not stack.
    func stackKey(for item: HeraldHistoryItem) -> String? {
        StackKeying.key(level: level(item.app), app: item.app, manifestFamily: family(of: item.app), group: item.notification.group)
    }

    // MARK: Changes (a thin layer over `StackBook`)

    @discardableResult
    func deliver(_ key: String, stackKey: String?, promoted: Bool = false, keepPlace: Bool = false) -> StackBook.Delivery {
        book.deliver(key, stackKey: stackKey, promoted: promoted, keepPlace: keepPlace)
    }

    @discardableResult
    func remove(_ key: String) -> StackBook.Removal? { book.remove(key) }

    /// The level or a group changed: re-key every live banner. True when any moved to another stack.
    @discardableResult
    func regroup(_ stackKey: (String) -> String?) -> Bool { book.rekey(stackKey) }

    func order(of key: String) -> Int? { book.order(of: key) }

    func isExpanded(stackKey: String?) -> Bool { stackKey.map { book.isExpanded($0) } ?? false }

    func setExpanded(stackKey: String, _ open: Bool) { book.setExpanded(stackKey, open) }

    /// The stack `key` is the top card of while it is closed, with its banners newest first; nil for a banner that is
    /// alone, a card under another one, or a stack that is open (its rows act on themselves). This is what the card's
    /// close button, its snooze menu and its body click act on.
    func closedGroup(topKey key: String) -> [String]? {
        guard let stackKey = book.stackKey(of: key), !book.isExpanded(stackKey) else { return nil }
        let members = book.members(ofStack: stackKey)
        return members.count > 1 && members.first == key ? members : nil
    }

    /// The members of the stack `key` is in, oldest first (the order a snoozed stack is brought back in).
    func restoreOrder(of key: String) -> [String] {
        book.stackKey(of: key).map { book.restoreOrder(ofStack: $0) } ?? [key]
    }

    // MARK: Report

    /// The live stacks, for `GET /v1/stacks`.
    func infos(app: String?, item: (String) -> HeraldHistoryItem?,
               frame: (String) -> HeraldStackInfo.Frame?) -> [HeraldStackInfo] {
        StackReport.infos(book: book, app: app, item: item, frame: frame)
    }

    // MARK: Escape

    /// Esc closes the open stacks while a Herald window has the key (Settings, History, ...). A banner panel never
    /// takes the key (DESIGN section 8), so Esc cannot reach it directly, and listening for keys in other apps would
    /// need an Accessibility or Input Monitoring grant; the Collapse button and a click on the badge are the way to
    /// close a stack from the banner itself.
    func installEscapeMonitor(_ collapseAll: @escaping @MainActor () -> Void) {
        guard escapeMonitor == nil else { return }
        escapeMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            if event.keyCode == 53 { MainActor.assumeIsolated { collapseAll() } }
            return event
        }
    }
}
