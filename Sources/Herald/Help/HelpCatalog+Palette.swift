import Foundation

// The component palette: one entry per component the Designer can place, saying what it renders.
extension HeraldHelpCatalog {
    static let palette: [HelpEntry] = [
        HelpEntry("palette.text", "Text", "Text from a notification field or fixed wording, styled and limited to the lines you set"),
        HelpEntry("palette.image", "Image", "A picture from the notification or a fixed file, fitted into its cell"),
        HelpEntry("palette.issuerIcon", "App icon", "The icon of the app that issued the notification, as a rounded square or circle"),
        HelpEntry("palette.timestamp", "Time", "The time the notification arrived, as a clock time or a relative time"),
        HelpEntry("palette.button", "Button", "One action button of the banner, labeled and styled by you"),
        HelpEntry("palette.actions", "Actions", "The row of action buttons the notification carries, from the issuer, from you or both"),
        HelpEntry("palette.iconButton", "Icon button", "A small round button showing a symbol, such as a dismiss cross"),
        HelpEntry("palette.badge", "Badge", "A small capsule showing a short status or count, such as {status} or {count}"),
        HelpEntry("palette.stackBadge", "Stack count", "A count of how many banners from this app are stacked together"),
        HelpEntry("palette.progress", "Progress", "A bar bound to a 0–1 number field"),
        HelpEntry("palette.rive", "Rive animation", "A Rive file played inside the banner; its pointer states and fields can bind to state machine inputs"),
        HelpEntry("palette.spacer", "Spacer", "Empty space that keeps a slot open when neighbours collapse"),
    ]
    /// The tooltip of a palette component, by its component type ("badge", "rive", ...).
    static func component(_ type: String) -> HelpEntry? { entry("palette.\(type)") }
}
