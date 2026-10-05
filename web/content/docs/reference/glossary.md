# Glossary

Every term you meet in Herald's documentation, in alphabetical order. Each entry gives a short definition and
links to the page that explains the term in full.

| Term | Meaning | Read more |
|---|---|---|
| Action | What a button does when pressed: open a URL, call the app back, run a command, a script or an Apple Shortcut, reply, dismiss or snooze. | [Actions](actions.md) |
| Action origin | Where an action came from: `issuer` when the app sent or declared it, `template` when the user's template added it. The origin decides which confirmation applies. | [Actions](actions.md) |
| `actionRef` | A component's pointer to an action by its id, such as `"markRead"`. The component is empty when that action is not in the resolved list. | [Button](components/button.md) |
| `actionRules` | A template's ordered rules over the app's actions: hide, relabel, restyle, reorder and add. | [Actions](actions.md) |
| Ad hoc silence | A one-off quiet period that starts now and ends at a time or after some minutes, regardless of the schedule. | [Quiet hours](quiet-hours.md#ad-hoc-silence-and-resume) |
| Agent key | A secret (`hrk_...`) that lets a cloud agent send notifications through your relay. You can revoke it at any time. | [Connect an agent](../cloud/connect-agent.md) |
| App id | The identifier a sending app chooses, such as `example.bidbot`. Its History, icon, sound, templates, manifest and assets are all kept under it. | [Manifests](manifests.md) |
| Artboard | A canvas inside a `.riv` file. A `rive` component plays one artboard. | [Rive](rive.md) |
| Asset | A file an app ships for its templates to use, for example a Rive animation declared in the manifest. | [Rive](rive.md) |
| `auto` | A track size that is as large as the content in it. | [Grid and layout](grid-and-layout.md) |
| Audio message | A recorded voice message sent in the `audio` field of a notification. Herald checks it, caches it and plays it. | [Voice](voice.md#the-audio-field) |
| Banner | The borderless panel Herald shows on screen for a notification. It stays on top and never takes focus. | [How banners behave](banners.md) |
| Binding | A string with `{token}` placeholders that connects a component to notification data. | [Bindings](bindings.md) |
| Built-in template | One of the four layouts that need no design: `builtin.imageLeft`, `builtin.imageRight`, `builtin.hero` and `builtin.compact`. | [Templates](../TEMPLATES.md) |
| Bundle | A `.heraldtemplate` file: a zip holding one template and the Rive files it plays, made for sharing. | [Rive](rive.md) |
| Callback | The request Herald sends to an app's callback URL when a `callback` action is pressed. | [Replies API](api/replies.md#callback-request) |
| Cell | A rectangle of grid tracks that holds one component. A merged cell spans more than one row or column. | [Grid and layout](grid-and-layout.md) |
| `collapse` and `keep` | The two ways an empty component behaves: `collapse` removes it and lets an empty row or column shrink to nothing, `keep` leaves its space blank. | [Grid and layout](grid-and-layout.md) |
| Collapse planner | The part of Herald that works out which cells, rows and columns collapse for one notification. | [Grid and layout](grid-and-layout.md) |
| Command permission | The user's approval for an app to have Herald run shell commands, scripts or Shortcuts on its behalf. | [Actions](actions.md) |
| Component | What a cell draws, such as `text`, `image`, `button` or `stackBadge`. | [Components](components/README.md) |
| Composer | The Designer in quick-send mode, where you type and send a notification by hand. | [Quick send](../APP.md#quick-send) |
| Confirmation | The question Herald asks inside the banner before it runs code or sends data to a non-local host. It is never a separate alert window. | [Actions](actions.md) |
| Connector | The sign-in that lets a cloud agent such as ChatGPT reach your relay without a static key. | [Connect ChatGPT](../cloud/connect-chatgpt.md) |
| Designer | The visual editor for templates, with a palette, a grid canvas, an inspector and a live preview. | [Design a banner](../AUTHORING.md) |
| Device token | The secret (`hrd_...`) that proves a paired Mac to the relay. Herald stores it in its secret store. | [How the relay works](../cloud/how-it-works.md) |
| Effect | An animation of an SF Symbol, such as bounce, pulse or variableColor. | [Symbols](symbols.md) |
| Empty | The state of a component that has nothing to show, such as when all its tokens are absent. Each component page says when it is empty. | [Components](components/README.md) |
| Engine | The thing that turns text into speech: Kokoro, the system voice, or Off. The user picks it in Settings > Voice. | [Voice](voice.md#engines) |
| `extra` | A template's own key and value pairs, read as `{extra.key}` and passed to every action. | [Bindings](bindings.md) |
| Family | The product an app belongs to, such as `webwatcher`. It comes from the manifest's `family`, else from the app id before its first dot. | [Stacking](stacking.md) |
| Field | One piece of data a notification carries. A manifest declares fields with a type and a sample, and the field's name is the token. | [Manifests](manifests.md) |
| `fill` | A track size that takes an equal share of the space left over. | [Grid and layout](grid-and-layout.md) |
| Gap and padding | The space between tracks, and between the banner edge and the tracks. Both are measured in points. | [Grid and layout](grid-and-layout.md) |
| Grid | The rows and columns that make up a template. A grid has between 1 and 12 rows and columns, and the default is 3 rows by 4 columns. | [Grid and layout](grid-and-layout.md) |
| `group` | A notification field that names what the notification is about. It is the stacking key under the `bySender` level. | [Stacking](stacking.md#the-group-field) |
| Herald | The service as a whole: the app in the menu bar, the `herald` command, the `herald-mcp` server and the Swift, Python and Node clients. | [README](../../README.md) |
| History | The record of delivered notifications for each app, with the payload, the resolved fields, the button used and any speech. | [History API](api/history.md) |
| `hover` and `pressed` | Keywords that `inputBindings` can attach to a Rive input so the pointer drives the animation. | [Rive](rive.md) |
| Input | A number, a Boolean or a trigger on a Rive state machine that Herald sets from fields and the pointer. | [Rive](rive.md) |
| Issuer | An app seen as the source of notifications. | [Manifests](manifests.md) |
| Kind | The type of an action: `url`, `callback`, `command`, `script`, `shortcut`, `openApp`, `reply`, `dismiss` or `snooze`. | [Actions](actions.md) |
| Kokoro | A neural voice engine that runs locally. It needs a one-time download of about 340 MB. | [Make Herald speak](../VOICE.md#install-kokoro) |
| `layoutVersion` | A template field. The value `2` marks a grid template. | [Grid and layout](grid-and-layout.md) |
| Manifest | What an app declares about itself: its fields with samples, its actions, its assets, its default template and its family. | [Manifests](manifests.md) |
| MCP | The Model Context Protocol. The `herald-mcp` server uses it to give AI agents Herald's tools. | [MCP tools](mcp/README.md) |
| Merged payload | The JSON every action receives: the notification, its resolved fields, the template's `extra` and the action that fired. | [Actions](actions.md) |
| `metadata` | Free-form JSON on a notification. It is stored in History and supplies tokens to templates. Unknown top-level keys are moved into it. | [Notifications API](api/notifications.md#post-v1notify) |
| Mute | The global switch, **Mute Sounds** in the menu, that silences chimes and speech. Banners still show. | [Voice](voice.md#mute) |
| Panel | The window behind a banner. It does not take focus from the app you are using. | [How banners behave](banners.md) |
| Presentation | A notification field that chooses between a banner, speech only, or both: `banner`, `voice` or `both`. | [Voice](voice.md#the-presentation-field) |
| Preview | An offscreen picture of a template, rendered as a PNG for a given set of values. | [Templates API](api/templates.md) |
| Priority | A notification field with the values `low`, `normal`, `high` and `urgent`. `urgent` can break through quiet hours for apps the user allows. | [Quiet hours](quiet-hours.md#urgent-breaks-through) |
| Quiet hours | Periods when Herald holds back speech, sounds or banners, set as windows or as an ad hoc silence. | [Quiet hours](quiet-hours.md) |
| Relay | A small Cloudflare Worker in your own account that holds a mailbox for your Mac, so a cloud agent can send notifications without reaching the Mac directly. | [Cloud relay](../CLOUD.md) |
| Replay | Playing a notification's speech again from its speaker control on the banner or in History. | [Voice](voice.md#replay) |
| Resolved list | The final list of actions a banner shows: the app's actions and the snooze action, after the template's rules. | [Actions](actions.md) |
| Scripts folder | The `scripts/` folder in Herald's support directory, where `script` actions look for their files. | [Actions](actions.md) |
| SF Symbol | An Apple system icon. Buttons, badges and app icons can use one. | [Symbols](symbols.md) |
| Silenced | The state of a notification part held back by quiet hours: speech, the chime or the banner. | [Quiet hours](quiet-hours.md#what-silenced-means) |
| Snooze | Hiding a banner and bringing it back later. The clock menu offers 5 minutes, 15 minutes, 1 hour and Tomorrow 9:00. | [Notifications API](api/notifications.md#post-v1snooze) |
| Speech | The text of a notification read aloud by the engine. Its record in History is the `speech` object. | [Voice](voice.md) |
| Stack | Banners folded into one with a count because they share a stacking key. | [Stacking](stacking.md) |
| `stackBadge` | The component that shows the stack count as a pill and opens the stack when pressed. | [stackBadge](components/stackBadge.md) |
| Stacking key | What banners must share to stack together. It is set by the stacking level. | [Stacking](stacking.md#stacking-levels) |
| Stacking level | How banners are grouped: `byApp`, `byIssuer`, `bySender` or `never`. There is a global default and a per-app override. | [Stacking](stacking.md#stacking-levels) |
| State machine | The Rive logic object that reacts to inputs. A `rive` component plays one. | [Rive](rive.md) |
| Support directory | The folder where Herald keeps its data: `~/Library/Application Support/Herald/`. | [Cloud relay](../CLOUD.md) |
| Template | A reusable banner design for one app: a grid of cells, collapse behaviour, action rules, extras and default content. | [Templates](../TEMPLATES.md) |
| Token | A name inside braces in a binding, such as `{title}` or `{stack.count}`. | [Bindings](bindings.md) |
| Track | One row or one column of a grid. | [Grid and layout](grid-and-layout.md) |
| Trigger | Either a Rive input that fires once, or the `trigger` of a symbol effect (`onAppear`, `onChange`, `onHover` or `repeating`). | [Rive](rive.md) |
| Voice | The ability to speak notifications and play voice messages, produced locally by an engine. | [Voice](voice.md) |
| Window (quiet hours) | A repeating quiet period with a start, an end and the days it starts on. | [Quiet hours](quiet-hours.md#windows) |

## Related

- [Reference index](README.md): every reference page.
- [Make Herald speak](../VOICE.md): the voice terms in practice.
