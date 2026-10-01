import Foundation
import Combine
#if canImport(HeraldClient)
import HeraldClient
#endif

// MARK: - Form rows

/// One row of the composer's buttons editor. The editor works on plain strings; `build()` turns a row
/// into the wire `HeraldButton` (and a row that is not finished, i.e. has no label, becomes nothing).
struct ComposerButton: Identifiable, Equatable {
    enum Action: String, CaseIterable, Identifiable {
        case url, callback, command
        var id: String { rawValue }
    }
    enum Style: String, CaseIterable, Identifiable {
        case `default`, destructive, cancel
        var id: String { rawValue }
    }

    var id = UUID()
    var label = ""
    var action: Action = .url
    /// `url`: the link to open. `command`: the shell command. `callback`: optional callback URL that
    /// overrides the one the app registered.
    var value = ""
    /// `callback` only: JSON payload text, empty for none.
    var payload = ""
    var style: Style = .default

    init() {}

    init(_ b: HeraldButton) {
        label = b.label
        style = Style(rawValue: b.style ?? "") ?? .default
        if let c = b.command { action = .command; value = c }
        else if let cb = b.callback {
            action = .callback; value = cb.url ?? ""
            if let p = cb.payload, let d = try? HeraldJSON.encoder().encode(p) { payload = String(decoding: d, as: UTF8.self) }
        } else { action = .url; value = b.url ?? "" }
    }

    /// Parsed callback payload; nil for empty text and for text that is not JSON (see `hasInvalidPayload`).
    private var parsedPayload: JSONValue? {
        let t = payload.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return nil }
        return try? JSONDecoder().decode(JSONValue.self, from: Data(t.utf8))
    }

    var hasInvalidPayload: Bool {
        action == .callback && !payload.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && parsedPayload == nil
    }

    func build() -> HeraldButton? {
        let l = label.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !l.isEmpty else { return nil }
        let v = value.trimmingCharacters(in: .whitespacesAndNewlines)
        let st = style == .default ? nil : style.rawValue
        switch action {
        case .url: return HeraldButton(label: l, style: st, url: v.isEmpty ? nil : v)
        case .command: return HeraldButton(label: l, style: st, command: v.isEmpty ? nil : v)
        case .callback:
            return HeraldButton(label: l, style: st, callback: HeraldCallback(url: v.isEmpty ? nil : v, payload: parsedPayload))
        }
    }
}

struct MetadataRow: Identifiable, Equatable {
    var id = UUID()
    var key = ""
    var value = ""
}

// MARK: - Model

/// The state behind the composer window, and the one place that decides what the form means as a
/// notification.
///
/// The form edits a *payload*; a saved template is only ever the baseline underneath it. Picking a
/// template copies its values into the form so the user sees concrete content, and `payload` then
/// sends only what differs from that template. That mirrors the wire contract exactly (payload fields
/// override the template, `TemplateResolver` fills the rest) so that
///   - Send, the preview and the "Copy as..." code all describe the same notification, and
///   - an untouched template field stays a template field: its `{placeholders}` are still filled by
///     the resolver from `metadata`, and later edits to the template reach notifications that use it.
/// Text the user typed themselves is a literal on the wire (the resolver never rescans payload text),
/// so `{tokens}` typed into the form are expanded here, from the metadata rows, before they are sent.
@MainActor
final class ComposerModel: ObservableObject {
    static let customSoundTag = "__custom__"

    // Identity
    @Published var app = ""
    @Published var notificationID = ""
    /// The saved template the form is based on, if any. Change it through `applyTemplate`.
    @Published private(set) var template: HeraldTemplate?

    // Content
    @Published var title = ""
    @Published var subtitle = ""
    @Published var body = ""
    /// File path, `data:` URI or https URL.
    @Published var imageSpec = ""
    @Published var clickURL = ""
    @Published var buttons: [ComposerButton] = []

    // Behaviour
    /// "" = the app's default, "none", a system sound name, or `customSoundTag` (then `customSoundPath`).
    @Published var soundSelection = ""
    @Published var customSoundPath = ""
    /// nil = default (app setting or template).
    @Published var persistent: Bool?
    /// Seconds; empty = default.
    @Published var timeoutText = ""
    @Published var snooze = false
    @Published var reminderOn = false
    @Published var reminderTitle = ""
    @Published var reminderHasDue = false
    @Published var reminderDue = ComposerModel.defaultDue()
    /// "" = default, else low | normal | high.
    @Published var priority = ""

    // Look
    @Published var layout: HeraldLayout = .imageLeft
    @Published var accentColor: String?
    @Published var showSubtitle = true
    @Published var showBody = true
    @Published var showTimestamp = true
    @Published var maxBodyLines = HeraldTemplate.defaultMaxBodyLines

