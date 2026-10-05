import Foundation

/// What a click on a banner's body does. A click never dismisses a banner that has nothing to open: the close button does
/// that. Text that is cut short is shown in full first.
///
/// Whether text is cut short is not measured while a banner sits there. A click lifts the line limits and the banner looks at
/// its own height a moment later: if it grew, there was more to read and it stays open; if not, the click goes on to what it
/// would otherwise do.
public enum BannerTap: Equatable, Sendable {
    /// Lift the line limits (then see `afterExpanding`).
    case expand
    /// Back to the short form.
    case collapse
    /// The notification's own "open": its link (which also puts the banner away), or opening a closed stack.
    case open
    case nothing

    /// How long the banner is given to lay itself out again before its height is compared.
    public static let settleSeconds = 0.2

    /// The first decision of a click.
    /// - expanded: the banner already shows its whole text.
    /// - hasLink: the notification carries a URL to open.
    /// - stacked: the card stands for a closed stack of several notifications (opening the stack shows them all).
    public static func click(expanded: Bool, hasLink: Bool, stacked: Bool) -> BannerTap {
        if stacked { return .open }
        if !expanded { return .expand }
        return hasLink ? .open : .collapse
    }

    /// The second decision, once the limits were lifted. `grew`: the banner got taller, so text had been cut short.
    /// A banner that did not grow had nothing more to show: one with a link opens it; one without is left exactly as it was.
    public static func afterExpanding(grew: Bool, hasLink: Bool) -> BannerTap {
        if grew { return .nothing }
        return hasLink ? .open : .collapse
    }
}
