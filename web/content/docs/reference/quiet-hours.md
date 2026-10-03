# Quiet hours

Windows during which Herald holds back speech, sounds and/or banners. Set in Settings > Voice > Quiet hours, the
bell menu ("Quiet for 1 Hour"), the API, the CLI or the MCP. The wire types are in `HeraldQuiet.swift`; the
evaluator is pure (`QuietHours`) and tested.

## Windows

```json
{"id":"night","days":["fri","sat"],"start":"22:30","end":"07:30",
 "speech":true,"sounds":false,"banners":false,"speakSummary":true}
```

| Property | Type | Default | Meaning |
|---|---|---|---|
| `id` | string | generated | Identifier. |
| `days` | array of `mon` ... `sun` | `[]` = every day | Days the window **starts** on. Names are normalised from their first three letters (`Mon`, `monday`, `MON`). |
| `start` | string `HH:MM` | required | Local time, 24-hour (`H:MM` also read). |
| `end` | string `HH:MM` | required | Local time. An `end` that is not later than `start` runs into the next morning. |
| `speech` | boolean | `true` | Silences speech and voice messages. |
| `sounds` | boolean | `false` | Silences the arrival chime. |
| `banners` | boolean | `false` | Silences banners. |
| `speakSummary` | boolean | `false` | When the window ends, speak one summary of what was held back. |

A window **belongs to the day it starts**: Fri 22:30 to 07:30 runs into Saturday morning. Start is inclusive,
end exclusive. Times use the user's local calendar at delivery time.

## What "silenced" means

| Silenced | Effect |
|---|---|
| speech | `speak`, `audio` and the voice presentation are not synthesised or played. History records `speech.suppressed: "quiet-hours"` with the text. A voice-only notification held back is shown as a normal banner instead, unless banners are silenced too. |
| sounds | No arrival chime. |
| banners | The banner has no panel: it goes to History (unread) and the "+N more" pill, still counted as unread. |

`speakSummary` plays one line when the window ends: "3 messages while you were away: Build, Deploy and 1 more".

## Ad hoc silence and Resume

- **Ad hoc**: silence until a time or for a number of minutes, regardless of the schedule. Speech and sounds by
  default, banners only if asked. Quick forms: the bell menu "Quiet for 1 Hour", `herald quiet --for 60`.
- **Resume now**: ends the current ad hoc silence and the current occurrence of every active window (the next
  occurrence applies as usual). The menu shows "Quiet until 07:30" with "Resume Now" while quiet.
- What is silenced at any instant is the **union** of the active, not-resumed windows and an unexpired ad hoc
  silence. `status.source` is `window`, `adhoc` or `both`.

## Urgent breaks through

A notification with `"priority":"urgent"` breaks quiet hours **only for apps whose "Urgent can break quiet
hours" setting the user turned on** (off by default). Nothing in the API can turn it on.

## API

`GET /v1/settings/quiet-hours` returns:

```json
{"windows":[{"id":"night","days":[],"start":"22:30","end":"07:30","speech":true,"sounds":false,"banners":false,"speakSummary":false}],
 "adHoc":null,
 "status":{"active":false,"speech":false,"sounds":false,"banners":false,"until":null,"source":null}}
```

`PUT /v1/settings/quiet-hours` takes any of these, applied in this order:

| Field | Meaning |
|---|---|
| `windows` | Replaces the whole schedule: an array of windows. |
| `resume` | `true` ends the current silence (what `herald quiet off` sends). |
| `adHoc` | `{"until":"07:30" or an ISO 8601 date,"minutes":60,"speech":true,"sounds":true,"banners":false}`. `until` ("HH:MM") is the next time the clock reads it; give `until` or `minutes`. |

An ad hoc silence started by the same request wins over a `resume` in it. The reply is the same shape as the
GET. Dates in replies are ISO 8601. Errors are `400` with a message for an invalid time.

```sh
curl -s -X PUT -H "$AUTH" -H 'Content-Type: application/json' $BASE/v1/settings/quiet-hours \
  -d '{"windows":[{"days":["mon","tue","wed","thu","fri"],"start":"22:30","end":"07:30","speech":true,"sounds":true}]}'
curl -s -X PUT -H "$AUTH" -H 'Content-Type: application/json' $BASE/v1/settings/quiet-hours \
  -d '{"adHoc":{"minutes":60}}'
```

CLI: `herald quiet --until 07:30`, `herald quiet --for 60 [--banners]`, `herald quiet off`, `herald quiet status`.

MCP: `get_quiet_hours`, `set_quiet_hours {windows?, until?, minutes?, banners?, resume?}` (the MCP's flat
`until`/`minutes`/`banners` become the `adHoc` object). Tell the user before silencing them.

## Common mistakes

| Mistake | What happens | Fix |
|---|---|---|
| `end` earlier than `start` and expecting a same-day window | It is overnight by design. | Pick the times you mean. |
| `days:["fri"]` expecting Saturday morning to be excluded | The window belongs to Friday and runs into Saturday. | Include `fri` only; that is the intent. |
| Forgetting banners are not silenced by default | Banners still show. | Set `banners: true` in the window. |
| Expecting urgent to bypass quiet hours for any app | Only apps the user opted in. | Ask the user to enable it in Settings > Apps. |
