import Foundation

/// What a click on the stack's count badge or title does: one intent for both, so they cannot drift apart.
enum StackToggle {
    enum Action: Equatable { case expand, collapse }

    static func action(expanded: Bool) -> Action { expanded ? .collapse : .expand }

    /// The badge's VoiceOver label.
    static func badgeLabel(count: Int) -> String { "\(count) stacked notifications, click to expand" }
}
