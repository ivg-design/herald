import Foundation

/// The inline reply field a banner shows after Reply is pressed (a `reply` action). Like an inline confirmation it
/// replaces the actions row inside the banner and is never a window: the model is pure so the state and its tests need
/// no window server. `id` identifies this prompt, so a Send for a prompt that was replaced meanwhile is ignored.
public struct BannerReplyPrompt: Equatable, Identifiable, Sendable {
    public let id: UUID
    public var placeholder: String
    /// What the user typed so far, shown only by a preview (`/v1/preview` with `replying`); a live field keeps its own text.
    public var sample: String

    public static let defaultPlaceholder = "Reply\u{2026}"

    public init(id: UUID = UUID(), placeholder: String? = nil, sample: String = "") {
        self.id = id
        let p = placeholder?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        self.placeholder = p.isEmpty ? Self.defaultPlaceholder : p
        self.sample = sample
    }
}
