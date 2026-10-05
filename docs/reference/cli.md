# Command line tool

`herald` is a command line tool that sends notifications to Herald and controls it from a shell. It is a thin client
over the [HTTP API](api/README.md): it finds the running app, adds the bearer token, sends one request and prints the
reply. Use it from scripts, cron jobs, build steps and terminals where writing a `curl` command is more work than
the task. Every command below names the endpoint it calls, so the API reference documents the fields in full.

## Install the tool

The tool ships inside Herald.app at `Herald.app/Contents/Helpers/herald`. To put it on your shell path:

1. Open Herald's **Settings** and choose the **MCP** tab.
2. Press **Install `herald` command line tool**.
3. If macOS asks for an administrator password, enter it. The tool is copied to `/usr/local/bin/herald`, which
   needs it when that folder is not writable by you.

Check the result in a terminal:

```sh
herald health
```

```json
{
  "ok" : true,
  "pid" : 69080,
  "version" : "1.8.1"
}
```

`herald health` prints the version of the running app. Building from source with `make install-cli` installs the same tool:

- to `/usr/local/bin`, or
- to `~/bin` when `/usr/local/bin` is not writable.

![Herald Settings on the MCP tab with the button that installs the command line tool](../../web/public/shots/docs/settings-mcp.png "The MCP tab: the button for the command line tool sits next to the MCP server installers.")

## How the tool finds Herald

Herald writes its port and bearer token to its support folder, `~/Library/Application Support/Herald/`, in the files
`port` and `token`. The tool reads them on every call, so you never pass them by hand. If the port file is missing,
the tool uses port `48617`.

Replies are JSON. The tool prints them pretty-printed with sorted keys. Commands that write a file (`template export`,
`template import`) print one line of text instead.

## Global options

Global options work in front of or after any command.

| Option | Type | Description |
|---|---|---|
| `--port N` | integer | The port to call. A number from 1 to 65535. `--port=N` works too. Default: the `port` file in the support folder, else `48617`. |
| `--token T` | string | The bearer token. Default: the `token` file. Prefer the file, because a flag shows up in the output of `ps`. |
| `--json FILE` | path | A JSON object to use as the request body, or `-` to read it from standard input. Other flags are merged on top of it. Only `notify` and `register` take it. |
| `-h`, `--help` | flag | Print the usage text. `herald help <command>` prints the same text. |
| `--version` | flag | Print `herald 1.1.0`. The string is fixed in the tool; `herald health` reports the app's own version. |

Every value option also accepts the form `--option=value`.

