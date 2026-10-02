import Foundation
import HeraldClient

// The tools that close the gap between what the Designer, Quick send, History and Settings can do and what the
// MCP server offered (docs/reference/parity.md). Each one is a thin wrapper over a Herald HTTP route: it names the
// route, picks arguments for the query or body, and returns Herald's JSON. No decision is made here.

/// How a tool maps onto a route.
struct RouteCall {
    var method: String
    var path: String
    var query: [String: String] = [:]
    var body: JSONValue?
    /// Seconds to wait for Herald's answer; nil keeps the default. `wait_for_reply` long-polls.
    var timeout: TimeInterval?
}

struct ParityTool {
    var definition: MCPToolDefinition
    var route: @Sendable (MCPArgs) throws -> RouteCall
}

enum ParityTools {
    static func text(_ args: MCPArgs, _ key: String) throws -> String? {
        try args.string(key).flatMap { $0.isEmpty ? nil : $0 }
    }

    /// An argument as a query string value: 5 not "5.0", true as "true".
    static func queryValue(_ args: MCPArgs, _ key: String) -> String? {
        guard let v = args.value(key), !v.isNull else { return nil }
        switch v {
        case .string(let s): return s
        case .bool(let b): return b ? "true" : "false"
        case .number(let n): return n == n.rounded() && abs(n) < 1e15 ? String(Int(n)) : String(n)
        default: return nil
        }
    }

    static func query(_ args: MCPArgs, _ keys: [String]) -> [String: String] {
        var q: [String: String] = [:]
        for k in keys { if let v = queryValue(args, k) { q[k] = v } }
        return q
    }

    /// The listed arguments, as a JSON object body.
    static func body(_ args: MCPArgs, _ keys: [String]) -> JSONValue {
        var o: [String: JSONValue] = [:]
        for k in keys { if let v = args.value(k), !v.isNull { o[k] = v } }
        return .object(o)
    }

