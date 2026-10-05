# SF Symbols

SF Symbols are Apple's icon set. Herald draws them on buttons, badges and the issuer icon of a banner, and on the
action buttons themselves, with control over weight, size, rendering mode, colours, a variable value and, on
macOS 14 and later, motion effects. This page is for anyone who designs a banner template and wants an icon in it,
and for agents that write templates. The names come from the SF Symbols app, or from Herald's own symbol search.

Every JSON example here is valid against the component schema. Examples use the fictional app `example.bidbot` or
the WebWatcher email issuer, and the `$HERALD` and `$TOKEN` variables from [Connect](api/README.md#connect).

## Where a symbol can go

A symbol is a property called `symbol` on a component or on an action. This section lists every place it can go and
what Herald does with it there, so you can choose where the icon belongs.

| Where | What the symbol does |
|---|---|
| [`iconButton`](components/iconButton.md) | It is the glyph of the button, and it is required. A plain name or an object with `name` and styling. |
| [`button`](components/button.md) | It is drawn with the label, on the side `placement` picks. An action's own `symbol` wins over it. |
| [`actions`](components/actions.md) | Every button of the row gets it, unless that button's action has its own. |
| [`issuerIcon`](components/issuerIcon.md) | It is drawn instead of the app icon, at 62 percent of `size`. The app icon is drawn when the name is unknown. |
| [`badge`](components/badge.md) | It is drawn beside the value, before it (`leading`) or after it (`trailing`). |
| An action | It is the icon of that one button wherever the action appears. |
| An `actionRules` rule | It gives the icon to every action the rule matches. |

### Icons on individual action buttons

A row of buttons often needs a different icon on each button. Set `symbol` on the action itself, and the button shows
it in any `button` or `actions` component. You can set it three ways:

- On an action you write inline, in a template or in a notification.
- On an action an `actionRules` rule adds with `add`.
- On an action the issuer declared, with a rule that matches it. This is how you give an icon to a button the app
  sent, without changing the app.

A rule's `match` is an action id, an action label (not case-sensitive) or `*` for every action. The rule's `symbol`
replaces the matched actions' symbol, and a symbol with an empty name removes it. [Actions](actions.md) describes
rules in full.

```json
{"actionRules": [
  {"match": "markRead", "symbol": {"name": "checkmark.circle", "weight": "semibold"}},
  {"match": "archive", "symbol": "archivebox"}]}
```

### An icon-only button

Set the symbol's `placement` to `only` to drop the label and show just the icon. The label is not lost: it stays as
the button's tooltip, so the button remains understandable on hover. Do this on the action, so the button is icon-only
wherever the action appears:

```json
{"match": "archive", "symbol": {"name": "archivebox", "placement": "only"}}
```

For a round button that is always a single icon, use an [`iconButton`](components/iconButton.md) instead. It has no
label to drop.

## The `symbol` value

A symbol is either a plain name, or an object that names the symbol and styles it. This section explains each part of
the object, with the allowed values and the default for each, and shows how to find a valid name.

A plain name draws the symbol with the defaults of the place it is in:

```json
"bell.badge"
```

An object adds styling:

```json
{"name": "bell.badge", "weight": "semibold", "scale": "large", "placement": "leading",
 "renderingMode": "palette", "colors": ["#FF3B30", "primary"], "variableValue": 0.6,
 "effect": {"kind": "bounce", "trigger": "onChange", "speed": 1.5}}
```

| Property | Type | Default | Allowed values |
|---|---|---|---|
| `name` | string | none | An SF Symbol name. It is required. |
| `weight` | string | The component's own. | `ultraLight`, `thin`, `light`, `regular`, `medium`, `semibold`, `bold`, `heavy`, `black`. |
| `scale` | string | `medium` | `small`, `medium`, `large`. The size relative to the text. |
| `placement` | string | `leading` | `leading`, `trailing`, `only`. |
| `renderingMode` | string | `monochrome` | `monochrome`, `hierarchical`, `palette`, `multicolor`. |
| `colors` | array | The component's tint. | One to three colours. |
| `variableValue` | number or string | none | A number from 0 to 1, or a `{token}`. |
| `effect` | object | none | See [Effects](#effects). |

Notes on each property:

- **`name`** may contain a `{token}`, which is how the `replace` effect has something to swap.
  - An unknown name draws the component's default look. An `iconButton` shows `questionmark.circle`, a `button` shows its plain label and an `issuerIcon` keeps the app icon.
  - The validator warns that the name is not an SF Symbol on this Mac.
- **`weight`** defaults to `semibold` on buttons, `bold` on an `iconButton` and `regular` elsewhere.
- **`placement`** sets the side of the label the symbol sits on, in a `button`, an `actions` row or a `badge`.
  - `only` drops the label.
  - An `iconButton` and an `issuerIcon` ignore it.
- **`colors`** takes values of these kinds:
  - A hex colour: `#RGB`, `#RGBA`, `#RRGGBB` or `#RRGGBBAA`.
  - A keyword: `accent`, `primary` or `secondary`.
  - A `{token}` whose value is one of those.
  - More than three colours are ignored with a warning, and a colour that does not resolve is skipped.
  - Hex colours get the same legibility adjustment as other components.
  - With no `colors`, a symbol uses the component's tint: the `color` of an `iconButton`, the accent of a button, or the text colour of a badge.
- **`variableValue`** works on symbols that have variable layers, such as `wifi`, `speaker.wave.3` and `chart.bar`.
  - A value above 1 up to 100 is read as a percentage, like the progress bar, so `{progress}` can carry 0 to 100.
  - Other values are clamped to 0 to 1.
  - A symbol without variable layers ignores it.

### Finding a name

Names must match the SF Symbols on the Mac that shows the banner. Search them with Herald's own list, which uses the
same categories and synonyms as the Designer's symbol browser, so an agent or a script finds real names without
opening the SF Symbols app:

```sh
herald symbols envelope --limit 2
```

```json
{"total": 32, "offset": 0, "limit": 2,
 "symbols": [{"name": "envelope.front", "categories": ["communication"]},
             {"name": "envelope.front.fill", "categories": ["communication", "multicolor"]}],
 "categories": [{"key": "all", "title": "All", "icon": "square.grid.2x2", "count": 7779}]}
```

The search is [`GET /v1/symbols`](api/templates.md#get-v1symbols), also available as the MCP tool
[`list_symbols`](mcp/templates.md#list_symbols). It matches every word of the query against names, search terms and
synonyms, can narrow to one category, and pages through the results. The reply lists the categories with their
counts. In the Designer the same list is the [symbol browser](#in-the-designer).

### Rendering modes

The rendering mode decides how the symbol's layers take colour. Pick it by how many colours you want.

| Mode | Colours used | Result |
|---|---|---|
| `monochrome` | The first colour, else the tint. | One flat colour. |
| `hierarchical` | The first colour, else the tint. | Layers take shades of that colour. |
| `palette` | One colour: it, and the same colour at 55 percent for the second layer. Two or three: one per layer. None: the tint and the tint at 55 percent. | Each layer has its own colour. |
| `multicolor` | None. `colors` is ignored. | The symbol's own colours. Not every symbol has any. |

The validator warns about two combinations:

- `palette` with no `colors` gets the warning `palette rendering needs 2 or 3 colours`.
- `multicolor` with `colors` gets a warning that `colors` is ignored.

### Static previews

Static renders show the weight, scale, rendering mode, colours and variable value. They do not draw effects. Static
renders are `POST /v1/preview`, the MCP tool `render_preview`, and the rows of History. Effects run only in live
banners and in the Designer's live preview.

## Effects

An effect makes the symbol move: it bounces, pulses, lights up layer by layer, scales, appears, disappears or
swaps. Use one sparingly, to say that something changed or is still going on. An effect is an object in the
symbol's `effect` property:

```json
{"kind": "pulse", "trigger": "repeating", "speed": 1.2}
```

| Property | Type | Default | Description |
|---|---|---|---|
| `kind` | string | none | One of `bounce`, `pulse`, `variableColor`, `scale`, `appear`, `disappear`, `replace`. Required. |
| `trigger` | string | `onAppear` | When the effect plays. One of `onAppear`, `onChange`, `onHover`, `repeating`. |
| `speed` | number | `1` | How fast it plays, from 0.25 to 4. A value outside the range is clamped, and the validator warns. |
| `cumulative` | boolean | `false` | `variableColor` only: layers stay lit instead of lighting one at a time. |
| `reversing` | boolean | `false` | `variableColor` only: the effect plays back and forth. |

> [!NOTE]
> Effects need macOS 14 or later. They are ignored on macOS 13, they are off when the user turned on **Reduce Motion**
> (System Settings > Accessibility > Display), and they are not drawn in static renders. The banner stays readable
> without them.

### Triggers

The trigger says what makes the effect play.

| Trigger | When it plays |
|---|---|
| `onAppear` | Once, about 0.35 seconds after the banner appears. |
| `onChange` | Each time something the symbol is bound to changes: its name after tokens are filled in, or a token in `colors` or `variableValue`. |
| `onHover` | Each time the pointer enters the symbol. |
| `repeating` | Continuously, for the effects that can run continuously: `pulse`, `variableColor` and `scale`. |

For `onChange`, bind something: a `variableValue` of `{signal}` or a `name` that is a token such as `{statusSymbol}`. With nothing bound, nothing ever changes.

### Kinds

Each kind reacts to the triggers in its own way.

| Kind | What it does | Triggers that work |
|---|---|---|
| `bounce` | The symbol hops once. | `onAppear`, `onChange`, `onHover`. |
| `pulse` | The layers fade in and out. | All four. With `repeating` it pulses for as long as the banner is up. |
| `variableColor` | The layers light up in sequence. | All four. A single run lasts about 1.6 seconds divided by `speed`. `repeating` is continuous. |
| `scale` | The symbol grows while the effect is active. | All four. Timing is the same as `variableColor`. |
| `appear` | The symbol is hidden, then appears. | It plays once after the banner appears, whatever the trigger. |
| `disappear` | The symbol fades away. | `onAppear`: after it appeared. `onChange` and `onHover`: when that happens. |
| `replace` | The symbol swaps with a transition when its name changes. | `onChange`, with a `name` that contains a `{token}`. |

Choosing an effect:

- Use `pulse`, `variableColor` or `scale` for a continuous effect.
- `bounce` is a single hop, and `repeating` does not play it.
- A `replace` with a `name` that has no token never changes, and the validator warns.

## Examples by rendering mode

Each example is a complete `iconButton` cell component, so you can paste it into a template. They share the same
action, which opens the notification's `url`.

`monochrome` draws one colour:

```json
{"type": "iconButton",
 "symbol": {"name": "bell.badge", "renderingMode": "monochrome", "colors": ["accent"]},
 "action": {"id": "open", "label": "Open", "kind": "url", "url": "{url}"}}
```

`hierarchical` draws shades of one colour:

```json
{"type": "iconButton",
 "symbol": {"name": "speaker.wave.3.fill", "renderingMode": "hierarchical", "colors": ["#007AFF"]},
 "action": {"id": "open", "label": "Open", "kind": "url", "url": "{url}"}}
```

`palette` draws each layer in its own colour:

```json
{"type": "iconButton",
 "symbol": {"name": "bell.badge", "renderingMode": "palette", "colors": ["#FF3B30", "primary"]},
 "action": {"id": "open", "label": "Open", "kind": "url", "url": "{url}"}}
```

`multicolor` draws the symbol's own colours:

```json
{"type": "iconButton",
 "symbol": {"name": "externaldrive.badge.checkmark", "renderingMode": "multicolor"},
 "action": {"id": "open", "label": "Open", "kind": "url", "url": "{url}"}}
```

## Examples by effect

`bounce` hops when the count changes. The badge shows the bound value:

```json
{"type": "badge", "binding": "{count}", "color": "#FF3B30",
 "symbol": {"name": "envelope.fill", "scale": "small",
            "effect": {"kind": "bounce", "trigger": "onChange"}}}
```

`pulse` runs continuously on the issuer icon, to show that something is live:

```json
{"type": "issuerIcon", "size": 28,
 "symbol": {"name": "dot.radiowaves.left.and.right", "renderingMode": "hierarchical",
            "colors": ["accent"],
            "effect": {"kind": "pulse", "trigger": "repeating", "speed": 0.8}}}
```

`variableColor` runs cumulative and reversing, driven by a field from the issuer:

```json
{"type": "iconButton", "size": 22,
 "symbol": {"name": "wifi", "renderingMode": "hierarchical", "variableValue": "{signal}",
            "effect": {"kind": "variableColor", "trigger": "repeating",
                       "cumulative": true, "reversing": true}},
 "action": {"id": "dismiss", "label": "Dismiss", "kind": "dismiss"}}
```

`scale` grows when the pointer enters:

```json
{"type": "iconButton", "size": 22,
 "symbol": {"name": "checkmark.circle.fill", "weight": "semibold",
            "effect": {"kind": "scale", "trigger": "onHover"}},
 "actionRef": "markRead"}
```

`appear` shows the symbol once the banner is up:

```json
{"type": "issuerIcon", "size": 24,
 "symbol": {"name": "checkmark.seal.fill", "effect": {"kind": "appear"}}}
```

`disappear` fades a glyph away when the pointer enters:

```json
{"type": "iconButton", "size": 20,
 "symbol": {"name": "xmark", "effect": {"kind": "disappear", "trigger": "onHover"}},
 "action": {"id": "dismiss", "label": "Dismiss", "kind": "dismiss"}}
```

`replace` swaps the glyph when the issuer's status changes the symbol name. The issuer sends a field `statusSymbol`
with a value such as `checkmark.circle` or `exclamationmark.triangle`:

```json
{"type": "iconButton", "size": 22,
 "symbol": {"name": "{statusSymbol}", "effect": {"kind": "replace", "trigger": "onChange"}},
 "action": {"id": "dismiss", "label": "Dismiss", "kind": "dismiss"}}
```

## Examples by component

A labelled `button` with a symbol before the label:

```json
{"type": "button", "actionRef": "markRead",
 "symbol": {"name": "checkmark", "placement": "leading", "weight": "bold"}}
```

An icon-only close button. The `iconButton` draws its own glyph, and the action carries the same symbol so the
action looks the same wherever else it appears:

```json
{"type": "iconButton", "symbol": "xmark", "size": 16,
 "action": {"id": "dismiss", "label": "Dismiss", "kind": "dismiss",
            "symbol": {"name": "xmark", "weight": "bold"}}}
```

A complete template with a badge symbol, a row whose buttons all get a small dot, and rules that override or add
icons on individual actions:

```json
{"name": "symbols-demo", "app": "webwatcher.email", "layoutVersion": 2, "collapseEmpty": true,
 "grid": {"rows": 2, "cols": 2, "rowSizes": ["auto", "auto"], "colSizes": ["fill", "auto"],
          "gap": 8, "padding": 12, "width": 380},
 "cells": [
  {"id": "title", "row": 0, "col": 0,
   "component": {"type": "text", "binding": "{title}", "style": "title"}},
  {"id": "unread", "row": 0, "col": 1, "align": "topTrailing",
   "component": {"type": "badge", "binding": "{count}", "color": "#FF3B30",
                 "symbol": {"name": "envelope.fill", "scale": "small", "placement": "leading"}}},
  {"id": "acts", "row": 1, "col": 0, "colSpan": 2,
   "component": {"type": "actions", "source": "merged", "layout": "wrap",
                 "symbol": {"name": "circle.fill", "scale": "small"}}}],
 "actionRules": [
  {"match": "markRead", "symbol": {"name": "checkmark.circle", "weight": "semibold"}},
  {"match": "archive", "symbol": "archivebox"},
  {"add": {"id": "followup", "label": "Follow up", "kind": "shortcut",
           "shortcut": "Create follow-up",
           "symbol": {"name": "flag.fill", "renderingMode": "palette",
                      "colors": ["#FF9500", "primary"]}}}]}
```

## Precedence

A button can get its symbol from the component, from its action, or from a rule. This section says which one wins.

| Where | Which symbol is drawn |
|---|---|
| `button` | The action's `symbol`, else the component's `symbol`. |
| `actions` row | Each action's `symbol`, including one a rule set, else the component's `symbol`. |
| `iconButton` | Its own `symbol`, always. The action's symbol is not used. |
| A rule's `symbol` | It replaces the matched action's symbol. An empty name clears the symbol. |

Because every action has its own symbol, two buttons in one cell can show different icons. A symbol with
`placement: "only"` on an action makes that button icon-only.

## In the Designer

The [Designer](../AUTHORING.md) shows a **Symbol** section in the inspector when you select a component that takes a
symbol. It has a **Name** field with a picker, and rows for each property of the symbol object. Every change appears on
the canvas and in the live preview at once.

![The symbol browser with categories on the left, a grid of symbols and an empty preview pane that asks you to select a symbol](../../web/public/shots/docs/designer-symbol-browser.png "The symbol browser opened from the picker next to Name. No symbol is selected here. Select one to preview it, then press Use symbol or double-click it.")

The picker next to **Name** opens the symbol browser, either in a sheet or in a floating panel that stays beside the
Designer. The browser has these parts:

- A sidebar with **All symbols**, **Recents**, **Favourites** and Apple's categories, each with a count.
- A search field that matches names, keywords and synonyms, such as `bin`, `mail` or `alert`.
- A grid size slider, and a star on a symbol to add it to your favourites.
- A preview that draws the selected symbol with the weight, mode and colours of the **Symbol** section, and the
  **Use symbol** button. A double-click on a symbol uses it as well.

The rows of the **Symbol** section are:

| Row | What it sets |
|---|---|
| **Name** | `name`. A name that is not an SF Symbol on this Mac shows a warning that the default look is drawn. |
| **Weight** and **Scale** | `weight` and `scale`. |
| **Place** | `placement`: **Before**, **After** or **Only**. Shown where it applies. |
| **Mode** | `renderingMode`: monochrome, hierarchical, palette or multicolor. |
| **Color**, **Color 2**, **Color 3** | `colors`. Each takes a colour well, **Accent**, **Primary**, **Secondary** or a `{token}`. |
| **Variable** | `variableValue`: a number with a slider, or a `{token}`. |
| **Effect**, **When**, **Speed** | `effect`: its kind, `trigger` and `speed`. **Cumulative** and **Reversing** appear for `variableColor`. |

On the **Actions** tab, every action row has its own symbol picker and a **Shows** choice:

- **Text** removes the symbol.
- **Icon and text** keeps it before the label.
- **Icon only** sets `placement` to `only`.

The choice writes the action's symbol, so it holds in every cell that shows the action. The live preview plays effects. Static previews, in the Designer's snapshot and in `render_preview`, show everything except the motion.

## Common mistakes

| Mistake | What happens | Fix |
|---|---|---|
| A misspelt name. | The default look is drawn, and the validator warns. | Copy the name from the SF Symbols app, or search with `herald symbols`. |
| `palette` with no colours. | The tint and the tint at 55 percent are used, and the validator warns. | Give it two or three colours. |
| `multicolor` with `colors`. | `colors` is ignored, and the validator warns. | Remove `colors`, or use `palette`. |
| `cumulative` or `reversing` on `bounce`. | They are ignored, and the validator warns. | They apply only to `variableColor`. |
| `trigger: "repeating"` on `bounce` or `disappear`. | The effect never plays. | Use `onAppear`, `onChange` or `onHover`, or choose `pulse` for something continuous. |
| `replace` with a `name` that has no token. | Nothing changes, and the validator warns. | Use a `{token}` in `name` and `trigger: "onChange"`. |
| Expecting an effect in `render_preview`. | Previews are static, so there is no motion. | Check in the Designer's live preview, or send a test banner. |
| `variableValue` on a symbol without variable layers. | It is ignored. | Choose a symbol that supports it, such as `wifi` or `speaker.wave.3`. |
| Expecting effects on macOS 13, or with Reduce Motion. | They are ignored by design. | None. The banner is still readable. |
| `placement: "only"` where nothing else says what the button does. | The label is dropped and only the tooltip keeps it. | Keep the label, or use a clear icon. |
| `placement: "only"` on a `badge`. | The pill is drawn with neither the symbol nor the value. | Use `leading` or `trailing` on a badge. |

## Related

- [Banner design in the Designer](../AUTHORING.md): the inspector and the **Actions** tab.
- [Actions](actions.md): action rules, `match` and `add`.
- [Components](components/README.md): `iconButton`, `button`, `actions`, `issuerIcon` and `badge`.
- [Templates API](api/templates.md#get-v1symbols): `GET /v1/symbols`.
- [Rive](rive.md): the other way to put motion in a banner.
