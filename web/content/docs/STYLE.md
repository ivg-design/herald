# Documentation style guide

This is the format every page of Herald's documentation follows. It is for anyone who writes or edits a file under
`docs/`, `README.md` or `clients/README.md`, person or agent. Read it before you change a page. The lint script
`web/scripts/test-docs-structure.mjs` checks the mechanical rules; the rest is checked in review.

The Markdown in this repository is the single source. The docs site renders the same files, so every convention
here is plain Markdown that also reads well on GitHub.

## The reader comes first

A page is finished when a reader who has never seen Herald can answer three questions from it:

1. What is this thing, and why would I use it?
2. How do I use it? What exactly do I send, type or click?
3. What comes back, and what can go wrong?

Reference material packed into a sentence fails all three. These are the patterns this guide exists to remove:

| Do not write | Write instead |
|---|---|
| Two endpoints, tools or commands in one paragraph. | One block per endpoint, tool or command. |
| A pseudo-JSON signature with `?` or a pipe in it. | A request table and a real example. |
| A list of field names in a sentence. | A table, one field per row. |
| A reply described in prose. | A real response in a fenced block and a table of its fields. |
| A section that starts with a field list. | One or two sentences on what the thing is for, then the list. |

## Page shape

Every page has the same order.

1. **Title.** One `#` heading, sentence case, naming the thing ("Quiet hours", not "Quiet Hours Reference").
2. **Opening paragraph.** What the page covers and who it is for, in one paragraph. No heading above it.
3. **Before you start.** Only when there are prerequisites: a short list of what must be true first.
4. **Concepts.** The ideas the reader needs, in plain words, before any table of fields.
5. **The body.** Blocks in the shapes below.
6. **Related.** The last section: links to the task page that uses this reference, or to the reference a task page
   relies on. Every reference page links to its task page and every task page links back.

Headings are sentence case and say what the section holds. Levels are never skipped: `##` then `###` then `####`.
The site builds the "On this page" list from `##` and `###`, so those two levels must make sense when read alone.

## Describe the product as it is

The docs describe Herald as it works today, in the present tense, as if it had always worked this way.

- No version history. No "new in", "since", "as of", "previously", "used to", "no longer", "replaces", and no
  sections about what a release added. The changelog is the only place for history.
- No version numbers, with two exceptions: the macOS requirement, and a version that is itself data the reader
  must send or will read (a `layoutVersion` value, an MCP protocol version string, a `version` field in a reply).
- An older input form that Herald still accepts is documented only if a reader could meet it in existing files.
  It goes in one table named "Accepted older forms" at the end of the reference page, with two columns (older
  form, current form) and no narrative.
- No time or effort estimates.

## Language

- Plain, grammatical, factual sentences. Explain why as well as what.
- No marketing words. No em dashes. Use a colon, a comma or a new sentence.
- Address the reader as "you". Herald is "Herald", never "we".
- Proper nouns are exact: Herald, WebWatcher, ChatGPT, OpenAI, Cloudflare, Claude Code, Claude Desktop, Codex,
  macOS, SF Symbols, Rive.
