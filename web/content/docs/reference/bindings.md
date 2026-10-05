# Bindings and tokens

A banner shows data that arrives with each notification. A **binding** is how a template says which data goes
where: a string with `{token}` placeholders, written in a component's `binding` property. This page explains
what a token is, where its value comes from, how values are printed, and what happens when a value is
missing. It is for anyone who writes template JSON or designs a banner in the Designer.

## Concepts

A **token** is a name between braces, such as `{title}` or `{customer.name}`. When Herald draws a banner it
replaces each token with the value of the field of that name. A binding can be one token, several tokens
with text around them, or plain text:

```json
{"type": "text", "binding": "{count} new from {sender}"}
```

Everything a notification sends is flattened into one dictionary of **fields**. A token reads one field.
Nothing else connects a notification to a banner, so a field a template never names is never shown.

A field is **absent** when the notification does not send it or sends a blank value. A component whose tokens
are all absent is **empty**, and an empty component can collapse. See [Empty values](#empty-values).

## Syntax

| Rule | Example | Result |
|---|---|---|
| A token is letters, digits, `_`, `.` and `-` between braces. | `{customer.name}` | The field `customer.name`. |
| Braces that do not enclose such a name are plain text. | `{}`, `{ a b }`, `{"json": 1}` | Left exactly as written. |
| Substituted text is never scanned again. | A value `{x}` | Stays as typed. |
| There are no expressions, filters or default values. | | Format values before you send them. |

## Where values come from

Each source adds fields. An earlier source wins over a later one when two define the same name.

| Order | Source | Fields |
|---|---|---|
| 1 | The notification's own keys | `title`, `subtitle`, `body`, `image`, `url`, `app`, `id`, `priority`, `sound`, `group` |
| 2 | The app's manifest | `appName` |
| 3 | `metadata` | Every scalar and list in it, and keys a sender put at the top level of the request. See [Metadata](#metadata). |
| 4 | The template's `extra` | `extra.<key>`, always text. |
| 5 | Delivery | `deliveredAt`, the delivery time as an ISO 8601 string. |
| 6 | The banner's stack | `stack.count`, present only while two or more notifications are stacked. See [Stacking](stacking.md). |

Blank values are left out, so a field that is an empty string is the same as a field that is missing.

`image` is also present whenever the banner has a picture, for example a preview that was handed one.

### Built-in tokens

These tokens exist without any manifest. Whether they have a value depends on what the notification sent.

| Token | Type | Description |
|---|---|---|
| `{title}` | text | The headline. |
| `{subtitle}` | text | The second line. |
| `{body}` | text | The main text. |
| `{image}` | image | The notification's picture. |
| `{url}` | url | The notification's link. |
| `{app}` | text | The app id, for example `example.bidbot`. |
| `{appName}` | text | The app's display name from its manifest. |
| `{id}` | text | The notification id. |
| `{priority}` | text | `low`, `normal`, `high` or `urgent`, when sent. |
| `{sound}` | text | The sound the notification asked for. |
| `{group}` | text | The stacking key. |
| `{deliveredAt}` | date | When Herald received the notification. |
| `{stack.count}` | number | How many notifications the banner stands for. Absent while the banner is alone. |
| `{extra.key}` | text | A value from the template's `extra`. |

### Metadata

`metadata` carries any data your app wants a template to use. Herald flattens it into fields:

- A string, number or boolean becomes a field with the key's name.
- An object becomes dotted names, up to three levels of nesting: `customer.name`, `customer.address.city`.
- An array of strings, numbers or booleans becomes a list.
- `null`, and arrays that hold objects, are skipped.
- A key that is already taken by an earlier source is skipped.

A key at the top level of a notification request that is not a notification field, such as a manifest field
called `count`, is moved into `metadata` before any of this. These two requests give the same fields. When a
key is in both places, the top-level one wins.

```json
{"app": "example.bidbot", "title": "Bid accepted", "count": 2}
```

```json
{"app": "example.bidbot", "title": "Bid accepted", "metadata": {"count": 2}}
```

A request with nested data and the fields it produces:

```json
{
  "app": "example.bidbot",
  "title": "Bid accepted",
  "amount": 4200,
  "metadata": {
    "client": {"name": "Acme", "address": {"city": "Oslo"}},
    "tags": ["rfp", "q3"],
    "note": null
  }
}
```

| Field | Value | Note |
|---|---|---|
| `title` | `Bid accepted` | A notification key. |
| `amount` | `4200` | A top-level key, moved into `metadata`. |
| `client.name` | `Acme` | Flattened. |
| `client.address.city` | `Oslo` | Flattened. |
| `tags` | `rfp, q3` | A list prints joined by a comma and a space. |
| `note` | none | `null` is skipped, so the field is absent. |

### Where a token comes from in the Designer

The Designer files every token it offers under where its value comes from. The sample shown beside a token
is what the preview fills it with.

| Group in the menu | Source | What it is | Sample |
|---|---|---|---|
| **From the issuer app (manifest field)** | The manifest | A field the app's manifest declares, with a type and a sample. The app promises to send it. | The manifest's `sample`. |
| **From the notification (payload field)** | The notification | A built-in token, or any other key a real notification carried or you typed as a custom token. Nobody promises it, so it is absent when the notification does not send it. | The last real value, or a stand-in. |
| **Set here (fixed value)** | The template | An `extra.<key>` value you wrote in the template. The same for every notification. | The value itself. |

The palette on the left lists the same tokens in smaller groups: **Issuer fields**, **Standard**,
**Seen in notifications**, **Extra (yours)** and **Custom**.

A fixed picture is the same idea without a token. An `image` component whose binding is a plain file path
shows that file for every notification, and is never empty while the file exists. See
[Image source](components/image.md).

## Formatting

Values are printed as plain text. Components that need a number or a date read the text.

| Value | Printed as |
|---|---|
| Text | Itself. |
| Number | Without a trailing `.0`: `3` and `3.5`. |
| Boolean | `true` or `false`. |
| List | The items joined with a comma and a space. |

When the app has a manifest, a field declared `number` or `bool` that arrives as text is converted.

| Declared type | Text | Becomes |
|---|---|---|
| `number` | `"2"` | The number 2. |
| `bool` | `true`, `yes` or `1` | True. |
| `bool` | `false`, `no` or `0` | False. |

How components read their value:

| Component | Reads the value as |
|---|---|
| `progress` | A fraction. `0.4`, `40` and `40%` all mean 40 percent. A number above 1 is a percentage. The result is held between 0 and 1. |
| `timestamp` | A date: ISO 8601 text, or seconds or milliseconds since 1970. With `relative` it prints `3 min. ago`. Otherwise it prints the time for today and the date and time for another day. |
| `image` | A file path, an `https` URL or a `data:` URI. |

## Empty values

A component is **empty** when its binding has at least one token and every token is absent. A binding with
no token is literal text, and it is empty only when it is blank.

In a binding with several tokens, absent tokens become empty text, literal text stays, and the result is
trimmed. Literal text never keeps a component alive.

| Binding | Fields present | Result |
|---|---|---|
| `{title}` | none | Empty. |
| `{sender}: {subject}` | `subject` only | `: Invoice 4021` |
| `{sender} {subject}` | `subject` only | `Invoice 4021` |
| `{count} new` | none | Empty, not `new`. |
| `Inbox` | none | `Inbox`, because it has no token. |

Write bindings so that a missing part still reads well, or split them into two components that collapse
independently. A multi-line text drops a line whose tokens are all absent, and is empty when no line has
content.

What each component counts as its binding is on its page under empty values:
[Components](components/README.md). `issuerIcon` and `spacer` never read data and are never empty. A `rive`
cell is empty only when it names no animation. An action label that comes out empty shows the action's id.
The full rules for collapsing are in [Collapse semantics](../TEMPLATES.md#collapse-semantics).

## Template default text

A template's default `title`, `subtitle`, `body` and `url` use the same token syntax, but they are filled
when the notification arrives, from a smaller set of values:

1. `metadata`, including nested names such as `{customer.name}`.
2. The notification's own `title`, `subtitle`, `body`, `app`, `id` and `group`.

A token with no value becomes empty text. Only text that comes from the template is filled. A notification's
own text may contain braces, and they are left alone. In a `url`, each substituted value is percent-encoded.

## Sample values

The Designer, [`POST /v1/preview`](api/templates.md#post-v1preview) with `"data": "sample"` and the MCP tool
`render_preview` fill fields from the `sample` values in the app's manifest. A declared field with no sample
gets a stand-in:

| Field type | Stand-in |
|---|---|
| `text` | The key made readable: `receivedAt` becomes `Received at`. `title`, `subtitle` and `body` get `Notification title`, `A short subtitle` and `Body text goes here.` |
| `number` | `3` |
| `date` | The current time. |
| `url` | `https://example.com` |
| `bool` | `true` |
| `list` | `One`, `Two`, `Three` |
| `image` | Nothing, because there is no picture to invent. |

Without a manifest, only a generic title, subtitle and body exist.

## Where tokens may be used

| Place | Tokens | Note |
|---|---|---|
| `binding` of `text`, `badge`, `progress`, `timestamp` and `image` | yes | |
| A text's `lines`, in a run's `token` | yes | |
| `inputBindings` values of `rive` | yes | A single token keeps its number or boolean type. |
| An action's `label` and `input` | yes | |
| The `url` of an action the template adds | yes | Values are percent-encoded. A leading `{url}` whose value is an openable link is kept whole. |
| The `url` of an action the issuer sends | no | It is used as written. |
| A shell `command` | no | Data reaches the command on standard input and in `HERALD_*` environment variables. See [Actions](actions.md). |
| Template defaults `title`, `subtitle`, `body`, `url` | yes | See [Template default text](#template-default-text). |
| `symbol.colors` and `symbol.variableValue` | yes | See [Symbols](symbols.md). |
| `stateMachine`, `artboard`, `asset`, `path` | no | Always literal. |

## Declared fields and warnings

The manifest tells the Designer and the validator which tokens an app sends, with a type and a sample. See
[Manifests](manifests.md). With a manifest, the validator warns about a token the manifest does not declare:

```text
token {sender} is not declared in the manifest (it only resolves if the issuer sends it)
```

The warning does not block saving, because a notification can still send the field in `metadata`. The
validator also warns when `{extra.key}` has no matching key in the template's `extra`.

## Related

- [Grid, cells and layout](grid-and-layout.md): where components and their bindings sit.
- [Template guide](../TEMPLATES.md): bindings in a worked template.
- [Design a banner in the Designer](../AUTHORING.md): the **Insert field** menus and the palette.
- [Manifests](manifests.md): declaring the fields an app sends.
- [Components](components/README.md): each component's bindings and empty behaviour.