    static let all: [ParityTool] = [
        // MARK: Settings
        ParityTool(definition: MCPToolDefinition(
            name: "get_settings", title: "Get settings",
            description: """
            Read every Herald setting that Settings shows (general, voice) with its current value, a `schema` (key, type, range, \
            description) and `options` (system sounds, displays, voices, corners, stacking levels, history cap choices). Quiet hours \
            have their own tool (get_quiet_hours); per-app settings are in list_apps.
            """,
            inputSchema: Schema.input(), readOnly: true, idempotent: true),
            route: { _ in RouteCall(method: "GET", path: "/v1/settings") }),

        ParityTool(definition: MCPToolDefinition(
            name: "set_settings", title: "Change settings",
            description: """
            Change one or more Herald settings. `settings` is an object of key: value pairs from get_settings' schema, for example \
            {"muteAllSounds": true, "stacking": "bySender", "voiceSpeed": 1.2}. Every value is validated first; one bad key changes \
            nothing. These are the user's own preferences: say what you are changing. `port` restarts the local server (this MCP \
            server follows the port file); `launchAtLogin` registers the login item.
            """,
            inputSchema: Schema.input(["settings": Schema.object("Setting keys and new values, e.g. {\"muteAllSounds\": true}.")], required: ["settings"]),
            idempotent: true),
            route: { a in RouteCall(method: "PUT", path: "/v1/settings", body: .object(try a.requiredObject("settings"))) }),

        ParityTool(definition: MCPToolDefinition(
            name: "list_apps", title: "List apps and their settings",
            description: """
            The apps that have sent to Herald, each with its per-app settings (sound, stay-until-dismissed, timeout, corner, display, \
            mute banners, stacking override), voice settings (speak, voice, urgent breaks quiet hours) and approvals: whether the user \
            allowed command buttons and which non-local callback host they approved. Includes the `schema` for update_app_settings. \
            Pass `app` for one.
            """,
            inputSchema: Schema.input(["app": Schema.string("Only this app id.")]), readOnly: true, idempotent: true),
            route: { a in RouteCall(method: "GET", path: "/v1/apps/settings", query: query(a, ["app"])) }),

        ParityTool(definition: MCPToolDefinition(
            name: "update_app_settings", title: "Change an app's settings",
            description: """
            Change one app's settings (Settings > Apps and Voice). `settings` holds keys from list_apps' schema: sound, persistent, \
            timeout, corner (null follows the app), display ("main" or a display id), muteBanners, stacking (null follows the default), \
            speak, voice, urgentBreaksQuiet. Approvals can only be WITHDRAWN: revokeCommands: true, revokeCallbackHost: true. Granting \
            an app permission to run commands or call a remote host is refused (403): only the user can, in Settings > Apps.
            """,
            inputSchema: Schema.input([
                "app": Schema.string("The app id (see list_apps)."),
                "settings": Schema.object("Keys and values to change, e.g. {\"muteBanners\": true, \"corner\": \"bottomLeft\"}."),
            ], required: ["app", "settings"]), idempotent: true),
            route: { a in
                var o = try a.requiredObject("settings")
                o["app"] = .string(try a.requiredString("app"))
                return RouteCall(method: "PUT", path: "/v1/apps/settings", body: .object(o))
            }),

        ParityTool(definition: MCPToolDefinition(
            name: "register_app", title: "Register an app",
            description: """
            Register or update an issuing app: display name, icon (a file path or data:image/png;base64 URI, at most 256 KB), bundle id \
            (focused when a banner is clicked), callback URL for callback buttons, whether it asks to run command buttons (the user must \
            still confirm that in Settings > Apps), and defaults (sound, persistent, timeout, corner). Fields you omit keep their value.
            """,
            inputSchema: Schema.input([
                "app": Schema.string("The app id."), "appName": Schema.string("Display name."),
                "icon": Schema.string("File path or data:image/png;base64,... URI."),
                "bundleId": Schema.string("Bundle id to focus on click."),
                "callbackURL": Schema.string("Where callback buttons POST."),
                "allowCommands": Schema.boolean("Ask for permission to run command buttons (the user confirms)."),
                "defaults": Schema.object("{sound?, persistent?, timeout?, corner?}"),
            ], required: ["app"]), idempotent: true),
            route: { a in RouteCall(method: "POST", path: "/v1/register",
                                    body: body(a, ["app", "appName", "icon", "bundleId", "callbackURL", "allowCommands", "defaults"])) }),

        ParityTool(definition: MCPToolDefinition(
            name: "voice_status", title: "Voice and Kokoro status",
            description: "The speech engine, whether the optional Kokoro voice is installed (what is missing, install progress, whether ~/.claude/tts can be reused), the available voices and the last error.",
            inputSchema: Schema.input(), readOnly: true, idempotent: true),
            route: { _ in RouteCall(method: "GET", path: "/v1/voice") }),

        ParityTool(definition: MCPToolDefinition(
            name: "install_voice", title: "Install Kokoro voice",
            description: """
            Start, cancel or shortcut the Kokoro voice install (Settings > Voice). install downloads about 340 MB from the kokoro-onnx \
            GitHub release and builds a Python environment: ask the user first. useExisting links a complete ~/.claude/tts without \
            downloading. Poll voice_status for progress.
            """,
            inputSchema: Schema.input(["action": Schema.string("What to do.", values: ["install", "cancel", "useExisting"])], required: ["action"]),
            idempotent: false),
            route: { a in RouteCall(method: "POST", path: "/v1/voice/install", body: body(a, ["action"])) }),

        ParityTool(definition: MCPToolDefinition(
            name: "install_mcp", title: "Install the MCP server in a client",
            description: """
            Settings > MCP. Without `client`: the status of each client (Claude Code, Codex, Claude Desktop) and the server path. With \
            `client` (claudeCode, codex, claudeDesktop, cli, generic): add herald-mcp to that client's configuration with `--agent <client>` (a backup of the \
            file is kept; claudeCode runs `claude mcp add`) and register the agent as an issuer: app agent.claude-code, agent.codex, \
            agent.claude-desktop or agent.<slug> (generic needs `name`), with a manifest, a default template and the product's icon. \
            Re-running keeps the user's edits. `cli` installs the `herald` command line tool. It edits another application's \
            configuration: do it only when the user asked.
            """,
            inputSchema: Schema.input([
                "client": Schema.string("Which client to install into; omit for the status.", values: ["claudeCode", "codex", "claudeDesktop", "cli", "generic"]),
                "reinstall": Schema.boolean("Replace an existing registration (claudeCode)."),
                "name": Schema.string("generic only: the client's name; its notifications arrive as agent.<slug of the name>."),
                "icon": Schema.string("An image file on this Mac to use as the agent's icon (otherwise the product's own icon is used)."),
                "opens": Schema.string("What the agent's Open button brings to the front: a bundle id (com.apple.Terminal) or an application path (/Applications/iTerm.app). Default: Claude.app for Claude Desktop; for Claude Code, Codex and generic clients the terminal or editor this server runs in (detected), else Terminal. A reinstall keeps the app the user chose."),
            ]), idempotent: true),
            route: { a in
                guard let client = try text(a, "client") else { return RouteCall(method: "GET", path: "/v1/mcp") }
                var body: [String: JSONValue] = ["client": .string(client), "reinstall": .bool(try a.bool("reinstall") ?? false)]
                for k in ["name", "icon", "opens", "detectedHost"] { if let v = a.value(k) { body[k] = v } }
                return RouteCall(method: "POST", path: "/v1/mcp/install", body: .object(body))
            }),

        ParityTool(definition: MCPToolDefinition(
            name: "get_replies", title: "Get replies typed into banners",
            description: """
            The answers the user typed into a banner's inline Reply, oldest first, from a per-app queue. Each reply has \
            notificationId, app, text, repliedAt and the title of the notification it answers. `since` (ISO 8601 or epoch seconds) \
            returns only newer ones; with `consume: true` the returned replies leave the queue (History keeps them on the \
            notification record). To ask a question and wait for the answer use send_notification (persistent: true, an id) then \
            wait_for_reply.
            """,
            inputSchema: Schema.input([
                "app": Schema.string("The app id (an agent's own app by default)."),
                "since": Schema.string("Only replies after this time: ISO 8601 or epoch seconds."),
                "consume": Schema.boolean("Remove the returned replies from the queue (default false)."),
            ]), readOnly: false, idempotent: false),
            route: { a in RouteCall(method: "GET", path: "/v1/replies", query: query(a, ["app", "since", "consume"])) }),

        ParityTool(definition: MCPToolDefinition(
            name: "wait_for_reply", title: "Wait for the user's reply",
            description: """
            Ask-a-question pattern: after send_notification (use persistent: true so the banner stays) wait here until the user \
            presses Reply on that notification and sends text, for at most timeoutSeconds (1 to 300, default 60). Returns \
            {replied: true, reply: {text, repliedAt, ...}} or {replied: false, timedOut: true}; call it again to keep waiting. \
            The reply is taken out of the queue unless consume is false. Answers at once when the reply is already there.
            """,
            inputSchema: Schema.input([
                "notificationId": Schema.string("The id send_notification returned."),
                "app": Schema.string("The app the notification was sent as (an agent's own app by default)."),
                "timeoutSeconds": Schema.number("How long to wait, 1 to 300 (default 60).", min: 1, max: 300),
                "consume": Schema.boolean("Remove the reply from the queue once read (default true)."),
            ], required: ["notificationId"]), readOnly: false, idempotent: false),
            route: { a in
                var q = query(a, ["app", "consume"])
                q["id"] = try text(a, "notificationId")
                let seconds = min(max(try a.number("timeoutSeconds") ?? 60, 1), 300)
                q["timeout"] = String(Int(seconds))
                return RouteCall(method: "GET", path: "/v1/replies/wait", query: q, timeout: seconds + 15)
            }),

        ParityTool(definition: MCPToolDefinition(
            name: "list_approvals", title: "List template command approvals",
            description: "The commands, scripts and Shortcuts the user approved for templates (Settings > Actions): app, template, the exact commands and when. Approvals are granted by the user when a banner asks; they cannot be granted here.",
            inputSchema: Schema.input(), readOnly: true, idempotent: true),
            route: { _ in RouteCall(method: "GET", path: "/v1/actions/approvals") }),

        ParityTool(definition: MCPToolDefinition(
            name: "revoke_approval", title: "Revoke a template approval",
            description: "Withdraw the approval of a template's commands, scripts and Shortcuts (Settings > Actions > Revoke). The user is asked again the next time it runs.",
            inputSchema: Schema.input(["app": Schema.string("The app id."), "template": Schema.string("The template name.")], required: ["app", "template"]),
            destructive: true, idempotent: true),
            route: { a in RouteCall(method: "DELETE", path: "/v1/actions/approvals", query: query(a, ["app", "template"])) }),

        // MARK: Templates
        ParityTool(definition: MCPToolDefinition(
            name: "duplicate_template", title: "Duplicate a template",
            description: "Copy a saved template (or a builtin.* layout) under a new name, optionally for another app. Without newName the copy is \"<name> copy\" (numbered when taken). The Designer's Duplicate.",
            inputSchema: Schema.input([
                "app": Schema.string("The app the template belongs to."), "name": Schema.string("Template to copy (saved, or builtin.*)."),
                "newName": Schema.string("Name of the copy."), "toApp": Schema.string("Create the copy for this app instead."),
            ], required: ["app", "name"])),
            route: { a in RouteCall(method: "POST", path: "/v1/templates/duplicate", body: body(a, ["app", "name", "newName", "toApp"])) }),

        ParityTool(definition: MCPToolDefinition(
            name: "rename_template", title: "Rename a template",
            description: "Rename a saved template. The app's default template follows the new name. Command, script and Shortcut approvals belong to the old name, so the user is asked again.",
            inputSchema: Schema.input(["app": Schema.string("The app id."), "name": Schema.string("Current name."), "newName": Schema.string("New name.")],
                                      required: ["app", "name", "newName"]),
            destructive: true),
            route: { a in RouteCall(method: "POST", path: "/v1/templates/rename", body: body(a, ["app", "name", "newName"])) }),

        ParityTool(definition: MCPToolDefinition(
            name: "set_default_template", title: "Set the default template",
            description: "Make a template the app's default (the manifest's defaultTemplate: used by notifications that name no template), or clear it by omitting `name`. The app needs a manifest.",
            inputSchema: Schema.input(["app": Schema.string("The app id."), "name": Schema.string("Template name (saved or builtin.*); omit to clear.")], required: ["app"]),
            idempotent: true),
            route: { a in RouteCall(method: "PUT", path: "/v1/templates/default", body: body(a, ["app", "name"])) }),

        ParityTool(definition: MCPToolDefinition(
            name: "export_template_bundle", title: "Export a template bundle",
            description: """
            Pack a saved template and the Rive files it plays into one .heraldtemplate bundle (the Designer's Export). With `path` \
            (ending in .heraldtemplate, on this Mac) Herald writes the file; without it the bundle comes back as base64.
            """,
            inputSchema: Schema.input(["app": Schema.string("The app id."), "name": Schema.string("Template name."),
                                       "path": Schema.string("Where to write the file, e.g. ~/Desktop/hero.heraldtemplate.")], required: ["app", "name"]),
            readOnly: false, idempotent: true),
            route: { a in RouteCall(method: "GET", path: "/v1/templates/export", query: query(a, ["app", "name", "path"])) }),

        ParityTool(definition: MCPToolDefinition(
            name: "import_template_bundle", title: "Import a template bundle",
            description: """
            Import a .heraldtemplate bundle (the Designer's Import): `path` to the file on this Mac (any size up to 64 MB) or `base64` \
            (up to about 700 KB). `app` retargets it to another issuer. onConflict when the name exists: keepBoth (default, saves as \
            "name 2"), replace (overwrites: destructive) or fail. Its Rive files go into the app's assets folder. Script actions in it \
            still need the script files and the user's approval.
            """,
            inputSchema: Schema.input([
                "path": Schema.string("A .heraldtemplate file on this Mac."), "base64": Schema.string("The bundle, base64 encoded."),
                "app": Schema.string("Import for this app instead of the one in the bundle."),
                "onConflict": Schema.string("What to do when the name is taken.", values: ["keepBoth", "replace", "fail"]),
            ]), destructive: true),
            route: { a in RouteCall(method: "POST", path: "/v1/templates/import", body: body(a, ["path", "base64", "app", "onConflict"])) }),

        ParityTool(definition: MCPToolDefinition(
            name: "delete_manifest", title: "Delete a manifest",
            description: "Delete an app's manifest and the copies of its Rive assets (templates stay). The app's notifications then use the generic look.",
            inputSchema: Schema.input(["app": Schema.string("The app id.")], required: ["app"]), destructive: true, idempotent: true),
            route: { a in RouteCall(method: "DELETE", path: "/v1/manifest", query: query(a, ["app"])) }),

        // MARK: Assets and symbols
        ParityTool(definition: MCPToolDefinition(
            name: "list_assets", title: "List an app's assets",
            description: "The Rive animations and images stored for an app, with size, whether the manifest declares them, which templates play them, and the component snippet to use.",
            inputSchema: Schema.input(["app": Schema.string("The app id.")], required: ["app"]), readOnly: true, idempotent: true),
            route: { a in RouteCall(method: "GET", path: "/v1/assets", query: query(a, ["app"])) }),

        ParityTool(definition: MCPToolDefinition(
            name: "upload_asset", title: "Upload a Rive file or image",
            description: """
            Add a Rive animation (.riv, at most 10 MB, 32 per app) or an image (PNG, JPEG, GIF, WebP, HEIC, TIFF, BMP, at most 10 MB) to \
            an app's assets, like the Designer's Add. Give `path` (a file on this Mac, any size within the limit) or `base64` (up to about \
            700 KB, with `name`). The reply has the stored path and the component to use: {"type":"rive","path":"x.riv"} for an \
            animation, the path for an image field or a fixed image source. Same name replaces the file.
            """,
            inputSchema: Schema.input([
                "app": Schema.string("The app id."), "path": Schema.string("A file on this Mac."),
                "base64": Schema.string("The file, base64 encoded (small files)."),
                "name": Schema.string("File name, e.g. confetti.riv or logo.png (required with base64)."),
                "kind": Schema.string("rive or image; inferred from the name when omitted.", values: ["rive", "image"]),
            ], required: ["app"]), idempotent: true),
            route: { a in RouteCall(method: "POST", path: "/v1/assets", body: body(a, ["app", "path", "base64", "name", "kind"])) }),

        ParityTool(definition: MCPToolDefinition(
            name: "delete_asset", title: "Delete an asset",
            description: "Delete a Rive file or image from an app's assets by file name (see list_assets). Templates that play a deleted animation show a placeholder; the reply lists them.",
            inputSchema: Schema.input(["app": Schema.string("The app id."), "file": Schema.string("File name, e.g. confetti.riv.")], required: ["app", "file"]),
            destructive: true, idempotent: true),
            route: { a in RouteCall(method: "DELETE", path: "/v1/assets", query: query(a, ["app", "file"])) }),

        ParityTool(definition: MCPToolDefinition(
            name: "list_symbols", title: "List SF Symbols",
            description: "Search the SF Symbol names available on this Mac, with their categories, for a component's `symbol` property. `q` matches every word in the name or its search terms (\"bell\", \"arrow up\"); `category` narrows it (the reply lists categories with counts). Page with limit and offset.",
            inputSchema: Schema.input([
                "q": Schema.string("Search words."), "category": Schema.string("A category key from the reply, e.g. communication, weather."),
                "limit": Schema.integer("Names per page (default 100, at most 1000).", min: 0, max: 1000),
                "offset": Schema.integer("Skip this many.", min: 0),
            ]), readOnly: true, idempotent: true),
            route: { a in RouteCall(method: "GET", path: "/v1/symbols", query: query(a, ["q", "category", "limit", "offset"])) }),

        ParityTool(definition: MCPToolDefinition(
            name: "rive_check", title: "Check a Rive component",
            description: "Load a `rive` component without a window and report the artboards, state machines, inputs and view-model properties it found, optionally after pointer steps (hoverIn, hoverOut, pressDown, pressUp). Nothing is shown or stored.",
            inputSchema: Schema.input([
                "app": Schema.string("The app id (assets resolve in its folder)."),
                "component": Schema.object("The rive component: {asset? | path?, artboard?, stateMachine?, ...}"),
                "fields": Schema.object("Field values for the component's bindings."),
                "simulate": .object(["type": .string("array"), "items": .object(["type": .string("string")]), "description": .string("Pointer steps to run in order.")]),
            ], required: ["app", "component"]), readOnly: true, idempotent: true),
            route: { a in RouteCall(method: "POST", path: "/v1/rive/check", body: body(a, ["app", "component", "fields", "simulate"])) }),

        // MARK: History and banners
        ParityTool(definition: MCPToolDefinition(
            name: "history_search", title: "Search history",
            description: "Search History like its search box: every word must appear (any case, accents folded) in the title, subtitle, body, app id or app name. Newest first. Omit `app` to search all apps.",
            inputSchema: Schema.input(["q": Schema.string("Words to find."), "app": Schema.string("Only this app."),
                                       "limit": Schema.integer("At most this many (default 50, 1000 max).", min: 0, max: 1000)], required: ["q"]),
            readOnly: true, idempotent: true),
            route: { a in RouteCall(method: "GET", path: "/v1/history/search", query: query(a, ["q", "app", "limit"])) }),

        ParityTool(definition: MCPToolDefinition(
            name: "reshow_notification", title: "Re-show a notification",
            description: "Show a notification from History again as a new banner, with its sound and a fresh delivery time (History's Re-show as Banner).",
            inputSchema: Schema.input(["app": Schema.string("The app id."), "id": Schema.string("The notification id (see list_history).")], required: ["app", "id"])),
            route: { a in RouteCall(method: "POST", path: "/v1/history/reshow", body: body(a, ["app", "id"])) }),

        ParityTool(definition: MCPToolDefinition(
            name: "delete_history", title: "Delete from history",
            description: "Delete one notification from History (app and id) and close its banner, or clear an app's whole history (app and all: true), or everything (all: true without app). This cannot be undone.",
            inputSchema: Schema.input([
                "app": Schema.string("The app id."), "id": Schema.string("The notification id; omit to clear with all."),
                "all": Schema.boolean("Clear every notification of the app (or of all apps when `app` is omitted)."),
            ]), destructive: true, idempotent: true),
            route: { a in
                if let id = try text(a, "id") {
                    return RouteCall(method: "DELETE", path: "/v1/history/item", query: ["app": try a.requiredString("app"), "id": id])
                }
                guard try a.bool("all") == true else { throw ToolFailure("Give app and id to delete one notification, or all: true to clear.") }
                return RouteCall(method: "DELETE", path: "/v1/history", query: query(a, ["app"]))
            }),

        ParityTool(definition: MCPToolDefinition(
            name: "export_history", title: "Export history",
            description: "History as JSON (the full records, newest first), for one app or all. With `path` (ending in .json, on this Mac) Herald writes the file and returns only the count.",
            inputSchema: Schema.input(["app": Schema.string("Only this app."), "path": Schema.string("Write the JSON to this file.")]),
            readOnly: false, idempotent: true),
            route: { a in RouteCall(method: "GET", path: "/v1/history/export", query: query(a, ["app", "path"])) }),

        ParityTool(definition: MCPToolDefinition(
            name: "snooze", title: "Snooze a banner",
            description: "Hide a banner and show it again after `minutes` (up to 43200), or with cancel: true bring a snoozed banner back now (the banner's clock menu).",
            inputSchema: Schema.input([
                "app": Schema.string("The app id."), "id": Schema.string("The notification id."),
                "minutes": Schema.number("Minutes until it returns.", min: 0.01, max: 43200),
                "cancel": Schema.boolean("Cancel the snooze and show it now."),
            ], required: ["app", "id"])),
            route: { a in
                if try a.bool("cancel") == true { return RouteCall(method: "POST", path: "/v1/unsnooze", body: body(a, ["app", "id"])) }
                guard try a.number("minutes") != nil else { throw ToolFailure("Give minutes, or cancel: true.") }
                return RouteCall(method: "POST", path: "/v1/snooze", body: body(a, ["app", "id", "minutes"]))
            }),

        ParityTool(definition: MCPToolDefinition(
            name: "expand_stack", title: "Open or close a stack",
            description: "Open a stack of banners as a list, or close it (see list_stacks for app and group).",
            inputSchema: Schema.input(["app": Schema.string("The app id."), "group": Schema.string("The stack's group (defaults to the app id)."),
                                       "expanded": Schema.boolean("true opens (default), false closes.")], required: ["app"]),
            idempotent: true),
            route: { a in RouteCall(method: "POST", path: "/v1/stacks/expand", body: body(a, ["app", "group", "expanded"])) }),
    ]

