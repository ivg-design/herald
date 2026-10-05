# Herald

Herald is a notification service for macOS. Apps, scripts and AI agents send it a notification, and Herald draws a
banner on your screen, keeps it in a searchable History, and lets you answer it with buttons, a reply or a voice
message. It listens on your Mac only, and you design how each app's banners look.

![A Herald banner with an app icon, a title, a body line and a timestamp in the top right corner of the screen](web/public/shots/docs/banner-plain.png "A banner sent with one curl command. The icon and name belong to the app that sent it.")

## Requirements

- macOS 13.1 or later.
- To build from source: Xcode and [XcodeGen](https://github.com/yonaskolb/XcodeGen).

## Install

1. Download the notarized disk image (`Herald-VERSION-buildN-macOS.dmg`) from the [releases page](https://github.com/ivg-design/herald/releases).
2. Drag Herald to `/Applications` and open it.
3. A bell appears in the menu bar. The first time you open Herald from `/Applications`, it asks whether to start at login.

[Install Herald](docs/install.md) has the details: where the port and token files are, how to update and uninstall,
and how to build from source.

## Quick start

With Herald running, this command shows a banner. It reads Herald's port and token from the files Herald writes in
its support folder.

```sh
D="$HOME/Library/Application Support/Herald"
curl -s -X POST "http://127.0.0.1:$(cat "$D/port")/v1/notify" \
  -H "Authorization: Bearer $(cat "$D/token")" -H "Content-Type: application/json" \
  -d '{"app":"example.bidbot","title":"Bid accepted","body":"Your bid was accepted."}'
```

Herald answers `{"ok": true, "id": "..."}` and the banner appears. [Send your first notification](docs/getting-started.md)
continues with buttons, updating a banner in place, dismissing it, and the same calls from the command line,
Python, Node and Swift.

## Ways to send a notification

| Way | Use it when | Where it is documented |
|---|---|---|
| HTTP API | You write the request yourself, in any language. | [HTTP API](docs/reference/api/README.md) |
| `herald` command line tool | You send from a shell script or a terminal. | [Command line](docs/reference/cli.md) |
| Python, Node and Swift clients | You send from a program and want a small library. | [Clients](clients/README.md) |
| MCP server | An AI agent on this Mac sends and designs banners. | [Herald MCP server](docs/MCP.md) |
| Cloud relay | An agent that runs in the cloud, such as ChatGPT, sends to this Mac. | [Cloud agents](docs/CLOUD.md) |

[WebWatcher](docs/examples/webwatcher.md) is an app that delivers its alerts through Herald, and
[BidBot](docs/examples/bidbot/README.md) is a complete example that sends every kind of banner.

## Documentation

Start with the task pages. Each one has numbered steps and says what you should see.

| Page | What you do there |
|---|---|
| [Install Herald](docs/install.md) | Install, update, uninstall and build from source. |
| [Send your first notification](docs/getting-started.md) | Show, update and dismiss a banner from curl, the CLI, Python, Node and Swift. |
| [Agent quick start](docs/AGENT-QUICKSTART.md) | Let an AI agent on this Mac use Herald. |
| [The Herald app](docs/APP.md) | Use the menu bar menu, History and every Settings tab. |
| [Design a banner](docs/AUTHORING.md) | Lay out a banner in the Designer. |
| [Templates](docs/TEMPLATES.md) | Save, share and reuse banner designs. |
| [Buttons and actions](docs/ACTIONS.md) | Make buttons that open links, run commands or call your app back. |
| [Voice](docs/VOICE.md) | Speak notifications and play voice messages. |
| [Herald MCP server](docs/MCP.md) | Install the MCP server and connect an agent. |
| [Testing](docs/TESTING.md) | Check a design and a flow without waiting for real events. |
| [Troubleshooting](docs/troubleshooting.md) | Fix a banner that does not appear, a 401, a silent sound and more. |

Cloud agents reach your Mac through a small relay in your own Cloudflare account.

| Page | What you do there |
|---|---|
| [Cloud agents](docs/CLOUD.md) | Understand the relay and set it up. |
| [How the relay works](docs/cloud/how-it-works.md) | Read the architecture, the security model and the limits. |
| [Connect an agent with a key](docs/cloud/connect-agent.md) | Give Claude Code or Codex a key. |
| [Connect ChatGPT](docs/cloud/connect-chatgpt.md) | Approve ChatGPT as a connector. |
| [Agents without a browser](docs/cloud/device-flow.md) | Approve an agent by a code. |
| [Reply events](docs/cloud/reply-events.md) | Tell an agent the moment you reply. |
| [Custom domain](docs/cloud/custom-domain.md) | Put the relay on your own domain. |
| [Operating the relay](docs/cloud/operating.md) | Update, monitor and delete the relay. |

The [reference](docs/reference/README.md) is the complete description of every endpoint, tool, command, component
and setting.

| Reference | What it covers |
|---|---|
| [HTTP API](docs/reference/api/README.md) | Every endpoint of the local API. |
| [MCP tools](docs/reference/mcp/README.md) | Every tool of the MCP server. |
| [Command line](docs/reference/cli.md) | Every `herald` command. |
| [Clients](clients/README.md) | The Swift, Python and Node clients. |
| [How banners behave](docs/reference/banners.md) | Where a banner appears, how long it stays, what a click does. |
| [Grid and layout](docs/reference/grid-and-layout.md) | The template object, the grid and how empty cells collapse. |
| [Components](docs/reference/components/README.md) | One page per template component. |
| [Manifests](docs/reference/manifests.md) | How an app declares its fields, actions and assets. |
| [Bindings](docs/reference/bindings.md) | The `{token}` syntax and where values come from. |
| [Actions](docs/reference/actions.md) | Action kinds, rules and confirmation gates. |
| [Stacking](docs/reference/stacking.md) | How banners fold into stacks. |
| [Quiet hours](docs/reference/quiet-hours.md) | Windows that silence speech, sounds and banners. |
| [Voice](docs/reference/voice.md) | Speech engines and voice messages. |
| [Rive](docs/reference/rive.md) and [Symbols](docs/reference/symbols.md) | Motion and SF Symbols on banners. |
| [Parity](docs/reference/parity.md) | Every capability against its route, command and tool. |
| [Glossary](docs/reference/glossary.md) | The words Herald uses. |

## Build from source

```sh
brew install xcodegen
xcodegen generate
xcodebuild -project Herald.xcodeproj -scheme Herald -configuration Debug build CODE_SIGNING_ALLOWED=NO
swift test
```

`make install` builds a release app into `/Applications` and the `herald` and `herald-mcp` tools into
`/usr/local/bin`. See [Install Herald](docs/install.md#build-from-source) for what each step does.

## How the code is laid out

| Folder | What it holds |
|---|---|
| `Sources/Herald` | The app. `Core/` holds the server, router, History and app registry, which SwiftPM also builds as `HeraldCore` for tests. |
| `Sources/HeraldClient` | The shared library: models, template schema and validation, and the Swift client. |
| `Sources/herald-cli` | The `herald` command line tool. |
| `Sources/herald-mcp` | The MCP server. |
| `relay` | The Cloudflare Worker that forms the cloud relay. |
| `clients` | The Python and Node clients. |
| `docs` | This documentation. |

## Project

The [project board](https://github.com/users/ivg-design/projects/14) tracks planned work. The changelog is
[CHANGELOG.md](CHANGELOG.md). Herald uses the [Rive](https://rive.app) runtime to play animations on banners and,
if you install it, the [Kokoro](https://github.com/thewh1teagle/kokoro-onnx) models to speak on your Mac.
