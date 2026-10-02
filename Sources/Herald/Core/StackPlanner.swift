import Foundation

// The pure half of stacking (DESIGN section 9): which notifications belong in one stack, which card is on top,
// what a count is after a delivery, a replacement, a dismissal or a snooze, and what the History window folds under
// a disclosure. No AppKit here, so every rule is unit tested (StackPlannerTests); `StackCenter` feeds it the live
// banners and `BannerCenter` draws the result.

/// The key a live banner is known by: its app and its notification id (ids are only unique per app).
public enum BannerKey {
    public static let separator = "\u{1}"
    public static func make(_ app: String, _ id: String) -> String { app + separator + id }
    public static func split(_ key: String) -> (app: String, id: String)? {
        let p = key.components(separatedBy: separator)
        return p.count == 2 ? (p[0], p[1]) : nil
    }
}

// MARK: - Levels and keys

/// How notifications are grouped into stacks (the `stacking` setting: a global default, a per-issuer override and
/// the bell menu's quick switch).
public enum StackingLevel: String, Codable, CaseIterable, Sendable {
    /// One stack per product family: the manifest's `family`, else the issuer id's prefix before the first dot, so
    /// `webwatcher.web` and `webwatcher.email` share a stack.
    case byApp
    /// One stack per issuer (manifest) id.
    case byIssuer
    /// One stack per payload `group` (an email sender, a watched site, a bid id); the issuer id when none was sent.
    case bySender
    /// Banners never fold together.
    case never

    /// The global default.
    public static let defaultLevel: StackingLevel = .bySender

    public var title: String {
        switch self {
        case .byApp: return "By App"
        case .byIssuer: return "By Issuer"
        case .bySender: return "By Sender"
        case .never: return "Never"
        }
    }

    public var detail: String {
        switch self {
        case .byApp: return "One stack for every notification of a product family, such as all WebWatcher."
        case .byIssuer: return "One stack for each issuer, such as all Gmail notifications."
        case .bySender: return "One stack for each sender the issuer names with a group, such as one email sender or one watched site."
        case .never: return "Every notification is its own banner."
        }
    }
}

public enum StackKeying {
    /// A blank value is no value.
    public static func clean(_ s: String?) -> String? {
        guard let t = s?.trimmingCharacters(in: .whitespacesAndNewlines), !t.isEmpty else { return nil }
        return t
    }

    /// The product family of an issuer: its manifest's `family`, else the issuer id up to the first dot
    /// (`webwatcher.email` is in `webwatcher`), else the whole id.
    public static func family(app: String, manifestFamily: String?) -> String {
        if let f = clean(manifestFamily) { return f }
        if let dot = app.firstIndex(of: "."), dot != app.startIndex { return String(app[..<dot]) }
        return app
    }

    /// The group a `bySender` stack is keyed by: the payload's `group`, else the issuer id.
    public static func effectiveGroup(app: String, group: String?) -> String { clean(group) ?? app }

    /// The level that applies to an issuer: its own override, else the global default.
    public static func level(override: StackingLevel?, default global: StackingLevel) -> StackingLevel {
        override ?? global
    }

    private static let separator = "\u{1}"

    /// The key notifications are stacked under at `level`, or nil when they never stack. Keys of different levels
    /// never collide, so a stack keeps its identity while the level changes under it (`StackBook.rekey` moves the
    /// members instead).
    public static func key(level: StackingLevel, app: String, manifestFamily: String?, group: String?) -> String? {
        switch level {
        case .never:
            return nil
        case .byApp:
            return "app" + separator + family(app: app, manifestFamily: manifestFamily)
        case .byIssuer:
            return "issuer" + separator + app
        case .bySender:
            return "sender" + separator + app + separator + effectiveGroup(app: app, group: group)
        }
    }

