# SF Symbols

Available from Herald 1.3. SF Symbols are Apple's icon set (the SF Symbols app lists the names). Herald uses them
on `button`, `iconButton`, `actions`, `issuerIcon` and `badge` components and on actions themselves, with full
control over weight, size, rendering mode, colours, variable value and, on macOS 14 and later, symbol effects.

Everything here is from the schema (`HeraldSymbol`), the validator and the renderer (`SymbolViews`). Every JSON
example validates against the shipped component schema.

## Where a symbol can go

| Where | Property | What it does |
|---|---|---|
| [`iconButton`](components/iconButton.md) | `symbol` (required) | The glyph. A plain name, or an object with `name` and styling. |
| [`button`](components/button.md) | `symbol` | A symbol drawn with the label (placement picks the side). An action's own `symbol` wins. |
| [`actions`](components/actions.md) | `symbol` | A symbol every button of the row gets, unless its action has its own. |
| [`issuerIcon`](components/issuerIcon.md) | `symbol` | Drawn **instead of** the app icon; the app icon is the fallback when the name is unknown. Glyph size is 62 % of `size`. |
| [`badge`](components/badge.md) | `symbol` | Drawn beside the value (placement leading or trailing); `only` drops the value, unless the badge has no value to show. |
| An action | `symbol` | On any action object (an issuer's, a rule's `add`, or an inline one). |
| An `actionRules` rule | `symbol` | Gives the **matched** actions a symbol: `{"match":"archive","symbol":"archivebox"}`. |

## The `symbol` value

Either a plain name:

```json
"bell.badge"
```

or an object:

```json
{"name":"bell.badge","weight":"semibold","scale":"large","placement":"leading",
 "renderingMode":"palette","colors":["#FF3B30","primary"],"variableValue":0.6,
 "effect":{"kind":"bounce","trigger":"onChange","speed":1.5}}
```

