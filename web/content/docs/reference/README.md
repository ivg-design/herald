# Herald reference

The reference describes every part of Herald exactly: each HTTP endpoint, MCP tool, command line command, template
component and setting. Use it to look something up. To learn how to do a task, start with the task pages in the
[documentation map](../../README.md#documentation). This page is the index: every reference page, grouped by what it
covers, with one sentence each.

## Where to start

| If you want to | Read |
|---|---|
| Design a banner | [Grid and layout](grid-and-layout.md), then [Bindings](bindings.md), then [Components](components/README.md). |
| Send notifications from your own code | [HTTP API](api/README.md), [Command line](cli.md) or [Clients](../../clients/README.md). |
| Let an AI agent use Herald | [MCP tools](mcp/README.md). |
| Understand what a banner does when you click it | [How banners behave](banners.md). |
| Look up a word | [Glossary](glossary.md). |

## How banners behave and look

| Page | What it covers |
|---|---|
| [How banners behave](banners.md) | Where a banner appears, how long it stays, what a click does, and how stacks, replies and snoozing work. |
| [Grid and layout](grid-and-layout.md) | The template object, the grid, merged cells, cell sizes and how empty rows and columns collapse. |
| [Bindings](bindings.md) | The `{token}` syntax, where values come from, and what counts as empty. |
| [Manifests](manifests.md) | How an app declares the fields it sends, its actions and its assets. |
| [Stacking](stacking.md) | The four stacking levels, the `group` field and the open list. |
| [Quiet hours](quiet-hours.md) | Windows and one-off periods that silence speech, sounds and banners. |

## Components

A template is made of components. [Components](components/README.md) explains what every component shares: the cell,
alignment, empty values, colours and limits. Each component then has its own page.

| Component | What it draws |
|---|---|
| [`text`](components/text.md) | A line or paragraph of text, with Markdown links. |
| [`image`](components/image.md) | A picture from a file, a link or the notification. |
| [`issuerIcon`](components/issuerIcon.md) | The icon of the app that sent the notification. |
| [`timestamp`](components/timestamp.md) | The time the notification was delivered. |
| [`button`](components/button.md) | One button that runs an action. |
| [`actions`](components/actions.md) | The row of buttons from the app and the template, with the snooze menu. |
| [`iconButton`](components/iconButton.md) | A round button with a symbol, such as the close button. |
| [`badge`](components/badge.md) | A small pill with a label. |
| [`stackBadge`](components/stackBadge.md) | The count of a stack, which opens the stack when pressed. |
| [`progress`](components/progress.md) | A progress bar. |
| [`rive`](components/rive.md) | A Rive animation. |
| [`spacer`](components/spacer.md) | Empty room that keeps cells apart. |

## Buttons, motion and voice

| Page | What it covers |
|---|---|
| [Actions](actions.md) | Action kinds, the rules that hide or add buttons, approvals, and what an action receives. |
| [Voice](voice.md) | Speaking a notification, playing a voice message, the speech engines and what History records. |
| [Rive](rive.md) | Preparing a `.riv` file, its inputs, where files live, and how to test an animation. |
| [Symbols](symbols.md) | Using SF Symbols on components and actions: weight, scale, colour and effects. |

## Interfaces

Each interface has one home for every endpoint, tool or command, so a fact is never written twice.

| Page | What it covers |
|---|---|
| [HTTP API](api/README.md) | Connecting, the token, request rules, shared errors and limits, and the index of every endpoint page. |
| [Notifications API](api/notifications.md) | Show, speak, dismiss and snooze, and every field of a notification. |
| [Apps API](api/apps.md) | Registering, listing and removing apps, per-app settings and approvals. |
| [Templates API](api/templates.md) | Saving, copying, exporting and previewing templates, and the component and symbol lists. |
| [Manifests API](api/manifests.md) | Saving, reading and deleting an app's manifest. |
| [Assets API](api/assets.md) | Storing an app's Rive animations and images. |
| [History API](api/history.md) | Reading, searching, re-showing, deleting and exporting past notifications. |
| [Replies API](api/replies.md) | Reading what a user typed into a banner, and the callback Herald sends. |
| [Stacks API](api/stacks.md) | Listing and opening stacks, and the stacking setting. |
| [Settings API](api/settings.md) | General, voice and quiet hours settings. |
| [Voice and MCP setup API](api/setup.md) | Installing the Kokoro voice and the MCP server. |
| [Cloud relay API](api/relay.md) | Deploying, pairing and managing the relay from this Mac. |
| [Diagnostics API](api/diagnostics.md) | Health, the Designer snapshot and the Rive check. |
| [MCP tools](mcp/README.md) | What the MCP server is, its conventions and the index of every tool. |
| [Notification tools](mcp/notifications.md) | Sending, speaking, dismissing, snoozing, stacks and replies. |
| [Template tools](mcp/templates.md) | Manifests, templates, previews, symbols, shortcuts and assets. |
| [App and settings tools](mcp/apps-and-settings.md) | Apps, settings, quiet hours, approvals, voice, MCP install and History. |
| [Relay tools](mcp/relay.md) | Setting up and operating the relay. |
| [Command line](cli.md) | Every `herald` command, with options and exit status. |
| [Clients](../../clients/README.md) | The Swift, Python and Node client libraries. |
| [Relay remote API](relay-api.md) | The relay's own endpoints for agents, OAuth connectors and devices. |
| [Parity](parity.md) | Each capability against its HTTP route, command and MCP tool. |

## Words

| Page | What it covers |
|---|---|
| [Glossary](glossary.md) | The terms Herald uses, with a sentence each. |

## Check an example

Template and component examples in these pages were checked with Herald's own validator. There are three ways to check
yours:

- Call the [`validate_template`](mcp/templates.md#validate_template) tool. It works without Herald running.
- Send the template with [`PUT /v1/templates`](api/templates.md#put-v1templates). Herald refuses a bad one with an error that names the cell.
- Draw it with [`POST /v1/preview`](api/templates.md#post-v1preview) and look at the picture.

## Related

- [Install Herald](../install.md)
- [Send your first notification](../getting-started.md)
- [The Herald app](../APP.md)
