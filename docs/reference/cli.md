# The `herald` command line tool

`herald` sends notifications and controls Herald.app from a shell. It is a thin client over the HTTP API
([api.md](api.md)): it reads the port and token from `~/Library/Application Support/Herald/` and prints the JSON
reply. Installed at `/usr/local/bin/herald` (or `~/bin`) by `make install-cli`, or from Herald.app >
Settings > MCP > "Install `herald` command line tool"; also at `Herald.app/Contents/Helpers/herald`.

```
herald <command> [options]
```

## Global options

| Option | Meaning |
|---|---|
| `--port N` | Service port (default: `<support>/port`, else 48617). `--port=N` also works. |
| `--token T` | Bearer token (default: `<support>/token`). Prefer the file: a flag shows in `ps`. |
| `--json FILE` | Raw JSON payload from `FILE`, or `-` for stdin (`notify`, `register`). Other flags are merged on top of it. |
| `-h`, `--help` | Help (also `herald help <command>`). |
| `--version` | Prints `herald 1.1.0` (a fixed string; use `GET /v1/health` for the app's version). |

Environment: `HERALD_SUPPORT_DIR` points the tool at another Herald's data folder (a development build).

## Exit codes

| Code | Meaning |
|---|---|
| 0 | OK; the reply is printed as pretty JSON. |
| 1 | Usage error, or an HTTP error (the reply is printed; a 401 adds `unauthorized (check the token file or --token)`). |
| 2 | Herald is not running: `Herald is not running. Launch Herald.app first.` |

## Commands

| Command | Purpose |
|---|---|
| `notify` | Send a notification (needs `--app` and `--title`, or `--template`, or `--json`). |
| `register` | Register or update an app. |
| `compose` | Open the Composer window in Herald.app. |
| `snooze` | `--app ID --id ID --minutes N` (N fractional, 0 < N <= 43200). |
| `unsnooze` | `--app ID --id ID`: bring a snoozed banner back now. |
| `dismiss` | `--app ID --id ID`: dismiss one banner. |
| `dismiss-all` | `--app ID` dismisses all banners of an app; with `--group G` only that stack. (`dismissAll` is accepted too.) |
| `stacks` | `[--app ID]`: list live stacks. |
| `history` | `--app ID [--limit N] [--clear]`: show or clear history. |
| `template` | `export` and `import` of `.heraldtemplate` bundles; `list`, `put`, `delete`, `duplicate`, `rename`, `default`. |
| `apps` | List registered apps; `apps settings`, `apps set` for per-app settings. |
| `settings` | Show (`settings`) or change (`settings set KEY=VALUE ...`) Herald's settings. |
| `assets` | `list`, `add`, `rm` an app's Rive files and images. |
| `symbols` | Search SF Symbol names. |
| `voice` | Kokoro: `status`, `install`, `cancel`, `use-existing`. |
| `mcp` | `status`, `install CLIENT [--reinstall]`. |
| `approvals` | List template command approvals; `approvals revoke --app --template`. |
| `manifest` | `manifest delete --app ID`. |
| `speak` | Say text aloud, no banner. |
| `quiet` | Quiet hours. |
| `health` | Check that Herald is running (no token needed). |

There is no CLI command to save a manifest or to read the component schema: use the API, the MCP server or the
Designer. Nothing in the CLI grants an approval for commands or callbacks; only the user does, in Settings.

## notify

```sh
herald notify --app bidbot --title "Bid accepted" --body "Your bid of \$4,200 was accepted" \
  --url "https://example.com/bids/42" --image /path/preview.png \
  --button "Open=https://example.com/bids/42" --sound Glass --snooze
echo '{"app":"bidbot","title":"Bid accepted","buttons":[{"label":"Open","url":"https://x"}]}' | herald notify --json -
```

| Option | Maps to | Notes |
|---|---|---|
| `--app ID` | `app` | |
| `--id ID` | `id` | Replace an existing banner with this id. |
| `--title T`, `--subtitle T`, `--body T` | | |
| `--image PATH\|URL\|data:` | `image` | |
| `--url URL` | `url` | |
| `--group G` | `group` | Stack key ([stacking.md](stacking.md)). |
| `--sound NAME\|PATH\|none` | `sound` | |
| `--timeout SECONDS` | `timeout` | 0 = until dismissed. |
| `--persistent`, `--no-persistent` | `persistent` | |
| `--snooze`, `--no-snooze` | `snooze` | |
| `--priority low\|normal\|high\|urgent` | `priority` | |
| `--button "Label=target"` | `buttons[]` | Repeatable. Targets: `https://...` opens a URL; `cmd:shell command` runs a command (the app needs `allowCommands`); `cb:{"k":1}` POSTs that JSON as the callback payload (`cb:` alone: an empty payload). |
| `--reminder "Title\|2026-10-02T09:00"` | `reminder` | Title and ISO 8601 due, split on the last `\|`; a bare string is just a title. |
| `--metadata JSON` | `metadata` | A JSON object; template tokens read it. |
| `--template NAME` | `template` | `--title` may then be omitted. |
| `--layout L` | `layout` | `imageLeft`, `imageRight`, `hero`, `compact`. |
| `--accent #RRGGBB` | `accentColor` | |
| `--no-subtitle`, `--no-body`, `--no-time` | `showSubtitle`/`showBody`/`showTimestamp` = false | |
| `--max-body-lines N` | `maxBodyLines` | |
| `--speak`, `--speak-text T`, `--voice NAME`, `--speed 0.5-2.0`, `--lang en-us` | `speak` | [voice.md](voice.md). |
| `--audio PATH\|URL\|data:` | `audio` | At most 20 MB. |
| `--presentation banner\|voice\|both` | `presentation` | |

`--flag=value` works for any value flag. Flags are merged **on top of** `--json`.

## register

```sh
herald register --app bidbot --name BidBot --icon /path/icon.png --bundle-id com.example.bidbot \
  --callback-url http://127.0.0.1:5123/herald --allow-commands --sound Glass --timeout 0 --corner topRight
```

| Option | Maps to |
|---|---|
| `--app ID` (required) | `app` |
| `--name NAME` | `appName` |
| `--icon PATH\|data:` | `icon` |
| `--bundle-id ID` | `bundleId` |
| `--callback-url URL` | `callbackURL` |
| `--allow-commands`, `--no-allow-commands` | `allowCommands` (a request; the user confirms it) |
| `--sound NAME`, `--timeout S`, `--persistent`, `--no-persistent` | `defaults` |
| `--corner C` | `defaults.corner`: `topRight`, `topLeft`, `bottomRight`, `bottomLeft` |
| `--json FILE\|-` | a base payload |

## speak, quiet

```sh
herald speak --app build --text "Deploy finished" [--voice NAME] [--speed N] [--lang L] [--id ID]
herald quiet status
herald quiet --until 07:30          # silence speech and sounds until 07:30
herald quiet --for 60 --banners     # for an hour, banners too
herald quiet off                    # resume now
```

`quiet` needs exactly one of `--until HH:MM` (24-hour, two-digit minutes) or `--for MINUTES`, or `status`/`off`.

## history, stacks, dismiss

```sh
herald history --app bidbot --limit 10
herald history --app bidbot --clear
herald stacks --app webwatcher.email
herald dismiss-all --app webwatcher.email --group "billing@acme.com"
```

## Settings, apps, assets, symbols

Values in `KEY=VALUE` are JSON where they parse (`true`, `3`, `1.2`, `null`) and strings otherwise. Everything is validated
by Herald, all or nothing ([api.md](api.md#settings)).

```sh
herald settings                                   # values, schema and options
herald settings set muteAllSounds=true stacking=bySender voiceSpeed=1.2
herald apps settings --app webwatcher.email
herald apps set --app webwatcher.email muteBanners=true corner=bottomLeft sound=Ping timeout=8
herald apps set --app webwatcher.email revokeCommands=true      # withdraw only; granting is the user's
herald assets list --app webwatcher.email
herald assets add --app webwatcher.email --file ~/Desktop/bell.riv
herald assets rm --app webwatcher.email --file bell.riv
herald symbols bell --category communication --limit 20
herald voice status;  herald voice use-existing
herald mcp status;  herald mcp install claudeCode --reinstall
herald approvals;  herald approvals revoke --app webwatcher.email --template email-accumulated
```

## History search, re-show, delete, export

```sh
herald history search invoice paid --app bidbot --limit 20
herald history reshow --app bidbot --id bid-42
herald history delete --app bidbot --id bid-42
herald history export --app bidbot --out ~/Desktop/bidbot.json
```

## template list, put, delete, duplicate, rename, default

```sh
herald template list --app webwatcher.email
herald template put draft.json                    # one template object; "-" reads stdin; validated by Herald
herald template duplicate --app webwatcher.email --name hero [--new-name hero2] [--to-app other.app]
herald template rename --app webwatcher.email --name hero --new-name banner
herald template default --app webwatcher.email --name banner      # or --clear
herald template delete --app webwatcher.email --name banner
herald manifest delete --app old.app
```

## template export and import

Bundles carry a template with the Rive files it plays ([rive.md](rive.md#packaging-with-a-template-heraldtemplate)).

```sh
herald template export --app webwatcher.email --name email-accumulated [--out FILE]
herald template import FILE [--app ID] [--keep-both | --replace | --fail]
```

| Option | Meaning |
|---|---|
| `export --app --name` | Required. `--out FILE` (or `-o`) is the destination; default `<name>.heraldtemplate` in the current directory. Prints `Wrote <path> (N animation files)`; warnings (a missing animation, scripts and Shortcuts that stay behind) go to stderr. |
| `import FILE` | The bundle may also be given as `--file FILE`. |
| `--app ID` | Import for another issuer instead of the one the bundle names. |
| `--keep-both` (default) | If the name is taken, save as `NAME 2`, `NAME 3`... |
| `--replace` | Overwrite the template with that name. |
| `--fail` | Stop if the name is taken. |

Import works on the files directly (Rive files go to `<support>/assets/<app>/`, never replacing a different file)
and then asks the running Herald to save the template, so Herald must be running.

## health

`herald health` calls `GET /v1/health` and prints `{"ok":true,"version":"1.2.0","pid":123}`; no token is needed.
Use it in scripts to wait for Herald.
