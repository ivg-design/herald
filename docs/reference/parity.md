# What you can do where

Herald has four ways in: the app's own windows, the local HTTP API, the `herald` command-line tool and the MCP server for agents. This page answers one question: "I can do this in the app; how do I do it over HTTP, from the command line and through MCP?" Find the thing you do in the app in the first column, then follow the link in the column you want.

Every MCP tool wraps one HTTP route, and every CLI command is one or two HTTP requests, so a capability that exists in MCP exists in HTTP. The CLI covers the routes that are natural at a prompt, so it has the fewest. A cell reads **none** when that way in cannot do it, and **UI only** when it is a view state such as a selection or a zoom level, with nothing stored to read or set. A task that must stay with a person at the Mac is listed under the table of its area and in [What only a person can do](#what-only-a-person-can-do).

| Way in | Who uses it | Needs |
|---|---|---|
| The app's windows | A person at the Mac. | Herald running. |
| [HTTP API](api/README.md) | Any program on the Mac. | The bearer token. |
| [CLI](cli.md) | A person or script at a terminal. | Herald running. |
| [MCP server](mcp/README.md) | An agent. | An MCP client with `herald-mcp` installed. |

## Notifications and banners

Show, close and snooze banners, and read what the user typed into them. The app column names the menu, the Quick send window or the Designer.

| What you do in the app | HTTP | CLI | MCP |
|---|---|---|---|
| **Compose...** (Quick send), then send | [`POST /v1/notify`](api/notifications.md#post-v1notify) | [`herald notify`](cli.md#herald-notify) | [`send_notification`](mcp/notifications.md#send_notification) |
| **Send test** in the Designer | [`POST /v1/notify`](api/notifications.md#post-v1notify) | [`herald notify`](cli.md#herald-notify) | [`send_test`](mcp/notifications.md#send_test) |
| **Speak** in **Settings > Voice** | [`POST /v1/speak`](api/notifications.md#post-v1speak) | [`herald speak`](cli.md#herald-speak) | [`speak`](mcp/notifications.md#speak) |
| Close button on a banner | [`POST /v1/dismiss`](api/notifications.md#post-v1dismiss) | [`herald dismiss`](cli.md#herald-dismiss) | [`dismiss`](mcp/notifications.md#dismiss) |
| **Dismiss All** | [`POST /v1/dismissAll`](api/notifications.md#post-v1dismissall) | [`herald dismiss-all`](cli.md#herald-dismiss-all) | [`dismiss`](mcp/notifications.md#dismiss) |
| Clock menu on a banner | [`POST /v1/snooze`](api/notifications.md#post-v1snooze) | [`herald snooze`](cli.md#herald-snooze) | [`snooze`](mcp/notifications.md#snooze) |
| Bring a snoozed banner back | [`POST /v1/unsnooze`](api/notifications.md#post-v1unsnooze) | [`herald unsnooze`](cli.md#herald-unsnooze) | [`snooze`](mcp/notifications.md#snooze) |
| Click a stack to see its list | [`GET /v1/stacks`](api/stacks.md#get-v1stacks) | [`herald stacks`](cli.md#herald-stacks) | [`list_stacks`](mcp/notifications.md#list_stacks) |
| Click a stack to open or close it | [`POST /v1/stacks/expand`](api/stacks.md#post-v1stacksexpand) | none | [`expand_stack`](mcp/notifications.md#expand_stack) |
| Read a reply in History | [`GET /v1/replies`](api/replies.md#get-v1replies) | none | [`get_replies`](mcp/notifications.md#get_replies) |
| Wait for a reply to one banner | [`GET /v1/replies/wait`](api/replies.md#get-v1replieswait) | none | [`wait_for_reply`](mcp/notifications.md#wait_for_reply) |
| Menu: **Compose...** | [`POST /v1/compose`](api/notifications.md#post-v1compose) | [`herald compose`](cli.md#herald-compose) | none |

Only in some places:

- **Press a banner button** exists only in the app. A button runs code or sends data on the user's behalf, so no API, command or tool presses one. An agent can send a button and read the answer.

## Templates

A template is one JSON document, and every edit the Designer makes rewrites it. Saving a template therefore covers every edit, and the same validation runs on both sides.

| What you do in the app | HTTP | CLI | MCP |
|---|---|---|---|
| **Templates** list in the Designer | [`GET /v1/templates`](api/templates.md#get-v1templates) | [`herald template list`](cli.md#herald-template-list) | [`list_templates`](mcp/templates.md#list_templates) |
| Open a template | [`GET /v1/templates`](api/templates.md#get-v1templates) | [`herald template list`](cli.md#herald-template-list) | [`get_template`](mcp/templates.md#get_template) |
| **Save** | [`PUT /v1/templates`](api/templates.md#put-v1templates) | [`herald template put`](cli.md#herald-template-put) | [`put_template`](mcp/templates.md#put_template) |
| **Delete** | [`DELETE /v1/templates`](api/templates.md#delete-v1templates) | [`herald template delete`](cli.md#herald-template-delete) | [`delete_template`](mcp/templates.md#delete_template) |
| **Duplicate** | [`POST /v1/templates/duplicate`](api/templates.md#post-v1templatesduplicate) | [`herald template duplicate`](cli.md#herald-template-duplicate) | [`duplicate_template`](mcp/templates.md#duplicate_template) |
| Rename a template | [`POST /v1/templates/rename`](api/templates.md#post-v1templatesrename) | [`herald template rename`](cli.md#herald-template-rename) | [`rename_template`](mcp/templates.md#rename_template) |
| **Set as issuer default** | [`PUT /v1/templates/default`](api/templates.md#put-v1templatesdefault) | [`herald template default`](cli.md#herald-template-default) | [`set_default_template`](mcp/templates.md#set_default_template) |
| **Export...** a bundle | [`GET /v1/templates/export`](api/templates.md#get-v1templatesexport) | [`herald template export`](cli.md#herald-template-export) | [`export_template_bundle`](mcp/templates.md#export_template_bundle) |
| **Import...** a bundle | [`POST /v1/templates/import`](api/templates.md#post-v1templatesimport) | [`herald template import`](cli.md#herald-template-import) | [`import_template_bundle`](mcp/templates.md#import_template_bundle) |
| The problems button | none | none | [`validate_template`](mcp/templates.md#validate_template) |
| **Component** menu in the **Cell** tab | [`GET /v1/components`](api/templates.md#get-v1components) | none | [`component_schema`](mcp/templates.md#component_schema) |
| **Actions** tab, add a rule | [`PUT /v1/templates`](api/templates.md#put-v1templates) | [`herald template put`](cli.md#herald-template-put) | [`add_action_rule`](mcp/templates.md#add_action_rule) |
| **Actions** tab, **Follow-up** block | [`PUT /v1/templates/follow-up`](api/templates.md#put-v1templatesfollow-up) | [`herald template follow-up`](cli.md#herald-template-follow-up) | [`set_follow_up`](mcp/templates.md#set_follow_up) |
| Symbol browser | [`GET /v1/symbols`](api/templates.md#get-v1symbols) | [`herald symbols`](cli.md#herald-symbols) | [`list_symbols`](mcp/templates.md#list_symbols) |
| **Run Apple Shortcut** form | [`GET /v1/shortcuts`](api/templates.md#get-v1shortcuts) | none | [`list_shortcuts`](mcp/templates.md#list_shortcuts) |
| Select a cell, undo, redo, zoom, drag | none | none | UI only |

Only in some places:

- **Problems button**: the app and MCP check a draft without saving it. Over HTTP and the CLI, `PUT /v1/templates` validates as it saves.
- **Selection, undo, redo, zoom and drag** are view state of the Designer window. A saved template holds the result.

## Previews and checks

See what a banner looks like, and check that Herald is up, without opening a window.

| What you do in the app | HTTP | CLI | MCP |
|---|---|---|---|
| Live preview, light or dark | [`POST /v1/preview`](api/templates.md#post-v1preview) | none | [`render_preview`](mcp/templates.md#render_preview) |
| **Last real** in the preview header | [`POST /v1/preview`](api/templates.md#post-v1preview) | none | [`render_preview`](mcp/templates.md#render_preview) |
| Preview a stack or a confirmation | [`POST /v1/preview`](api/templates.md#post-v1preview) | none | [`render_preview`](mcp/templates.md#render_preview) |
| Look at the whole Designer | [`GET /v1/designer/snapshot`](api/diagnostics.md#get-v1designersnapshot) | none | [`designer_snapshot`](mcp/templates.md#designer_snapshot) |
| Rive details in the **Cell** tab | [`POST /v1/rive/check`](api/diagnostics.md#post-v1rivecheck) | none | [`rive_check`](mcp/templates.md#rive_check) |
| The bell in the menu bar | [`GET /v1/health`](api/diagnostics.md#get-v1health) | [`herald health`](cli.md#herald-health) | [`herald_status`](mcp/notifications.md#herald_status) |

## Manifests and assets

What a manifest holds is in [Manifests](manifests.md).

| What you do in the app | HTTP | CLI | MCP |
|---|---|---|---|
| **Fields** in the Designer palette | [`GET /v1/manifests`](api/manifests.md#get-v1manifests) | none | [`list_manifests`](mcp/templates.md#list_manifests) |
| Open one app's fields | [`GET /v1/manifest`](api/manifests.md#get-v1manifest) | none | [`get_manifest`](mcp/templates.md#get_manifest) |
| Apps send a manifest themselves | [`PUT /v1/manifest`](api/manifests.md#put-v1manifest) | none | [`put_manifest`](mcp/templates.md#put_manifest) |
| Remove an app's manifest | [`DELETE /v1/manifest`](api/manifests.md#delete-v1manifest) | [`herald manifest delete`](cli.md#herald-manifest-delete) | [`delete_manifest`](mcp/templates.md#delete_manifest) |
| **Assets** in the Designer palette | [`GET /v1/assets`](api/assets.md#get-v1assets) | [`herald assets list`](cli.md#herald-assets-list) | [`list_assets`](mcp/templates.md#list_assets) |
| **Add...** under **Assets** | [`POST /v1/assets`](api/assets.md#post-v1assets) | [`herald assets add`](cli.md#herald-assets-add) | [`upload_asset`](mcp/templates.md#upload_asset) |
| **Remove...** under **Assets** | [`DELETE /v1/assets`](api/assets.md#delete-v1assets) | [`herald assets rm`](cli.md#herald-assets-rm) | [`delete_asset`](mcp/templates.md#delete_asset) |

Only in some places:

- **Saving a manifest** has no app window and no CLI command: a manifest comes from the app that sends it. Use `PUT /v1/manifest` or `put_manifest`.

## History

Past notifications, kept per app.

| What you do in the app | HTTP | CLI | MCP |
|---|---|---|---|
| History window | [`GET /v1/history`](api/history.md#get-v1history) | [`herald history`](cli.md#herald-history) | [`list_history`](mcp/apps-and-settings.md#list_history) |
| A follow-up's line in a History row | [`GET /v1/history`](api/history.md#get-v1history) | [`herald history`](cli.md#herald-history) | [`list_history`](mcp/apps-and-settings.md#list_history) |
| The search field | [`GET /v1/history/search`](api/history.md#get-v1historysearch) | [`herald history search`](cli.md#herald-history-search) | [`history_search`](mcp/apps-and-settings.md#history_search) |
| **Re-show as Banner** | [`POST /v1/history/reshow`](api/history.md#post-v1historyreshow) | [`herald history reshow`](cli.md#herald-history-reshow) | [`reshow_notification`](mcp/apps-and-settings.md#reshow_notification) |
| **Delete** on one item | [`DELETE /v1/history/item`](api/history.md#delete-v1historyitem) | [`herald history delete`](cli.md#herald-history-delete) | [`delete_history`](mcp/apps-and-settings.md#delete_history) |
| **Clear NAME History...** | [`DELETE /v1/history`](api/history.md#delete-v1history) | [`herald history delete`](cli.md#herald-history-delete) | [`delete_history`](mcp/apps-and-settings.md#delete_history) |
| **Export JSON...** | [`GET /v1/history/export`](api/history.md#get-v1historyexport) | [`herald history export`](cli.md#herald-history-export) | [`export_history`](mcp/apps-and-settings.md#export_history) |

## Settings and apps

The app column names the Settings tab. The keys and their values are in the [settings API](api/settings.md) and the [apps API](api/apps.md).

| What you do in the app | HTTP | CLI | MCP |
|---|---|---|---|
| **Settings > General** | [`GET /v1/settings`](api/settings.md#get-v1settings) | [`herald settings`](cli.md#herald-settings) | [`get_settings`](mcp/apps-and-settings.md#get_settings) |
| Change a general or voice setting | [`PUT /v1/settings`](api/settings.md#put-v1settings) | [`herald settings set`](cli.md#herald-settings-set) | [`set_settings`](mcp/apps-and-settings.md#set_settings) |
| Quiet hours, **Settings > Voice** | [`GET /v1/settings/quiet-hours`](api/settings.md#get-v1settingsquiet-hours) | [`herald quiet`](cli.md#herald-quiet) | [`get_quiet_hours`](mcp/apps-and-settings.md#get_quiet_hours) |
| Change quiet hours or silence for a while | [`PUT /v1/settings/quiet-hours`](api/settings.md#put-v1settingsquiet-hours) | [`herald quiet`](cli.md#herald-quiet) | [`set_quiet_hours`](mcp/apps-and-settings.md#set_quiet_hours) |
| Menu: **Stack Notifications** | [`PUT /v1/settings/stacking`](api/stacks.md#put-v1settingsstacking) | [`herald settings set`](cli.md#herald-settings-set) | [`set_settings`](mcp/apps-and-settings.md#set_settings) |
| Kokoro voice, **Settings > Voice** | [`GET /v1/voice`](api/setup.md#get-v1voice) | [`herald voice`](cli.md#herald-voice) | [`voice_status`](mcp/apps-and-settings.md#voice_status) |
| Install the Kokoro voice | [`POST /v1/voice/install`](api/setup.md#post-v1voiceinstall) | [`herald voice`](cli.md#herald-voice) | [`install_voice`](mcp/apps-and-settings.md#install_voice) |
| **Settings > MCP**, install in a client | [`POST /v1/mcp/install`](api/setup.md#post-v1mcpinstall) | [`herald mcp`](cli.md#herald-mcp) | [`install_mcp`](mcp/apps-and-settings.md#install_mcp) |
| Apps register themselves | [`POST /v1/register`](api/apps.md#post-v1register) | [`herald register`](cli.md#herald-register) | [`register_app`](mcp/apps-and-settings.md#register_app) |
| **Settings > Apps**, the list | [`GET /v1/apps`](api/apps.md#get-v1apps) | [`herald apps`](cli.md#herald-apps) | [`list_apps`](mcp/apps-and-settings.md#list_apps) |
| **Settings > Apps**, one app | [`GET /v1/apps/settings`](api/apps.md#get-v1appssettings) | [`herald apps settings`](cli.md#herald-apps-settings) | [`list_apps`](mcp/apps-and-settings.md#list_apps) |
| Change an app's sound, timeout, corner or voice | [`PUT /v1/apps/settings`](api/apps.md#put-v1appssettings) | [`herald apps set`](cli.md#herald-apps-set) | [`update_app_settings`](mcp/apps-and-settings.md#update_app_settings) |
| **Remove NAME...** in **Settings > Apps** | [`DELETE /v1/apps/{id}`](api/apps.md#delete-v1appsid) | none | [`delete_app`](mcp/apps-and-settings.md#delete_app) |
| Reveal the token file or the log in Finder | none | none | UI only |

Only in some places:

- **Registering an app** has no window: an app registers itself, and **Settings > Apps** then lists it.
- **Removing an app** has no CLI command. Use `DELETE /v1/apps/{id}` or `delete_app`.
- **Revealing a file in Finder** is a button in the app. The files are plain paths in `~/Library/Application Support/Herald/`.

## Approvals

An approval is the user's permission for something that runs code or sends data off the Mac. What each one covers is in [Approvals](actions.md#approvals).

| What you do in the app | HTTP | CLI | MCP |
|---|---|---|---|
| See an app's command and callback approvals | [`GET /v1/apps/settings`](api/apps.md#get-v1appssettings) | [`herald apps settings`](cli.md#herald-apps-settings) | [`list_apps`](mcp/apps-and-settings.md#list_apps) |
| Revoke with **Allow this app to run commands, scripts and Shortcuts** | [`PUT /v1/apps/settings`](api/apps.md#put-v1appssettings) | [`herald apps set`](cli.md#herald-apps-set) | [`update_app_settings`](mcp/apps-and-settings.md#update_app_settings) |
| See a follow-up's approval state | [`GET /v1/actions/approvals`](api/apps.md#get-v1actionsapprovals) | [`herald approvals`](cli.md#herald-approvals) | [`list_approvals`](mcp/apps-and-settings.md#list_approvals) |
| See a template's code approvals, **Settings > Actions** | [`GET /v1/actions/approvals`](api/apps.md#get-v1actionsapprovals) | [`herald approvals`](cli.md#herald-approvals) | [`list_approvals`](mcp/apps-and-settings.md#list_approvals) |
| **Revoke** a template's approval | [`DELETE /v1/actions/approvals`](api/apps.md#delete-v1actionsapprovals) | [`herald approvals revoke`](cli.md#herald-approvals-revoke) | [`revoke_approval`](mcp/apps-and-settings.md#revoke_approval) |
| Grant any approval | none | none | none |

Only in some places:

- **Granting an approval** exists only in the app, by design: the program that holds the token is the one the approval protects against, so it must not approve itself. Reading and revoking are open.

## Cloud relay

The relay lets agents that run elsewhere send notifications to this Mac. The app window is **Settings > Cloud**. [Cloud](../CLOUD.md) explains the relay and these controls. The CLI has no relay commands.

| What you do in the app | HTTP | CLI | MCP |
|---|---|---|---|
| **Settings > Cloud**, status and **Update the relay** | [`GET /v1/relay/status`](api/relay.md#get-v1relaystatus) | none | [`relay_status`](mcp/relay.md#relay_status) |
| **Open Cloudflare...** in the deploy sheet | [`GET /v1/relay/token-url`](api/relay.md#get-v1relaytoken-url) | none | [`relay_token_url`](mcp/relay.md#relay_token_url) |
| Enter the Cloudflare API token in the deploy sheet | [`POST /v1/relay/token`](api/relay.md#post-v1relaytoken) | none | [`relay_set_cloudflare_token`](mcp/relay.md#relay_set_cloudflare_token) |
| **Enable relay**, **Redeploy** | [`POST /v1/relay/deploy`](api/relay.md#post-v1relaydeploy) | none | [`relay_deploy`](mcp/relay.md#relay_deploy) |
| **Pair with a code** | [`POST /v1/relay/pair`](api/relay.md#post-v1relaypair) | none | [`relay_pair`](mcp/relay.md#relay_pair) |
| **Unpair** | [`POST /v1/relay/unpair`](api/relay.md#post-v1relayunpair) | none | [`relay_unpair`](mcp/relay.md#relay_unpair) |
| **Advanced** fields | [`GET /v1/relay/settings`](api/relay.md#get-v1relaysettings) | none | [`relay_settings`](mcp/relay.md#relay_settings) |
| **Apply settings** | [`PUT /v1/relay/settings`](api/relay.md#put-v1relaysettings) | none | [`relay_settings`](mcp/relay.md#relay_settings) |
| **Load zones** | [`GET /v1/relay/zones`](api/relay.md#get-v1relayzones) | none | [`relay_zones`](mcp/relay.md#relay_zones) |
| **Test connection** | [`POST /v1/relay/test`](api/relay.md#post-v1relaytest) | none | [`relay_test`](mcp/relay.md#relay_test) |
| **Delete relay from Cloudflare...** | [`POST /v1/relay/delete`](api/relay.md#post-v1relaydelete) | none | [`relay_delete`](mcp/relay.md#relay_delete) |
| **Copy instructions** | [`GET /v1/relay/instructions`](api/relay.md#get-v1relayinstructions) | none | [`relay_instructions`](mcp/relay.md#relay_instructions) |
| Connected agents | [`GET /v1/relay/connectors`](api/relay.md#get-v1relayconnectors) | none | [`list_connectors`](mcp/relay.md#list_connectors) |
| **Create key** | [`POST /v1/relay/keys`](api/relay.md#post-v1relaykeys) | none | [`create_agent_key`](mcp/relay.md#create_agent_key) |
| **Revoke** a key | [`DELETE /v1/relay/keys/{id}`](api/relay.md#delete-v1relaykeysid) | none | [`revoke_agent_key`](mcp/relay.md#revoke_agent_key) |
| Reply subscriptions | [`GET /v1/relay/events`](api/relay.md#get-v1relayevents) | none | [`relay_events`](mcp/relay.md#relay_events) |
| **End** a subscription | [`DELETE /v1/relay/events/subscriptions/{id}`](api/relay.md#delete-v1relayeventssubscriptionsid) | none | [`relay_remove_event_subscription`](mcp/relay.md#relay_remove_event_subscription) |
| Today's usage | [`GET /v1/relay/usage`](api/relay.md#get-v1relayusage) | none | [`relay_usage`](mcp/relay.md#relay_usage) |

Only in some places:

- **Approving a connector** happens only on the Mac, by design: the connector's request is answered in the app with the code the agent printed.
- **Reading the stored Cloudflare token** is not possible anywhere. It is written once and never read back.

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
