# Two-way actions

> **Changed in 1.4.** New action kind `openApp` (brings an app to the front; no confirmation). Button `style` is
> now `normal`, `prominent`, `destructive` or `cancel`, and a destructive action asks inline before it runs,
> whether it came from a template or from the issuer. The `actions` component can split the list with `include`
> and an action is drawn in one cell only; `button` accepts `actionId` as an alias of `actionRef`. A template can
> make the banner click open the issuing app with `onClick: "openApp"`.

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
| `kind` | `url`, `callback`, `command`, `script`, `shortcut`, `openApp`, `dismiss`, `snooze`. May be left out when one of `shortcut`, `script`, `command`, `callback`, `url`, `bundleId` / `path` is present. |
| `style` | `normal`, `prominent`, `destructive` (red, asks before running), `cancel`; `default` means `normal`. |
| `url` / `callback` / `command` / `script` / `shortcut` | The one property that belongs to the kind. |
| `bundleId` / `path` | For `openApp`: the app's bundle id, or its path (ends in `.app`, `~` expanded). Both optional. |
| `input` | For `shortcut`: text with bindings. Absent means the full JSON payload. |
| `snoozeMinutes` | For `snooze` (default 15). |

v1 buttons (`label` plus one of `url`, `command`, `callback`) are still accepted everywhere an action is.

## Kinds

- `url`: opens `http`, `https` or `mailto` URLs only. Bindings are filled in.
- `callback`: POSTs `{"notificationId","app","action","payload"}` to the callback URL; a 2xx dismisses the
  banner (see [API.md](API.md#callbacks)).
- `command`: runs through `/bin/zsh -lc` after a confirmation (below). The command text is never interpolated:
  the merged payload arrives on stdin as JSON and in `HERALD_*` environment variables (`HERALD_APP`,
  `HERALD_NOTIFICATION_ID`, `HERALD_ACTION_ID`, `HERALD_ACTION_KIND`, `HERALD_TEMPLATE`, `HERALD_FIELD_<name>`,
  `HERALD_EXTRA_<name>`).
- `script`: runs a file from `~/Library/Application Support/Herald/scripts/` (a relative name, no `..`)
  with the merged payload JSON on stdin. The file must be executable.
- `shortcut`: runs `/usr/bin/shortcuts run "<name>" --input-path <file>`. With `input` set, the file holds
  that text with bindings filled in; without it, the file holds the full merged payload as JSON.
- `openApp`: brings an application to the front, see [Open app](#open-app).
- `dismiss`, `snooze`: built in.

## Open app

`openApp` runs no code, so it needs no confirmation, from an issuer or a template. Herald itself stays in the
background. The application is the first of these that exists on this Mac:

1. the action's `bundleId`;
2. the action's `path`;
3. the manifest's `appBundleId`;
4. the manifest's `appPath`;
5. the bundle id the issuer registered with;
6. the app named like the manifest's `appName` (`<appName>.app` in the Applications folders).

With neither `bundleId` nor `path` an `openApp` action opens the issuing app. If nothing resolves, nothing
happens: the banner stays, shows "Action failed - no installed application found", and History keeps the
note "<label>: no installed application found" (`actionNote`). `validate_template` reports it as a warning,
not an error, since the template may be written for another Mac.

| Where | Form |
|---|---|
| Template rule | `{"add":{"id":"open-ww","label":"Open WebWatcher","kind":"openApp"}}` |
| Manifest action (issuer) | `{"id":"open","label":"Open WebWatcher","kind":"openApp"}`, optional `bundleId` / `path`; the manifest also takes `appBundleId` and `appPath` |
| Payload button (issuer) | `{"label":"Open","openApp":{"bundleId":"com.apple.mail"}}` |
| Banner click | template option `"onClick": "openApp"` (default `"url"`) |

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
| `relabel`, `style`, `position` | Change the label, style (`normal`, `prominent`, `destructive`, `cancel`) or 0-based position of the matched actions. |
| `add` | Appends a new template-owned action (at `position` if given). Same id replaces. |

An `actions` component with `source: "issuer"`, `"template"` or `"merged"` decides which origin it shows
(`include` narrows it to named ids, and `align`, `wrap` and `spacing` arrange the buttons); a `button` or
`iconButton` points at one action by `actionRef` (a `button` also accepts `actionId`, the same thing). Template rules also apply to buttons
sent with the notification, so you can relabel an issuer's button without touching the issuer.

## One action, one cell

An action is drawn in at most one cell of a template. Cells are visited top to bottom, left to right: a `button`
bound by `actionRef` / `actionId` claims its action, an `actions` cell with `include` claims those ids in that
order, and an `actions` cell without `include` shows what nobody claimed. When two cells ask for the same
action the first in reading order draws it and the other renders empty (validation warns, naming both). That
is how one action list is split across a banner; see [TEMPLATES.md](TEMPLATES.md#one-action-one-cell).

## Destructive actions

An action whose effective style is `destructive` (set by the issuer, the manifest, a rule or the button) is drawn
with a red label and asks first: pressing it replaces the buttons with an inline "Run "Delete"?" row and Cancel,
every time. It applies to template buttons and issuer actions alike, and comes before any approval the kind
itself needs (a command's permission, a template's confirmation). The question is drawn in the banner and never
takes focus. Old templates with `"destructive": true` on a button still work.

## Symbols on actions

An action can carry an SF Symbol, drawn on its button (a `button`, the `actions` row, an `iconButton`): `{"id":"archive","label":"Archive","kind":"command","command":"...","symbol":"archivebox"}`. `symbol` is a name or the full styling object (weight, scale, placement, renderingMode, colors, variableValue, effect; see TEMPLATES.md, "Symbols"). A component's own `symbol` is the default for the buttons it draws, and the action's `symbol` wins.

A rule can give a symbol to existing actions without touching the issuer: `{"match":"markRead","symbol":{"name":"checkmark.circle.fill","renderingMode":"palette","colors":["white","#34C759"]}}` (`match: "*"` for all). `add_action_rule` accepts `symbol` on the rule and on an added action; an unknown name is a warning and the button simply has no symbol.

## The look of each button

Every action has its own look: it shows its text, an icon with its text, or an icon only. In the Designer, open the Actions tab: each row,
for the issuer's buttons (from the manifest) and for the ones you added, has **Shows** (Text, Icon and text, Icon only) and its own icon
picker with the full symbol styling (weight, scale, mode, colours, effect). Buttons that share a cell no longer share one icon. The reset
arrow on a row puts the action back as the issuer sent it, which also undoes an icon change. The form for adding or editing an action has
the same **Shows** choice; an **Icon only** action needs no label, and a label you give it is used as the tooltip.

In template JSON the look is the action's `symbol`. For an issuer's action it is a rule with `match` and `symbol`; for an action you
added it is `symbol` on the action itself. `placement` is `leading` (the default), `trailing` or `only`, and `only` drops the label:

```json
{"actionRules":[
  {"match":"markRead","symbol":{"name":"checkmark.circle","placement":"only"}},
  {"add":{"id":"archive","label":"Archive","kind":"command","command":"/usr/local/bin/archive",
          "symbol":{"name":"archivebox","placement":"only"}}}
]}
```

Text only is an action with no `symbol`. The same fields are in [reference/symbols.md](reference/symbols.md) and
[reference/actions.md](reference/actions.md#rules-actionrules).

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

- Nothing runs on delivery. Actions run only when you press the button. `openApp`, `url`, `dismiss` and `snooze` run no code and need no confirmation (`openApp` only activates an app; a `destructive` style still asks first).
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