    // Data
    @Published var metadata: [MetadataRow] = []

    init(app: String = "") { self.app = app }

    // MARK: Templates

    /// Makes `t` the baseline and copies its values into the form. nil only detaches the template: the
    /// current values stay, and from then on they are plain payload fields. The app, the id and the
    /// metadata rows are the sender's and are never touched by a template.
    func applyTemplate(_ t: HeraldTemplate?) {
        template = t
        guard let t else { return }
        title = t.title ?? ""; subtitle = t.subtitle ?? ""; body = t.body ?? ""
        imageSpec = t.image ?? ""; clickURL = t.url ?? ""
        buttons = t.buttons.map(ComposerButton.init)
        (soundSelection, customSoundPath) = Self.soundFields(t.sound)
        persistent = t.persistent
        timeoutText = t.timeout.map { Self.timeoutString($0) } ?? ""
        snooze = t.snooze ?? false
        priority = t.priority ?? ""
        if let r = t.reminder {
            reminderOn = true; reminderTitle = r.title ?? ""
            if let due = r.due.flatMap({ ISODate.parse($0) }) { reminderHasDue = true; reminderDue = due }
            else { reminderHasDue = false }
        } else {
            reminderOn = false; reminderTitle = ""; reminderHasDue = false
        }
        layout = t.layout; accentColor = t.accentColor
        showSubtitle = t.showSubtitle; showBody = t.showBody; showTimestamp = t.showTimestamp
        maxBodyLines = t.maxBodyLines
    }

    /// Back to an empty form for the same app.
    func clear() {
        template = nil
        notificationID = ""
        title = ""; subtitle = ""; body = ""; imageSpec = ""; clickURL = ""
        buttons = []
        soundSelection = ""; customSoundPath = ""
        persistent = nil; timeoutText = ""; snooze = false
        reminderOn = false; reminderTitle = ""; reminderHasDue = false; reminderDue = Self.defaultDue()
        priority = ""
        layout = .imageLeft; accentColor = nil
        showSubtitle = true; showBody = true; showTimestamp = true
        maxBodyLines = HeraldTemplate.defaultMaxBodyLines
        metadata = []
    }

    /// The whole form as a template, with `{placeholders}` left exactly as typed. This is what
    /// "Save as template..." stores.
    func draftTemplate(named name: String) -> HeraldTemplate {
        var t = HeraldTemplate(name: name, app: app.trimmed, layout: layout)
        t.accentColor = accentColor?.nonBlank
        t.showSubtitle = showSubtitle; t.showBody = showBody; t.showTimestamp = showTimestamp
        t.maxBodyLines = maxBodyLines
        t.title = title.nonBlank; t.subtitle = subtitle.nonBlank; t.body = body.nonBlank
        t.image = imageSpec.trimmed.nonBlank; t.url = clickURL.trimmed.nonBlank
        t.buttons = buttons.compactMap { $0.build() }
        t.sound = soundValue
        t.persistent = persistent
        t.timeout = timeoutValue
        t.snooze = snooze ? true : nil
        t.priority = priority.nonBlank
        t.reminder = reminderValue
        return t
    }

    // MARK: Derived values

    var soundValue: String? {
        switch soundSelection {
        case "": return nil
        case Self.customSoundTag: return customSoundPath.trimmed.nonBlank
        default: return soundSelection
        }
    }

    /// nil for an empty field and for text that is not a non-negative number (see `issues`).
    var timeoutValue: Double? {
        guard let d = Double(timeoutText.trimmed), d >= 0, d.isFinite else { return nil }
        return d
    }

    var reminderValue: HeraldReminder? {
        guard reminderOn else { return nil }
        return HeraldReminder(title: reminderTitle.nonBlank, due: reminderHasDue ? Self.localISO(reminderDue) : nil)
    }

    var metadataValue: JSONValue? {
        var o: [String: JSONValue] = [:]
        for r in metadata where !r.key.trimmed.isEmpty { o[r.key.trimmed] = .string(r.value) }
        return o.isEmpty ? nil : .object(o)
    }

    // MARK: The payload

