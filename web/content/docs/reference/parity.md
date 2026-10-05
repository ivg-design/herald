# What you can do where

Herald has four ways in: the app's own windows, the local HTTP API, the `herald` command-line tool and the MCP server
for agents. This page lists what each one can do, so you can pick the right one and know in advance when a task needs a
person at the Mac. Use it as a map: find the task in the first column, then follow the link in the column you want.

The aim is that anything a person can do in Herald's windows and Settings, an agent can do through MCP, apart from the
few things that must stay with the user (see [What only a person can do](#what-only-a-person-can-do)).

## How the four fit together

The HTTP API is the foundation. Every MCP tool is a thin wrapper over one HTTP route, and every CLI command is one or
two HTTP requests. So a capability that exists in MCP exists in HTTP, and the reverse is usually true as well. The CLI
covers the routes that are natural at a prompt, so it has the fewest. The app's windows call the same code the API
does.

| Way in | Who uses it | Needs |
|---|---|---|
| The app's windows | A person at the Mac. | Herald running. |
| [HTTP API](api/README.md) | Any program on the Mac. | The bearer token. |
| [CLI](cli.md) | A person or script at a terminal. | Herald running. |
| [MCP server](mcp/README.md) | An agent. | An MCP client with `herald-mcp` installed. |

A cell reads **none** when that way in cannot do the task. A cell reads **UI only** when the task is a view state, such
as a selection or a zoom level, with nothing stored that could be read or set.

## Notifications and banners

Send notifications, close them, snooze them and read the answers to them. The window column names the menu-bar menu, the Quick send window or the Designer.

| Task | App window | HTTP API | CLI | MCP tool |
|---|---|---|---|---|
| Show a notification | **Compose...** (Quick send) | [`POST /v1/notify`](api/notifications.md#post-v1notify) | [`notify`](cli.md#herald-notify) | [`send_notification`](mcp/notifications.md#send_notification) |
| Show a template with sample values | **Send test** in the Designer | [`POST /v1/notify`](api/notifications.md#post-v1notify) | [`notify`](cli.md#herald-notify) | [`send_test`](mcp/notifications.md#send_test) |
| Say text aloud | **Speak** in **Settings > Voice** | [`POST /v1/speak`](api/notifications.md#post-v1speak) | [`speak`](cli.md#herald-speak) | [`speak`](mcp/notifications.md#speak) |
| Close one banner, or all of an app | Close button, **Dismiss All** | [`POST /v1/dismiss`](api/notifications.md#post-v1dismiss), [`POST /v1/dismissAll`](api/notifications.md#post-v1dismissall) | [`dismiss`](cli.md#herald-dismiss), [`dismiss-all`](cli.md#herald-dismiss-all) | [`dismiss`](mcp/notifications.md#dismiss) |
| Snooze a banner, or bring it back | Clock menu on the banner | [`POST /v1/snooze`](api/notifications.md#post-v1snooze), [`POST /v1/unsnooze`](api/notifications.md#post-v1unsnooze) | [`snooze`](cli.md#herald-snooze), [`unsnooze`](cli.md#herald-unsnooze) | [`snooze`](mcp/notifications.md#snooze) |
| List stacks, open or close one | Click a stack | [`GET /v1/stacks`](api/stacks.md#get-v1stacks), [`POST /v1/stacks/expand`](api/stacks.md#post-v1stacksexpand) | [`stacks`](cli.md#herald-stacks) | [`list_stacks`](mcp/notifications.md#list_stacks), [`expand_stack`](mcp/notifications.md#expand_stack) |
| Read a typed reply | History item | [`GET /v1/replies`](api/replies.md#get-v1replies), [`GET /v1/replies/wait`](api/replies.md#get-v1replieswait) | none | [`get_replies`](mcp/notifications.md#get_replies), [`wait_for_reply`](mcp/notifications.md#wait_for_reply) |
| Press a banner button | Click the button | none | none | none |
| Open the Quick send window | Menu: **Compose...** | [`POST /v1/compose`](api/notifications.md#post-v1compose) | [`compose`](cli.md#herald-compose) | none |

Pressing a button is left to the person at the Mac on purpose. An agent can send a button and read what the user
answered, but it cannot press one for them.

## Templates

A template is one JSON document. The Designer's editing actions, such as adding a cell, merging two, or changing a
property, all rewrite that document. So saving a template covers every edit the Designer can make, and the same
validation runs on both sides.

| Task | App window | HTTP API | CLI | MCP tool |
|---|---|---|---|---|
| List and read templates | **Templates** list in the Designer | [`GET /v1/templates`](api/templates.md#get-v1templates) | [`template list`](cli.md#herald-template-list) | [`list_templates`](mcp/templates.md#list_templates), [`get_template`](mcp/templates.md#get_template) |
| Save a template, with validation | **Save** | [`PUT /v1/templates`](api/templates.md#put-v1templates) | [`template put`](cli.md#herald-template-put) | [`put_template`](mcp/templates.md#put_template) |
| Delete a template | **Delete** | [`DELETE /v1/templates`](api/templates.md#delete-v1templates) | [`template delete`](cli.md#herald-template-delete) | [`delete_template`](mcp/templates.md#delete_template) |
| Duplicate a template | **Duplicate** | [`POST /v1/templates/duplicate`](api/templates.md#post-v1templatesduplicate) | [`template duplicate`](cli.md#herald-template-duplicate) | [`duplicate_template`](mcp/templates.md#duplicate_template) |
| Rename a template | none | [`POST /v1/templates/rename`](api/templates.md#post-v1templatesrename) | [`template rename`](cli.md#herald-template-rename) | [`rename_template`](mcp/templates.md#rename_template) |
| Set or clear the app's default | **Set as issuer default** | [`PUT /v1/templates/default`](api/templates.md#put-v1templatesdefault) | [`template default`](cli.md#herald-template-default) | [`set_default_template`](mcp/templates.md#set_default_template) |
| Export a `.heraldtemplate` bundle | **Export...** | [`GET /v1/templates/export`](api/templates.md#get-v1templatesexport) | [`template export`](cli.md#herald-template-export) | [`export_template_bundle`](mcp/templates.md#export_template_bundle) |
| Import a bundle | **Import...** | [`POST /v1/templates/import`](api/templates.md#post-v1templatesimport) | [`template import`](cli.md#herald-template-import) | [`import_template_bundle`](mcp/templates.md#import_template_bundle) |
| Check a draft without saving it | The problems button | none | none | [`validate_template`](mcp/templates.md#validate_template) |
| Read the component schema | **Component** menu in the **Cell** tab | [`GET /v1/components`](api/templates.md#get-v1components) | none | [`component_schema`](mcp/templates.md#component_schema) |
| Add an action rule | **Actions** tab | [`PUT /v1/templates`](api/templates.md#put-v1templates) | [`template put`](cli.md#herald-template-put) | [`add_action_rule`](mcp/templates.md#add_action_rule) |
| Browse SF Symbol names | Symbol browser | [`GET /v1/symbols`](api/templates.md#get-v1symbols) | [`symbols`](cli.md#herald-symbols) | [`list_symbols`](mcp/templates.md#list_symbols) |
| List installed Shortcuts | **Run Apple Shortcut** form | [`GET /v1/shortcuts`](api/templates.md#get-v1shortcuts) | none | [`list_shortcuts`](mcp/templates.md#list_shortcuts) |
| Select a cell, undo, redo, zoom, drag | Designer | none | none | UI only |

## Previews and checks

| Task | App window | HTTP API | CLI | MCP tool |
|---|---|---|---|---|
| Render a banner, light or dark, at a scale | Live preview | [`POST /v1/preview`](api/templates.md#post-v1preview) | none | [`render_preview`](mcp/templates.md#render_preview) |
| Render with the last real notification | **Last real** in the preview header | [`POST /v1/preview`](api/templates.md#post-v1preview) | none | [`render_preview`](mcp/templates.md#render_preview) |
| Render a stack or a confirmation | none | [`POST /v1/preview`](api/templates.md#post-v1preview) | none | [`render_preview`](mcp/templates.md#render_preview) |
| Snapshot the whole Designer | none | [`GET /v1/designer/snapshot`](api/diagnostics.md#get-v1designersnapshot), [`POST /v1/designer/snapshot`](api/diagnostics.md#post-v1designersnapshot) | none | [`designer_snapshot`](mcp/templates.md#designer_snapshot) |
| Check a Rive file's artboards and inputs | Rive details in the **Cell** tab | [`POST /v1/rive/check`](api/diagnostics.md#post-v1rivecheck) | none | [`rive_check`](mcp/templates.md#rive_check) |
| Check that Herald is running | The bell in the menu bar | [`GET /v1/health`](api/diagnostics.md#get-v1health) | [`health`](cli.md#herald-health) | [`herald_status`](mcp/notifications.md#herald_status) |

## Manifests and assets

| Task | App window | HTTP API | CLI | MCP tool |
|---|---|---|---|---|
| List and read manifests | **Fields** in the Designer palette | [`GET /v1/manifests`](api/manifests.md#get-v1manifests), [`GET /v1/manifest`](api/manifests.md#get-v1manifest) | none | [`list_manifests`](mcp/templates.md#list_manifests), [`get_manifest`](mcp/templates.md#get_manifest) |
| Save a manifest | none | [`PUT /v1/manifest`](api/manifests.md#put-v1manifest) | none | [`put_manifest`](mcp/templates.md#put_manifest) |
| Delete a manifest | none | [`DELETE /v1/manifest`](api/manifests.md#delete-v1manifest) | [`manifest delete`](cli.md#herald-manifest-delete) | [`delete_manifest`](mcp/templates.md#delete_manifest) |
| List an app's animations and images | **Assets** in the Designer palette | [`GET /v1/assets`](api/assets.md#get-v1assets) | [`assets list`](cli.md#herald-assets-list) | [`list_assets`](mcp/templates.md#list_assets) |
| Upload a Rive file or an image | **Add...** under **Assets** | [`POST /v1/assets`](api/assets.md#post-v1assets) | [`assets add`](cli.md#herald-assets-add) | [`upload_asset`](mcp/templates.md#upload_asset) |
| Remove an uploaded file | **Remove...** under **Assets** | [`DELETE /v1/assets`](api/assets.md#delete-v1assets) | [`assets rm`](cli.md#herald-assets-rm) | [`delete_asset`](mcp/templates.md#delete_asset) |

What a manifest holds is in [Manifests](manifests.md).

## History

| Task | App window | HTTP API | CLI | MCP tool |
|---|---|---|---|---|
| List an app's History | History window | [`GET /v1/history`](api/history.md#get-v1history) | [`history`](cli.md#herald-history) | [`list_history`](mcp/apps-and-settings.md#list_history) |
| Search History | The search field | [`GET /v1/history/search`](api/history.md#get-v1historysearch) | [`history`](cli.md#herald-history) `search` | [`history_search`](mcp/apps-and-settings.md#history_search) |
| Show an item again as a banner | **Re-show as Banner** | [`POST /v1/history/reshow`](api/history.md#post-v1historyreshow) | [`history`](cli.md#herald-history) `reshow` | [`reshow_notification`](mcp/apps-and-settings.md#reshow_notification) |
| Delete one item, or clear an app | **Delete**, **Clear NAME History...** | [`DELETE /v1/history/item`](api/history.md#delete-v1historyitem), [`DELETE /v1/history`](api/history.md#delete-v1history) | [`history`](cli.md#herald-history) `delete`, `--clear` | [`delete_history`](mcp/apps-and-settings.md#delete_history) |
| Export History as JSON | **Export JSON...** | [`GET /v1/history/export`](api/history.md#get-v1historyexport) | [`history`](cli.md#herald-history) `export` | [`export_history`](mcp/apps-and-settings.md#export_history) |

## Settings and apps

The window column names the Settings tab. The keys and their values are in the
[settings API](api/settings.md) and the [apps API](api/apps.md).

| Task | App window | HTTP API | CLI | MCP tool |
|---|---|---|---|---|
| General: port, launch at login, mute, tooltips, History size | **Settings > General** | [`GET /v1/settings`](api/settings.md#get-v1settings), [`PUT /v1/settings`](api/settings.md#put-v1settings) | [`settings`](cli.md#herald-settings) | [`get_settings`](mcp/apps-and-settings.md#get_settings), [`set_settings`](mcp/apps-and-settings.md#set_settings) |
| Voice: engine, default voice, speed, language | **Settings > Voice** | [`PUT /v1/settings`](api/settings.md#put-v1settings) | [`settings`](cli.md#herald-settings) | [`set_settings`](mcp/apps-and-settings.md#set_settings) |
| Quiet hours and ad-hoc silence | **Settings > Voice**, menu | [`GET /v1/settings/quiet-hours`](api/settings.md#get-v1settingsquiet-hours), [`PUT /v1/settings/quiet-hours`](api/settings.md#put-v1settingsquiet-hours) | [`quiet`](cli.md#herald-quiet) | [`get_quiet_hours`](mcp/apps-and-settings.md#get_quiet_hours), [`set_quiet_hours`](mcp/apps-and-settings.md#set_quiet_hours) |
| Global stacking level | Menu: **Stack Notifications** | [`GET /v1/settings/stacking`](api/stacks.md#get-v1settingsstacking), [`PUT /v1/settings/stacking`](api/stacks.md#put-v1settingsstacking) | [`settings`](cli.md#herald-settings) | [`set_settings`](mcp/apps-and-settings.md#set_settings) |
| Install or use the Kokoro voice | **Settings > Voice** | [`GET /v1/voice`](api/setup.md#get-v1voice), [`POST /v1/voice/install`](api/setup.md#post-v1voiceinstall) | [`voice`](cli.md#herald-voice) | [`voice_status`](mcp/apps-and-settings.md#voice_status), [`install_voice`](mcp/apps-and-settings.md#install_voice) |
| Install the MCP server in a client | **Settings > MCP** | [`GET /v1/mcp`](api/setup.md#get-v1mcp), [`POST /v1/mcp/install`](api/setup.md#post-v1mcpinstall) | [`mcp`](cli.md#herald-mcp) | [`install_mcp`](mcp/apps-and-settings.md#install_mcp) |
| Register an app: name, icon, callback, command request | None; apps register themselves | [`POST /v1/register`](api/apps.md#post-v1register) | [`register`](cli.md#herald-register) | [`register_app`](mcp/apps-and-settings.md#register_app) |
| List apps and read their settings | **Settings > Apps** | [`GET /v1/apps`](api/apps.md#get-v1apps), [`GET /v1/apps/settings`](api/apps.md#get-v1appssettings) | [`apps`](cli.md#herald-apps) | [`list_apps`](mcp/apps-and-settings.md#list_apps) |
| Change an app's sound, timeout, corner, display, voice | **Settings > Apps** | [`PUT /v1/apps/settings`](api/apps.md#put-v1appssettings) | [`apps`](cli.md#herald-apps) `set` | [`update_app_settings`](mcp/apps-and-settings.md#update_app_settings) |
| Remove an app with its History, templates and manifest | **Remove NAME...** in **Settings > Apps** | [`DELETE /v1/apps/{id}`](api/apps.md#delete-v1appsid) | none | [`delete_app`](mcp/apps-and-settings.md#delete_app) |
| Reveal the token file, the scripts folder or the log in Finder | Buttons in Settings | none | none | UI only |

## Approvals

An approval is the user's permission for something that runs code or sends data off the Mac. What each one covers is in
[Approvals](actions.md#approvals).

| Task | App window | HTTP API | CLI | MCP tool |
|---|---|---|---|---|
| See an app's command and callback approvals | **Settings > Apps** | [`GET /v1/apps/settings`](api/apps.md#get-v1appssettings) | [`apps`](cli.md#herald-apps) | [`list_apps`](mcp/apps-and-settings.md#list_apps) |
| Revoke an app's approvals | **Allow this app to run commands** in **Settings > Apps** | [`PUT /v1/apps/settings`](api/apps.md#put-v1appssettings) | [`apps`](cli.md#herald-apps) `set` | [`update_app_settings`](mcp/apps-and-settings.md#update_app_settings) |
| See a template's code approvals | **Settings > Actions** | [`GET /v1/actions/approvals`](api/apps.md#get-v1actionsapprovals) | [`approvals`](cli.md#herald-approvals) | [`list_approvals`](mcp/apps-and-settings.md#list_approvals) |
| Revoke a template's approval | **Revoke** | [`DELETE /v1/actions/approvals`](api/apps.md#delete-v1actionsapprovals) | [`approvals`](cli.md#herald-approvals) `revoke` | [`revoke_approval`](mcp/apps-and-settings.md#revoke_approval) |
| Grant any approval | The question in the banner, the switches in Settings | none | none | none |

## Cloud relay

The relay lets agents that run elsewhere send notifications to this Mac. The app window is **Settings > Cloud**, and the
CLI has no relay commands. [Cloud](../CLOUD.md) explains the relay and these controls.

| Task | App window | HTTP API | MCP tool |
|---|---|---|---|
| Read setup state, version and updates | **Settings > Cloud**, **Update the relay** | [`GET /v1/relay/status`](api/relay.md#get-v1relaystatus) | [`relay_status`](mcp/relay.md#relay_status) |
| Open the Cloudflare token page | **Open Cloudflare...** in the deploy sheet | [`GET /v1/relay/token-url`](api/relay.md#get-v1relaytoken-url) | [`relay_token_url`](mcp/relay.md#relay_token_url) |
| Store the Cloudflare API token | The deploy sheet | [`POST /v1/relay/token`](api/relay.md#post-v1relaytoken) | [`relay_set_cloudflare_token`](mcp/relay.md#relay_set_cloudflare_token) |
| Deploy or update the relay | **Enable relay**, **Redeploy** under **Advanced** | [`POST /v1/relay/deploy`](api/relay.md#post-v1relaydeploy) | [`relay_deploy`](mcp/relay.md#relay_deploy) |
| Pair, or turn the relay off | **Enable relay**, **Pair with a code** and **Unpair** under **Advanced** | [`POST /v1/relay/pair`](api/relay.md#post-v1relaypair), [`POST /v1/relay/unpair`](api/relay.md#post-v1relayunpair) | [`relay_pair`](mcp/relay.md#relay_pair), [`relay_unpair`](mcp/relay.md#relay_unpair) |
| Read and change the Advanced fields | **Advanced**, **Apply settings** | [`GET /v1/relay/settings`](api/relay.md#get-v1relaysettings), [`PUT /v1/relay/settings`](api/relay.md#put-v1relaysettings) | [`relay_settings`](mcp/relay.md#relay_settings) |
| List zones for a custom domain | **Load zones** under **Advanced** | [`GET /v1/relay/zones`](api/relay.md#get-v1relayzones) | [`relay_zones`](mcp/relay.md#relay_zones) |
| Test the connection | **Test connection** under **Advanced** | [`POST /v1/relay/test`](api/relay.md#post-v1relaytest) | [`relay_test`](mcp/relay.md#relay_test) |
| Delete the relay from Cloudflare | **Delete relay from Cloudflare...** under **Advanced** | [`POST /v1/relay/delete`](api/relay.md#post-v1relaydelete) | [`relay_delete`](mcp/relay.md#relay_delete) |
| Instructions for ChatGPT, Claude or Codex | **Copy instructions** | [`GET /v1/relay/instructions`](api/relay.md#get-v1relayinstructions) | [`relay_instructions`](mcp/relay.md#relay_instructions) |
| List connected agents, create or revoke a key | **Create key**, **Revoke** | [`GET /v1/relay/connectors`](api/relay.md#get-v1relayconnectors), [`POST /v1/relay/keys`](api/relay.md#post-v1relaykeys) | [`list_connectors`](mcp/relay.md#list_connectors), [`create_agent_key`](mcp/relay.md#create_agent_key), [`revoke_agent_key`](mcp/relay.md#revoke_agent_key) |
| List reply subscriptions, or end one | **End** | [`GET /v1/relay/events`](api/relay.md#get-v1relayevents) | [`relay_events`](mcp/relay.md#relay_events), [`relay_remove_event_subscription`](mcp/relay.md#relay_remove_event_subscription) |
| Read today's usage | **Settings > Cloud** | [`GET /v1/relay/usage`](api/relay.md#get-v1relayusage) | [`relay_usage`](mcp/relay.md#relay_usage) |

## What only a person can do

These are left out of the API, the CLI and MCP on purpose.

| Task | Why it stays with the user |
|---|---|
| Grant an approval: an app's command permission, a callback host, a template's code. | The program that holds the token is the one the approval protects against, so it must not approve itself. Reading and revoking are open. |
| Press a banner button. | A button runs code or sends data on the user's behalf. |
| Approve a connector's request to use the relay. | The request is answered on the Mac, with the code the agent printed. |
| Read the stored Cloudflare token. | The token is a secret that is written once and never read back. |
| Open the Designer, Quick send, History or Settings windows. | The API never activates a window or takes focus. Previews and snapshots give an agent what a person would look at. |
| Mark a notification as opened, as a banner click does. | It would act as a click the user did not make. |

## Settings are validated against one table

Every general setting is one row in a single table. An unknown key, a wrong type or a value out of range gets `400`, and
nothing is changed. [`GET /v1/settings`](api/settings.md#get-v1settings) returns the same table as `schema`, so an agent
can discover the keys and their limits without a document.

## Related

- [HTTP API](api/README.md): the endpoint blocks every row links to.
- [MCP tools](mcp/README.md): the tool blocks.
- [CLI](cli.md): the command blocks.
- [The app](../APP.md): the menu, History and every Settings tab.
- [Actions](actions.md): the approvals only a person can grant.
