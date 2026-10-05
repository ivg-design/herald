# Testing Herald

This page shows how to test Herald and an integration with it without disturbing the Herald you use every day. It
covers a second instance of the app with its own data, the sending and previewing you can do against it, the automatic
test suites, and the checks that draw a banner or a Designer window without opening a window. It is for people who
build an integration, and for people who change Herald itself.

The commands use `$HERALD` and `$TOKEN` from [Connect](reference/api/README.md#connect), pointed at the second
instance as the steps below show.

## Run a second instance of Herald

Herald keeps everything it owns in one support folder: the `token` and `port` files, History, templates, manifests
and settings. Two environment variables point a copy of the app at its own folder and its own port, so it runs beside
the installed Herald and never reads or writes its data.

| Variable | Type | Description |
|---|---|---|
| `HERALD_SUPPORT_DIR` | path | The support folder to use instead of `~/Library/Application Support/Herald`. The app creates it. |
| `HERALD_PORT` | integer | The port to listen on, from 1024 to 65535. It beats a port set in Settings. Default: `48617`. |

### Before you start

- A build of Herald.app. The installed one works. To build a debug copy from the repository:

  ```sh
  xcodegen generate
  xcodebuild -project Herald.xcodeproj -scheme Herald -configuration Debug \
    -derivedDataPath /tmp/herald-dd build CODE_SIGNING_ALLOWED=NO
  ```

- A free port. The steps use `48700`.

### Steps

1. Start the app's executable with the two variables set. The folder does not need to exist yet.

   ```sh
   HERALD_SUPPORT_DIR=/tmp/herald-test HERALD_PORT=48700 \
     /tmp/herald-dd/Build/Products/Debug/Herald.app/Contents/MacOS/Herald &
   ```

   Herald starts and creates `/tmp/herald-test`. For an installed copy, use `/Applications/Herald.app/Contents/MacOS/Herald`.

2. Point your shell at the new instance by reading its own files:

   ```sh
   D=/tmp/herald-test
   HERALD="http://127.0.0.1:$(cat "$D/port")"
   TOKEN="$(cat "$D/token")"
   ```

3. Ask it for its health. The `pid` is the second instance's, not the installed one's.

   ```sh
   curl -s "$HERALD/v1/health"
   ```

   ```json
   {"ok": true, "pid": 70211, "version": "1.8.1"}
   ```

4. Point the other tools at it. They read the second instance's `port` and `token` files from `HERALD_SUPPORT_DIR`:

   ```sh
   HERALD_SUPPORT_DIR=/tmp/herald-test herald health
   HERALD_SUPPORT_DIR=/tmp/herald-test herald-mcp --version
   ```

   An MCP client gets the variable in the server's `env` entry. The [MCP guide](MCP.md) lists the server's flags and variables.

### Check that it works

`curl -s "$HERALD/v1/health"` answers with the pid of the second process, and `ls /tmp/herald-test` lists `port` and
`token`. Send one test banner with the call in [Send a notification to the second
instance](#send-a-notification-to-the-second-instance). It appears on your screen and not in the installed Herald's
History.

### If it does not work

| Symptom | Cause | Fix |
|---|---|---|
| `curl` says the connection was refused. | The app is still starting, or the port is taken. | Wait a second and retry. If another program owns the port, pick a different `HERALD_PORT`. |
| `herald` prints `Herald is not running`. | The tool read the installed Herald's folder. | Set `HERALD_SUPPORT_DIR` on the command. |
| A call returns `401`. | `$TOKEN` came from the installed Herald's token file. | Read `token` from the second instance's folder. |
| Settings you change in the second instance show up in the installed one. | A few preferences are stored by macOS under one app identifier, which a folder cannot redirect. | Leave the settings of the second instance alone while testing, or change them back afterwards. |

To stop the instance, quit it from its menu bar icon, or end the process you started.

## Send a notification to the second instance

Use a made-up app id such as `example.bidbot`. A test never has to touch a real app's History or manifest.

```sh
curl -s -X POST "$HERALD/v1/notify" \
  -H "Authorization: Bearer $TOKEN" -H "Content-Type: application/json" \
  -d '{"app":"example.bidbot","id":"bid-42","title":"Bid accepted","body":"Your bid of $4,200 was accepted"}'
```

```json
{"ok": true, "id": "bid-42"}
```

Send it again with the same `id` to see the banner replaced in place. Close the banner, then delete what the test left
behind:

```sh
herald dismiss-all --app example.bidbot
herald history --app example.bidbot --clear
```

The [`POST /v1/notify`](reference/api/notifications.md#post-v1notify) block lists every field you can send. Agents send
the same notification with [`send_test`](reference/mcp/notifications.md#send_test).

## Check a banner or a template without a window

Three routes draw into an image with no window, so they never take focus and can run at any time. They suit scripts and
continuous integration as much as a quick look.

| What you want to see | Route | MCP tool |
|---|---|---|
| A template drawn as a banner, light or dark, with the data you choose. | [`POST /v1/preview`](reference/api/templates.md#post-v1preview) | [`render_preview`](reference/mcp/templates.md#render_preview) |
| The Designer window, with a template open and a cell selected. | [`GET /v1/designer/snapshot`](reference/api/diagnostics.md#get-v1designersnapshot) | [`designer_snapshot`](reference/mcp/templates.md#designer_snapshot) |
| Whether a Rive animation loads, which inputs it has and what a click does. | [`POST /v1/rive/check`](reference/api/diagnostics.md#post-v1rivecheck) | [`rive_check`](reference/mcp/templates.md#rive_check) |

### Preview a template

The reply is a PNG. The `data` argument takes one of three things, and leaving a key out of an object shows how the
template collapses an empty field.

- `"sample"`, for the manifest's sample values.
- `"last"`, for the app's latest notification.
- An object of your own.

```sh
curl -s -X POST "$HERALD/v1/preview" \
  -H "Authorization: Bearer $TOKEN" -H "Content-Type: application/json" \
  -d '{"app":"example.bidbot","template":"builtin.hero","data":"sample","appearance":"dark"}' \
  -o preview.png
```

`preview.png` is the banner Herald would show. Offscreen drawing cannot play a `rive` component or open a menu: a Rive
animation is drawn as a labelled placeholder. Use the Rive check below for those.

### Snapshot the Designer

```sh
curl -s "$HERALD/v1/designer/snapshot?app=example.bidbot&width=1100&height=820" -o designer.png
```

The query parameters, with their ranges, are in
[`GET /v1/designer/snapshot`](reference/api/diagnostics.md#get-v1designersnapshot). They choose the size, the saved
template to open and the cell to select. See [Designing a banner](AUTHORING.md) for what the Designer shows.

### Check a Rive animation

The check loads the component in the view a banner uses, reports the artboards, state machines and inputs it found,
and can play pointer steps in order. The full request and reply are in
[Testing without a window](reference/rive.md#testing-without-a-window).

## Run the test suites

Herald has four sets of tests. Each one runs without the others.

| Suite | Where | Command | What it needs |
|---|---|---|---|
| Swift unit tests | `Tests/HeraldTests` | `swift test` | Nothing running. |
| Banner snapshot tests | `Tests/HeraldTests/BannerSnapshotTests.swift`, `ActionArrangementLiveTests.swift` | `HERALD_UI_TESTS=1 HERALD_UI_APP=... swift test --filter BannerSnapshotTests` | A built Herald.app. |
| Relay tests | `relay/test` | `cd relay && npm test` | Node and the relay's `npm install`. |
| Documentation checks | `web/scripts` | `cd web && node scripts/test-docs-structure.mjs` | Node. |

### Swift unit tests

```sh
swift test
```

The command runs the `HeraldTests` target without launching the app. It covers:

- The router and notification payloads.
- History, snooze, stacking and quiet hours.
- Templates, the grid solver and the Designer model.
- The command line parser, the MCP server, the clients and the relay client.

The SwiftUI views belong to the Xcode app target, which the package's test host cannot link, so everything that is
not a view is tested here. To run one group, filter by test class:

```sh
swift test --filter CLIArgumentTests
```

### Banner snapshot tests

`BannerSnapshotTests` checks what a banner looks like. It renders templates through a running Debug Herald over
`POST /v1/preview` and compares each PNG with a reference in `Tests/Fixtures/`. The tests are opt-in, so a plain
`swift test` stays fast and needs no window server. `ActionArrangementLiveTests` uses the same switches to check how
action buttons are arranged.

```sh
HERALD_UI_TESTS=1 HERALD_UI_APP=/tmp/herald-dd/Build/Products/Debug/Herald.app \
  swift test --filter BannerSnapshotTests
```

| Variable | Type | Description |
|---|---|---|
| `HERALD_UI_TESTS` | `1` | Runs the live tests. Without it they are skipped. |
| `HERALD_UI_APP` | path | The Herald.app build to launch. It starts on a free port with a throwaway support folder and quits when the run ends. Your installed Herald is not touched. |
| `HERALD_UI_PORT` | integer | The port for the launched instance. Default: any free one. |
| `HERALD_PORT`, `HERALD_SUPPORT_DIR` | integer, path | Used instead of `HERALD_UI_APP` to run against a Herald you started yourself, as in [Run a second instance](#run-a-second-instance-of-herald). The tests register an app called `ui-tests` in it. |
| `HERALD_UI_RECORD` | `1` | Writes the reference images instead of comparing against them. |

A pixel counts as different when a colour channel is more than 12 off. A run fails when more than 0.4% of the pixels
differ or the mean difference is 1 level or more. A failure writes the actual image and a diff, with the differing
pixels in red, to `$TMPDIR/herald-ui-tests-failures/`.

The references are pixels of the macOS version they were recorded on. After an operating system update that moves text,
or after a deliberate change to a banner, a template or a built-in, record them again, look at the changed PNGs in git
and commit them:

```sh
HERALD_UI_TESTS=1 HERALD_UI_RECORD=1 HERALD_UI_APP=/tmp/herald-dd/Build/Products/Debug/Herald.app \
  swift test --filter BannerSnapshotTests
git diff --stat Tests/Fixtures
```

Two things are pinned so a reference does not change between runs. The built-in layouts are drawn with the timestamp
bound to a fixed `{frozenClock}` field, because the width of the real time moves everything to its right by fractions of
a point. The tests also register their app with a fixed icon, because an app without one gets a letter tile whose colour
changes with every run.

Some tests need no app and always run:

- The comparator.
- The check that every reference image exists and decodes.
- The collapse and keep matrix, checked against an independent oracle.
- The rules that decide which action buttons survive a cap.

One more test is opt-in because it needs your own Shortcuts: `HERALD_LIVE_SHORTCUTS=1 swift test --filter
ManifestTests/testLiveShortcutsList` lists them through the real `shortcuts` tool.

### Relay tests

```sh
cd relay
npm install
npm test
npm run typecheck
```

`npm test` runs Vitest in the Cloudflare Workers test pool. The files in `relay/test` cover the relay itself, the
device flow, OAuth, consent, tenancy, reply events, the host registry and presentation. `npm run typecheck` checks the
TypeScript without building. See [How the relay works](cloud/how-it-works.md) for what
these tests protect.

### Documentation checks

The structure lint reads the Markdown in the repository and needs no server:

```sh
cd web
node scripts/test-docs-structure.mjs
```

It reports pages that break [the style guide](STYLE.md): a block with two endpoints, a code block with no language,
JSON that does not parse, a link that goes nowhere, and wording that describes history instead of the product. Two more
scripts, `test-docs-hscroll.mjs` and `test-demos.mjs`, drive a browser against a built site and need `BASE` set to its
address.

## Related

- [Notifications API](reference/api/notifications.md): the request you send to test a banner.
- [Diagnostics API](reference/api/diagnostics.md): health, Designer snapshot and Rive check.
- [Templates API](reference/api/templates.md): preview and the template routes.
- [Command line tool](reference/cli.md): `HERALD_SUPPORT_DIR` and the commands that clean up after a test.
- [Troubleshooting](troubleshooting.md): what to check when Herald does not answer.
