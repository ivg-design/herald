# Actions (two-way buttons)

A button on a banner can run something the **issuer** supplied (call the app back, open a URL, a command), or
something **you** added in the template (a shell command, a script, an Apple Shortcut, a URL, snooze, dismiss),
or both. Herald merges the two lists, lets template rules rewrite the result, and hands every action the
merged payload. The short guide is [../ACTIONS.md](../ACTIONS.md); this page is the full reference.

## Action object

```json
{"id":"followup","label":"Follow up","kind":"shortcut","style":"default",
 "shortcut":"Create follow-up","input":"{title}\n{url}"}
```

| Property | Type | Applies to | Meaning |
|---|---|---|---|
| `id` | string | all | Stable name. Rules (`match`) and components (`actionRef`) refer to it. Defaults to a slug of the label (`"Mark as Read"` becomes `mark-as-read`). |
| `label` | string | all | Button text; `{tokens}` are filled; falls back to the `id` if that leaves nothing. Required (defaults to `id` if omitted). |
| `kind` | string | all | `url`, `callback`, `command`, `script`, `shortcut`, `openApp`, `reply`, `dismiss`, `snooze`. May be omitted when exactly one of `shortcut`, `script`, `command`, `callback`, `url`, `bundleId`/`path` is present (checked in that order). |
| `style` | string | all | `normal`, `prominent`, `destructive` (asks for confirmation before running), `cancel`; `default` means `normal`. |
| `url` | string | `url` | An http, https or mailto URL; may contain `{tokens}` in a template action. |
| `callback` | object | `callback` | `{url?, payload?}`; `url` defaults to the app's registered `callbackURL`. |
| `command` | string | `command` | A shell command line, run with `/bin/zsh -lc`. |
| `script` | string | `script` | A file name inside `~/Library/Application Support/Herald/scripts/` (no `/` path escapes, no `..`, no `~`). |
| `shortcut` | string | `shortcut` | Name of an installed Apple Shortcut. |
| `input` | string | `shortcut` | Text with `{tokens}` handed to the Shortcut. Omit to hand it the full merged payload as JSON. |
| `snoozeMinutes` | integer 1 to 10080 | `snooze` | Minutes; omitted means the built-in snooze **menu** (5 min, 15 min, 1 h, Tomorrow 9:00). |
| `bundleId` | string | `openApp` | Bundle identifier of the application to bring to the front (`com.ivg.webwatcher`). Tried first. |
| `path` | string | `openApp` | Path of the application (`/Applications/WebWatcher.app`; `~` is expanded; must end in `.app`). Tried after `bundleId`. |
| `symbol` | name or object | all | **Available from 1.3.** An SF Symbol on this action's button. See [symbols.md](symbols.md). |

v1 buttons (`label` plus one of `url`, `command`, `callback`) are accepted everywhere an action is.

## Kinds