    /// What a key stands for: its level, the issuer (the family for `byApp`) and, for `bySender`, the group.
    public static func describe(_ key: String) -> (level: StackingLevel, app: String, group: String?)? {
        let parts = key.components(separatedBy: separator)
        switch parts.first {
        case "app" where parts.count == 2: return (.byApp, parts[1], nil)
        case "issuer" where parts.count == 2: return (.byIssuer, parts[1], nil)
        case "sender" where parts.count == 3: return (.bySender, parts[1], parts[2])
        default: return nil
        }
    }
}

// MARK: - The live set

/// The banners that are up, with the order they arrived in and the stack each one belongs to. The one place the
/// rules of a stack live: a new banner for a key that already has a live stack folds into it and becomes its top
/// card; the same id again replaces in place and never raises the count; a dismissed member leaves; the stack's
/// position is its top card's.
///
/// `order` is the arrival order (larger is newer). The newest member of a stack is its top card, and a stack sits
/// on screen where its top card would.
public struct StackBook: Equatable, Sendable {
    public struct Member: Equatable, Sendable {
        public var id: String
        /// nil: the banner is not stacked (stacking is `never` for it).
        public var stackKey: String?
        public var order: Int
    }

    /// What delivering a banner did.
    public enum Delivery: Equatable, Sendable {
        /// A banner of its own: stacking is off for it, or no other live banner has its key.
        case alone
        /// It joined a live stack (`count` members now). It is the top card unless it was `promoted` (older than
        /// everything on screen, a deferred banner coming back).
        case folded(count: Int, isTop: Bool)
        /// The id was already live: it was replaced in place, so the count did not change. It moves to the top of a
        /// stack of two or more (`promoted`), where the newest content shows; a lone banner keeps its place.
        case replaced(count: Int, promoted: Bool)
    }

    /// What removing a banner left behind.
    public struct Removal: Equatable, Sendable {
        public var stackKey: String?
        /// Members the stack still has (0 when it is gone).
        public var remaining: Int
        /// The card that is now on top, when the stack still has members.
        public var newTop: String?
    }

    private var live: [String: Member] = [:]
    private var expandedKeys: Set<String> = []
    private var counter = 0

    public init() {}

    public var count: Int { live.count }
    public func contains(_ id: String) -> Bool { live[id] != nil }
    public func order(of id: String) -> Int? { live[id]?.order }
    public func stackKey(of id: String) -> String? { live[id]?.stackKey }
    public var ids: [String] { Array(live.keys) }

    // MARK: Changes

    /// A banner was delivered (or delivered again under the same id) for `stackKey`. `promoted` is for a banner
    /// that is older than everything on screen (lazy promotion), which goes below. `keepPlace` is for a banner that
    /// is only redrawn (a failure line, an "Open Reminders" button), not delivered again: it never changes places.
    @discardableResult
    public mutating func deliver(_ id: String, stackKey: String?, promoted: Bool = false, keepPlace: Bool = false) -> Delivery {
        let key = stackKey.flatMap { StackKeying.clean($0) == nil ? nil : $0 }
        if var existing = live[id] {
            if existing.stackKey == key {
                // The same banner again. Where a stack has other members the update moves to the top, so what it
                // says is what the card shows; alone, it keeps its place.
                let mates = key.map { self.members(ofStack: $0).count } ?? 1
                let wasTop = key.map { self.members(ofStack: $0).first == id } ?? true
                var moved = false
                if mates > 1 && !wasTop && !keepPlace {
                    counter += 1
                    existing.order = counter
                    live[id] = existing
                    moved = true
                }
                return .replaced(count: mates, promoted: moved)
            }
            // Same id, other key (its group changed): it leaves the old stack and arrives in the new one.
            live[id] = nil
            pruneExpanded()
        }
        let order: Int
        if promoted { order = (live.values.map(\.order).min() ?? 1) - 1 } else { counter += 1; order = counter }
        live[id] = Member(id: id, stackKey: key, order: order)
        guard let key else { return .alone }
        let stack = self.members(ofStack: key)
        return stack.count > 1 ? .folded(count: stack.count, isTop: stack.first == id) : .alone
    }

