# Quiet hours

Quiet hours are periods when Herald holds back speech, arrival sounds, banners, or any mix of the three. They
exist so a build that finishes at 3 a.m. does not read itself out loud next to a sleeping person, and so the user
can say "no interruptions for an hour" with one click. This page explains how windows work, what each kind of
silence does, and how an urgent notification gets through. It is for users who set the schedule and for agents
and apps that read or change it.

## Concepts

Herald has two kinds of quiet period, and they combine.

- A **window** is a repeating schedule: from a start time to an end time, on chosen days. It is the right tool
  for nights and weekends.
- An **ad hoc silence** is a one-off: quiet until a time, or for a number of minutes, starting now. It is the right
  tool for a meeting.

At any moment, what is silenced is the union of every active window and the ad hoc silence. If a window silences
speech and the ad hoc silence silences banners, both are silenced. The status Herald reports names the source:
`window`, `adhoc` or `both`.

A window can silence three things, and each is a separate switch:

| Silenced | What the user notices |
|---|---|
| Speech | Spoken notifications and voice messages stay quiet. |
| Sounds | The arrival chime does not play. |
| Banners | New banners do not appear on screen. |

Nothing is lost. Silenced notifications still go to History.

## Where quiet hours are set

The schedule lives in **Settings > Voice > Quiet hours**. A status line reads **Not quiet right now.** or
**Quiet until 07:30** with a **Resume Now** button. Below it is one editor per window, then **Add Window** and
**Quiet for 1 Hour**.