| Property | Type | Default | Allowed values / notes |
|---|---|---|---|
| `name` | string | required | An SF Symbol name (`"bell.badge"`, `"checkmark.circle.fill"`). May contain a `{token}` (that is how `replace` has something to swap). An unknown name draws the default look (an `iconButton` shows `questionmark.circle`; a `button` shows its plain label; an `issuerIcon` keeps the app icon). The validator warns `'x' is not an SF Symbol on this Mac`. |
| `weight` | string | the component's own (buttons: semibold, `iconButton`: bold; the schema documents `regular`) | `ultraLight`, `thin`, `light`, `regular`, `medium`, `semibold`, `bold`, `heavy`, `black`. |
| `scale` | string | `medium` | `small`, `medium`, `large`: the size relative to the text. |
| `placement` | string | `leading` | `leading`, `trailing`, `only`. Beside a label (`button`, `actions` row, `badge`); `only` drops the label. Ignored by `iconButton` and `issuerIcon`. |
| `renderingMode` | string | `monochrome` | `monochrome` (one colour), `hierarchical` (shades of one colour), `palette` (2 to 3 colours), `multicolor` (the symbol's own colours). |
| `colors` | array of 1 to 3 strings | the component's tint | `#RGB`, `#RGBA`, `#RRGGBB`, `#RRGGBBAA`, `accent`, `primary`, `secondary`, or a `{token}` whose value is one of those. More than 3 are ignored (warning); a colour that does not resolve is skipped. |
| `variableValue` | number or string | none | `0` to `1` for symbols that support it (`wifi`, `speaker.wave.3`, `chart.bar`...); or a `{token}` bound to a numeric field, e.g. `"{progress}"`. A value above 1 up to 100 is read as a percentage, like the progress bar. Symbols that do not support it ignore it. |
| `effect` | object | none | See [Effects](#effects). |

Colour resolution: hex colours go through the same legibility nudge as other components; keywords follow the
system. A symbol with no `colors` uses the component's tint (`color` on an `iconButton`, the button's accent, the
text colour on a badge pill).

### Rendering modes in detail

| Mode | Colours used | Notes |
|---|---|---|
| `monochrome` | the first colour, else the tint | Plain single colour. |
| `hierarchical` | the first colour, else the tint | Layers take shades of it. |
| `palette` | 1 colour: it plus that colour at 55 % for the secondary layer. 2 or 3: layer one, two, three. 0: the tint plus 55 % | Warns `palette rendering needs 2 or 3 colours` when `colors` is empty. |
| `multicolor` | none | `colors` is ignored (warning). The symbol's own colours; not all symbols have any. |

### Static previews

Static renders (`POST /v1/preview`, MCP `render_preview`, history rows) show **weight, scale, rendering mode,
colours and the variable value**. **Effects are not drawn** there: they run only in live banners and in the
Designer's live preview.

## Effects

```jsonc
// a fragment of a symbol object
"effect":{"kind":"pulse","trigger":"repeating","speed":1.2}
```

Symbol effects need **macOS 14**. On macOS 13 they are ignored. They are also **disabled when the user turned on
Reduce Motion** (System Settings > Accessibility > Display), and not drawn in static renders.

| Property | Type | Default | Notes |
|---|---|---|---|
| `kind` | string | required | `bounce`, `pulse`, `variableColor`, `scale`, `appear`, `disappear`, `replace`. |
| `trigger` | string | `onAppear` | `onAppear`, `onChange`, `onHover`, `repeating`. |
| `speed` | number | 1 | 0.25 to 4 (clamped; the validator warns outside it). |
| `cumulative` | boolean | `false` | `variableColor` only: layers stay on instead of lighting one at a time. |
| `reversing` | boolean | `false` | `variableColor` only: plays back and forth. |

### Triggers

| Trigger | Plays |
|---|---|
| `onAppear` | Once, about 0.35 s after the banner appears. |
| `onChange` | When anything the symbol is bound to changes: its (token-filled) name, or a token in `colors` or `variableValue`. Typical use: `variableValue:"{signal}"` or a `replace` whose `name` is a token. |
| `onHover` | Each time the pointer enters the symbol. |
| `repeating` | Continuously, for the effects that are continuous (`pulse`, `variableColor`, `scale`). |

### Kinds

| Kind | What it does | Triggers |
|---|---|---|
| `bounce` | The symbol hops. | Discrete: plays on `onAppear`, `onChange`, `onHover`. With `repeating` it only plays when something else triggers it (**TBD - verify**); use `pulse` for a continuous effect. |
| `pulse` | Layers fade in and out. | All four. `repeating` pulses for as long as the banner is up. |
| `variableColor` | Layers light up in sequence (set `cumulative` and `reversing` for variations). | One run lasts about 1.6 s divided by `speed` for the discrete triggers; `repeating` is continuous. |
| `scale` | The symbol scales up while active. | Same as `variableColor`. |
| `appear` | The symbol is hidden, then appears. | Plays once after the banner appears (the trigger does not matter; `repeating` is treated as `onAppear`, with a warning). |
| `disappear` | The symbol disappears. | `onAppear`: after it appeared. `onChange` / `onHover`: when that fires. `repeating` is treated as `onAppear`. |
| `replace` | Swaps the symbol with a transition when its name changes. | Use `onChange` and a `name` containing a `{token}` (warns otherwise). |

## Examples by rendering mode

`monochrome`, one colour:

```json
{"type":"iconButton","symbol":{"name":"bell.badge","renderingMode":"monochrome","colors":["accent"]},
 "action":{"id":"open","label":"Open","kind":"url","url":"{url}"}}
```

`hierarchical`, shades of one colour:

```json
{"type":"iconButton","symbol":{"name":"speaker.wave.3.fill","renderingMode":"hierarchical","colors":["#007AFF"]},
 "action":{"id":"open","label":"Open","kind":"url","url":"{url}"}}
```

`palette`, two colours:

```json
{"type":"iconButton","symbol":{"name":"bell.badge","renderingMode":"palette","colors":["#FF3B30","primary"]},
 "action":{"id":"open","label":"Open","kind":"url","url":"{url}"}}
```

`multicolor`, the symbol's own colours:

```json
{"type":"iconButton","symbol":{"name":"externaldrive.badge.checkmark","renderingMode":"multicolor"},
 "action":{"id":"open","label":"Open","kind":"url","url":"{url}"}}
```

## Examples by effect

`bounce` on a change of count (the badge is the bound value):

```json
{"type":"badge","binding":"{count}","color":"#FF3B30",
 "symbol":{"name":"envelope.fill","scale":"small","effect":{"kind":"bounce","trigger":"onChange"}}}
```

`pulse`, continuously, on an issuer icon:

```json
{"type":"issuerIcon","size":28,
 "symbol":{"name":"dot.radiowaves.left.and.right","renderingMode":"hierarchical","colors":["accent"],
           "effect":{"kind":"pulse","trigger":"repeating","speed":0.8}}}
```

`variableColor`, cumulative and reversing, driven by a field:

```json
{"type":"iconButton","size":22,
 "symbol":{"name":"wifi","renderingMode":"hierarchical","variableValue":"{signal}",
           "effect":{"kind":"variableColor","trigger":"repeating","cumulative":true,"reversing":true}},
 "action":{"id":"dismiss","label":"Dismiss","kind":"dismiss"}}
```

`scale` on hover:

```json
{"type":"iconButton","size":22,
 "symbol":{"name":"checkmark.circle.fill","weight":"semibold","effect":{"kind":"scale","trigger":"onHover"}},
 "actionRef":"markRead"}
```

`appear` once the banner is up:

```json
{"type":"issuerIcon","size":24,"symbol":{"name":"checkmark.seal.fill","effect":{"kind":"appear"}}}
```

`disappear` when the pointer enters (a glyph that fades away on hover):

```json
{"type":"iconButton","size":20,
 "symbol":{"name":"xmark","effect":{"kind":"disappear","trigger":"onHover"}},
 "action":{"id":"dismiss","label":"Dismiss","kind":"dismiss"}}
```

`replace` when the bound status changes the symbol name:

```json
{"type":"iconButton","size":22,
 "symbol":{"name":"{statusSymbol}","effect":{"kind":"replace","trigger":"onChange"}},
 "action":{"id":"dismiss","label":"Dismiss","kind":"dismiss"}}
```

(The issuer sends `statusSymbol`: `"checkmark.circle"`, `"exclamationmark.triangle"`, ... .)

## Examples by component

A labelled button with a leading symbol:

```json
{"type":"button","actionRef":"markRead",
 "symbol":{"name":"checkmark","placement":"leading","weight":"bold"}}
```

An action row where every button gets a symbol, and one overrides it:

```json
{"name":"symbols-demo","app":"webwatcher.email","layoutVersion":2,"collapseEmpty":true,
 "grid":{"rows":2,"cols":2,"rowSizes":["auto","auto"],"colSizes":["fill","auto"],"gap":8,"padding":12,"width":380},
 "cells":[
  {"id":"title","row":0,"col":0,"component":{"type":"text","binding":"{title}","style":"title"}},
  {"id":"unread","row":0,"col":1,"align":"topTrailing",
   "component":{"type":"badge","binding":"{count}","color":"#FF3B30",
                "symbol":{"name":"envelope.fill","scale":"small","placement":"leading"}}},
  {"id":"acts","row":1,"col":0,"colSpan":2,
   "component":{"type":"actions","source":"merged","layout":"wrap","symbol":{"name":"circle.fill","scale":"small"}}}],
 "actionRules":[
  {"match":"markRead","symbol":{"name":"checkmark.circle","weight":"semibold"}},
  {"match":"archive","symbol":"archivebox"},
  {"add":{"id":"followup","label":"Follow up","kind":"shortcut","shortcut":"Create follow-up",
          "symbol":{"name":"flag.fill","renderingMode":"palette","colors":["#FF9500","primary"]}}}]}
```

An icon-only close button:

```json
{"type":"iconButton","symbol":"xmark","size":16,
 "action":{"id":"dismiss","label":"Dismiss","kind":"dismiss","symbol":{"name":"xmark","weight":"bold"}}}
```

## Precedence

- `button`: the action's `symbol`, else the component's.
- `actions` row: each action's `symbol` (including one set by an `actionRules` rule), else the component's.
- `iconButton`: its own `symbol` (the glyph) always.
- A rule's `symbol` replaces the matched action's symbol; an empty name clears it.
- Each action has its own symbol, so two buttons in one cell can show different icons. `placement: "only"` on an action's symbol makes that button icon only (**1.8**).

## In the Designer

Selecting one of these components shows a **Symbol** panel in the inspector: a Name field with a symbol picker
(a warning "Not an SF Symbol on this Mac: the default look is drawn" for an unknown name), Weight, Scale, Place
(Before, After, Only: leading, trailing, only), Mode (monochrome, hierarchical, palette, multicolor), colours,
variable value and effect. On the Actions tab every action row has its own picker and a **Shows** choice (Text, Icon and text, Icon only), which writes the action's symbol and its `placement` (`only` for Icon only; no symbol for Text). The live preview pane runs the effects; static previews (including MCP
`render_preview`) show everything except the motion. Control details beyond this are **TBD - verify** against the
shipped 1.3 build.

## Common mistakes

| Mistake | What happens | Fix |
|---|---|---|
| A misspelt name | Default look; validation warning. | Copy the name from the SF Symbols app. |
| `palette` with no colours | Warning; the tint and a 55 % tint are used. | Give 2 or 3 colours. |
| `multicolor` with `colors` | Ignored (warning). | Remove `colors` or use `palette`. |
| `cumulative` or `reversing` on `bounce` | Ignored (warning). | They only apply to `variableColor`. |
| Expecting an effect in `render_preview` | Static: no motion. | Check in the Designer or send a test banner. |
| `variableValue` on a symbol without variants | Ignored. | Use one that supports it (`wifi`, `speaker.wave.3`). |
| Expecting effects on macOS 13 or with Reduce Motion | Ignored by design. | None; the banner is still readable. |
| `placement: "only"` on a `button` with no other way to tell what it does | The label is dropped; the tooltip keeps it. | Keep the label or add a `tooltip` on an `iconButton`. |
