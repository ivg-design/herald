# Install Herald

This page takes you from nothing to a running Herald: install the app, open it for the first time, find the files
that other programs use to talk to it, and later update, uninstall or build it from source. It is for anyone who
installs Herald on their own Mac.

## Before you start

- A Mac running macOS 13.1 or later.
- To build from source only: Xcode and XcodeGen (`brew install xcodegen`).

## Steps

### Install the app

1. Download `Herald-<version>-build<n>-macOS.dmg` from the [releases page](https://github.com/ivg-design/herald/releases).
   The release also holds a `.sha256` file with the checksum of the download.
2. Optional: check the download. The first column of the `.sha256` file must equal the hash this command prints.

   ```sh
   shasum -a 256 ~/Downloads/Herald-*-macOS.dmg
   ```

3. Open the disk image and drag **Herald** onto the **Applications** folder.
4. Open **Herald** from Applications. The app is signed with a Developer ID and notarized by Apple, so macOS opens it
   without a warning.

Herald has no Dock icon and no window of its own. It lives in the menu bar.

### First launch

1. Look at the right side of the menu bar. A bell has appeared.
2. Click the bell. The menu opens.

   ![The Herald menu: the unread count, Compose, Design Template, History, Mute Sounds, Quiet for 1 Hour, Stack Notifications, Dismiss All, Settings and Quit](../web/public/shots/docs/menu.png "The menu from the menu bar bell. [The Herald app](APP.md#the-menu-bar-menu) explains each item.")

3. If Herald runs from `/Applications` and has not asked before, it asks **Launch Herald at login?** Choose
   **Launch at Login** so notifications from your other apps always have somewhere to go, or **Not Now**. You can change
   this later with **Settings > General > Launch at login**.

Herald now listens for notifications on `127.0.0.1`, which only your Mac can reach.

### Find the port and the token

Programs that send notifications need two values. Herald writes them to files in its support folder,
`~/Library/Application Support/Herald/`.

| File | What it holds |
|---|---|
| `port` | The port the local API listens on. The default is `48617`. The file exists while Herald is running. |
| `token` | The secret every request except `GET /v1/health` must send as a bearer token. It is readable only by your user account. |

Read them into shell variables like this. The same block starts every example in the [HTTP API](reference/api/README.md#connect).

```sh
D="$HOME/Library/Application Support/Herald"
HERALD="http://127.0.0.1:$(cat "$D/port")"
TOKEN="$(cat "$D/token")"
```

You can also open the token's folder from the app: **Settings > General > Reveal Token File in Finder**. To change the
port, use **Settings > General > Port** and **Apply**. [The Herald app](APP.md#general) lists every control.

### Install the command line tool

The `herald` tool is inside the app. Open **Settings > MCP**, find **Command line tool** and press
**Install `herald` command line tool**. Herald copies it to `/usr/local/bin/herald` and asks for an administrator
password only if that folder is not writable. The same section lists the MCP server for AI agents; see
[Herald MCP server](MCP.md).

### Update Herald

Herald does not update itself. To update, download the newer disk image from the releases page, quit Herald with
**Quit Herald** in the bell menu, and drag the new Herald onto **Applications**, replacing the old one. Open it again.

Your apps, templates, History and settings stay in the support folder, so they are still there.

### Uninstall Herald

1. If you set up the [cloud relay](CLOUD.md), turn it off first with **Settings > Cloud > Enable relay**. To remove
   the relay from your Cloudflare account too, use **Settings > Cloud > Advanced > Delete relay from Cloudflare**.
2. Turn off **Settings > General > Launch at login**.
3. Choose **Quit Herald** in the bell menu.
4. Drag `/Applications/Herald.app` to the Trash.
5. Delete what Herald left behind. Skip any line you want to keep.

   ```sh
   rm -rf "$HOME/Library/Application Support/Herald"
   rm -rf "$HOME/Library/Logs/Herald"
   defaults delete com.ivg.herald
   rm -f /usr/local/bin/herald /usr/local/bin/herald-mcp
   ```

6. If you added the MCP server to Claude Code, Codex or Claude Desktop, remove it there too. In Claude Code the
   command is `claude mcp remove herald`.

Herald also keeps the relay's device token and your Cloudflare token in the macOS Keychain, in items whose service
names start with `com.ivg.herald`. Delete them in Keychain Access if you want them gone.

## Build from source

Use this when you want the newest code or want to change it. The steps run in the repository root.

1. Install XcodeGen and generate the Xcode project.

   ```sh
   brew install xcodegen
   xcodegen generate
   ```

2. Build the app, then run the tests.

   ```sh
   xcodebuild -project Herald.xcodeproj -scheme Herald -configuration Debug build CODE_SIGNING_ALLOWED=NO
   swift test
   ```

3. To install what you built, run `make install`. It does three things:

   - It builds a release app.
   - It replaces `/Applications/Herald.app`.
   - It installs the `herald` and `herald-mcp` tools to `/usr/local/bin`, or to `~/bin` when `/usr/local/bin` is not
     writable.

   `make install-cli` installs only the two tools.

A build you make yourself is signed ad hoc, which is enough to run on the Mac that built it. Release builds are signed
with a Developer ID and notarized with `scripts/notarize.sh --dmg`.

## Check that it works

With Herald running, ask it for its health. This request needs no token.

```sh
curl -s "$HERALD/v1/health"
```

```json
{"ok": true, "pid": 4821, "version": "1.8.1"}
```

`ok` is `true` and `pid` is Herald's process id. If the command prints nothing, Herald is not running or the `port`
file is missing.

## If it does not work

| Symptom | Cause | Fix |
|---|---|---|
| No bell in the menu bar. | Herald is not running, or the menu bar is full and macOS hides the icon. | Open Herald from Applications. Close other menu bar items, or use a menu bar manager. |
| `cat: .../port: No such file or directory`. | Herald is not running. It removes the file when it quits. | Open Herald, then read the file again. |
| `curl: (7) Failed to connect`. | The port file names a port another program owns, or Herald failed to bind it. | Open **Settings > General**. The line under **Port** says what happened. Choose another port and press **Apply**. |
| `make install` stops at `xcodegen`. | XcodeGen is not installed. | Run `brew install xcodegen`. |

More fixes are in [Troubleshooting](troubleshooting.md).

## Related

- [Send your first notification](getting-started.md): the next step.
- [The Herald app](APP.md): the menu, History and Settings.
- [HTTP API: Connect](reference/api/README.md#connect): how the port and token are used.
- [Command line](reference/cli.md): every `herald` command.