    /// What goes over the wire (and into "Copy as..."): the form minus whatever equals the template.
    var payload: HeraldNotification {
        let base = template ?? HeraldTemplate(name: "", app: "")
        let hasTemplate = template != nil
        let appID = app.trimmed

        // Expand `{tokens}` in the text the user typed, using the metadata rows. A throwaway template
        // holding the form text does it with the real resolver, so the rules match the server's.
        var probe = HeraldNotification(app: appID, title: "")
        probe.metadata = metadataValue
        var typed = HeraldTemplate(name: "", app: appID)
        typed.title = title; typed.subtitle = subtitle; typed.body = body; typed.url = clickURL.trimmed
        let filled = TemplateResolver.resolve(probe, with: typed)

        /// nil = absent (or inherited from the template); "" = the user cleared a template's text.
        func text(_ form: String, template raw: String?, expanded: String?) -> String? {
            if form.trimmed.isEmpty { return (hasTemplate && !(raw ?? "").isEmpty) ? "" : nil }
            if hasTemplate && form == (raw ?? "") { return nil }
            return expanded ?? form
        }

        var n = HeraldNotification(app: appID, id: notificationID.trimmed.nonBlank,
                                   title: text(title, template: base.title, expanded: filled.title) ?? "")
        n.template = template?.name
        n.subtitle = text(subtitle, template: base.subtitle, expanded: filled.subtitle)
        n.body = text(body, template: base.body, expanded: filled.body)
        n.url = text(clickURL, template: base.url, expanded: filled.url)
        n.image = text(imageSpec, template: base.image, expanded: imageSpec.trimmed)

        let formButtons = buttons.compactMap { $0.build() }
        if hasTemplate { n.buttons = formButtons == base.buttons ? nil : formButtons }
        else { n.buttons = formButtons.isEmpty ? nil : formButtons }

        // Behaviour. A control left at "default" cannot cancel a value the template pins (the wire has
        // no "unset" for these), so it simply inherits; the preview always shows the resolved truth.
        if soundValue != base.sound { n.sound = soundValue ?? "default" }
        if persistent != base.persistent { n.persistent = persistent }
        if timeoutValue != base.timeout { n.timeout = timeoutValue }
        if snooze != (base.snooze ?? false) { n.snooze = snooze }
        if let p = priority.nonBlank, p != base.priority { n.priority = p }
        if reminderValue != base.reminder { n.reminder = reminderValue }

        // Look
        if layout != base.layout { n.layout = layout }
        if let a = accentColor?.nonBlank, a != base.accentColor { n.accentColor = a }
        if showSubtitle != base.showSubtitle { n.showSubtitle = showSubtitle }
        if showBody != base.showBody { n.showBody = showBody }
        if showTimestamp != base.showTimestamp { n.showTimestamp = showTimestamp }
        if maxBodyLines != base.maxBodyLines { n.maxBodyLines = maxBodyLines }

        n.metadata = metadataValue
        return n
    }

    /// The notification as the server will see it after template resolution: what the preview draws
    /// and what a live banner will show.
    var resolved: HeraldNotification { TemplateResolver.resolve(payload, with: template) }

    /// Reasons Send is disabled, most important first.
    var issues: [String] {
        var out: [String] = []
        if app.trimmed.isEmpty { out.append("Choose or type an app id.") }
        if resolved.title.trimmed.isEmpty { out.append("Title is required.") }
        if !timeoutText.trimmed.isEmpty && timeoutValue == nil { out.append("Auto-dismiss must be a number of seconds.") }
        for b in buttons where b.hasInvalidPayload { out.append("Button \u{201C}\(b.label)\u{201D}: payload is not valid JSON.") }
        return out
    }

    // MARK: Helpers

    /// "" for the app's default, `none`, a system sound name, or the custom-file tag for a path.
    static func soundFields(_ sound: String?) -> (selection: String, custom: String) {
        guard let s = sound?.trimmed, !s.isEmpty else { return ("", "") }
        if s.hasPrefix("/") || s.hasPrefix("~") { return (customSoundTag, s) }
        return (s, "")
    }

    static func timeoutString(_ d: Double) -> String {
        d == d.rounded() && abs(d) < 1e9 ? String(Int(d)) : String(d)
    }

    /// Tomorrow 09:00 local, the same default the Reminders button would suggest.
    static func defaultDue(now: Date = Date(), calendar: Calendar = .current) -> Date {
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: now) ?? now
        return calendar.date(bySettingHour: 9, minute: 0, second: 0, of: tomorrow) ?? tomorrow
    }

    /// ISO 8601 with the local UTC offset ("2026-10-02T09:00:00-04:00"), which reads better in the
    /// generated code than the UTC form `ISODate.string(from:)` produces.
    static func localISO(_ date: Date, timeZone: TimeZone = .current) -> String {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        f.timeZone = timeZone
        return f.string(from: date)
    }
}

fileprivate extension String {
    /// Whitespace and newlines removed from both ends.
    var trimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }
    /// self, or nil when it holds nothing but whitespace. The text itself is not altered.
    var nonBlank: String? { trimmed.isEmpty ? nil : self }
}