| Kind | What happens |
|---|---|
| `url` | Opens the URL with the system, only if its scheme is `http`, `https` or `mailto`. Anything else (`file:`, `smb:`, custom schemes) is refused: "this link type is not allowed". |
| `callback` | POSTs `{"notificationId","app","action":"<label>","payload":...}` to the callback URL. A 2xx dismisses the banner. See [Callbacks](#callbacks). |
| `command` | Runs `/bin/zsh -lc "<command>"` in your home folder. The command text is **never interpolated**; the data arrives on stdin and in `HERALD_*` variables. |
| `script` | Runs a file from the scripts folder with the merged payload JSON on stdin. `.sh`/`.zsh` run through zsh, `.bash` bash, `.py` python3, `.rb` ruby, `.pl` perl, `.scpt`/`.applescript` osascript; otherwise the file must be executable. |
| `shortcut` | `/usr/bin/shortcuts run "<name>" --input-path <temp file>`; the file holds `input` (filled with fields, `.txt`) or the merged payload JSON (`.json`). |
| `reply` | Swaps the buttons for a text field inside the banner; the text is stored (`reply`, `repliedAt`, reply queue) and POSTed to `callback` when there is one. Any issuer may declare it. |
| `openApp` | Brings an application to the front. See [Open app](#open-app). |
| `dismiss` | Closes the banner; the notification stays in History. |
| `snooze` | Hides the banner and brings it back after `snoozeMinutes`, or opens the menu when there are none. |

### Open app

`openApp` activates an application: a click on the button is the user's own, so the application it opens comes to
the front, while Herald itself stays in the background (nothing here activates Herald). It runs no code, so it
needs no confirmation, from the issuer or from a template. Which application is opened, the first of these that
exists on this Mac:

1. the action's own `bundleId`;
2. the action's own `path`;
3. the manifest's `appBundleId`;
4. the manifest's `appPath`;
5. the bundle id the issuer registered with (`POST /v1/register`, `bundleId`);
6. the application named like the manifest's `appName` (looked for as `<appName>.app` in `/Applications`,
   `/Applications/Utilities`, `/System/Applications` and `~/Applications`).

An action with neither `bundleId` nor `path` therefore opens the **issuing application**. If none of them
resolves, nothing happens: the banner stays, shows "Action failed - no installed application found", and History
keeps the note "<label>: no installed application found" next to the item. `validate_template` reports the same
case as a **warning** (it is not an error: the template may be written for another Mac).

Where it can be written:

| Place | Form |
|---|---|
| Template rule | `{"add":{"id":"open-ww","label":"Open WebWatcher","kind":"openApp"}}` (MCP: `add_action_rule`) |
| Manifest action (issuer) | `{"id":"open","label":"Open WebWatcher","kind":"openApp"}` with optional `bundleId` / `path`; the manifest also takes `appBundleId` and `appPath` |
| Payload button (issuer) | `{"label":"Open","openApp":{"bundleId":"com.apple.mail"}}` |
| Banner click | template option `"onClick": "openApp"` (default `"url"`: open the notification's link) |
| Designer | Actions tab > Add action > Open app (bundle id and path fields, "Choose app..." picker); the action editor offers it for any action |

Every process action gets a 30 second timeout (SIGTERM, then SIGKILL two seconds later) and its output goes to
`~/Library/Logs/Herald/actions.log` (one backup generation). A second click on a banner whose action is still
running is ignored. A failure shows "Action failed" in the banner with a short reason.

## Issuer actions and template actions

- **Issuer actions** come from the notification (`actions`, alias `buttons`) or from the manifest by id
  (`actionIds`). They can only be `url`, `callback`, `command`, `openApp` or `dismiss`.
- **Template actions** are yours: `script`, `shortcut`, `snooze`, and `command`/`url`/`dismiss` too. They come
  from `actionRules[].add`, from an inline `action` on a `button`, `iconButton` or `rive` component, and from
  the template's legacy `buttons`.

Each resolved action carries an **origin** (`issuer` or `template`) that decides its gate.

## The resolved list

```
issuer actions (payload buttons, or the manifest's actions named by actionIds)
+ the built-in snooze action, when the notification has "snooze": true
-> through actionRules, in order
= resolved actions
```

Which actions a notification offers, in order of precedence (`ActionResolver.issuerSource`):

1. `buttons` (the server folds the payload alias `actions` into it; `buttons` wins when both are sent). An
   explicit empty array means "no buttons".
2. Otherwise each id of `actionIds`, looked up in the manifest by its declared id (case-insensitive; unknown ids
   are skipped).
3. Otherwise none. **The manifest's actions are never shown just because the manifest declares them.** A sample
   preview (the Designer, `render_preview`, `POST /v1/preview` with sample data) stands in for an issuer that
   names every declared action; a preview of real data shows only what that data sends.

A button the notification sends with the same label as a manifest action takes that action's declared id, so a
rule can say `"match":"markRead"`.

## Rules (`actionRules`)

Applied in order to the resolved list.

| Rule | Effect |
|---|---|
| `match` | Selects actions by id or label (case-insensitive), or `"*"` for all. |
| `hide: true` | Removes the matched actions. |
| `relabel` | New label for the matched actions. |
| `style` | New style: `normal`, `prominent`, `destructive` (asks for confirmation before running), `cancel`; `default` means `normal`. An empty string clears it. |
| `position` | Moves the matched actions to this 0-based index (clamped). |
| `symbol` | **1.3.** Gives the matched actions an SF Symbol (a name or an object). With `"placement":"only"` (**1.8**) the button is the icon alone and the label is dropped. |
| `add` | Appends a new template-owned action (at `position` when the rule has no `match`). An action with an existing id replaces that action (keeping its place unless `position` is given). |

A rule needs a `match` or an `add`. `hide` makes the other change fields pointless (the validator warns). A
`match` that matches nothing does nothing. Examples:

```json
{"match":"markRead","hide":true}
```

```json
{"match":"archive","relabel":"Archive it","style":"destructive","position":0}
```

```json
{"add":{"id":"followup","label":"Follow up","kind":"shortcut","shortcut":"Create follow-up","input":"{title}\n{url}"}}
```

An added action with the id of one of the issuer's own **replaces** that button; the confirmation prompt says
so and that the issuer will not hear about the press.

### The look of one action (1.8)

Each action has its own look, so buttons that share a cell can have different icons. For an issuer's action, a rule sets it; for an action
you added, `symbol` goes on the action. `placement: "only"` makes an icon-only button; the label stays the tooltip and what VoiceOver reads.

```json
{"actionRules":[
  {"match":"markRead","symbol":{"name":"checkmark.circle","placement":"only"}},
  {"add":{"id":"archive","label":"Archive","kind":"command","command":"/usr/local/bin/archive",
          "symbol":{"name":"archivebox","placement":"only"}}}
]}
```

In the Designer, every row of the Actions tab has **Shows** (Text, Icon and text, Icon only) and an icon picker with the full symbol styling.
The reset arrow of a row also undoes an icon change. The form for adding an action has the same **Shows** choice, and an Icon only
action needs no label. Text only is no `symbol`.

### Where actions appear

- The `actions` component lists the resolved list from a `source` ([components/actions.md](components/actions.md)).
- `button` and `iconButton` show one action by `actionRef`, or an inline action ([components/button.md](components/button.md)).
- `rive` runs one on click ([components/rive.md](components/rive.md)).
- The banner body, when clicked, opens the notification's `url` (http, https, mailto only). A click never dismisses a banner that has
  no link: cut-short text expands instead, and the close button dismisses ([Clicking a banner](api.md#clicking-a-banner)).

## Confirmation gates

Nothing runs on delivery: actions run only when a person presses a button. Code that runs on this Mac needs
agreement first (`ActionRunner.gate`):

| Origin | Kind | Gate |
|---|---|---|
| issuer | `command`, `script`, `shortcut` | The app's **command permission**: the app must have registered `allowCommands: true` **and** the user confirmed it (Settings > Apps, or "Always allow" on the first press). |
| template | `command`, `script`, `shortcut` | One confirmation **per template**, bound to exactly what was shown (below). |
| any | `url`, `dismiss`, `snooze` | None. |
| issuer | `callback` | None for a loopback callback URL; a non-loopback host needs approval. |

The question is drawn **inside the banner** as a row replacing the action row, never as a modal alert (a modal
would activate Herald and take the keyboard from the app you are in). Its buttons:

| Confirmation | Primary | Secondary | |
|---|---|---|---|
| `callbackHost` ("Send X's button action to HOST?") | Send once | Always allow HOST | Cancel |
| `command`, `script`, `shortcut` for an issuer | Run once | Always allow APP | Cancel |
| `templateCommand` ("Run a command from the TEMPLATE template?") | Run once | Always allow this template | Cancel |
| `remindersError`, `remindersDenied` | OK | Open Privacy Settings (denied only) | |

The exact command, script (name, SHA-256 and the start of its text) or Shortcut (name and input) is shown
verbatim in a monospaced box. "Always allow this template" is bound to what was shown: if a command is edited,
a script file's hash changes, or a Shortcut's name or input changes, Herald asks again. It also covers every
other piece of code in the same template. Approvals are stored in
`~/Library/Application Support/Herald/template-approvals.json`.

Draw one without driving the UI: `POST /v1/preview` takes `"confirmation"` (a kind, or an object with `kind`,
`name`, `host`, `url`, `command`, `template`, `others`, `replaces`, `message`).

## What an action receives

Every action gets the **merged payload**:

```json
{"app":"webwatcher.email","id":"inbox",
 "action":{"id":"followup","label":"Follow up","kind":"shortcut"},
 "fields":{"title":"2 new from Acme","count":2,"customer.name":"Acme"},
 "extra":{"queue":"inbox"},
 "notification":{"app":"webwatcher.email","title":"2 new from Acme","metadata":{}}}
```

(`fields` are the resolved tokens, `extra` the template's `extra`, `notification` the full payload; the runner
also adds the template name and the cached image path.) Where it goes:

| Kind | Delivery |
|---|---|
| `command` | JSON on stdin, plus environment variables. |
| `script` | JSON on stdin, plus the same environment variables. Prefer a script over a `command` for text from untrusted senders (an email subject can contain anything). |
| `shortcut` | `input` text, else the JSON, in a temp file passed as `--input-path`. |
| `callback` | The issuer's own `payload` is kept; the template's `extra` is added under `payload.extra` when the payload is an object (or absent) and does not use that key itself. |

Environment variables (at most 100, 4 KB each): `HERALD_APP`, `HERALD_NOTIFICATION_ID`, `HERALD_ACTION` (the
label), `HERALD_ACTION_ID`, `HERALD_ACTION_KIND`, `HERALD_ORIGIN` (`issuer` or `template`), `HERALD_TEMPLATE`, then
`HERALD_FIELD_<NAME>` for each field and `HERALD_EXTRA_<KEY>` for each `extra` value (names upper-cased, anything
not alphanumeric becomes `_`).

## Callbacks

`POST` body: `{"notificationId","app","action":"<label>","payload":...}` to `callback.url`, else the app's
registered `callbackURL`. Answer 2xx once the action has happened: Herald dismisses the banner. Any other status
keeps the banner and shows "Action failed". The budget is 5 seconds per attempt, with one retry after a short
pause for transport errors and 408, 429 and 5xx; other 4xx are final. The URL must be on this Mac (`127.0.0.1`,
`::1`, `localhost`) unless the user approved its host; redirects are never followed.

## Scripts folder

`~/Library/Application Support/Herald/scripts/` (created at launch; `herald_status` lists it). A script action
names a file by its relative name. Files outside the folder are refused. A symlink you place inside the folder
is yours to follow. `herald_status` and the Designer list the folder; `add_action_rule` warns when the file is
missing.

## Apple Shortcuts

`GET /v1/shortcuts` and MCP `list_shortcuts` return the names from `shortcuts list`; the Designer has a
"Run shortcut..." picker. Text input goes to the Shortcut's "Receive input from" action; JSON arrives as a
file.

## Security summary

- Nothing runs on delivery.
- The MCP can create and edit templates and actions but cannot press a button, and `send_notification` refuses
  `command` buttons unless `allowCommandButtons` is true.
- Issuer code needs the app's command permission; template code is confirmed once per template and bound to
  its exact text, hash or name.
- Scripts live under the scripts folder only; data reaches them on stdin.
- Link actions open only http, https and mailto.

## Common mistakes

| Mistake | What happens | Fix |
|---|---|---|
| Sending `{"kind":"shortcut"}` from an issuer | Rejected: only `url`, `callback`, `command`, `dismiss` are issuer kinds. | Add it in the template with an `add` rule. |
| Expecting `{command}` text to receive field values | The command is not interpolated. | Read `$HERALD_FIELD_TITLE` or stdin JSON. |
| A script path like `../x.sh` or `/tmp/x.sh` | Refused: "script must be a file inside the scripts folder". | Put the file in the scripts folder. |
| `snoozeMinutes: 0` or 20000 | Validation error (1 to 10080). | Stay in range. |
| Two `add` rules with one id | The later replaces the earlier. | Use distinct ids. |
| `hide` plus `relabel` in one rule | `relabel` has no effect (warning). | Use separate rules. |
