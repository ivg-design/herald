# Two-way actions

A button on a banner can run something the **issuer** supplied (a callback to the sending app, a URL, a
command) or something **you** added in the template (a shell command, a script, an Apple Shortcut), or
both. Herald merges the two lists, lets template rules rewrite the result, and hands every action the
merged payload.

## Action shape

```json
{"id":"followup","label":"Follow up","kind":"shortcut","style":"default",
 "shortcut":"Create follow-up","input":"{title}\n{url}"}
```

| Field | Meaning |
|---|---|
| `id` | Stable id; rules and `actionRef` match on it. Derived from the label when omitted. |
| `label` | Button text. |
| `kind` | `url`, `callback`, `command`, `script`, `shortcut`, `dismiss`, `snooze`. |
| `style` | `default`, `destructive`, `cancel`. |
| `url` / `callback` / `command` / `script` / `shortcut` | The one property that belongs to the kind. |
| `input` | For `shortcut`: text with bindings. Absent means the full JSON payload. |
| `snoozeMinutes` | For `snooze` (default 15). |

v1 buttons (`label` plus one of `url`, `command`, `callback`) are still accepted everywhere an action is.

## Kinds

- `url`: opens `http`, `https` or `mailto` URLs only. Bindings are filled in.
- `callback`: POSTs `{"notificationId","app","action","payload"}` to the callback URL; a 2xx dismisses the
  banner (see [API.md](API.md#callbacks)).
- `command`: runs through `/bin/zsh -lc` after a confirmation (below). Bindings in the command text are filled in
  (shell-quoted) and the merged payload is passed on stdin as JSON.
- `script`: runs a file from `~/Library/Application Support/Herald/scripts/` (a relative name, no `..`)
  with the merged payload JSON on stdin. The file must be executable.
- `shortcut`: runs `/usr/bin/shortcuts run "<name>" --input-path <file>`. With `input` set, the file holds
  that text with bindings filled in; without it, the file holds the full merged payload as JSON.
- `dismiss`, `snooze`: built in.

## Merging: issuer plus template

The resolved list is the issuer's actions (from the payload `buttons`/`actions`, or the manifest's
`actions` for `actionIds`) followed by the template's additions, passed through `actionRules` in order.
The manifest's actions are not shown just because it declares them: a notification has to send `buttons` (or
`actions`, the same list under its documented name) or name manifest actions with `actionIds: ["markRead"]`.
A sample preview (the Designer, `render_preview` with sample data) stands in for an issuer that names every
declared action, and says so; a preview of real data shows only what that data sends. One function
(`ActionResolver.issuerSource`) resolves all of this for the banner, the press, the preview and the Designer.

```json
"actionRules": [
  {"match":"markRead","hide":true},
  {"match":"archive","relabel":"Archive it","style":"destructive","position":0},
  {"add":{"id":"followup","label":"Follow up","kind":"shortcut","shortcut":"Create follow-up","input":"{title}\n{url}"}}
]
```

| Rule | Effect |
|---|---|
| `match` | Selects issuer or template actions by id or label (case-insensitive); `"*"` selects all. |
| `hide: true` | Removes the matched actions. |
| `relabel`, `style`, `position` | Change the label, style or 0-based position of the matched actions. |
| `add` | Appends a new template-owned action (at `position` if given). Same id replaces. |

An `actions` component with `source: "issuer"`, `"template"` or `"merged"` decides which origin it shows;
a `button` or `iconButton` points at one action by `actionRef`. Template rules also apply to buttons
sent with the notification, so you can relabel an issuer's button without touching the issuer.

## Symbols on actions

An action can carry an SF Symbol, drawn on its button (a `button`, the `actions` row, an `iconButton`): `{"id":"archive","label":"Archive","kind":"command","command":"...","symbol":"archivebox"}`. `symbol` is a name or the full styling object (weight, scale, placement, renderingMode, colors, variableValue, effect; see TEMPLATES.md, "Symbols"). A component's own `symbol` is the default for the buttons it draws, and the action's `symbol` wins.

A rule can give a symbol to existing actions without touching the issuer: `{"match":"markRead","symbol":{"name":"checkmark.circle.fill","renderingMode":"palette","colors":["white","#34C759"]}}` (`match: "*"` for all). `add_action_rule` accepts `symbol` on the rule and on an added action; an unknown name is a warning and the button simply has no symbol.

## Augmenting the payload

Every action receives the **merged payload**: the issuer's top-level fields, its `metadata`, and the
template's `extra` key/values you authored (template `extra` wins on a key clash). Callbacks include it
under `payload`, so you can enrich what an issuer's app hears back. Bindings in `input`, `command` and
`url` read from the same merged data.

## Apple Shortcuts

Herald lists installed shortcuts with `shortcuts list` (`GET /v1/shortcuts`, MCP `list_shortcuts`, and a
picker in the Designer: "Run shortcut..."). `shortcuts run` is headless, so a template's shortcut action is
confirmed like a script: Herald shows the shortcut's name and its input the first time it would run, and asks
again when either changes. It only runs when you press the button. Text input goes to the shortcut's
"Receive input from" action; JSON input arrives as a file.

## Security

- Nothing runs on delivery. Actions run only when you press the button.
- **Issuer commands** (`command` buttons sent in a notify) need `allowCommands` requested by the app and
  confirmed in Settings > Apps, as in 1.0.
- **Template-authored commands, scripts and shortcuts** (rule `add`s, inline component actions and a
  template's default `buttons`) are yours. Herald asks once per template, showing the command, the script's
  name, SHA-256 and text, or the shortcut's name and input, the first time it would run. "Always Allow This
  Template" is bound to exactly what was shown: if a command is edited, a script file changes (its hash) or a
  shortcut's name or input changes, Herald asks again. When such an action took the place of one of the
  issuer's own buttons (same id), the prompt says which button it replaced and that the issuer will not hear
  about the press.
- Scripts must live under the `scripts` folder; paths outside it are refused.
- Scripts receive the data on stdin, not on the command line, so prefer a script over a `command` when the
  action handles text from untrusted senders (an email subject can contain anything).
- Callbacks to a non-loopback host still need your approval; redirects are never followed.
- The MCP can create and edit templates and actions but cannot press a button.
