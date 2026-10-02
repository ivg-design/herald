import Foundation

/// Everything `/v1/preview` draws, worked out from the request before any view exists: the template (a
/// `builtin.*` one, a stored one or an inline one, in grid form), the notification as the server would see it
/// after template resolution, the fields a grid template binds to, and the resolved action list. Pure, so the
/// rules (which template, which data, what a sample is) are unit tested without a window server.
public struct PreviewPlan: Sendable {
    /// The template as asked for; its content defaults (a v1 `title: "{sender} wrote"`) fill the notification.
    public var template: HeraldTemplate
    /// The same template in grid form (a v1 look becomes its built-in grid), which is what gets drawn.
    public var grid: HeraldTemplate
    /// The notification after `TemplateResolver.resolve`, as the banner would receive it.
    public var notification: HeraldNotification
    public var fields: [String: HeraldFieldValue]
    public var actions: [HeraldResolvedAction]
    public var manifest: HeraldManifest?
    public var deliveredAt: Date
    /// True when the data came from the manifest's samples (or generic ones) rather than from the request.
    public var usedSamples: Bool

    /// The hint of the first reply action in the resolved list, for a preview that draws the reply field.
    public var replyPlaceholder: String? { actions.first { $0.action.kind == .reply }?.action.reply?.placeholder }

    public static let defaultTemplateName = BuiltinTemplates.name(for: .imageLeft)

    /// `placeholderImage` is an image spec (a `data:` URI) the preview uses for an image the sample data leaves
    /// out, so an image cell shows up in a sample preview instead of collapsing; real data never gets one.
    public static func make(_ r: PreviewSpec, manifest: HeraldManifest?,
                            stored: (_ name: String) -> HeraldTemplate?, now: Date = Date(),
                            placeholderImage: String? = nil) throws -> PreviewPlan {
        let template = try resolveTemplate(r, manifest: manifest, stored: stored)
        let grid = BuiltinTemplates.gridTemplate(for: template)

        // The data: the request's own notification, else the manifest's samples as a notification.
        var fields: [String: HeraldFieldValue]
        var note: HeraldNotification
        if let data = r.data {
            note = data
            note.app = r.app
            fields = [:]
        } else {
            let samples = TemplateResolver.sampleFields(manifest: manifest)
            note = sampleNotification(app: r.app, samples: samples, manifest: manifest)
            fields = samples
        }
        // As in a live delivery: `actionIds` become the manifest's buttons before the template's defaults apply.
        note = ActionResolver.materializingActionIDs(note, manifest: manifest)
        note = TemplateResolver.resolve(note, with: template)
        note.template = nil

        // Same derivation as a real delivery (AppController.notify), so a preview binds what a banner binds.
        let derived = TemplateResolver.fields(for: note, manifest: manifest, extra: template.extra, deliveredAt: now)
        fields.merge(derived) { _, real in real }
        // A blank value is absent: a sample the data does not override must not survive an explicit blank.
        if r.data != nil { fields = derived }

        if r.data == nil, let placeholder = placeholderImage {
            let wanted = Set(grid.referencedTokens)
            let imageKeys = ["image"] + (manifest?.fields.filter { $0.type == .image }.map(\.key) ?? [])
            for key in imageKeys where wanted.contains(key) && fields[key] == nil {
                fields[key] = .text(placeholder)
                if key == "image" { note.image = placeholder }
            }
        }

        // The same function a live banner uses. A sample names every declared action (`actionIds`), a real payload
        // only what it sends, so a preview with `data` shows no manifest action the issuer did not name.
        let source = ActionResolver.issuerSource(for: note, manifest: manifest)
        let actions = ActionResolver.resolveDetailed(issuer: source.buttons, ids: source.ids, rules: template.actionRules)
        return PreviewPlan(template: template, grid: grid, notification: note,
                           fields: fields, actions: actions, manifest: manifest, deliveredAt: now,
                           usedSamples: r.data == nil)
    }

    /// An inline template as sent (checked against the manifest too: a Rive asset the manifest lacks is an
    /// error the caller can fix); a name looks at the four `builtin.*` templates, then the app's stored ones;
    /// no template means the manifest's `defaultTemplate` when that exists, else `builtin.imageLeft`.
    static func resolveTemplate(_ r: PreviewSpec, manifest: HeraldManifest?,
                                stored: (String) -> HeraldTemplate?) throws -> HeraldTemplate {
        switch r.template {
        case .inline(var t)?:
            if t.app.isEmpty { t.app = r.app }
            let errors = t.validate(manifest: manifest).filter(\.isError)
            guard errors.isEmpty else {
                throw BackendError(400, "invalid template: " + errors.map { issue in
                    (issue.cellId.map { "cell \($0): " } ?? "") + issue.path + ": " + issue.message
                }.joined(separator: "; "))
            }
            return t
        case .named(let name)?:
            if let t = lookup(name, app: r.app, stored: stored) { return t }
            throw BackendError(404, "template not found: \(name)")
        case nil:
            if let name = manifest?.defaultTemplate, !name.isEmpty, let t = lookup(name, app: r.app, stored: stored) { return t }
            return BuiltinTemplates.template(layout: .imageLeft, app: r.app)
        }
    }

    private static func lookup(_ name: String, app: String, stored: (String) -> HeraldTemplate?) -> HeraldTemplate? {
        BuiltinTemplates.named(name, app: app) ?? stored(name)
    }

    /// The sample fields as a notification: the standard keys at the top, everything else in `metadata`. It
    /// names every action the manifest declares (`actionIds`), the way an issuer that wants them all would
    /// (a manifest-less preview gets one "Open" button so the action row is visible).
    static func sampleNotification(app: String, samples: [String: HeraldFieldValue],
                                   manifest: HeraldManifest?) -> HeraldNotification {
        func text(_ key: String) -> String? {
            if case .text(let s)? = samples[key], !s.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return s }
            return nil
        }
        let top: Set<String> = ["title", "subtitle", "body", "image", "url"]
        var metadata: [String: JSONValue] = [:]
        for (k, v) in samples where !top.contains(k) { metadata[k] = ActionResolver.json(v) }
        var n = HeraldNotification(app: app, title: text("title") ?? "",
                                   subtitle: text("subtitle"), body: text("body"),
                                   image: text("image"), url: text("url"),
                                   metadata: metadata.isEmpty ? nil : .object(metadata))
        if let m = manifest {
            if !m.actions.isEmpty { n.actionIds = ActionResolver.sampleSource(manifest: m).ids }
        } else {
            n.buttons = [HeraldButton(label: "Open", url: "https://example.com")]
        }
        return n
    }
}
