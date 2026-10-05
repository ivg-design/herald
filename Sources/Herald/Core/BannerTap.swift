import Foundation

/// What a click on a banner's body does. A click never dismisses a banner that has nothing to open: the close button does
/// that. Text that is cut short is shown in full first.
public enum BannerTap: Equatable, Sendable {
    /// Show the whole text (the banner grows).
    case expand
    /// Back to the short form.
    case collapse
    /// The notification's own "open": its link (which also puts the banner away), or opening a closed stack.
    case open
    case nothing

    /// - truncated: some text of the banner is cut short right now.
    /// - expanded: the banner is already showing its whole text.
    /// - hasLink: the notification carries a URL to open.
    /// - stacked: the card stands for a closed stack of several notifications.
    public static func decide(truncated: Bool, expanded: Bool, hasLink: Bool, stacked: Bool) -> BannerTap {
        if truncated && !expanded { return .expand }
        if hasLink || stacked { return .open }
        return expanded ? .collapse : .nothing
    }
}