    /// A banner went away (dismissed, expired, snoozed, muted).
    @discardableResult
    public mutating func remove(_ id: String) -> Removal? {
        guard let m = live.removeValue(forKey: id) else { return nil }
        pruneExpanded()
        guard let key = m.stackKey else { return Removal(stackKey: nil, remaining: 0, newTop: nil) }
        let rest = members(ofStack: key)
        return Removal(stackKey: key, remaining: rest.count, newTop: rest.first)
    }

    /// Removes every member of a stack (the card's close button, "Dismiss all") and returns them, newest first.
    @discardableResult
    public mutating func removeStack(_ stackKey: String) -> [String] {
        let ids = members(ofStack: stackKey)
        for id in ids { live[id] = nil }
        expandedKeys.remove(stackKey)
        return ids
    }

    /// The stacking level or an issuer's group changed: every member gets the key `key` now says (nil: unstacked).
    /// Arrival order is kept, so the newest member of a new stack is still its top. Returns true when any member
    /// moved to another stack.
    @discardableResult
    public mutating func rekey(_ key: (String) -> String?) -> Bool {
        var changed = false
        for (id, m) in live {
            let k = key(id).flatMap { StackKeying.clean($0) == nil ? nil : $0 }
            if k != m.stackKey { live[id]?.stackKey = k; changed = true }
        }
        if changed { pruneExpanded() }
        return changed
    }

    // MARK: Queries

    /// The members of a stack, newest first.
    public func members(ofStack key: String) -> [String] {
        live.values.filter { $0.stackKey == key }.sorted { $0.order > $1.order }.map(\.id)
    }

    /// Where every stack stands, newest top first.
    public func plan() -> StackPlan {
        var byKey: [String: [Member]] = [:]
        for m in live.values { if let k = m.stackKey { byKey[k, default: []].append(m) } }
        let stacks = byKey.map { key, list in
            StackPlan.Stack(key: key, members: list.sorted { $0.order > $1.order }.map(\.id))
        }
        let newest = { (s: StackPlan.Stack) in self.live[s.top]?.order ?? 0 }
        return StackPlan(stacks: stacks.sorted { newest($0) > newest($1) })
    }

    /// The members of a stack in the order they arrived, oldest first: the order a snoozed stack comes back in, so
    /// it is rebuilt with the same top card.
    public func restoreOrder(ofStack key: String) -> [String] { members(ofStack: key).reversed() }

    // MARK: Expansion

    /// Whether the stack is open as a list. A stack only opens while it has two or more members.
    public func isExpanded(_ key: String) -> Bool {
        expandedKeys.contains(key) && members(ofStack: key).count > 1
    }

    /// Opens or closes a stack. A stack with fewer than two members stays closed.
    public mutating func setExpanded(_ key: String, _ open: Bool) {
        if open, members(ofStack: key).count > 1 { expandedKeys.insert(key) } else { expandedKeys.remove(key) }
    }

    public var expandedStacks: Set<String> { expandedKeys.filter { isExpanded($0) } }

    /// A stack that is gone or has dropped to one member is no longer open (it would reopen on its own when it grew).
    private mutating func pruneExpanded() {
        expandedKeys = expandedKeys.filter { members(ofStack: $0).count > 1 }
    }
}

/// The stacks of a `StackBook` at one moment.
public struct StackPlan: Equatable, Sendable {
    public struct Stack: Equatable, Sendable {
        public var key: String
        /// Banner ids, newest first.
        public var members: [String]
        public var count: Int { members.count }
        /// The id of the card that is on top (the newest member).
        public var top: String { members[0] }
    }

    /// Every stack that has a key (a banner alone under its key is a stack of one), newest top first.
    public var stacks: [Stack]

    public func stack(containing id: String) -> Stack? { stacks.first { $0.members.contains(id) } }
    public func stack(forKey key: String) -> Stack? { stacks.first { $0.key == key } }

