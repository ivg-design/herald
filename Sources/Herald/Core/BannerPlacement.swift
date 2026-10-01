import Foundation

// The pure half of where banners go (per-app display and corner, issue #28) and of which banner comes back
// when the stack has room again (lazy promotion, issue #25). No AppKit here, so the rules are unit tested
// (BannerStackTests); `BannerCenter` feeds them real displays and real panels.

/// Display choices. A display is named by the number macOS gives it (`CGDirectDisplayID`, as a string), which
/// survives a reboot and a re-plug of the same monitor; `main` is the primary display.
public enum BannerDisplay {
    /// The primary display (the one with the menu bar). Also what a choice falls back to when its display is not connected.
    public static let main = "main"

    /// The display a banner goes to: `choice` when that display is connected, else the primary one. `connected`
    /// lists the display ids with the primary first (`NSScreen.screens` order); empty gives `main`.
    public static func resolve(_ choice: String?, connected: [String]) -> String {
        guard let first = connected.first else { return main }
        guard let choice, choice != main, connected.contains(choice) else { return first }
        return choice
    }
}

/// One stack of banners: a corner of one display. Banners of every app that chose the same display and corner
/// stack together, newest on top.
public struct BannerSlot: Hashable, Sendable {
    public var screen: String
    public var corner: HeraldCorner
    public init(screen: String, corner: HeraldCorner) { self.screen = screen; self.corner = corner }

    /// The slot an app's banners go to: its own choice, else the corner it registered, else top right, on the
    /// display it chose (when connected) or the primary one.
    public static func resolve(screen: String?, corner: HeraldCorner?, connected: [String]) -> BannerSlot {
        BannerSlot(screen: BannerDisplay.resolve(screen, connected: connected), corner: corner ?? .topRight)
    }
}

/// Banners that exist only in History (not restored to a panel at launch, or held back by quiet hours) and are
/// counted by the "+N more" pill. They come back oldest first, into the stack that has room.
public struct DeferredBanners: Equatable, Sendable {
    public struct Entry: Equatable, Sendable {
        public var key: String
        public var slot: BannerSlot
        /// Arrival order: lower is older. A key keeps its place when it is added again.
        public var order: Int
    }

    private var entries: [String: Entry] = [:]
    private var counter = 0

    public init() {}

    public var count: Int { entries.count }
    public var isEmpty: Bool { entries.isEmpty }
    public func contains(_ key: String) -> Bool { entries[key] != nil }
    public var keys: [String] { entries.values.sorted { $0.order < $1.order }.map(\.key) }
    public var slots: Set<BannerSlot> { Set(entries.values.map(\.slot)) }

    public func count(in slot: BannerSlot) -> Int { entries.values.filter { $0.slot == slot }.count }

    /// The oldest deferred banner of `slot`.
    public func oldest(in slot: BannerSlot) -> Entry? {
        entries.values.filter { $0.slot == slot }.min { $0.order < $1.order }
    }

    /// Adds `key` (or moves it to `slot`, keeping its age).
    public mutating func add(_ key: String, slot: BannerSlot) {
        if var e = entries[key] { e.slot = slot; entries[key] = e; return }
        counter += 1
        entries[key] = Entry(key: key, slot: slot, order: counter)
    }

    /// Adds keys oldest first.
    public mutating func add(_ keys: [String], slot: (String) -> BannerSlot) {
        for k in keys { add(k, slot: slot(k)) }
    }

    @discardableResult
    public mutating func remove(_ key: String) -> Bool { entries.removeValue(forKey: key) != nil }

    /// Moves every entry to the slot `slot` computes for its key (an app's display or corner was changed).
    /// Returns true when something moved.
    @discardableResult
    public mutating func reslot(_ slot: (String) -> BannerSlot) -> Bool {
        var moved = false
        for (k, e) in entries {
            let s = slot(k)
            if s != e.slot { entries[k]?.slot = s; moved = true }
        }
        return moved
    }
}

/// Lazy promotion (issue #25): a banner that was dismissed frees a place on its stack, and the oldest deferred
/// banner of that stack takes it, one at a time, only when the stack really has room.
public enum BannerPromotion {
    public enum Decision: Equatable, Sendable {
        /// Show the oldest deferred banner of the stack now.
        case promote
        /// A banner of this stack is still being measured; decide again once its height is known.
        case wait
        /// Nothing to do: nothing was freed, nothing is deferred, or the stack is full. The freed places are forgotten.
        case stop
    }

    /// - freed: places freed on this stack by dismissals that no promotion has used yet.
    /// - deferred: banners waiting for this stack.
    /// - unmeasured: banners on the stack that have no height yet.
    /// - overflow: banners on the stack that do not fit (hidden). They are older than anything deferred and
    ///   take the room first, so while there are any the stack is full.
    public static func decide(freed: Int, deferred: Int, unmeasured: Int, overflow: Int) -> Decision {
        guard freed > 0, deferred > 0 else { return .stop }
        if unmeasured > 0 { return .wait }
        return overflow > 0 ? .stop : .promote
    }
}
