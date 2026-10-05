# Docs restructure: inventory

What every documentation page looked like before the rewrite, and where its content is now. A blob is reference
content packed into prose: a pseudo-signature, several endpoints or tools in one paragraph or cell, a list of field
names in a sentence, a table cell that holds a paragraph, or a section with no explanation of what it is for.

## How the pages were counted

- **Lint hits**: problems reported by `web/scripts/test-docs-structure.mjs` when it was first run on the old files
  (336 in 33 files: 206 pseudo-signatures, 41 version-history phrases, 39 unresolved links, 21 paragraphs with
  several endpoints, 11 endpoint headings with no example, 10 fences without a language, 4 invalid JSON blocks).
- **Dense paragraphs**: prose blocks with five or more inline code spans, a rough measure of field lists in sentences.
- **Blobs found**: what the person rewriting the page counted when reading it.

## Before

| Page | Lint hits | Dense paragraphs | Blobs found | Where the content is now |
|---|---|---|---|---|
| `README.md` | 16 | 5 | 5+ (pseudo-JSON API table, notification field list in a paragraph, security limits in bullets, install/API/examples/troubleshooting mixed; a "What's new in 1.6 to 1.8" section) | README.md (landing + docs map), docs/install.md, docs/getting-started.md, docs/troubleshooting.md, docs/examples/webwatcher.md |
| `clients/README.md` | 2 | 0 | 3 (one-sentence Swift section, one snippet each for Python and Node, no function tables) | clients/README.md |
| `docs/API.md` | 31 | 9 | 31 mechanical; a version-framed overview that repeated the reference in prose | deleted; facts in docs/reference/api/*.md |
| `docs/reference/api.md` | 74 | 21 | 74 mechanical, 21 dense paragraphs: every multi-endpoint bullet, every pseudo-signature, the relay table with paragraph cells | deleted; 13 pages under docs/reference/api/ |
| `docs/reference/mcp-tools.md` | 75 | 5 | 75 mechanical; about 35 (two giant parity and relay tables with arguments packed into cells, pseudo-signatures) | deleted; 5 pages under docs/reference/mcp/ |
| `docs/CLOUD.md` | 22 | 14 | 22 mechanical, 14 dense paragraphs: tools and endpoints lists in prose, the OAuth endpoint table with paragraph cells, device endpoints in one sentence, secret-store history | docs/CLOUD.md (setup how-to) + 7 pages under docs/cloud/ + docs/reference/relay-api.md |
| `docs/MCP.md` | 28 | 10 | about 8 (20 tools in one sentence, a paragraph naming about 50 tools, relay and device-flow lists) | docs/MCP.md (how-to) + docs/reference/mcp/README.md |
| `docs/AGENT-QUICKSTART.md` | 7 | 5 | 1 large (a 14-step cloud walkthrough in prose, CLI and HTTP content out of place) | docs/AGENT-QUICKSTART.md; cloud steps in docs/cloud/* |
| `docs/TEMPLATES.md` | 5 | 11 | 8 | docs/TEMPLATES.md; field tables in reference/grid-and-layout.md and components/* |
| `docs/AUTHORING.md` | 3 | 2 | 4, plus three sections that were lists of form fields | docs/AUTHORING.md (Designer how-to); Quick send and Template editor in docs/APP.md |
| `docs/ACTIONS.md` | 4 | 10 | 3 | docs/ACTIONS.md (how-to); reference in reference/actions.md |
| `docs/VOICE.md` | 6 | 6 | 6 | docs/VOICE.md (how-to) |
| `docs/TESTING.md` | 0 | 3 | 3 | docs/TESTING.md |
| `docs/reference/actions.md` | 6 | 6 | about 8 | docs/reference/actions.md |
| `docs/reference/manifests.md` | 4 | 2 | about 5 | docs/reference/manifests.md; endpoints in api/manifests.md |
| `docs/reference/grid-and-layout.md` | 4 | 6 | 6 | docs/reference/grid-and-layout.md |
| `docs/reference/bindings.md` | 1 | 7 | 5 | docs/reference/bindings.md |
| `docs/reference/voice.md` | 2 | 0 | 7 | docs/reference/voice.md; POST /v1/speak in api/notifications.md |
| `docs/reference/quiet-hours.md` | 1 | 1 | 5 | docs/reference/quiet-hours.md; endpoints in api/settings.md |
| `docs/reference/stacking.md` | 6 | 0 | 4 | docs/reference/stacking.md; endpoints in api/stacks.md |
| `docs/reference/glossary.md` | 0 | 6 | 8 | docs/reference/glossary.md |
| `docs/reference/parity.md` | 2 | 0 | 1 structural (6-column tables, Before/After history) | docs/reference/parity.md |
| `docs/reference/README.md` | 2 | 0 | 2 (TBD wording, a Versions section) | docs/reference/README.md |
| `docs/reference/cli.md` | 1 | 3 | 14 commands without a block of their own, paragraph cells | docs/reference/cli.md (38 command blocks) |
| `docs/reference/rive.md` | 2 | 6 | about 14 | docs/reference/rive.md; POST /v1/rive/check in api/diagnostics.md |
| `docs/reference/symbols.md` | 1 | 1 | about 8 | docs/reference/symbols.md |
| `docs/reference/components/*.md (13 files)` | 7 | 12 | about 25 (every Properties table had a notes column holding paragraphs; README had 5) | docs/reference/components/*.md |
| `docs/examples/README.md` | 0 | 0 | 1 | docs/examples/README.md |
| `docs/examples/bidbot/README.md` | 4 | 3 | 1 large (one long feature list) | docs/examples/bidbot/README.md |

## After

Every page follows `docs/STYLE.md`. `node web/scripts/test-docs-structure.mjs` reports no problems in 71 files.

| Measure | Before | After |
|---|---|---|
| Markdown files | 39 | 71 (70 pages and the style guide) |
| Site pages | 62 | 77 |
| Lint problems | 336 in 33 files | 0 |
| Pseudo-signatures | 206 | 0 |
| Paragraphs with several endpoints | 21 | 0 |
| Version-history phrases | 41 | 0 |
| Prose blocks with seven or more code spans | not counted | 2 (both are sentences that name the keys of a result, in `mcp/templates.md` and `manifests.md`) |
| Table cells over 230 characters | not counted | 0 |
| Figures | 0 | 107 references to 40 captures, plus 3 example renders |
| Local API endpoints with their own block and example | 0 of 78 | 78 of 78 |
| Relay API endpoints with their own block | 0 | 35 |
| MCP tools with their own block | about 21 of 69 | 69 of 69 |
| CLI commands with their own block | 6 of 40 | 40 of 40 |

### Pages now

| Group on the site | Source files |
|---|---|
| Getting started | `docs/install.md`, `docs/getting-started.md`, `docs/AGENT-QUICKSTART.md`, `docs/APP.md` |
| Guides | `docs/AUTHORING.md`, `docs/TEMPLATES.md`, `docs/ACTIONS.md`, `docs/VOICE.md`, `docs/MCP.md`, `docs/TESTING.md` |
| Cloud relay | `docs/CLOUD.md`, `docs/cloud/how-it-works.md`, `connect-agent.md`, `connect-chatgpt.md`, `device-flow.md`, `reply-events.md`, `custom-domain.md`, `operating.md` |
| Concepts | `docs/reference/banners.md`, `manifests.md`, `grid-and-layout.md`, `bindings.md`, `actions.md`, `stacking.md`, `quiet-hours.md`, `voice.md` |
| Components | `docs/reference/components/*.md` (13) |
| Rive, SF Symbols | `docs/reference/rive.md` (6 pages), `docs/reference/symbols.md` (3 pages) |
| HTTP API | `docs/reference/api/README.md` and 12 area pages |
| MCP tools | `docs/reference/mcp/README.md` and 4 area pages |
| Reference | `docs/reference/cli.md`, `clients/README.md` (2 pages), `docs/reference/relay-api.md`, `parity.md`, `glossary.md` |
| Examples, Help | `docs/examples/bidbot/README.md`, `docs/examples/webwatcher.md`, `docs/troubleshooting.md` |

### Pages split, merged or moved

| Before | After |
|---|---|
| `docs/reference/api.md` | 13 pages under `docs/reference/api/`, one per area. |
| `docs/API.md` | Removed. Its facts are in `docs/reference/api/`. |
| `docs/reference/mcp-tools.md` | 5 pages under `docs/reference/mcp/`. |
| `docs/CLOUD.md` | `docs/CLOUD.md` keeps the concept and the setup. Seven task and concept pages under `docs/cloud/`, and `docs/reference/relay-api.md` for the relay's own API. |
| `README.md` sections Install, Examples, WebWatcher integration, Troubleshooting | `docs/install.md`, `docs/getting-started.md`, `docs/examples/webwatcher.md`, `docs/troubleshooting.md`. |
| Composer and Template editor sections of `docs/AUTHORING.md` | `docs/APP.md`. |
| New pages | `docs/APP.md` (menu, Quick send, History, every Settings tab), `docs/reference/banners.md` (how banners behave). |

The old site URLs redirect to the new ones. The list is `DOC_REDIRECTS` in `web/src/lib/docs-tree.ts`.