    static let routes: [String: ParityTool] = Dictionary(uniqueKeysWithValues: all.map { ($0.definition.name, $0) })

    /// Hand-written (a PNG comes back, not JSON): `designer_snapshot`.
    static let snapshotDefinition = MCPToolDefinition(
        name: "designer_snapshot", title: "Snapshot the Designer",
        description: """
        Draw the Designer window's content offscreen (no window is opened or focused) for an app and template and return it as a PNG: \
        the grid canvas with its handles, the inspector and the live preview. `select` selects a cell id so the inspector shows it. \
        Use it to check how the editor looks; render_preview shows the banner itself.
        """,
        inputSchema: Schema.input([
            "app": Schema.string("The app (issuer) to open."), "template": Schema.string("A saved template name to open."),
            "select": Schema.string("A cell id to select."),
            "width": Schema.integer("600 to 4000 (default 1100).", min: 600, max: 4000),
            "height": Schema.integer("400 to 3000 (default 820).", min: 400, max: 3000),
        ]), readOnly: true, idempotent: true)

    static let definitions: [MCPToolDefinition] = all.map(\.definition) + [snapshotDefinition]
}

extension MCPTools {
    /// Runs a parity tool; nil when `name` is not one.
    func callParity(_ name: String, _ args: MCPArgs) async throws -> MCPToolResult? {
        if name == "designer_snapshot" { return try await designerSnapshot(args) }
        guard let tool = ParityTools.routes[name] else { return nil }
        // The schema's `required` list is enforced here, so a missing argument is a tool error and never a half-formed request.
        for key in tool.definition.inputSchema["required"]?.arrayValue?.compactMap(\.stringValue) ?? [] {
            guard let v = args.value(key), !v.isNull, v.stringValue?.isEmpty != true else {
                throw ToolFailure("Missing required argument '\(key)'.")
            }
        }
        let call = try tool.route(args)
        let reply = try await client.call(call.method, call.path, query: call.query, body: call.body, timeout: call.timeout ?? 20)
        return .json(reply)
    }

    private func designerSnapshot(_ args: MCPArgs) async throws -> MCPToolResult {
        let png = try await client.designerSnapshot(app: try ParityTools.text(args, "app"), template: try ParityTools.text(args, "template"),
                                                    select: try ParityTools.text(args, "select"),
                                                    width: try args.int("width"), height: try args.int("height"))
        var info: [String: JSONValue] = ["bytes": .number(Double(png.count))]
        if let size = PNGInfo.size(of: png) { info["width"] = .number(Double(size.width)); info["height"] = .number(Double(size.height)) }
        return MCPToolResult(blocks: [.image(data: png, mimeType: "image/png"), .text(JSONValue.object(info).text())])
    }
}
