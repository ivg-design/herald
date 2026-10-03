# Voice: spoken notifications and voice messages

Herald can say a notification aloud or play a recorded voice message. The text always lands in History, so the
log stays searchable. **Everything is local**: speech is synthesised on this Mac by Kokoro (a Python process) or by
the system voice; no text or audio leaves the Mac. The one network use is the optional, user-started Kokoro
download. The task-oriented guide is [../VOICE.md](../VOICE.md); this page is the field reference. Silencing
speech on a schedule is [quiet-hours.md](quiet-hours.md).

## Payload fields

Three optional fields on `POST /v1/notify` (and `herald notify`, MCP `send_notification`):

```json
{"app":"build","title":"Build finished","body":"All 214 tests passed",
 "speak":true,"audio":"/path/to/message.wav","presentation":"both"}
```

| Field | Type | Meaning |
|---|---|---|
| `speak` | `true` or object | `true` says the title, then the body. An object `{text?, voice?, speed?, lang?}` customises it. `false` is the same as leaving it out. A bare string is read as `text`. |
| `audio` | string | A voice message: file path, https URL or `data:` URI of a WAV, MP3, M4A, AIFF or CAF, at most 20 MB. The kind is checked from the bytes, never the name; anything else is ignored. Cached under `history/audio/`. With both `speak` and `audio`, the speech plays first. |
| `presentation` | string | `banner` (default), `voice` (spoken only: no banner, no chime; the History entry is kept, marked read) or `both`. `voice` and `both` without `speak` or `audio` speak the title and body. |

### `speak` object

| Property | Type | Default | Rules |
|---|---|---|---|
| `text` | string | title then body | At most **2000 characters** (the rest is dropped). Markdown links are read as their label; whitespace is squeezed. When built from title and body, each part gets a full stop if it lacks `.`, `!` or `?`. |
| `voice` | string | the app's voice, else the engine default (`af_heart`) | A model id: ASCII letters, digits, `_`, `-`, `.`, at most 64 characters. Kokoro: `af_heart`, `af_bella`, `af_nicole`, `am_michael`, `bf_emma`, `bm_george`, and the rest the model reports. |
| `speed` | number | 1.0 | 0.5 to 2.0 (400 otherwise). |
| `lang` | string | engine default | Letters, `-`, `_`, at most 16 characters, e.g. `en-us`, `en-gb`. |

Invalid values are rejected with `400` before the notification is accepted (`invalid voice`, `invalid lang`,
`speed must be between 0.5 and 2.0`).

## `POST /v1/speak`

A shortcut for a notification with presentation `voice`:

```json
{"app":"build","text":"Deploy finished","voice":"af_bella","speed":1.1,"lang":"en-us","id":"deploy-1"}
```

Reply `{"ok":true,"id":"..."}`. `400` for a missing `app` or `text`, or an invalid voice, language or speed. The
history title is a short form of the text (80 characters).

## Engines (Settings > Voice)

| Engine | Notes |
|---|---|
| Kokoro (local, natural) | Optional download (about 340 MB) or reuse of `~/.claude/tts`. A worker process loads the model on the first request (a few seconds), then stays running; it restarts on the next request if it dies. |
| System voice | AVSpeechSynthesizer. Works at once, the default. Speaks directly, so there is no WAV to replay (a replay re-speaks the text). |
| Off | Nothing is spoken or played. |

Per app, "Speak per app" holds a Speak switch and an optional voice; an app with Speak off is never spoken.

## Behaviour

- A voice-only notification is never lost: if Herald is muted, the app's Speak switch is off, the engine is Off or
  the audio cannot be read, it is shown as a normal banner instead.
- Playback never overlaps: speech queues in arrival order, at most 20 waiting (older ones are dropped). Dismiss
  interrupts that notification's speech; Dismiss All and the global mute stop everything. Mute silences speech
  like chimes; explicit replays and the Test button ignore it.
- Banners with speech carry a replay control beside the timestamp (or in a thin row under the grid when the
  template has no timestamp). Replay uses the cached WAV, or re-synthesises if the file was pruned (the newest 300
  audio files are kept).
- Quiet hours hold speech back and record `speech.suppressed: "quiet-hours"`.

## History record

```json
"speech":{"text":"All 214 tests passed.","voice":"af_heart","audioPath":"/.../history/audio/....wav",
          "durationSeconds":2.4,"suppressed":null}
```

`audioPath` and `durationSeconds` are absent for the system voice or when synthesis failed.

## Surfaces

| Surface | How |
|---|---|
| HTTP | `speak`, `audio`, `presentation` on `/v1/notify`; `/v1/speak`; [api.md](api.md) |
| CLI | `herald notify --speak`, `--speak-text`, `--voice`, `--speed`, `--lang`, `--audio`, `--presentation`; `herald speak --app --text` ([cli.md](cli.md)) |
| MCP | `speak` tool; `speak`, `audio`, `presentation` on `send_notification` ([mcp-tools.md](mcp-tools.md)) |
| Swift | `HeraldClient.shared.speak(HeraldSpeakRequest(app:text:))`; `n.speak = HeraldSpeak()`; `n.presentation = .both` |

## Privacy and security

The worker is a child process talking over stdin/stdout; the text reaches it as a JSON string, never interpolated
into a shell command. Voice, language and speed are validated first. Audio is accepted only when its bytes are a
known audio format, at most 20 MB. Spoken text is stored in History like any other notification text.

## Developing against a second instance

`HERALD_PORT` and `HERALD_SUPPORT_DIR` start a build beside the installed Herald with its own port, token,
history and (for voice) preferences. `HERALD_TTS_WORKER` points a bare executable at a `tts_worker.py`.

## Common mistakes

| Mistake | What happens | Fix |
|---|---|---|
| `"speak": false` expecting it to disable a template default | Treated as no speech. | Omit it. |
| A `data:` URI audio over ~1 MB | Rejected by the 1 MB request limit. | Use a path or URL. |
| Voice name with a space | `400 invalid voice`. | Use the model id. |
| Expecting speech during quiet hours | Held back and logged. | See [quiet-hours.md](quiet-hours.md). |