`HERALD_SUPPORT_DIR` is an environment variable, not an option. It points the tool at another Herald's support
folder, such as the [second instance used for testing](../TESTING.md#run-a-second-instance-of-herald).

## Exit codes

| Code | Meaning |
|---|---|
| `0` | The request succeeded. The reply is on standard output. |
| `1` | The command line was wrong, or Herald answered with an HTTP error. The output of each case is listed under the table. |
| `2` | Herald is not running. The tool prints `Herald is not running. Launch Herald.app first.` to standard error. |

What a failure with code `1` prints:

- A usage error prints `herald: <message>` and `Try 'herald --help'.` to standard error.
- An HTTP error prints Herald's reply to standard output.
- A `401` adds `herald: unauthorized (check the token file or --token)` to standard error.

A script can wait for Herald to start:

```sh
until herald health >/dev/null 2>&1; do sleep 1; done
```

## Commands

| Command | What it does |
|---|---|
| [`herald notify`](#herald-notify) | Show a notification. |
| [`herald register`](#herald-register) | Register or update an app. |
| [`herald speak`](#herald-speak) | Say text aloud with no banner. |
| [`herald compose`](#herald-compose) | Open the Composer window. |
| [`herald snooze`](#herald-snooze) | Hide a banner and bring it back later. |
| [`herald unsnooze`](#herald-unsnooze) | Bring a snoozed banner back now. |
| [`herald dismiss`](#herald-dismiss) | Close one banner. |
| [`herald dismiss-all`](#herald-dismiss-all) | Close every banner of an app, or one stack. |
| [`herald stacks`](#herald-stacks) | List the stacks on screen. |
| [`herald quiet`](#herald-quiet) | Start quiet hours for a while. |
| [`herald quiet status`](#herald-quiet-status) | Show whether quiet hours are active. |
| [`herald quiet off`](#herald-quiet-off) | End the current quiet period. |
| [`herald history`](#herald-history) | Show or clear an app's History. |
| [`herald history search`](#herald-history-search) | Search History. |
| [`herald history reshow`](#herald-history-reshow) | Show a past notification again. |
| [`herald history delete`](#herald-history-delete) | Delete one History item. |
| [`herald history export`](#herald-history-export) | Export History as JSON. |
| [`herald template list`](#herald-template-list) | List saved templates. |
| [`herald template put`](#herald-template-put) | Save a template from a JSON file. |
| [`herald template delete`](#herald-template-delete) | Delete a template. |
| [`herald template duplicate`](#herald-template-duplicate) | Copy a template. |
| [`herald template rename`](#herald-template-rename) | Rename a template. |
| [`herald template default`](#herald-template-default) | Set or clear an app's default template. |
| [`herald template export`](#herald-template-export) | Write a template and its animations to a bundle file. |
| [`herald template import`](#herald-template-import) | Add a bundle file's template and animations. |
| [`herald manifest delete`](#herald-manifest-delete) | Delete an app's manifest. |
| [`herald apps`](#herald-apps) | List registered apps. |
| [`herald apps settings`](#herald-apps-settings) | Show per-app settings. |
| [`herald apps set`](#herald-apps-set) | Change per-app settings. |
| [`herald approvals`](#herald-approvals) | List template command approvals. |
| [`herald approvals revoke`](#herald-approvals-revoke) | Withdraw a template command approval. |
| [`herald settings`](#herald-settings) | Show Herald's settings. |
| [`herald settings set`](#herald-settings-set) | Change Herald's settings. |
| [`herald assets list`](#herald-assets-list) | List an app's Rive files and images. |
| [`herald assets add`](#herald-assets-add) | Add a Rive file or an image to an app. |
| [`herald assets rm`](#herald-assets-rm) | Remove a Rive file or an image. |
| [`herald symbols`](#herald-symbols) | Search SF Symbol names. |
| [`herald voice`](#herald-voice) | Show or manage the Kokoro voice engine. |
| [`herald mcp`](#herald-mcp) | Show or install the MCP server in a client. |
| [`herald health`](#herald-health) | Check that Herald is running. |

The tool has no command that saves a manifest or reads the component schema. Use the
[API](api/manifests.md#put-v1manifest), the [MCP server](mcp/README.md) or the Designer for those. No command grants an
approval for buttons that run commands or call back: only the person at the Mac does that, in Settings.

## Sending

### `herald notify`

Shows a notification as a banner and stores it in History. Sending the same `--id` again replaces the banner in place. There are three ways to give the content:

- `--app` and `--title`.
- `--app` and `--template`, when the template supplies the title.
- The whole notification as JSON with `--json`. Flags are merged on top of the JSON.

**Options**

| Option | Type | Description |
|---|---|---|
| `--app ID` | string | The app id. Required, here or in `--json`. |
| `--id ID` | string | Your id for the notification. Reusing an id replaces the banner on screen. |
| `--title T` | string | The headline. Required unless `--template` is given. |
| `--subtitle T` | string | A second line under the title. |
| `--body T` | string | The main text. |
| `--image PATH\|URL\|data:` | string | A picture: a file path, an `https` URL or a `data:` URI. |
| `--url URL` | string | A link the banner opens when clicked. |
| `--group G` | string | The stack key. Banners of one app with the same group fold into one [stack](stacking.md). |
| `--sound NAME\|PATH\|none` | string | The sound to play, a file, or `none`. |
| `--timeout SECONDS` | number | Seconds before the banner closes itself. `0` keeps it until it is closed. |
| `--persistent`, `--no-persistent` | flag | Keep the banner until it is closed, or not. |
| `--snooze`, `--no-snooze` | flag | Show the snooze menu on the banner, or hide it. |
| `--priority P` | string | One of `low`, `normal`, `high`, `urgent`. `urgent` breaks quiet hours only for apps that allow it. |
| `--button "Label=target"` | string | Add a button. Repeat the option for more. See the targets below. |
| `--follow-up-after DURATION` | string | Run one action if the banner is still unattended after this long: seconds, or `90s`, `10m`, `2h`. From 5 seconds to 7 days. Give it with one of the next four options. |
| `--follow-up-shortcut NAME` | string | The follow-up runs this Apple Shortcut. |
| `--follow-up-script FILE` | string | The follow-up runs this file from Herald's scripts folder. |
| `--follow-up-command CMD` | string | The follow-up runs this shell command. |
| `--follow-up-ref ID` | string | The follow-up runs the action of this id, or label, that the notification offers. |
| `--follow-up-input TEXT` | string | Text for the Shortcut or script, with `{tokens}` filled. Not valid with a command or a reference. |
| `--reminder "Title\|ISO8601"` | string | Add an Add-to-Reminders action. The text is split on the last `\|`; a bare string is only a title. |
| `--metadata JSON` | JSON | An object of extra values. Templates read it for their `{tokens}`. |
| `--template NAME` | string | A saved template for this app. |
| `--layout L` | string | One of `imageLeft`, `imageRight`, `hero`, `compact`. |
| `--accent #RRGGBB` | string | The accent colour for the title, buttons and links. |
| `--no-subtitle`, `--no-body`, `--no-time` | flag | Hide the subtitle, the body or the timestamp. |
| `--max-body-lines N` | integer | The most body lines to show. A positive integer. |
| `--speak` | flag | Say the title, then the body, aloud. |
| `--speak-text T` | string | Say `T` instead of the title and body. |
| `--voice NAME` | string | The voice to speak with. |
| `--speed N` | number | Speaking speed, from `0.5` to `2.0`. |
| `--lang L` | string | The language code, such as `en-us`. |
| `--audio PATH\|URL\|data:` | string | A recorded voice message to play. At most 20 MB. |
| `--presentation P` | string | One of `banner`, `voice`, `both`. `voice` speaks without a banner and keeps the History entry. |

The `--button` target decides what the button does:

| Target form | What the button does |
|---|---|
| `Label=https://example.com` | Opens the URL. |
| `Label=cmd:shell command` | Runs the command. The app must be allowed to run commands, scripts and Shortcuts. |
| `Label=script:file.sh` | Runs a file from Herald's scripts folder. The app must be allowed to run commands, scripts and Shortcuts. |
| `Label=shortcut:Name` | Runs an Apple Shortcut. The app must be allowed to run commands, scripts and Shortcuts. |
| `Label=cb:{"k":1}` | Sends the JSON as the payload of a callback to the app's callback URL. `cb:` alone sends an empty payload. |

The speech options build the notification's `speak` field. See [Voice](voice.md) for the field and its limits.

The follow-up options build the notification's `followUp` object. How a follow-up works is in
[Follow-ups](actions.md#follow-ups).

**Example**

```sh
herald notify --app example.bidbot --id bid-42 \
  --title "Bid accepted" --body "Your bid of \$4,200 was accepted" \
  --url "https://example.com/bids/42" \
  --button "Open=https://example.com/bids/42" --sound Glass --snooze
```

**Output**

```json
{
  "id" : "bid-42",
  "ok" : true
}
```

The same notification from JSON on standard input:

```sh
echo '{"app":"example.bidbot","title":"Bid accepted","buttons":[{"label":"Open","url":"https://example.com/bids/42"}]}' \
  | herald notify --json -
```

**Exit status**

- `1` with `herald: notify needs --app` or `herald: notify needs --title (or --template)` when those are missing.
- `1` and Herald's error when it rejects the notification.

**HTTP route**

[`POST /v1/notify`](api/notifications.md#post-v1notify)

### `herald register`

Registers an app, or updates one that exists: its name, icon, callback address and default banner settings. You do not
have to register an app before it sends, because Herald registers an unknown id on its first notification. Register
when you want a proper name and icon, a callback URL, or defaults.

**Options**

| Option | Type | Description |
|---|---|---|
| `--app ID` | string | The app id. Required, here or in `--json`. |
| `--name NAME` | string | The name shown on banners (`appName`). |
| `--icon PATH\|data:` | string | The app's icon: a file path or a `data:` URI. |
| `--bundle-id ID` | string | The app's bundle identifier, used by actions that open the app. |
| `--callback-url URL` | string | Where Herald sends the payload of a callback button. |
| `--allow-commands`, `--no-allow-commands` | flag | Ask to let the app's buttons run commands. This is a request: the person confirms it in Settings. |
| `--sound NAME` | string | The default sound for the app's banners. |
| `--timeout S` | number | The default timeout in seconds. |
| `--persistent`, `--no-persistent` | flag | The default for keeping banners until they are closed. |
| `--corner C` | string | Where the app's banners appear: `topRight`, `topLeft`, `bottomRight` or `bottomLeft`. |
| `--json FILE\|-` | path | A base JSON object. The flags above are merged on top. |

**Example**

```sh
herald register --app example.bidbot --name BidBot --icon ~/Pictures/bidbot.png \
  --callback-url http://127.0.0.1:5123/herald --sound Glass --corner topRight
```

**Output**

```json
{
  "ok" : true
}
```

**Exit status**

`1` with `herald: register needs --app` when the app id is missing.

**HTTP route**

[`POST /v1/register`](api/apps.md#post-v1register)

### `herald speak`

Says text aloud with no banner. The text is still stored in History. Use it when a spoken message is all you need.

**Options**

| Option | Type | Description |
|---|---|---|
| `--app ID` | string | The app id. Required. |
| `--text T` | string | What to say. Required. |
| `--voice NAME` | string | The voice to use. |
| `--speed N` | number | Speaking speed, from `0.5` to `2.0`. |
| `--lang L` | string | The language code, such as `en-us`. |
| `--id ID` | string | Your id for the notification. |

**Example**

```sh
herald speak --app example.bidbot --text "Deploy finished" --speed 1.1
```

**Output**

```json
{
  "id" : "7C1D0E52-3F0B-4B8E-9A55-0F3A1C0D2E11",
  "ok" : true
}
```

**HTTP route**

[`POST /v1/speak`](api/notifications.md#post-v1speak)

### `herald compose`

Opens the Composer window in Herald, where a person fills in a notification by hand and sends it. It takes no options.

**Example**

```sh
herald compose
```

**Output**

```json
{
  "ok" : true
}
```

**HTTP route**

[`POST /v1/compose`](api/notifications.md#post-v1compose)

## Closing and snoozing banners

### `herald snooze`

Hides a banner and shows it again after a number of minutes. The banner keeps its id.

**Options**

| Option | Type | Description |
|---|---|---|
| `--app ID` | string | The app id. Required. |
| `--id ID` | string | The notification id. Required. |
| `--minutes N` | number | How long to hide it. Required. Greater than 0 and at most 43200; fractions are allowed. |

**Example**

```sh
herald snooze --app example.bidbot --id bid-42 --minutes 15
```

**Output**

```json
{
  "ok" : true,
  "until" : "2026-10-02T13:15:00.000Z"
}
```

**Exit status**

- `1` and `herald: --minutes needs a number greater than 0 and at most 43200` for a value outside that range.
- `1` and Herald's `404` when the notification is unknown.

**HTTP route**

[`POST /v1/snooze`](api/notifications.md#post-v1snooze)

### `herald unsnooze`

Brings a snoozed banner back now, without waiting for the time to pass.

**Options**

| Option | Type | Description |
|---|---|---|
| `--app ID` | string | The app id. Required. |
| `--id ID` | string | The notification id. Required. |

**Example**

```sh
herald unsnooze --app example.bidbot --id bid-42
```

**Output**

```json
{
  "ok" : true
}
```

**HTTP route**

[`POST /v1/unsnooze`](api/notifications.md#post-v1unsnooze)

### `herald dismiss`

Closes one banner. The notification stays in History. Use it when the event behind a banner is over.

**Options**

| Option | Type | Description |
|---|---|---|
| `--app ID` | string | The app id. Required. |
| `--id ID` | string | The notification id. Required. |

**Example**

```sh
herald dismiss --app example.bidbot --id bid-42
```

**Output**

```json
{
  "ok" : true
}
```

**HTTP route**

[`POST /v1/dismiss`](api/notifications.md#post-v1dismiss)

### `herald dismiss-all`

Closes every banner of an app, or only the banners of one stack. The spelling `dismissAll` also works.

**Options**

| Option | Type | Description |
|---|---|---|
| `--app ID` | string | The app id. Required. |
| `--group G` | string | Close only the banners sent with this group. |

**Example**

```sh
herald dismiss-all --app example.bidbot --group "acme"
```

**Output**

```json
{
  "ok" : true
}
```

**HTTP route**

[`POST /v1/dismissAll`](api/notifications.md#post-v1dismissall)

### `herald stacks`

Lists the stacks of banners that are on screen, with the banners in each. See [Stacking](stacking.md) for what a stack
is.

**Options**

| Option | Type | Description |
|---|---|---|
| `--app ID` | string | Only the stacks of this app. Default: every app. |

**Example**

```sh
herald stacks --app example.bidbot
```

**Output**

```json
{
  "stacks" : [

  ]
}
```

The list is empty when no stack is on screen.

**HTTP route**

[`GET /v1/stacks`](api/stacks.md#get-v1stacks)

## Quiet hours

Quiet hours silence speech and sounds, and optionally banners, for a stretch of time. The weekly schedule is set in
Settings. The commands here start and end a one-off quiet period. [Quiet hours](quiet-hours.md) explains the rules.

### `herald quiet`

Starts a quiet period that ends at a clock time, or after a number of minutes. Give exactly one of `--until` and
`--for`.

**Options**

| Option | Type | Description |
|---|---|---|
| `--until HH:MM` | string | End at this time, in 24-hour form with two-digit minutes, such as `07:30`. |
| `--for MINUTES` | number | End after this many minutes. |
| `--banners` | flag | Silence banners as well. Without it, only speech and sounds are silenced. |

**Example**

```sh
herald quiet --for 60 --banners
```

**Output**

The reply is the quiet-hours state after the change.

**Exit status**

- `1` and `herald: quiet needs exactly one of --until HH:MM or --for MINUTES (or off, status)` when both or neither are given.
- `1` and `herald: --until needs a time such as 07:30` for a malformed time.

**HTTP route**

[`PUT /v1/settings/quiet-hours`](api/settings.md#put-v1settingsquiet-hours)

### `herald quiet status`

Shows whether quiet hours are active now, and the weekly windows that are set.

**Example**

```sh
herald quiet status
```

**Output**

```json
{
  "status" : {
    "active" : false,
    "banners" : false,
    "sounds" : false,
    "speech" : false
  },
  "windows" : [
    {
      "banners" : false,
      "days" : [

      ],
      "end" : "06:00",
      "id" : "window-1",
      "sounds" : true,
      "speakSummary" : false,
      "speech" : true,
      "start" : "22:30"
    }
  ]
}
```

**HTTP route**

[`GET /v1/settings/quiet-hours`](api/settings.md#get-v1settingsquiet-hours)

### `herald quiet off`

Ends the current quiet period now, including one started by `herald quiet`.

**Example**

```sh
herald quiet off
```

**Output**

The reply is the quiet-hours state after the change, in the shape described under [`PUT /v1/settings/quiet-hours`](api/settings.md#put-v1settingsquiet-hours).

**HTTP route**

[`PUT /v1/settings/quiet-hours`](api/settings.md#put-v1settingsquiet-hours) with `{"resume": true}`.

## History

[History](../APP.md#history) is the record of every notification Herald has shown.

### `herald history`

Shows the notifications Herald stored for one app, newest first, or clears them.

**Options**

| Option | Type | Description |
|---|---|---|
| `--app ID` | string | The app id. Required. |
| `--limit N` | integer | The most items to return. A positive integer. Default: `50`. |
| `--clear` | flag | Delete the app's History instead of showing it. |

**Example**

```sh
herald history --app example.bidbot --limit 10
```

**Output**

```json
{
  "items" : [

  ]
}
```

The list is empty when the app has sent nothing. Each item is the full record of one notification.

**HTTP route**

[`GET /v1/history`](api/history.md#get-v1history) to show.

[`DELETE /v1/history`](api/history.md#delete-v1history) with `--clear`.

### `herald history search`

Finds notifications that match the words you give. The words are separate arguments, with no quotes needed.

**Options**

| Option | Type | Description |
|---|---|---|
| `WORDS` | string | One or more words to find. Required. They come first, before any option. |
| `--app ID` | string | Search only this app. Default: every app. |
| `--limit N` | integer | The most items to return. |

**Example**

```sh
herald history search invoice paid --app example.bidbot --limit 20
```

**Output**

```json
{
  "count" : 0,
  "items" : [

  ],
  "query" : "invoice paid"
}
```

**HTTP route**

[`GET /v1/history/search`](api/history.md#get-v1historysearch)

### `herald history reshow`

Shows a past notification again as a new banner.

**Options**

| Option | Type | Description |
|---|---|---|
| `--app ID` | string | The app id. Required. |
| `--id ID` | string | The id of the notification in History. Required. |

**Example**

```sh
herald history reshow --app example.bidbot --id bid-42
```

**Output**

```json
{
  "id" : "bid-42",
  "ok" : true
}
```

**Exit status**

`1` and Herald's `404` (`no such notification in History`) when the id is not in History.

**HTTP route**

[`POST /v1/history/reshow`](api/history.md#post-v1historyreshow)

### `herald history delete`

Deletes one item from History.

**Options**

| Option | Type | Description |
|---|---|---|
| `--app ID` | string | The app id. Required. |
| `--id ID` | string | The id of the notification. Required. |

**Example**

```sh
herald history delete --app example.bidbot --id bid-42
```

**Output**

```json
{
  "ok" : true
}
```

**HTTP route**

[`DELETE /v1/history/item`](api/history.md#delete-v1historyitem)

### `herald history export`

Exports History as JSON. With `--out`, Herald writes the file and the command prints how many items it wrote. Without
it, the items are printed.

**Options**

| Option | Type | Description |
|---|---|---|
| `--app ID` | string | Export only this app. Default: every app. |
| `--out FILE` | path | Where to write the export. The name must end in `.json` and the folder must exist. `-o` also works. |

**Example**

```sh
herald history export --app example.bidbot --out ~/Desktop/bidbot.json
```

**Output**

```json
{
  "bytes" : 2048,
  "count" : 12,
  "path" : "/Users/you/Desktop/bidbot.json"
}
```

**HTTP route**

[`GET /v1/history/export`](api/history.md#get-v1historyexport)

## Templates and manifests

A [template](../TEMPLATES.md) is the saved layout of an app's banners. A manifest declares what an app sends.

### `herald template list`

Lists the saved templates of an app.

**Options**

| Option | Type | Description |
|---|---|---|
| `--app ID` | string | The app id. Default: every app. |

**Example**

```sh
herald template list --app example.bidbot
```

**Output**

```json
{
  "items" : [

  ]
}
```

**HTTP route**

[`GET /v1/templates`](api/templates.md#get-v1templates)

### `herald template put`

Saves one template from a JSON file. Herald validates it first and refuses a template with an error, naming the cell.

**Options**

| Option | Type | Description |
|---|---|---|
| `FILE` | path | A file holding one template object. `-` reads standard input. Required. |

**Example**

```sh
herald template put bid-accepted.json
```

**Output**

```json
{
  "ok" : true
}
```

**Exit status**

`1` and Herald's `400` (`invalid template: ...`) when validation fails.

**HTTP route**

[`PUT /v1/templates`](api/templates.md#put-v1templates)

### `herald template delete`

Deletes a template.

**Options**

| Option | Type | Description |
|---|---|---|
| `--app ID` | string | The app id. Required. |
| `--name NAME` | string | The template name. Required. |

**Example**

```sh
herald template delete --app example.bidbot --name bid-accepted
```

**Output**

```json
{
  "ok" : true
}
```

**HTTP route**

[`DELETE /v1/templates`](api/templates.md#delete-v1templates)

### `herald template duplicate`

Copies a template, in the same app or into another one.

**Options**

| Option | Type | Description |
|---|---|---|
| `--app ID` | string | The app that owns the template. Required. |
| `--name NAME` | string | The template to copy. Required. |
| `--new-name M` | string | The name of the copy. Default: Herald picks a free name. |
| `--to-app ID` | string | Copy into this app instead. Default: the same app. |

**Example**

```sh
herald template duplicate --app example.bidbot --name bid-accepted --new-name bid-won
```

**Output**

```json
{
  "app" : "example.bidbot",
  "copiedFrom" : {
    "app" : "example.bidbot",
    "name" : "bid-accepted"
  },
  "name" : "bid-won",
  "ok" : true
}
```

**HTTP route**

[`POST /v1/templates/duplicate`](api/templates.md#post-v1templatesduplicate)

### `herald template rename`

Renames a template. If it was the app's default, it stays the default under the new name.

**Options**

| Option | Type | Description |
|---|---|---|
| `--app ID` | string | The app id. Required. |
| `--name NAME` | string | The current name. Required. |
| `--new-name M` | string | The new name. Required. |

**Example**

```sh
herald template rename --app example.bidbot --name bid-won --new-name bid-accepted
```

**Output**

The reply names the new name and the old one, and carries a note that approvals belong to the old name. The fields are under [`POST /v1/templates/rename`](api/templates.md#post-v1templatesrename).

**HTTP route**

[`POST /v1/templates/rename`](api/templates.md#post-v1templatesrename)

### `herald template default`

Sets the template Herald uses when a notification names none, or clears it. Give `--name` or `--clear`, not both.

**Options**

| Option | Type | Description |
|---|---|---|
| `--app ID` | string | The app id. Required. |
| `--name NAME` | string | The template to make the default. |
| `--clear` | flag | Remove the default, so the built-in layout is used. |

**Example**

```sh
herald template default --app example.bidbot --name bid-accepted
```

**Output**

```json
{
  "app" : "example.bidbot",
  "defaultTemplate" : "bid-accepted",
  "ok" : true
}
```

**HTTP route**

[`PUT /v1/templates/default`](api/templates.md#put-v1templatesdefault)

### `herald template follow-up`

Sets, or switches off, the follow-up of an app's template: one action that runs when a banner is left unattended. The
command edits the template. With no `--name` it uses the app's default template, and creates one from the current
layout when the app has none. It prints whether the action still needs your one-time approval. It never approves
code: you approve at the Mac, in the banner's question.

**Options**

| Option | Type | Description |
|---|---|---|
| `--app ID` | string | The app id. Required. |
| `--name TEMPLATE` | string | The template to edit. Default: the app's default template. |
| `--after DURATION` | string | How long the banner goes unanswered first: seconds, or `90s`, `10m`, `2h`. From 5 seconds to 7 days. |
| `--shortcut NAME` | string | Run this Apple Shortcut. |
| `--script FILE` | string | Run this file from Herald's scripts folder. |
| `--command CMD` | string | Run this shell command. |
| `--action-ref ID` | string | Run the action of this id, or label, that the notification offers. |
| `--input TEXT` | string | Text for the Shortcut or script, with `{tokens}` filled. |
| `--label TEXT` | string | The name shown on the banner line **Follow-up ran: LABEL**. Default: the Shortcut or script name. |
| `--off` | flag | Switch the follow-up off, including one the issuer declares. Replaces `--after` and an action. |

Give one of `--shortcut`, `--script`, `--command` and `--action-ref` with `--after`, or give `--off`.

**Example**

```sh
herald template follow-up --app example.bidbot --name "Bid won" \
  --after 10m --shortcut "Forward to phone" --input "{title}"
```

**Output**

```json
{
  "saved": true,
  "app": "example.bidbot",
  "template": "Bid won",
  "createdTemplate": false,
  "followUp": {"after": 600, "action": {"id": "follow-up", "label": "Forward to phone",
                                       "kind": "shortcut", "shortcut": "Forward to phone"}},
  "action": {"id": "follow-up", "label": "Forward to phone", "kind": "shortcut"},
  "origin": "template",
  "approval": "needs-approval",
  "needsApproval": true,
  "note": "Saved. The follow-up will not run until the person approves this template's Shortcut at the Mac."
}
```

**Exit status**

- `1` with the message when the options are incomplete, such as `--after` without an action.
- `1` and Herald's error when it rejects the follow-up, for example for a kind that cannot follow up.

**HTTP route**

[`PUT /v1/templates/follow-up`](api/templates.md#put-v1templatesfollow-up)

### `herald template export`

Writes a template and the Rive files it plays into one `.heraldtemplate` bundle file, so it can move to another Mac.
See [Packaging with a template](rive.md#packaging-with-a-template-heraldtemplate) for what the bundle holds.

**Options**

| Option | Type | Description |
|---|---|---|
| `--app ID` | string | The app that owns the template. Required. |
| `--name NAME` | string | The template to export. Required. |
| `--out FILE` | path | Where to write the bundle. `-o` also works. Default: `<name>.heraldtemplate` in the current folder. |

**Example**

```sh
herald template export --app example.bidbot --name bid-accepted
```

**Output**

```text
Wrote /Users/you/bid-accepted.heraldtemplate (1 animation file)
```

Warnings go to standard error: a missing animation, and scripts and Shortcuts that stay behind.

**Exit status**

`1` and `herald: no template "NAME" for APP` when the template does not exist.

**HTTP routes**

The tool reads the template from [`GET /v1/templates`](api/templates.md#get-v1templates).

It reads the manifest, whose Rive files go in the bundle, from [`GET /v1/manifest`](api/manifests.md#get-v1manifest).
The tool writes the file itself.

### `herald template import`

Adds a bundle's template and animation files to Herald. Rive files go into the app's assets folder and never replace a
different file with the same name. Herald must be running, because the tool asks it to save the template.

**Options**

| Option | Type | Description |
|---|---|---|
| `FILE` | path | The bundle. Required. It may come first with no flag, or after `--file`. |
| `--app ID` | string | Import for this app instead of the app the bundle names. |
| `--keep-both` | flag | If the name is taken, save the new template as `NAME 2`, `NAME 3` and so on. This is the default. |
| `--replace` | flag | Overwrite the template that has the name. |
| `--fail` | flag | Stop with an error if the name is taken. |

Use at most one of `--keep-both`, `--replace` and `--fail`.

**Example**

```sh
herald template import bid-accepted.heraldtemplate --app example.bidbot --replace
```

**Output**

```text
Imported "bid-accepted" for example.bidbot; 0 new animation files, 1 already there
```

**Exit status**

The command exits with `1` in three cases:

- The file cannot be read.
- `--fail` is given and the name is taken.
- Herald refuses the template.

**HTTP routes**

The tool finds taken names with [`GET /v1/templates`](api/templates.md#get-v1templates).

It saves the template with [`PUT /v1/templates`](api/templates.md#put-v1templates).

### `herald manifest delete`

Deletes an app's manifest. The app, its History and its templates stay.

**Options**

| Option | Type | Description |
|---|---|---|
| `--app ID` | string | The app id. Required. |

**Example**

```sh
herald manifest delete --app example.bidbot
```

**Output**

```json
{
  "ok" : true
}
```

**HTTP route**

[`DELETE /v1/manifest`](api/manifests.md#delete-v1manifest)

## Apps and settings

Settings are written as `KEY=VALUE` words. Herald checks every key and applies all or none. The type of a value follows one rule:

- A value that parses as JSON keeps its type: `true`, `3`, `1.2`, `null`, a quoted string, an array or an object.
- Anything else is a string.

### `herald apps`

Lists the registered apps with their names, icons and defaults.

**Example**

```sh
herald apps
```

**Output**

```json
{
  "apps" : [
    {
      "app" : "example.bidbot",
      "appName" : "BidBot",
      "defaults" : {
        "sound" : "Glass"
      }
    }
  ]
}
```

**HTTP route**

[`GET /v1/apps`](api/apps.md#get-v1apps)

### `herald apps settings`

Shows the per-app settings, with the schema that lists every key and its allowed values.

**Options**

| Option | Type | Description |
|---|---|---|
| `--app ID` | string | Show one app. Default: every app. |

**Example**

```sh
herald apps settings --app example.bidbot
```

**Output**

The reply lists each app with its settings, voice and approvals, and a `schema` that describes every key. The fields are under [`GET /v1/apps/settings`](api/apps.md#get-v1appssettings).

**HTTP route**

[`GET /v1/apps/settings`](api/apps.md#get-v1appssettings)

### `herald apps set`

Changes per-app settings. The `KEY=VALUE` words may come before or after `--app`.

**Options**

| Option | Type | Description |
|---|---|---|
| `--app ID` | string | The app id. Required. |
| `KEY=VALUE` | string | One or more settings to change, such as `muteBanners=true` or `corner=bottomLeft`. Required. |

**Example**

```sh
herald apps set --app example.bidbot muteBanners=true corner=bottomLeft sound=Ping timeout=8
```

**Output**

The reply lists the keys it applied, `applied`, and the app's settings after the change.

**Notes**

- The command can withdraw an approval with `revokeCommands=true`. It cannot grant one: only the person at the Mac can.

**HTTP route**

[`PUT /v1/apps/settings`](api/apps.md#put-v1appssettings)

### `herald approvals`

Lists the approvals the person has given, such as the templates whose commands are allowed to run.

**Example**

```sh
herald approvals
```

**Output**

```json
{
  "items" : [

  ],
  "note" : "Approvals are granted by the user when a banner asks; here they can only be listed and revoked."
}
```

**HTTP route**

[`GET /v1/actions/approvals`](api/apps.md#get-v1actionsapprovals)

### `herald approvals revoke`

Withdraws the approval for one template's commands. The next time the template wants to run a command, the person is
asked again.

**Options**

| Option | Type | Description |
|---|---|---|
| `--app ID` | string | The app id. Required. |
| `--template NAME` | string | The template name. Required. |

**Example**

```sh
herald approvals revoke --app example.bidbot --template bid-accepted
```

**Output**

```json
{
  "ok" : true
}
```

**HTTP route**

[`DELETE /v1/actions/approvals`](api/apps.md#delete-v1actionsapprovals)

### `herald settings`

Shows Herald's own settings: their values, a schema that lists every key with its type and limits, and the choices
for keys that have a fixed list. `herald settings get` does the same.

**Example**

```sh
herald settings
```

**Output**

The reply holds the current `settings`, a `schema` that describes every key, and the `options` that a key accepts, such as the sound names. The fields are under [`GET /v1/settings`](api/settings.md#get-v1settings).

**HTTP route**

[`GET /v1/settings`](api/settings.md#get-v1settings)

### `herald settings set`

Changes Herald's settings.

**Options**

| Option | Type | Description |
|---|---|---|
| `KEY=VALUE` | string | One or more settings to change. Required. |

**Example**

```sh
herald settings set muteAllSounds=true stacking=bySender voiceSpeed=1.2
```

**Output**

The reply is the settings after the change, with `applied` listing the keys that changed.

**Exit status**

Both failures exit with `1`:

- A word with no `=` prints `herald: 'WORD' is not KEY=VALUE`.
- An unknown key or a value out of range prints Herald's `400`, and nothing is applied.

**HTTP route**

[`PUT /v1/settings`](api/settings.md#put-v1settings)

## Assets and symbols

### `herald assets list`

Lists the Rive files and images stored for an app, with the templates that use each.

**Options**

| Option | Type | Description |
|---|---|---|
| `--app ID` | string | The app id. Required. |

**Example**

```sh
herald assets list --app example.bidbot
```

**Output**

The reply names the app folder, the limits, and every Rive file and image. The fields are under [`GET /v1/assets`](api/assets.md#get-v1assets).

**HTTP route**

[`GET /v1/assets`](api/assets.md#get-v1assets)

### `herald assets add`

Copies a Rive file or an image into an app's assets. A file ending in `.riv` is a Rive file; a picture file is an image.

**Options**

| Option | Type | Description |
|---|---|---|
| `--app ID` | string | The app id. Required. |
| `--file PATH` | path | The file to add. Required. A relative path is made absolute from the current folder. |
| `--name N` | string | The stored name. Default: the file's name. |
| `--kind K` | string | `rive` or `image`. Needed only when the file name does not show which. |

**Example**

```sh
herald assets add --app example.bidbot --file ~/Desktop/bell.riv
```

**Output**

The reply gives the stored file name and path. For a Rive file it also gives the asset id and a ready `rive` component. The fields are under [`POST /v1/assets`](api/assets.md#post-v1assets).

**HTTP route**

[`POST /v1/assets`](api/assets.md#post-v1assets)

### `herald assets rm`

Removes one stored file. The reply lists the templates that still use it, under `stillReferencedBy`.

**Options**

| Option | Type | Description |
|---|---|---|
| `--app ID` | string | The app id. Required. |
| `--file NAME` | string | The stored file name. Required. |

**Example**

```sh
herald assets rm --app example.bidbot --file bell.riv
```

**Output**

```json
{
  "deleted" : "bell.riv",
  "ok" : true,
  "stillReferencedBy" : [

  ]
}
```

**HTTP route**

[`DELETE /v1/assets`](api/assets.md#delete-v1assets)

### `herald symbols`

Searches the SF Symbol names a template's `symbol` component can use. The words are separate arguments, before any
option. The reply also lists the categories.

**Options**

| Option | Type | Description |
|---|---|---|
| `WORDS` | string | Words to search for. Default: all symbols. |
| `--category C` | string | Only symbols in this category, such as `communication`. |
| `--limit N` | integer | The most symbols to return. |
| `--offset N` | integer | How many symbols to skip, for paging. |

**Example**

```sh
herald symbols bell --category communication --limit 2
```

**Output**

```json
{
  "limit" : 2,
  "offset" : 0,
  "symbols" : [
    {
      "categories" : [
        "communication"
      ],
      "name" : "bell"
    }
  ],
  "total" : 1
}
```

The output above is shortened: the real reply also carries the list of categories.

**HTTP route**

[`GET /v1/symbols`](api/templates.md#get-v1symbols)

## Voice, MCP and health

### `herald voice`

Shows the state of the Kokoro voice engine, or manages it. With no argument it shows the state. After an `install`, run `herald voice` again to see the progress. The words are in the Options table.

**Options**

| Option | Type | Description |
|---|---|---|
| `status` | word | Show the state. The default. |
| `install` | word | Install Kokoro. |
| `cancel` | word | Cancel a running install. |
| `use-existing` | word | Use an existing installation instead of installing. |

**Example**

```sh
herald voice use-existing
```

**Output**

```json
{
  "action" : "useExisting",
  "next" : "Poll GET /v1/voice for progress.",
  "ok" : true
}
```

With no word, the reply is the state described under [`GET /v1/voice`](api/setup.md#get-v1voice).

**HTTP routes**

To show the state: [`GET /v1/voice`](api/setup.md#get-v1voice).

For `install`, `cancel` and `use-existing`: [`POST /v1/voice/install`](api/setup.md#post-v1voiceinstall).

### `herald mcp`

Shows which agent clients have Herald's MCP server, or installs it in one. With no argument, or `status`, it shows the
state of every client and whether the command line tool is installed. `install CLIENT` adds the server to a client and
registers the agent as the app `agent.<client>`.

**Options**

| Option | Type | Description |
|---|---|---|
| `status` | word | Show the state. The default. |
| `install CLIENT` | string | Install in `claudeCode`, `codex`, `claudeDesktop`, `cli` or `generic`. |
| `--reinstall` | flag | Replace an existing installation. |
| `--name NAME` | string | The agent's display name. Required for `generic`, whose app id becomes `agent.<slug>`. |
| `--icon FILE` | path | An icon file for the agent. |
| `--opens APP` | string | What the banner's Open button brings forward: a bundle id or the path of an application. |

**Example**

```sh
herald mcp install generic --name "My Bot" --icon ~/Pictures/bot.png
```

**Output**

The reply carries the configuration to paste into the client.

**Exit status**

Both failures exit with `1`:

- A missing client prints `herald: mcp install needs one client: ...`.
- Herald's `400` is printed when `generic` has no `--name`, or the icon file does not exist.

**HTTP routes**

To show the state: [`GET /v1/mcp`](api/setup.md#get-v1mcp).

To install: [`POST /v1/mcp/install`](api/setup.md#post-v1mcpinstall).

The [MCP guide](../MCP.md) walks through connecting an agent.

### `herald health`

Checks that Herald is running. It needs no token, so it works before the token file exists. Use it in scripts to wait
for Herald.

**Example**

```sh
herald health
```

**Output**

```json
{
  "ok" : true,
  "pid" : 69080,
  "version" : "1.8.1"
}
```

**Exit status**

`2` when Herald is not running.

**HTTP route**

[`GET /v1/health`](api/diagnostics.md#get-v1health)

## Related

- [HTTP API](api/README.md): every endpoint these commands call, with all fields.
- [Send your first notification](../getting-started.md): the first `herald notify` or `curl` call.
- [MCP guide](../MCP.md): connect an agent instead of scripting the tool.
- [Testing](../TESTING.md): run the tool against a second Herald that does not disturb yours.
