import Foundation
import HeraldClient

/// One tool as `tools/list` describes it.
struct MCPToolDefinition {
    var name: String
    var title: String
    var description: String
    var inputSchema: JSONValue
    /// MCP annotations (hints for the client's permission prompts).
    var readOnly = false
    var destructive = false
    var idempotent = false

    var jsonValue: JSONValue {
        var annotations: [String: JSONValue] = [
            "title": .string(title), "readOnlyHint": .bool(readOnly), "openWorldHint": .bool(false),
        ]
        if !readOnly {
            annotations["destructiveHint"] = .bool(destructive)
            annotations["idempotentHint"] = .bool(idempotent)
        }
        return .object(["name": .string(name), "title": .string(title), "description": .string(description),
                        "inputSchema": inputSchema, "annotations": .object(annotations)])
    }
}

enum MCPToolCatalog {
    /// The sections of the component schema document `component_schema` can narrow to.
    static let schemaSections = ["definitions", "components", "bindings", "actions", "examples", "workflow"]

    static let templateObject = "A template object: {name, app, layoutVersion: 2, grid, cells, collapseEmpty?, actionRules?, extra?, accentColor?, sound?, ...}. Call component_schema for the format."

    /// Every tool, in the order DESIGN 7.6 lists them.
    static let all: [MCPToolDefinition] = [
        MCPToolDefinition(
            name: "herald_status", title: "Herald status",
            description: """
            Check that Herald is running and which version. Returns running, version, pid, the port and support directory \
            this server talks to, counts of apps, manifests, templates and installed Shortcuts, and the scripts folder with the \
            script files in it. Call it first: every tool except component_schema and validate_template needs Herald running.
            """,
            inputSchema: Schema.input(), readOnly: true, idempotent: true),

        MCPToolDefinition(
            name: "list_manifests", title: "List manifests",
            description: """
            List the manifests the issuing apps registered with Herald. A manifest declares the fields an app sends (a field key \
            is a {token} a template can bind) and the actions (buttons) it offers. Returns a summary per app: fields as \
            "key:type", action ids, assets, defaultTemplate. Use get_manifest for sample values.
            """,
            inputSchema: Schema.input(), readOnly: true, idempotent: true),

        MCPToolDefinition(
            name: "get_manifest", title: "Get manifest",
            description: """
            The full manifest of one app: fields (key, type, required, sample value), issuer actions with their ids, assets \
            (Rive files) and defaultTemplate. Field keys are the {tokens} a template can bind; the samples are what \
            render_preview and send_test show. Strings over 1200 characters (an embedded icon, a long sample) are \
            abbreviated to a marker such as "<data:image/png;base64,... 5022 characters omitted>"; pass full: true for the real \
            values. Also readable as the resource herald://manifests/<app> (always abbreviated).
            """,
            inputSchema: Schema.input(["app": Schema.string("The app id, e.g. \"webwatcher.email\" (see list_manifests)."),
                                       "full": Schema.boolean("Return long strings in full instead of abbreviating them.")],
                                      required: ["app"]),
            readOnly: true, idempotent: true),

        MCPToolDefinition(
            name: "put_manifest", title: "Save manifest",
            description: """
            Create or REPLACE an app's manifest (the whole document: get_manifest first, edit, send it back). An abbreviated \
            marker that get_manifest wrote for a long string is swapped back for the stored value; one that matches nothing \
            stored is refused (use get_manifest with full: true). Issuing apps \
            normally register their own; use this to describe an app that does not, to add sample values for the designer, or \
            to set defaultTemplate. Issuer actions are url, callback, command or dismiss; shortcut and script actions are \
            authored in templates (add_action_rule). Invalid manifests are rejected with the field path.
            """,
            inputSchema: Schema.input(["manifest": Schema.object(
                "{app, appName?, icon?, version?, fields: [{key, type: text|number|date|url|image|bool|list, required?, sample?}], actions: [{id?, label, kind: url|callback|command|dismiss, style?, url?, command?, callback?}], assets?, defaultTemplate?, family?: the product family byApp stacking groups issuers by, e.g. \"webwatcher\"}")],
                                      required: ["manifest"]),
            destructive: true, idempotent: true),

        MCPToolDefinition(
            name: "list_templates", title: "List templates",
            description: """
            List the saved templates (all apps, or one). A summary each: app, name, layoutVersion, cell count, the {tokens} it \
            reads, actionRules count, whether it is the app's default. The four built-in templates builtin.imageLeft, \
            builtin.imageRight, builtin.hero and builtin.compact always exist (get_template returns them as starting points).
            """,
            inputSchema: Schema.input(["app": Schema.string("Only this app's templates. Omit for all apps.")]),
            readOnly: true, idempotent: true),

        MCPToolDefinition(
            name: "get_template", title: "Get template",
            description: """
            The full JSON of one template, or of a built-in (name "builtin.hero" etc., generated for the app). Edit it and \
            save it back with put_template. Also readable as the resource herald://templates/<app>/<name>.
            """,
            inputSchema: Schema.input(["app": Schema.string("The app id."),
                                       "name": Schema.string("The template name, or builtin.imageLeft / builtin.imageRight / builtin.hero / builtin.compact.")],
                                      required: ["app", "name"]),
            readOnly: true, idempotent: true),

        MCPToolDefinition(
            name: "put_template", title: "Save template",
            description: """
            Create or replace a template. It is validated against the grid schema first: errors carry the JSON path and the \
            id of the offending cell, and nothing is saved until there are none (overlapping cells, a cell outside the grid, \
            an unknown component type or a property of the wrong type, a bad colour...). Warnings (a {token} the manifest does \
            not declare, an unknown key that is probably a typo) are returned but do not block. Names starting with \
            "builtin." are reserved. Set setAsDefault to make it the app's default template. Then check it with \
            render_preview.
            """,
            inputSchema: Schema.input([
                "template": Schema.object(templateObject),
                "app": Schema.string("The app id; only needed when the template object has no \"app\"."),
                "setAsDefault": Schema.boolean("Also set the app manifest's defaultTemplate to this template (the app needs a manifest)."),
            ], required: ["template"]),
            destructive: true, idempotent: true),

        MCPToolDefinition(
            name: "delete_template", title: "Delete template",
            description: "Delete a saved template. Built-in templates cannot be deleted. Notifications that name a deleted template fall back to the default look.",
            inputSchema: Schema.input(["app": Schema.string("The app id."), "name": Schema.string("The template name.")],
                                      required: ["app", "name"]),
            destructive: true, idempotent: true),

        MCPToolDefinition(
            name: "validate_template", title: "Validate template",
            description: """
            Check a template without saving it: give a draft as `template`, or a saved one as `app` + `name`. Returns valid, \
            errors and warnings (each with a path and the cell id) and, with the app's manifest sample data, which cells \
            would be empty and which rows and columns would collapse, plus the resulting action list. Works without Herald \
            running (the manifest check is then skipped).
            """,
            inputSchema: Schema.input([
                "template": Schema.object("A draft template object. Omit when using app + name."),
                "app": Schema.string("The app id (checks tokens against its manifest; required with name)."),
                "name": Schema.string("A saved template (or builtin.*) to validate instead of a draft."),
            ]),
            readOnly: true, idempotent: true),

        MCPToolDefinition(
            name: "component_schema", title: "Component schema",
            description: """
            The format of a template, for authoring: the grid, every component type (text, image, issuerIcon, timestamp, \
            button, actions, iconButton, badge, progress, rive, spacer) with each property, allowed values and default, how \
            {token} bindings and empty-collapsing work, the action kinds and rules, and complete examples. Read it before \
            writing a template. Narrow it with `component` or `section` to save tokens.
            """,
            inputSchema: Schema.input([
                "component": Schema.string("Only this component type's schema (plus the shared definitions).", values: HeraldComponent.typeNames),
                "section": Schema.string("Only this top-level section of the document.", values: schemaSections),
            ]),
            readOnly: true, idempotent: true),

        MCPToolDefinition(
            name: "render_preview", title: "Render preview",
            description: """
            Render a template offscreen with Herald's real banner renderer and get the picture back (an image block) plus \
            the path of the saved PNG. Preview a saved template with `name` (or builtin.*), an unsaved draft with \
            `template` (validated first; errors name the cell), or, with neither, the app's default template. Data is the manifest's sample values by default, or the app's \
            last real notification with source "last"; `data` overrides individual fields. Sample data stands in for an \
            issuer that names every action its manifest declares, so the buttons are those; a real notification shows only \
            the actions it sends. Render light and dark to check both. Requires Herald running.
            """,
            inputSchema: Schema.input([
                "name": Schema.string("A saved template's name, or builtin.imageLeft|imageRight|hero|compact. Needs app."),
                "template": Schema.object("An unsaved draft template object instead of name."),
                "app": Schema.string("The app id (defaults to the draft's app)."),
                "source": Schema.string("Where field values come from: sample (the manifest's samples, default) or last (the app's most recent notification in history).",
                                        values: ["sample", "last"]),
                "data": Schema.object("Field values that replace the source's, e.g. {\"count\": 12, \"subject\": \"A very long subject line\"}. Use it to test long text and empty fields (omit a key to see the collapse)."),
                "appearance": Schema.string("light (default) or dark.", values: ["light", "dark"]),
                "scale": Schema.number("Pixel scale, 1 to 3 (default 2).", min: 1, max: 3),
            ]),
            readOnly: true, idempotent: true),

        MCPToolDefinition(
            name: "send_notification", title: "Send notification",
            description: """
            Deliver a real notification: a banner appears on the user's screen and it is recorded in history. Same payload as \
            POST /v1/notify: app and title, optional subtitle, body (Markdown links), image, url, sound, id (the same id \
            replaces the visible banner), template, buttons [{label, url|command|callback}], snooze, reminder, metadata. \
            Manifest fields go in `fields` (or at the top level) and are what the template binds. `actionIds` names actions \
            the manifest declares (or send `buttons`/`actions` in full); the manifest's actions are not shown unless the \
            payload names them. Buttons with a shell `command` are refused unless allowCommandButtons is true: you can send \
            as any app id, so a command button would run under that app's command permission. Prefer send_test while \
            iterating on a template.
            """,
            inputSchema: Schema.input([
                "app": Schema.string("The sending app id."),
                "title": Schema.string("Title. May be omitted when `template` supplies it."),
                "subtitle": Schema.string("Subtitle."),
                "body": Schema.string("Body text; [text](https://...) links work."),
                "id": Schema.string("Notification id; sending the same id again replaces the banner in place."),
                "template": Schema.string("Name of a saved template of this app."),
                "fields": Schema.object("Manifest field values, e.g. {\"count\": 2, \"sender\": \"Acme Billing\"}; sent as top-level keys."),
                "buttons": .object(["type": .string("array"), "description": .string("Issuer buttons: [{label, style?, url?|command?|callback?}]. `actions` is accepted as an alias."),
                                    "items": .object(["type": .string("object")])]),
                "actionIds": .object(["type": .string("array"), "description": .string("Ids of actions the app's manifest declares, instead of repeating the buttons."),
                                      "items": .object(["type": .string("string")])]),
                "allowCommandButtons": Schema.boolean("Allow buttons that carry a shell `command` (refused by default)."),
                "metadata": Schema.object("Free-form metadata; readable as {key} in templates too."),
                "speak": .object(["description": .string("Say it aloud on the user's Mac (local voice): true speaks the title then the body, or {text?, voice?, speed?, lang?}.")]),
                "audio": Schema.string("Play a voice message: a WAV/MP3/M4A path, https URL or data: URI (at most 20 MB)."),
                "presentation": Schema.string("banner (default), voice (spoken only, no banner; history keeps the text) or both.",
                                              values: ["banner", "voice", "both"]),
            ], required: ["app"], extra: true),
            idempotent: false),

        MCPToolDefinition(
            name: "send_test", title: "Send test banner",
            description: """
            Show a template for real: sends a test notification for the app with the manifest's sample values (and, as \
            `actionIds`, the manifest's actions as the issuer's buttons) so the banner, sound and buttons can be seen on \
            screen. Manifest actions that run a shell command are left out unless allowCommandButtons is true. The template \
            must be saved (put_template). The id is "mcp-test-<template>", so repeating it replaces the banner instead of \
            stacking. Pressing an issuer callback button calls the issuing app, so tell the user before they click.
            """,
            inputSchema: Schema.input([
                "app": Schema.string("The app id."),
                "template": Schema.string("The saved template to show. Defaults to the manifest's defaultTemplate."),
                "data": Schema.object("Field values that replace the manifest samples."),
                "id": Schema.string("Notification id (default mcp-test-<template>)."),
                "includeIssuerActions": Schema.boolean("Send the manifest's actions as the issuer's buttons (default true), so actionRules have something to act on."),
                "allowCommandButtons": Schema.boolean("Also send manifest actions that run a shell command (left out by default)."),
            ], required: ["app"]),
            idempotent: true),

        MCPToolDefinition(
            name: "list_shortcuts", title: "List Shortcuts",
            description: """
            The names of the Apple Shortcuts installed on this Mac. Use one in an action of kind "shortcut" (see \
            add_action_rule): Herald runs it with the notification as input, from a button on the banner.
            """,
            inputSchema: Schema.input(), readOnly: true, idempotent: true),

        MCPToolDefinition(
            name: "add_action_rule", title: "Add action rule",
            description: """
            Add one rule to a saved template's actionRules: the two-way button system. A rule either changes an issuer action \
            {match: "<id|label|*>", hide?, relabel?, style?, symbol?, position?} or adds one of your own {add: {id, label, kind, ...}} \
            with kind url, command (shell), script (a file in Application Support/Herald/scripts, which herald_status lists: write \
            the file there first; it gets the notification JSON on stdin), shortcut (an Apple Shortcut from list_shortcuts; \
            input is text with {tokens}, or omitted for the full JSON), dismiss or snooze. A command, script or shortcut you add \
            is confirmed by the user in Herald the first time its button is pressed (with the script's hash, or the \
            shortcut's name and input), and again whenever it changes. An add with the id of one of the issuer's own \
            actions replaces that button, and the prompt says so. Example: \
            {"add": {"id": "followup", "label": "Follow up", "kind": "shortcut", "shortcut": "Create follow-up", \
            "input": "{title}\\n{url}"}}. Adding an action id that an earlier add-rule already has replaces that rule. \
            Any action (an add, or a match rule's `symbol`) can carry an SF Symbol: a name ("checkmark.circle") or the full \
            styling {name, weight, scale, placement, renderingMode, colors, variableValue, effect} (see component_schema \
            definitions.symbol); an unknown name is a warning, not an error. Example: \
            {"match": "markRead", "symbol": {"name": "checkmark.circle.fill", "renderingMode": "palette", "colors": ["white", "#34C759"]}}. \
            Validated before saving; returns the resulting button list.
            """,
            inputSchema: Schema.input([
                "app": Schema.string("The app id."),
                "template": Schema.string("The saved template's name (built-ins are read-only: copy one with put_template first)."),
                "rule": Schema.object("The rule: {match?, hide?, relabel?, style?: default|destructive|cancel, symbol?: <SF Symbol name or object>, position?, add?: {id, label, kind, url?|command?|script?|shortcut?, input?, snoozeMinutes?, style?, symbol?}}."),
            ], required: ["app", "template", "rule"]),
            destructive: true, idempotent: false),

        MCPToolDefinition(
            name: "list_history", title: "List history",
            description: """
            Recent notifications Herald delivered, newest first: id, app, title, times, the button used, template, and the \
            resolved field values. Use it to see what an app really sends (render_preview with source "last" uses it too).
            """,
            inputSchema: Schema.input([
                "app": Schema.string("Only this app. Omit for all apps."),
                "limit": Schema.integer("How many (default 10, at most 100).", min: 1, max: 100),
                "full": Schema.boolean("Return the complete records instead of the summary."),
            ]),
            readOnly: true, idempotent: true),

        MCPToolDefinition(
            name: "dismiss", title: "Dismiss banner",
            description: "Dismiss one banner by app and id, every banner of an app sent with one group (a stack: see list_stacks), or every banner of an app with all: true. It only closes the banner; the history keeps the notification.",
            inputSchema: Schema.input([
                "app": Schema.string("The app id."),
                "id": Schema.string("The notification id (see list_history)."),
                "group": Schema.string("Dismiss every banner of the app that was sent with this group (use instead of id)."),
                "all": Schema.boolean("Dismiss every banner of the app (use instead of id)."),
            ], required: ["app"]),
            destructive: true, idempotent: true),

        MCPToolDefinition(
            name: "list_stacks", title: "List stacks",
            description: """
            The stacks of banners on the user's screen: notifications Herald folded into one banner with a counter because \
            they share a stacking key. The user's stacking level decides the key: byApp (an issuer family such as every \
            WebWatcher), byIssuer (one app) or bySender (the payload's `group`, an email sender or a watched site; the app id \
            when a notification sent none). Each stack lists its level, app, group, count, whether it is open and its \
            notifications newest first. dismiss with {app, group} clears one.
            """,
            inputSchema: Schema.input([
                "app": Schema.string("Only stacks that hold a notification of this app. Omit for all."),
            ]),
            readOnly: true, idempotent: true),

        MCPToolDefinition(
            name: "speak", title: "Speak aloud",
            description: """
            Say `text` aloud on the user's Mac with Herald's local voice (Kokoro, or the system voice) without a banner. \
            It leaves a history entry holding the text, so the log stays searchable. Use it to report that a long task \
            finished or needs attention; keep it to a sentence or two (at most 2,000 characters). Nothing leaves the Mac.
            """,
            inputSchema: Schema.input([
                "app": Schema.string("The sending app id."),
                "text": Schema.string("What to say."),
                "voice": Schema.string("Voice name, e.g. af_heart (default), af_bella, am_michael, bf_emma."),
                "speed": Schema.number("Speech speed, 0.5 to 2.0 (default 1.0).", min: 0.5, max: 2.0),
                "lang": Schema.string("Language code, e.g. en-us or en-gb."),
                "id": Schema.string("Notification id for the history entry."),
            ], required: ["app", "text"]),
            idempotent: false),

        MCPToolDefinition(
            name: "get_quiet_hours", title: "Get quiet hours",
            description: """
            Read Herald's quiet hours: the scheduled windows (days, start/end, and whether each silences speech, sounds or \
            banners), any ad-hoc silence, and `status` (what is silenced right now and until when). While speech is \
            silenced, `speak` and `send_notification` with speak/audio are held back and logged in history as \
            speech.suppressed "quiet-hours".
            """,
            inputSchema: Schema.input([:], required: []),
            readOnly: true, idempotent: true),

        MCPToolDefinition(
            name: "set_quiet_hours", title: "Set quiet hours",
            description: """
            Change quiet hours. `windows` replaces the whole schedule: [{days?: ["mon",...] (empty = every day), start: "22:30", \
            end: "07:30" (an end not after start means the next morning), speech? (default true), sounds?, banners?, \
            speakSummary?}]. `until` ("07:30") or `minutes` (60) starts an ad-hoc silence of speech and sounds; `resume: true` \
            ends the current silence. A notification with priority "urgent" breaks quiet hours only for apps whose \
            "Urgent can break quiet hours" setting the user turned on. Tell the user before silencing them.
            """,
            inputSchema: Schema.input([
                "windows": .object(["type": .string("array"), "description": .string("The complete schedule: [{days?, start, end, speech?, sounds?, banners?, speakSummary?}]."),
                                    "items": .object(["type": .string("object")])]),
                "until": Schema.string("Silence until this clock time, HH:MM (next occurrence)."),
                "minutes": Schema.number("Silence for this many minutes.", min: 1, max: 10080),
                "banners": Schema.boolean("With until/minutes: silence banners too (default false)."),
                "resume": Schema.boolean("End the current silence now."),
            ], required: []),
            destructive: false, idempotent: false),
    ]

    static let byName: [String: MCPToolDefinition] = Dictionary(uniqueKeysWithValues: all.map { ($0.name, $0) })
}