- An OpenAI **dot** is an always-on cloud agent. Introduce it once on a page ("an OpenAI dot, an always-on cloud
  agent") and then write "a dot", "the dot", "your dot", in lower case. Never name an individual dot or a private
  project.
- Interface labels are bold and match the app: **Settings > Cloud > Enable relay**.
- Never include a real secret, token, key id, device id, account id, relay hostname or the name of a real app
  installed on someone's Mac. Use the placeholders below.

| Placeholder | Stands for |
|---|---|
| `example.bidbot` | An app id. Examples use the fictional BidBot, or `webwatcher.email` on pages about WebWatcher. |
| `$HERALD` | The local API base URL. |
| `$TOKEN` | The local API bearer token. |
| `$RELAY` | The relay's origin, `https://herald-relay.example.workers.dev`. |
| `$KEY` | An agent key or connector access token (`hrk_...`, `hra_...`). |
| `hrk_...`, `hra_...`, `hrd_...` | A key, access token or device token, always elided. |

## Code

- Every fenced block has a language: `sh`, `json`, `swift`, `python`, `js`, `toml`, `http`, or `text` for
  diagrams, file trees and literal output.
- Shell examples use `$HERALD` and `$TOKEN` (or `$RELAY` and `$KEY`). A page that uses them defines them once,
  near the top, by linking to or repeating the setup block:

  ```sh
  D="$HOME/Library/Application Support/Herald"
  HERALD="http://127.0.0.1:$(cat "$D/port")"
  TOKEN="$(cat "$D/token")"
  ```

- JSON examples are valid JSON. No `?`, no pipe between alternatives, no `...` inside a structure, no comments.
  Optional fields are listed in the table, not marked in the example. A long real value is shortened to a
  shorter valid value, not cut with an ellipsis.
- Examples are real: a request that works when pasted, and the response Herald gives, trimmed to what matters.
- Keep lines under about 100 characters. The site wraps longer lines, but short ones read better everywhere.

## Tables

The docs never scroll horizontally, at any width from a phone to a wide desktop. Tables are the usual cause.

- Keep cells short. A cell is a phrase or one or two sentences. Anything longer goes in a paragraph or a list
  under the table.
- At most five columns.
- Every description cell is a full sentence with a full stop.
- A pipe inside inline code in a table is written `\|`.
- Wide tables restack into labelled rows on small screens. The site does this from the header row, so every
  table needs a header with short labels.
- The site styles a few column names: a column named **Type** is set in mono, and a cell that says "yes" in a
  column named **Required** becomes a required marker. Use exactly those names.

## Figures

A page that describes something the user sees shows it. That covers the Designer and each inspector tab, each
Settings tab, History, the menu, each banner state, and each step of a how-to that changes what is on screen.

- The image comes directly after the sentence that introduces it.
- Use plain Markdown with real alt text and a caption in the title position:
  `![What the image shows, for someone who cannot see it](../web/public/shots/docs/settings-voice.png "What to look at.")`
- The path is relative to the Markdown file and points into `web/public/shots/docs/`, so it resolves on GitHub
  and on the site. Only images listed in that folder's `manifest.json` are used.
- Names of buttons, tabs and fields in the text match the labels visible in the screenshot exactly.
- Never use a screenshot of text that should be a code block. No decorative images.
- In a how-to, show a screenshot at each step where the screen changes.
- A capture of a whole Settings tab is much taller than wide, so the site shows a window of it and opens the
  rest on a click. Add `#focus=70` to the image path to show the part 70 percent of the way down. GitHub ignores it.
- An annotated figure is an image followed directly by an ordered list. The site overlays the list numbers on
  the image, and on GitHub the list reads as a plain legend.

## Callouts

Use GitHub alert syntax. The site renders each as a styled callout, and GitHub renders them natively.

```md
> [!NOTE]
> Background the reader should know. The page still works without it.

> [!TIP]
> A shortcut or a better way.

> [!WARNING]
> Something that loses data, exposes a secret, or cannot be undone.
```

Use them sparingly: at most one or two per section. A plain `>` blockquote is for quoted text only.

## Block shapes

### Endpoint block

Used for the local HTTP API and the relay API. One endpoint per block: one method, one path.

The heading is the method and path as inline code. Below it, in this order:

1. One or two sentences: what it does and when to use it.
2. `**Request**`: a table with the columns Name, In, Type, Required, Description. **In** is `path`, `query`,
   `body` or `header`. The default goes at the end of the description ("Default `50`."). Write "No parameters."
   when there are none.
3. `**Example request**`: a `sh` block with a curl command.
4. `**Example response**`: a `json` block with the real reply, trimmed. For a binary reply, say what it is.
5. `**Response fields**`: a table (Field, Type, Description) when the reply has more than two fields.
6. `**Errors**`: a table (Status, When). List the errors specific to this endpoint. The errors every endpoint
   shares are documented once and linked.
7. `**Notes**`: a short list for rules such as "all or nothing".

The labels are bold paragraphs exactly as written above. The site turns them into section labels and pairs
the two examples.

````md
### `POST /v1/dismiss`

Closes one banner. The notification stays in History. Use it when the event behind a banner is over.

**Request**

| Name | In | Type | Required | Description |
|---|---|---|---|---|
| `app` | body | string | yes | The app id the notification was sent with. |
| `id` | body | string | yes | The notification id. |

**Example request**

```sh
curl -s -X POST "$HERALD/v1/dismiss" \
  -H "Authorization: Bearer $TOKEN" -H "Content-Type: application/json" \
  -d '{"app":"example.bidbot","id":"bid-42"}'
```

**Example response**

```json
{"ok": true}
```

**Errors**

| Status | When |
|---|---|
| `400` | `app` or `id` is missing. |
````

### MCP tool block

One tool per block. The heading is the tool name as inline code. Below it:

1. One or two sentences: what the tool is for and when an agent should call it.
2. `**Arguments**`: a table (Name, Type, Required, Description). "No arguments." when there are none.
3. `**Example call**`: a `json` block with the arguments object.
4. `**Example result**`: a `json` block (or a sentence for an image result).
5. `**HTTP route**`: the endpoint the tool calls, linked to its endpoint block.
6. `**Side effects**`: one line. Say whether it shows a banner, speaks, changes state, or needs the user.
   "None. Read-only." when that is true.

### CLI command block

One command per block. The heading is the command as inline code (`herald send`). Below it: what it does, a
`**Options**` table (Option, Type, Description), an `**Example**` in a `sh` block, the output in a `text` or
`json` block, and the `**Exit status**` when it is not simply zero on success.

### Component block

One page per template component. The page has, in order:

1. What the component draws and when to use it.
2. `**Minimal example**`: the smallest valid JSON cell.
3. `**Realistic example**`: one cell as it would appear in a real template.
4. `**Properties**`: a table (Property, Type, Default, Description). Each description is a full sentence.
5. Behaviour sections: empty values and collapsing, sizing, interaction.
6. Common mistakes, as a table (Mistake, What happens, Fix).

### Field block

Used for notification fields, manifest fields and settings keys. Table first: Field (or Key), Type, Required
(or Default), Description. Each row is a full sentence. Follow the table with one minimal JSON example and one
realistic one. Rules that span several fields go in a list under the table, not in a cell.

### How-to shape

Used for task pages: connecting an agent, setting up the relay, designing a banner.

1. Opening paragraph: what you will have at the end.
2. `## Before you start`: what must be true first.
3. `## Steps`: a numbered list. One action per step. After the action, say what the reader should see
   ("The switch turns on and the status reads **Online**.").
4. `## Check that it works`: one way to confirm the result.
5. `## If it does not work`: a table (Symptom, Cause, Fix).
6. `## Related`: the reference pages behind the task.

A how-to does not explain internals. Link to the concept or reference page instead.

## Linking

- Link with relative paths between Markdown files (`../reference/api/settings.md#get-v1settings`). The site
  rewrites them to its own routes.
- Link text names the destination ("[Quiet hours](reference/quiet-hours.md)"), never "here" or a bare file name.
- Each endpoint, tool, component, field, setting key and CLI command is documented once, in its reference home.
  Other pages link to it and do not repeat its table.

## Checks

Run these before you commit a docs change:

```sh
cd web
node scripts/sync-content.mjs
node scripts/test-docs-structure.mjs
```

The structure lint fails on: two endpoints in one paragraph, a pseudo-JSON signature in a code span, an endpoint
heading with no fenced example, a fenced block without a language, invalid JSON in a `json` block, a skipped
heading level, an unescaped pipe in inline code inside a table, a relative link or image that does not resolve, an
image without alt text, a page about the app's windows or banners without a figure, version-history wording, and the
name of an individual dot or private project.