![The Quiet hours section of the Voice tab in Herald's Settings, showing one window from 22:30 until 07:30 with day buttons and the Speech, Sounds and Banners switches](../../web/public/shots/docs/settings-quiet-hours.png "A window editor: the day buttons, the From and until times, what the window silences, and the summary switch.")

The menu has the quick controls. When Herald is not quiet it shows **Quiet for 1 Hour**. While it is quiet it
shows **Quiet until 07:30** with **Resume Now** under it.

![The Herald menu with the Quiet for 1 Hour item](../../web/public/shots/docs/menu.png "The menu: Quiet for 1 Hour, or Quiet until a time with Resume Now while Herald is quiet.")

Agents and scripts use the API, the CLI or MCP:

- [`GET /v1/settings/quiet-hours`](api/settings.md#get-v1settingsquiet-hours) reads the schedule and the status.
- [`PUT /v1/settings/quiet-hours`](api/settings.md#put-v1settingsquiet-hours) changes it.
- [`herald quiet`](cli.md#herald-quiet) does the same from a shell.
- [`get_quiet_hours`](mcp/apps-and-settings.md#get_quiet_hours) and
  [`set_quiet_hours`](mcp/apps-and-settings.md#set_quiet_hours) are the MCP tools.

## Windows

A window is one JSON object. The editor in Settings writes the same object.

| Field | Type | Required | Description |
|---|---|---|---|
| `start` | string | yes | The start time, `HH:MM`, 24-hour, in the Mac's local time. |
| `end` | string | yes | The end time, `HH:MM`. It must differ from `start`. |
| `days` | array | no | The days the window starts on, from `mon` to `sun`. Empty or missing means every day. |
| `speech` | boolean | no | `true` silences speech. Default `true`. |
| `sounds` | boolean | no | `true` silences the arrival chime. Default `false`. |
| `banners` | boolean | no | `true` silences banners. Default `false`. |
| `speakSummary` | boolean | no | `true` speaks one summary when the window ends. Default `false`. |
| `id` | string | no | An identifier. Herald generates one when you omit it. Ids must be unique. |

Rules that span fields:

- A window belongs to the day it **starts** on. A window from Friday 22:30 to 07:30 runs into Saturday morning.
- When `end` is not later than `start`, the window ends the next morning. 22:30 to 07:30 is an overnight window.
  There is no way to write a window that ends on the same day it starts at an earlier time.
- The start is included and the end is excluded: at exactly 07:30 the window is over.
- Day names are read from their first three letters, so `Mon`, `monday` and `MON` all mean `mon`.
- A schedule holds at most 24 windows.
- A window that silences nothing (all three switches off) is not quiet.

**Minimal example**

```json
{"start": "22:30", "end": "07:30"}
```

This silences speech every night, because `speech` is on by default.

**Realistic example**

```json
{
  "id": "weeknights",
  "days": ["sun", "mon", "tue", "wed", "thu"],
  "start": "22:30",
  "end": "07:30",
  "speech": true,
  "sounds": true,
  "banners": false,
  "speakSummary": true
}
```

On Sunday to Thursday evenings this window silences speech and chimes until morning, but still shows banners.
Because it is keyed to the start day, it covers the nights that end on Monday to Friday mornings. When it ends,
Herald speaks one summary of what it held back.

### Summary on return

With `speakSummary` on, Herald keeps the titles of the notifications whose speech it held back. When the window ends, it speaks one line, for example "2 messages while you were away: Bid accepted, Deploy finished".

- Up to four titles are named and the rest are counted ("and 3 more").
- If nothing was held back, nothing is said.
- In Settings the switch is **Speak queued messages when it ends**, and it is available when the window silences speech.

## What silenced means

| Silenced | Effect on a notification |
|---|---|
| Speech | Nothing is synthesised or played. History keeps the text and marks the speech `suppressed: "quiet-hours"`. |
| Sounds | The arrival chime is skipped. The banner is unaffected. |
| Banners | The banner has no panel. The entry is in History, unread, and counts in the "+N more" pill. |

A voice-only notification whose speech is held back is shown as a banner instead, unless banners are silenced
too, in which case it waits in History like any other held-back banner. See
[Voice](voice.md#fall-back-to-a-banner).

## Ad hoc silence and Resume

An ad hoc silence starts now and ends at a time or after a number of minutes. It silences speech and sounds
unless told otherwise, and banners only when asked. **Quiet for 1 Hour** in the menu and in Settings starts a
60-minute silence of speech and sounds.

**Resume Now** ends the current quiet period early. It cancels an ad hoc silence and ends the current occurrence
of every active window. The next occurrence of each window applies as usual: resuming at 02:00 does not cancel
tomorrow night. It is offered only while Herald is quiet.

If one request both resumes and starts an ad hoc silence, the new ad hoc silence wins. The details of the request
are in [`PUT /v1/settings/quiet-hours`](api/settings.md#put-v1settingsquiet-hours).

## Urgent breaks through

A notification sent with `"priority": "urgent"` ignores quiet hours, but only for apps whose user has turned on
**Urgent can break quiet hours**. The switch is off by default, so an app cannot override the user's quiet
simply by marking everything urgent.

The switch is in **Settings > Voice > Speak per app**, on the app's row. It lifts every silence for that
notification: it speaks, chimes and shows its banner. An agent can read and change the same setting as the app
setting `urgentBreaksQuiet`, through [`PUT /v1/apps/settings`](api/apps.md#put-v1appssettings). Ask the user
first, because it lets that app wake them.

## Examples

**A quiet night.** Silence speech and chimes from 22:30 to 07:30 every day, keep banners, and speak a summary in
the morning.

```json
{"windows": [{"start": "22:30", "end": "07:30", "speech": true, "sounds": true, "speakSummary": true}]}
```

**A weekend lie-in.** Silence everything on Friday and Saturday nights until 09:00, so banners wait in History
too. The window starts on the listed day, so Saturday and Sunday mornings are covered.

```json
{"windows": [{"days": ["fri", "sat"], "start": "22:30", "end": "09:00", "speech": true, "sounds": true, "banners": true}]}
```

**An hour in a meeting.** Ad hoc, speech and sounds, 60 minutes.

```json
{"adHoc": {"minutes": 60}}
```

These bodies go to [`PUT /v1/settings/quiet-hours`](api/settings.md#put-v1settingsquiet-hours).

## Common mistakes

| Mistake | What happens | Fix |
|---|---|---|
| Writing `end` earlier than `start` and expecting a same-day window. | It is an overnight window by design. | Pick the times you mean. |
| Setting `days: ["fri"]` and expecting Saturday morning to be loud. | The window belongs to Friday and runs into Saturday. | That is the intent. Add a window for the days you want. |
| Expecting banners to be silenced by default. | Banners still show. | Set `banners` to `true` in the window. |
| Expecting urgent to break through for any app. | Only apps the user opted in. | Ask the user to turn on **Urgent can break quiet hours**. |
| Using the same `start` and `end`. | The update is rejected. | Choose different times. |

## Related

- [Make Herald speak](../VOICE.md): the voice setup that quiet hours silence.
- [Voice](voice.md): speech, mute and the fall back to a banner.
- [Settings API](api/settings.md#get-v1settingsquiet-hours): read and change the schedule over HTTP.
- [`herald quiet`](cli.md#herald-quiet) and [`set_quiet_hours`](mcp/apps-and-settings.md#set_quiet_hours): the CLI
  and MCP routes.
