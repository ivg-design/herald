# Glossary

Terms as Herald uses them. Links point to the page that defines them in full.

**Action.** What a button does: open a URL, call the issuer back, run a command, a script or an Apple Shortcut,
dismiss, snooze. See [actions.md](actions.md).

**Action origin.** Where a resolved action came from: `issuer` (sent with the notification or declared in the
manifest) or `template` (added by the user's template). The origin decides the confirmation gate.

**`actionRef`.** A component's pointer to a resolved action by id (`"markRead"`). Empty when that action is not
in the list. See [components/button.md](components/button.md).

**`actionRules`.** The template's ordered rules over the issuer's actions: hide, relabel, restyle, reorder, add.
See [actions.md](actions.md#rules-actionrules).

**App id / issuer.** The identifier a sending app uses (`example.bidbot`, `webwatcher.email`). Its history, icon, sound,
templates, manifest and Rive assets are all keyed by it. "Issuer" is the app seen as the source of notifications.

**Artboard.** A canvas inside a `.riv` file. A `rive` component plays one. See [rive.md](rive.md).

**Asset.** A file an issuer ships for templates to use; today a Rive animation declared in the manifest. Stored at
`Application Support/Herald/assets/<app>/<id>.riv`. See [rive.md](rive.md).

**`auto`.** A track size: as large as its content. See [grid-and-layout.md](grid-and-layout.md#sizes).

**Banner.** The borderless, always-on-top panel Herald draws for a notification. It never takes focus.

**Binding.** A string with `{token}` placeholders that connects a component to notification data. See
[bindings.md](bindings.md).

**Built-in template.** One of `builtin.imageLeft`, `builtin.imageRight`, `builtin.hero`, `builtin.compact`: the four
v1 layouts expressed as grid templates.

**Bundle (`.heraldtemplate`).** A zip with one template and the Rive files it plays, for sharing. See
[rive.md](rive.md#packaging-with-a-template-heraldtemplate).

**Callback.** The POST Herald sends to an app's callback URL when a `callback` action is pressed. See
[actions.md](actions.md#callbacks).

**Cell.** A rectangle of grid tracks (`row`, `col`, `rowSpan`, `colSpan`) holding one component. A **merged
cell** is a cell with a span above 1.

**`collapse` / `keep`.** What an empty component does: disappear (and let an empty row or column collapse to
zero), or stay blank and keep its space. Set per template (`collapseEmpty`) and per component (`emptyBehavior`).
See [grid-and-layout.md](grid-and-layout.md#collapse-planner).

**Collapse planner.** The pure function that turns "which components are empty" into collapsed cells, rows and
columns for one notification.

**Command permission.** The user's confirmation that an app may have Herald run shell commands. Needed for issuer
`command`, `script` and `shortcut` actions.

**Component.** What a cell shows: `text`, `image`, `issuerIcon`, `timestamp`, `button`, `actions`, `iconButton`,
`badge`, `stackBadge`, `progress`, `rive`, `spacer`. See [components/README.md](components/README.md).

**Confirmation.** The question Herald asks inside the banner before it runs code or sends to a non-local host.
Never a modal alert.

**Designer.** The visual editor: palette, grid canvas with merge/split, inspector, and a live preview pane at least
half of the window, with sample or last real data, light and dark, and Send test.

**Effect (symbol).** A macOS 14 animation of an SF Symbol: bounce, pulse, variableColor, scale, appear, disappear,
replace. See [symbols.md](symbols.md).

**Empty.** A component with nothing to show: all its tokens are absent, or its action is not in the list, and so
on. Each component page lists its "Empty when".

**`extra`.** The template's own key/values, read as `{extra.key}` and passed to every action as `extra`.

**Family.** The product an issuer belongs to (`webwatcher`), used by `byApp` stacking. From the manifest's
`family`, else the issuer id before its first dot.

**Field.** One datum a notification carries, flattened from top-level keys and `metadata`. Declared in the
manifest with a type and a sample. The name is the token.

**`fill`.** A track size: an equal share of the space left. See [grid-and-layout.md](grid-and-layout.md#sizes).

**Gap, padding.** Space between tracks, and between the banner edge and the tracks. 0 to 64 points.

**Grid.** The rows and columns of a v2 template: `rows`, `cols`, `rowSizes`, `colSizes`, `gap`, `padding`,
`width`. Up to 12 x 12; the default is 3 x 4.

**`group`.** A top-level notification key that is the stacking key under `bySender`.

**Herald.** The service: Herald.app (the menu bar app), the `herald` CLI, the `herald-mcp` server, the
`HeraldClient` Swift package and the Python/Node clients.

**History.** The per-app record of delivered notifications (1000 per app) with their payload, resolved fields,
the button used and speech.

**`hover`, `pressed`.** Keywords bound to a Rive input in `inputBindings`; driven by the mouse over the
animation. See [rive.md](rive.md#hover-pressed-click-and-visibility).

**Input (Rive).** A Number, Boolean or Trigger on a state machine that Herald writes from fields and the pointer.

**Kind (action).** `url`, `callback`, `command`, `script`, `shortcut`, `dismiss`, `snooze`.

**`layoutVersion`.** `2` for grid templates; `1` (or no grid) is a legacy fixed layout.

**Manifest.** What an issuer declares: fields with samples, actions, assets, default template, family. See
[manifests.md](manifests.md).

**MCP.** The Model Context Protocol. `herald-mcp` exposes Herald to AI agents. See [mcp-tools.md](mcp-tools.md).

**Merged payload.** The JSON every action receives: the notification, its resolved fields, the template's
`extra` and the action that fired.

**`metadata`.** Free-form JSON on a notification, stored in history and the source of template tokens. Unknown
top-level keys are moved into it.

**Panel.** The window behind a banner (a non-activating `NSPanel`).

**Preview.** An offscreen render of a template as PNG (`POST /v1/preview`, MCP `render_preview`). It cannot draw
Rive or menus and shows no symbol effects.

**Quiet hours.** Windows that hold back speech, sounds and/or banners. See [quiet-hours.md](quiet-hours.md).

**Resolved list.** The final list of actions a banner shows: issuer actions (and the snooze action) through the
template's rules.

**Scripts folder.** `~/Library/Application Support/Herald/scripts/`: where `script` actions find their files.

**Snooze.** Hiding a banner and bringing it back later. The clock menu offers 5 minutes, 15 minutes, 1 hour and
Tomorrow 9:00; the API takes any number of minutes up to 43200.

**Stack.** Notifications folded into one banner with a counter, because they share a stacking key. Levels:
`byApp`, `byIssuer`, `bySender`, `never`. See [stacking.md](stacking.md).

**State machine.** The Rive logic object that reacts to inputs. A `rive` component plays one.

**Support directory.** `~/Library/Application Support/Herald/`: `token`, `port`, `templates/`, `manifests/`,
`assets/`, `scripts/`, `history/`, `template-approvals.json`, `secrets/` (0600 files for the relay and Cloudflare secrets when the
data-protection keychain is unavailable; see [../CLOUD.md](../CLOUD.md#what-herald-stores-where)). Override with `HERALD_SUPPORT_DIR`.

**SF Symbol.** An Apple system icon, used by `iconButton`, buttons, badges and issuer icons. See
[symbols.md](symbols.md).

**Template.** A reusable banner design for one app: a grid of cells, collapse behaviour, action rules, extras and
default content. Stored one JSON file per template.

**Token.** A name inside `{ }` in a binding: letters, digits, `_`, `.`, `-`. Standard tokens are `title`,
`subtitle`, `body`, `image`, `url`, `app`, `appName`, `id`, `priority`, `sound`, `group`, `deliveredAt`,
`stack.count`; the rest come from the manifest, `metadata` and `extra.<key>`.

**Track.** One row or one column of the grid.

**Trigger.** Two meanings: a Rive Trigger input (fires once), and a symbol effect's `trigger` (`onAppear`,
`onChange`, `onHover`, `repeating`).

**Voice.** Spoken notifications and voice messages, synthesised locally. See [voice.md](voice.md).
