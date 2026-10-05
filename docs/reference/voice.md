# Voice

Herald can say a notification aloud, play a recorded voice message, or do both, with or without a banner. This
page is the reference for the voice fields of a notification, the engines that produce speech, how speech
behaves (queueing, replay, mute, falling back to a banner) and the `speech` record kept in History. It is for
anyone who sends notifications from an app or an agent. To turn voice on step by step, see
[Make Herald speak](../VOICE.md).

## Concepts

**Speech** is text that Herald reads aloud. You do not send audio: you send text (or let Herald use the title
and body) and an engine turns it into sound on the Mac. Nothing leaves the Mac, except the one-time, optional
download of the Kokoro model that the user starts in Settings.

**An audio message** is a recording you send yourself, such as a WAV file an app produced. Herald checks it,
caches it and plays it.

**Presentation** decides whether the notification is shown as a banner, spoken, or both. A voice-only
notification still leaves an entry in History, so the text stays searchable.

**An engine** is the thing that makes the speech: Kokoro (a local neural voice), the macOS system voice, or
Off. The user picks one in **Settings > Voice**. The sender cannot pick the engine, only the voice, speed and
language the engine understands.

The user stays in control. A global mute silences speech like it silences chimes, every app has its own **Speak**
switch, and [quiet hours](quiet-hours.md) hold speech back on a schedule. A notification that asked to be
voice-only is never lost when speech cannot play: it is shown as a banner instead.

## Notification fields

