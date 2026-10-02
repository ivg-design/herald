# Herald reference

The complete reference for Herald's templates, components, Rive animations, actions, API, CLI and MCP server.
Every page is written from the code. Where the code does not decide something the page says **TBD - verify**
instead of guessing. The shorter guides stay where they are: [../TEMPLATES.md](../TEMPLATES.md),
[../ACTIONS.md](../ACTIONS.md), [../API.md](../API.md), [../MCP.md](../MCP.md), [../AUTHORING.md](../AUTHORING.md),
[../VOICE.md](../VOICE.md), [../AGENT-QUICKSTART.md](../AGENT-QUICKSTART.md).

## Reading order

If you are designing a banner:

1. [grid-and-layout.md](grid-and-layout.md): the template object, the grid, cells and merging, sizes, and how empty
   rows and columns collapse.
2. [bindings.md](bindings.md): `{tokens}`, where values come from, what "empty" means.
3. [manifests.md](manifests.md): how an issuer declares fields, samples, actions and assets.
4. [components/README.md](components/README.md), then the component pages you need.
5. [actions.md](actions.md): buttons, rules, confirmation gates.
6. [rive.md](rive.md) and [symbols.md](symbols.md) when you want motion.

If you are integrating an app or an agent: [api.md](api.md), [cli.md](cli.md), [mcp-tools.md](mcp-tools.md).

## Contents

### Layout and data

| Page | Covers |
|---|---|
| [grid-and-layout.md](grid-and-layout.md) | Template fields, the 3 x 4 grid, sizes (fixed, auto, fill), merged cells, the size solver, the collapse planner with worked examples. |
| [bindings.md](bindings.md) | Token syntax, sources and precedence, types, empty rules, sample data. |
| [manifests.md](manifests.md) | Manifest fields, actions, assets, limits, endpoints. |

### Components (one page each)

Shared: [components/README.md](components/README.md): the cell, the 9-point alignment, empty behaviour, colours, light
and dark, limits.

| Component | Page |
|---|---|
| `text` | [components/text.md](components/text.md) |
| `image` | [components/image.md](components/image.md) |
| `issuerIcon` | [components/issuerIcon.md](components/issuerIcon.md) |
| `timestamp` | [components/timestamp.md](components/timestamp.md) |
| `button` | [components/button.md](components/button.md) |
| `actions` | [components/actions.md](components/actions.md) |
| `iconButton` | [components/iconButton.md](components/iconButton.md) |
| `badge` | [components/badge.md](components/badge.md) |
| `stackBadge` | [components/stackBadge.md](components/stackBadge.md) |
| `progress` | [components/progress.md](components/progress.md) |
| `rive` | [components/rive.md](components/rive.md) |
| `spacer` | [components/spacer.md](components/spacer.md) |

### Motion and icons

| Page | Covers |
|---|---|
| [rive.md](rive.md) | Preparing a `.riv`, inputs, hover and click, sizing, where files live, uploading, referencing, bundles, fallbacks, testing without a window, a worked example, troubleshooting. |
| [symbols.md](symbols.md) | SF Symbols (from 1.3): weight, scale, rendering modes, colours, variable value, placement, effects, with an example for each. |

### Behaviour

| Page | Covers |
|---|---|
| [actions.md](actions.md) | Action objects and kinds, issuer vs template actions, rules, confirmation gates, what actions receive, callbacks. |
| [stacking.md](stacking.md) | Stacking levels, behaviour, the counter, API. |
| [voice.md](voice.md) | `speak`, `audio`, `presentation`, engines, history. |
| [quiet-hours.md](quiet-hours.md) | Windows, ad hoc silence, resume, urgent, API. |

### Interfaces

| Page | Covers |
|---|---|
| [api.md](api.md) | Every HTTP endpoint with request, response and errors, limits. |
| [cli.md](cli.md) | The `herald` command line tool. |
| [mcp-tools.md](mcp-tools.md) | Every MCP tool and its arguments, resources. |
| [parity.md](parity.md) | Every Designer, History and Settings capability against its route, CLI command and MCP tool. |

### Reference

[glossary.md](glossary.md)

## Versions

The component set, grid, actions, manifests, Rive, stacking, voice and quiet hours describe Herald 1.2. Sections
marked **available from 1.3** (SF Symbols on components and actions, the Designer's live preview and Symbol
panel) describe work that ships in 1.3.

## Checking an example

All JSON in these pages that is a template or a component was checked with the real validator. To check your own:

```sh
herald-mcp   # then tools/call validate_template {"template": {...}}   (works without Herald running)
```

or `PUT /v1/templates` (rejects errors, naming the cell), then `POST /v1/preview` to look at it.