    /// How many banners the card of `id` stands for: the size of its stack, 1 when it is alone.
    public func count(of id: String) -> Int { stack(containing: id)?.count ?? 1 }

    /// A banner is on top unless it is under a newer member of a stack of two or more.
    public func isTop(_ id: String) -> Bool { stack(containing: id).map { $0.top == id } ?? true }

    /// Hidden under the top card of its stack: it has no panel of its own while the stack is closed.
    public func isFolded(_ id: String) -> Bool {
        guard let s = stack(containing: id) else { return false }
        return s.count > 1 && s.top != id
    }

    /// The top card of the stack `id` is in (itself when it is alone).
    public func top(of id: String) -> String { stack(containing: id)?.top ?? id }
}

// MARK: - Reports

public enum StackReport {
    /// The stacks as `GET /v1/stacks` lists them. `item` finds the history record behind a banner id; a stack none
    /// of whose members can be found is left out. `app` keeps only the stacks that hold a notification of that app.
    public static func infos(book: StackBook, app: String? = nil, item: (String) -> HeraldHistoryItem?,
                             frame: (String) -> HeraldStackInfo.Frame? = { _ in nil }) -> [HeraldStackInfo] {
        var out: [HeraldStackInfo] = []
        for stack in book.plan().stacks {
            let items = stack.members.compactMap(item)
            guard let first = items.first else { continue }
            if let app, !items.contains(where: { $0.app == app }) { continue }
            let described = StackKeying.describe(stack.key)
            out.append(HeraldStackInfo(
                level: (described?.level ?? .bySender).rawValue,
                app: described?.app ?? first.app,
                group: described?.group,
                count: stack.count,
                expanded: book.isExpanded(stack.key),
                members: items.map {
                    HeraldStackInfo.Member(app: $0.app, id: $0.id, title: $0.notification.title,
                                           group: StackKeying.clean($0.notification.group), deliveredAt: $0.deliveredAt)
                },
                frame: frame(stack.top)))
        }
        return out
    }
}

// MARK: - History

/// What the History window folds under a disclosure: notifications of one app that share an explicit `group`.
public enum HistoryGrouping {
    public struct Group: Equatable, Identifiable, Sendable {
        public var app: String
        public var group: String
        /// Newest first, in the order given.
        public var items: [HeraldHistoryItem]
        public var id: String { "g\u{1}" + app + "\u{1}" + group }
        /// Items whose banner was never dismissed.
        public var unread: Int { items.filter { $0.dismissedAt == nil }.count }
    }

    public enum Row: Equatable, Identifiable, Sendable {
        case item(HeraldHistoryItem)
        case group(Group)

        public var id: String {
            switch self {
            case .item(let i): return "i\u{1}" + i.app + "\u{1}" + i.id
            case .group(let g): return g.id
            }
        }
    }

    /// `items` (newest first) as rows: two or more notifications of one app with the same `group` become one group
    /// row, placed where the newest of them was; everything else stays a row of its own, in order.
    public static func rows(_ items: [HeraldHistoryItem]) -> [Row] {
        func key(_ i: HeraldHistoryItem) -> String? {
            StackKeying.clean(i.notification.group).map { i.app + "\u{1}" + $0 }
        }
        var counts: [String: Int] = [:]
        for i in items { if let k = key(i) { counts[k, default: 0] += 1 } }
        var placed: [String: Int] = [:]
        var rows: [Row] = []
        for i in items {
            guard let k = key(i), (counts[k] ?? 0) > 1 else { rows.append(.item(i)); continue }
            if let at = placed[k], case .group(var g) = rows[at] {
                g.items.append(i)
                rows[at] = .group(g)
            } else {
                placed[k] = rows.count
                rows.append(.group(Group(app: i.app, group: StackKeying.clean(i.notification.group) ?? "", items: [i])))
            }
        }
        return rows
    }
}