Three optional fields on a notification turn voice on. They go in the same JSON body as the other fields of
[`POST /v1/notify`](api/notifications.md#post-v1notify), and the CLI and MCP tools take the same three.

| Field | Type | Required | Description |
|---|---|---|---|
| `speak` | boolean or object | no | `true` speaks the title, then the body. An object sets the text, voice, speed and language. |
| `audio` | string | no | A recorded voice message: a file path, an `https` URL or a `data:` URI. |
| `presentation` | string | no | `banner`, `voice` or `both`. Default `banner`. |

Rules that span the fields:

- `speak: false` is the same as leaving `speak` out.
- A bare string is read as the `text` of a `speak` object.
- With both `speak` and `audio`, the speech plays first, then the recording.
- `presentation: "voice"` or `"both"` without `speak` or `audio` speaks the title and body.
- `presentation: "voice"` with `audio` and no `speak` plays only the recording.
- Invalid values are rejected before the notification is accepted. See [Errors](#errors).

**Minimal example**

```json
{"app": "example.bidbot", "title": "Bid accepted", "speak": true}
```

**Realistic example**

```json
{
  "app": "example.bidbot",
  "id": "bid-42",
  "title": "Bid accepted",
  "body": "Your bid of $4,200 on the Acme RFP was accepted.",
  "presentation": "both",
  "speak": {"text": "Good news. The Acme bid was accepted.", "voice": "af_bella", "speed": 1.1, "lang": "en-us"}
}
```

### The `speak` object

The object gives you control over what is said and how. Every property is optional, and `{}` behaves like
`true`.

| Property | Type | Default | Description |
|---|---|---|---|
| `text` | string | Title, then body. | What to say. At most 2000 characters; the rest is dropped. |
| `voice` | string | The app's voice, else the engine default. | A voice id such as `af_heart`. |
| `speed` | number | The app's speed, else the engine setting. | A value from 0.5 to 2.0. |
| `lang` | string | The engine setting, `en-us` by default. | A language code such as `en-us` or `en-gb`. |

How the text is prepared:

- Markdown links are read as their label: `[Open](https://example.com)` is read as "Open".
- Runs of whitespace become one space.
- When the text is built from the title and the body, each part gets a full stop if it does not already end in
  `.`, `!` or `?`, so the two parts do not run together.

How the other properties are checked:

- `voice` is a model id: ASCII letters, digits, `_`, `-` and `.`, at most 64 characters.
  - With Kokoro the ids are `af_heart`, `af_bella`, `af_nicole`, `am_michael`, `bf_emma`, `bm_george` and any others the installed model reports.
  - With the system voice, a `voice` that is not the identifier of an installed system voice is ignored and the voice chosen in Settings is used.
- `lang` is ASCII letters, `-` and `_`, at most 16 characters.
- `speed` outside 0.5 to 2.0 is rejected.

### The `audio` field

`audio` is a voice message you provide. Herald accepts WAV, MP3, M4A, AIFF and CAF.

- The size limit is 20 MB.
- The format is read from the file's bytes, never from its name. A file that is not audio is ignored and the
  notification is handled as if `audio` were absent.
- Herald copies the file into its own cache under `history/audio/`, so the sender may delete the original.
- A `data:` URI is also bound by the 1 MB request limit. Use a path or an `https` URL for anything larger. See
  [Limits](api/README.md#limits).

### The `presentation` field

| Value | What happens |
|---|---|
| `banner` | The notification is a banner. It is spoken only when `speak` or `audio` is set. This is the default. |
| `voice` | The notification is spoken only: no banner and no arrival chime. History keeps the entry, marked read. |
| `both` | The notification is a banner and is spoken. |

## Engines

The engine is a setting of the Mac, chosen in **Settings > Voice > Engine**. See
[Make Herald speak](../VOICE.md#choose-an-engine) for the steps.

| Engine | What it is | Notes |
|---|---|---|
| Kokoro (local, natural) | A neural voice that runs on the Mac. | Needs a one-time download of about 340 MB, or an existing installation to reuse. |
| System voice | The built-in macOS voices. | Works at once and is the default. |
| Off | Text-to-speech is switched off. | No text is spoken. Audio messages you send still play. |

Differences that matter to a sender:

- **Kokoro** loads its model on the first request, which takes a few seconds, then stays loaded so later
  requests take well under a second. If its worker process exits, the next request starts it again. Each
  spoken notification is stored as a WAV file, which makes replay exact.
- **System voice** speaks directly and produces no file. A replay speaks the text again.
- **Off** speaks no text. A voice-only notification that has no `audio` then falls back to a banner. See
  [Fall back to a banner](#fall-back-to-a-banner).

The voice, speed and Speak switch can also be set for one app. The keys are listed in the
[settings API](api/settings.md) and the [apps API](api/apps.md#put-v1appssettings).

## Behaviour

### Queueing

Speech never overlaps. Herald plays notifications one at a time in the order they arrived. At most 20 wait in
the queue; when more arrive, the oldest waiting ones are dropped, so a flood of notifications does not read out
for minutes.

Dismissing a banner interrupts that notification's speech. **Dismiss All** stops everything.

### Mute

The global mute (**Mute Sounds** in the menu) silences speech as it silences chimes: a muted Herald plays no
speech and no audio messages. Two things ignore mute because the user asked for them directly: the replay
control and the **Speak** test button in Settings.

### Replay

A banner that carries speech shows a small speaker control beside the timestamp. If the template draws no
timestamp, the control sits in a thin row under the grid. Pressing it plays the speech again, even while Herald
is muted. History shows the same control next to the spoken text.

![A Herald banner with a small speaker control beside its time](../../web/public/shots/docs/banner-speech.png "The speaker control on a spoken banner plays the message again.")

Replay uses the cached WAV. Herald keeps the newest 300 audio files; if the file for an older entry was
removed, replay synthesises the text again with the current engine.

### Fall back to a banner

A voice-only notification is never lost. Herald shows it as a normal banner when it could not be heard:

- Herald is muted.
- The app's **Speak** switch is off.
- The engine is Off and the notification has no `audio`.
- The audio could not be read, or synthesis failed.
- [Quiet hours](quiet-hours.md) are holding speech back (the banner is then also held back if the quiet window
  silences banners).

### Quiet hours

During quiet hours that silence speech, Herald does not synthesise or play anything. It records
`suppressed: "quiet-hours"` on the entry's speech record. A notification with `priority` `urgent` speaks anyway
for apps whose user turned on **Urgent can break quiet hours**. The details are in
[Quiet hours](quiet-hours.md).

## The speech record in History

Each spoken notification stores a `speech` object on its History entry. It is returned by the
[History API](api/history.md) and shown in the History window.

```json
{
  "speech": {
    "text": "Bid accepted. Your bid of $4,200 on the Acme RFP was accepted.",
    "voice": "af_heart",
    "audioPath": "/Users/you/Library/Application Support/Herald/history/audio/speech-1A2B.wav",
    "durationSeconds": 3.1,
    "suppressed": null
  }
}
```

| Field | Type | Description |
|---|---|---|
| `text` | string | What was or would have been said. |
| `voice` | string | The voice id used, when one was chosen. |
| `audioPath` | string | The cached audio file. Absent for the system voice and when synthesis failed. |
| `durationSeconds` | number | The length of the audio. Absent for the system voice and when synthesis failed. |
| `suppressed` | string | `quiet-hours` when speech was held back, otherwise null. |

## Where to send voice fields

| Surface | How |
|---|---|
| HTTP | The voice fields on [`POST /v1/notify`](api/notifications.md#post-v1notify), or [`POST /v1/speak`](api/notifications.md#post-v1speak) for speech with no banner. |
| CLI | The voice options on [`herald notify`](cli.md#herald-notify), or [`herald speak`](cli.md#herald-speak) for speech with no banner. |
| MCP | The [`speak`](mcp/notifications.md#speak) tool, and the same three fields on [`send_notification`](mcp/notifications.md#send_notification). |
| Swift | `HeraldClient.shared.speak(HeraldSpeakRequest(app:text:))`, or `speak` and `presentation` on a `HeraldNotification`. |

`POST /v1/speak` is a shortcut for a notification with presentation `voice`. Its History title is the text cut to
80 characters. Voice setup on a Mac, including the Kokoro installer, is exposed by the
[setup API](api/setup.md).

## Privacy and security

- Synthesis and playback are local. Kokoro runs in a child process of Herald that talks over standard input and
  output.
- The text reaches the worker as a JSON string. It is never placed in a shell command.
- Voice, language and speed are validated before they reach the engine.
- Audio is accepted only when its bytes are a known audio format and at most 20 MB.
- Spoken text is stored in History like any other notification text.

## Errors

| Status | When |
|---|---|
| `400` | `voice` is not a valid id (`invalid voice`) or `lang` is not a valid code (`invalid lang`). |
| `400` | `speed` is outside 0.5 to 2.0 (`speed must be between 0.5 and 2.0`). |
| `400` | `POST /v1/speak` has no `app` or no `text`. |
| `413` | The body is over 1 MB, for example a large `data:` URI in `audio`. |

## Common mistakes

| Mistake | What happens | Fix |
|---|---|---|
| Sending `"speak": false` to turn speech off. | It is treated as no `speak` field. | Omit the field. |
| Sending a `data:` URI for audio over about 1 MB. | The request is rejected. | Use a file path or an `https` URL. |
| Writing a voice name with a space, such as `af heart`. | `400 invalid voice`. | Use the model id, `af_heart`. |
| Expecting speech during quiet hours. | It is held back and logged. | See [Quiet hours](quiet-hours.md). |
| Sending `presentation: "voice"` and expecting a banner as well. | There is no banner. | Use `both`. |

## Related

- [Make Herald speak](../VOICE.md): choose an engine, install Kokoro and send a spoken notification.
- [Quiet hours](quiet-hours.md): silence speech on a schedule.
- [Notifications API](api/notifications.md): sending a notification with speech, and speech alone.
- [Settings API](api/settings.md) and [Setup API](api/setup.md): voice settings and the Kokoro installer.
- [How banners behave](banners.md): what the replay control sits beside.
