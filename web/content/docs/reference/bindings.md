# Bindings and tokens

A **binding** is a string with `{token}` placeholders. Components read data through bindings; nothing else
connects a notification to a banner.

```
"{title}"                      one token
"{count} new from {sender}"    several tokens and literal text
"Build {extra.build}"          a template `extra` value
"{customer.name}"              a nested metadata value
```

## Syntax

- A token is a name made of letters, digits, `_`, `.` and `-`, between `{` and `}`.
- Braces that do not enclose such a name (`{}`, `{ a b }`, `{"json": 1}`) are left exactly as written.
- Substituted text is never scanned again: a value that contains `{x}` stays as typed.
- There are no expressions, filters or defaults. Format values in the issuer.

## Where values come from

Each notification is flattened into one dictionary of **fields**. An earlier source wins over a later one, and
blank values are left out, so "absent" and "blank" are the same thing.

1. The payload's top-level keys: `title`, `subtitle`, `body`, `image`, `url`, `app`, `id`, `priority`, `sound`,
   `group`.
2. `appName` from the issuer's manifest.
3. Every scalar and list in `metadata`. Nested objects are flattened to dotted names, up to three levels deep
   (`customer.name`, `customer.address.city`); arrays of scalars become lists; `null` and mixed arrays are skipped.
   Any other top-level key a sender puts in a notify body (a manifest field such as `subject` or `count`) is
   moved into `metadata` by the server, so `{"title":"x","count":2}` and `{"title":"x","metadata":{"count":2}}`
   are the same thing (where both exist, the top-level key wins).
4. `extra.<key>`: the template's own `extra` values (always strings).
5. `deliveredAt`: the delivery time as ISO 8601.
6. `stack.count`: the number of notifications folded into the banner's stack; present only while there are two
   or more (see [stacking.md](stacking.md)).
7. `image` is also present whenever the banner has a picture (for example a Composer preview that was handed
   one).

The standard tokens, available without a manifest: `title`, `subtitle`, `body`, `image`, `url`, `app`,
`appName`, `id`, `priority`, `sound`, `group`, `deliveredAt`, `stack.count`.

## Three provenances

Every token in the Designer's pickers is filed under where its value comes from, and the sample shown beside
a token is what a preview fills it with:

| Group in the picker | Provenance | What it is | Sample shown |
|---|---|---|---|
| **From the issuer app (manifest field)** | the issuer | A field the issuer's manifest declares (`sender`, `thumbnail`). The issuer promises to send it, with a type and a sample. | the manifest's `sample` |
| **From the notification (payload field)** | the notification | A standard key (`title`, `body`, `image`, `deliveredAt`, `stack.count`...), or any other key a real notification carried (`customer.name`) or you typed as a custom token. Not promised by anyone: absent when the notification does not send it. | the sample or the last real value |
| **Set here (fixed value)** | the template | An `extra.<key>` value you wrote in the template. The same for every notification. | the value itself |

A fixed picture for an `image` component is the same idea without a token: the binding is a plain file path
(for example one inside `~/Library/Application Support/Herald/template-images/`), which is never empty while
the file exists. See [components/image.md](components/image.md#source).

## Types

With the issuer's manifest, a field declared `number` or `bool` that arrives as text is converted
(`"2"` becomes 2; `true`, `yes`, `1` and `false`, `no`, `0` become booleans). Display formatting:

| Value | Printed as |
|---|---|
| text | itself |
| number | without a trailing `.0` (`3`, `3.5`) |
| boolean | `true` / `false` |
| list | items joined with `, ` |

## Empty

A component is **empty** when its binding has at least one token and every one of them is absent. A binding
with no token is a literal; it is empty only when blank. In a mixed binding, absent tokens become empty text, literal text stays, and the
result is trimmed of leading and trailing whitespace: `"{sender}: {subject}"` without `sender` reads
`: Invoice #4021`. Literal text never keeps a component alive: `"{count} new"` with no `count` is empty, not
`new`. Design bindings so a missing part still reads well (`"{sender} {subject}"`), or split them into two
components that collapse independently.

What each component counts as its bindings is in its page under "Empty when". `rive` ignores tokens for
emptiness; `issuerIcon`, `spacer` never read data.

## Sample values

The Designer, `POST /v1/preview` with `"data":"sample"` and `render_preview` fill the fields from the manifest's
`sample` values. A declared field with no sample gets a stand-in: a humanised key for text (`receivedAt` becomes
"Received at"; `title`, `subtitle` and `body` get "Notification title", "A short subtitle", "Body text goes
here."), `3` for numbers, the current time for dates, `https://example.com` for urls, `true` for booleans, three
items for lists, and nothing for `image`. Without a manifest only a generic title, subtitle and body exist.

## Where tokens may be used

| Place | Tokens allowed |
|---|---|
| `text.binding`, `badge.binding`, `progress.binding`, `timestamp.binding`, `image.binding` | yes |
| `rive.inputBindings` values | yes (a single token keeps its type) |
| An action's `label` and `input` | yes |
| A **template** action's `url` | yes (values are percent-encoded; a leading `{url}` whose value is itself an openable link is kept whole). An action the **issuer** sent is used as written. |
| A shell `command` | no substitution into the command text for issuer data; data arrives on stdin and in `HERALD_*` environment variables (see [actions.md](actions.md#what-an-action-receives)) |
| Template defaults `title`, `subtitle`, `body`, `url` | yes, filled from `metadata` and the payload |
| `symbol.colors`, `symbol.variableValue` | yes, from 1.3 (see [symbols.md](symbols.md)) |
| `stateMachine`, `artboard`, `asset`, `path` | no, literal |

## Manifest field declarations

The manifest tells the Designer and the validator which tokens an issuer sends, with a type and a sample (see
[manifests.md](manifests.md)). With a manifest, `validate_template` warns about tokens it does not declare
(`token {x} is not declared in the manifest (it only resolves if the issuer sends it)`) and about `{extra.key}`
with no matching key in the template's `extra`.
