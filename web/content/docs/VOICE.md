# Herald voice: spoken notifications and voice messages

Herald can say a notification aloud, or play a recorded voice message. The text always lands in history, so the
log stays searchable. **Everything is local**: speech is synthesized on this Mac by a Python process (Kokoro) or
by the system voice; no text or audio is ever sent anywhere. The only network use is the optional, one-time
Kokoro download from GitHub, which you start yourself.

## Setup (Settings > Voice)

Pick an engine:

| Engine | What it is |
| --- | --- |
| **Kokoro (local, natural)** | A neural voice. Optional download; see below. |
| **System voice** | The built-in macOS voices (AVSpeechSynthesizer). Works at once; speaks directly, so there is no WAV to replay (a replay re-speaks the text). This is the default. |
| **Off** | Nothing is spoken or played. |

Kokoro, either way:

1. **Use existing installation at ~/.claude/tts**: shown when that folder holds `kokoro-v1.0.onnx`,
   `voices-v1.0.bin` and a `venv`. Herald symlinks them into `~/Library/Application Support/Herald/tts/`;
   nothing is copied or changed in the source.
2. **Download Kokoro (about 340 MB)**: fetches `kokoro-v1.0.onnx` and `voices-v1.0.bin` from the kokoro-onnx GitHub
   release (resumable; a cancelled download continues from the bytes already on disk), prints their SHA-256, then
   builds the Python environment: `uv venv --python 3.12 tts/venv && uv pip install kokoro-onnx soundfile`, or
   `python3 -m venv` plus pip when uv is not installed.

Then choose a default voice (af_heart, af_bella, af_nicole, am_michael, bf_emma, bm_george, and the rest the
model reports), the speed (0.5 to 2.0), and press **Speak** to test (a test plays even when Herald is muted).
"Speak per app" holds a Speak switch and an optional voice for each app; an app with Speak off is never spoken.

The first Kokoro request loads the model (a few seconds); the worker then stays running and later requests take
well under a second. If the worker dies it is restarted on the next request.

## API

`POST /v1/notify` gains three optional fields:

```json
{"app":"build","title":"Build finished","body":"All 214 tests passed",
 "speak": true,
 "audio": "/path/to/message.wav",
 "presentation": "banner"}
```

* `speak`: `true` says the title, then the body. Or an object `{"text":"...","voice":"af_heart","speed":1.1,"lang":"en-us"}`
  (all optional; `text` defaults to title then body). `false` is the same as leaving it out. Text is capped at
  2,000 characters, markdown links are read as their label.
* `audio`: a WAV, MP3, M4A, AIFF or CAF voice message as a file path, an https URL or a `data:` URI. At most 20 MB
  (a `data:` URI is also bound by the 1 MB request limit, so use a path or URL for larger files). The kind is
  checked from the file's bytes, never its name; anything else is ignored. It is cached under
  `history/audio/`. With both `speak` and `audio`, the speech plays first.
* `presentation`: `banner` (default), `voice` (spoken only: no banner, no chime; the history entry is kept and
  marked read), `both`. `voice` and `both` without `speak` or `audio` speak the title and body.

`POST /v1/speak` `{"app":"build","text":"Deploy finished","voice":"af_bella","speed":1.1,"lang":"en-us","id":"..."}`
is a shortcut for presentation `voice`; reply `{"ok":true,"id":"..."}`. Errors: 400 for a missing app or text, a bad
voice name (letters, digits, `_ - .`), a bad language, or a speed outside 0.5 to 2.0.

A voice-only notification is never lost: if Herald is muted, the app's Speak switch is off, the engine is Off, or
the audio could not be read, it is shown as a normal banner instead.

Playback never overlaps: notifications queue in arrival order (at most 20 waiting; older ones are dropped).
Dismiss interrupts that notification's speech, Dismiss All and the global mute stop everything. Mute silences
speech like it silences chimes; explicit replays and the Test button ignore it.

History items carry `speech: {text, voice, audioPath, durationSeconds}` (`audioPath` and `durationSeconds` are
absent for the system voice). The History window shows a speaker button and the spoken text under such an entry;
the button replays the cached WAV, or re-synthesizes the text if the file was pruned (Herald keeps the newest 300
audio files).

## Quiet hours (Settings > Voice > Quiet hours)

Windows `{days, start, end}` in local time (`days` empty = every day; a window belongs to the day it starts, so
Fri 22:30 to 07:30 runs into Saturday morning; an end not after the start means the next morning). Each window
silences **Speech** (default), **Sounds** and/or **Banners**. A silenced banner has no panel: it goes to History
(unread) and the "+N more" pill. Held-back speech is not synthesized; history shows `speech.suppressed: "quiet-hours"`
with the text. "Speak queued messages when it ends" plays one summary ("3 messages while you were away: ...").
`priority: "urgent"` bypasses quiet hours only for apps whose "Urgent can break quiet hours" is on (off by default).
A voice-only notification held back this way is shown as a banner instead (unless banners are silenced too).

The menu shows "Quiet until 07:30" with "Resume Now" while quiet (Resume ends the current occurrence only), or
"Quiet for 1 Hour" otherwise.

* `GET /v1/settings/quiet-hours` returns `{windows, adHoc, status:{active, speech, sounds, banners, until, source}}`.
* `PUT /v1/settings/quiet-hours` takes any of `{"windows":[...]}` (replaces the schedule),
  `{"resume":true}`, `{"adHoc":{"until":"07:30" | ISO date, "minutes":60, "speech":true,"sounds":true,"banners":false}}`.
* CLI: `herald quiet --until 07:30`, `herald quiet --for 60 [--banners]`, `herald quiet off`, `herald quiet status`.
* MCP: `get_quiet_hours`, `set_quiet_hours {windows?, until?, minutes?, banners?, resume?}`.

## CLI

```
herald notify --app build --title "Build finished" --speak
herald notify --app build --title "Build finished" --speak-text "All tests passed" --voice af_bella --speed 1.1 --lang en-us
herald notify --app build --title "Voice note" --audio ~/note.wav --presentation voice
herald speak  --app build --text "Deploy finished" [--voice NAME] [--speed N] [--lang L] [--id ID]
```

`--speak` (alone), `--speak-text`, `--voice`, `--speed`, `--lang`, `--audio`, `--presentation banner|voice|both`.

## MCP

`herald-mcp` has a `speak` tool `{app, text, voice?, speed?, lang?, id?}` and `speak`, `audio`, `presentation`
fields on `send_notification`. See [MCP.md](MCP.md).

## Swift client

```swift
try await HeraldClient.shared.speak(HeraldSpeakRequest(app: "build", text: "Deploy finished"))
var n = HeraldNotification(app: "build", title: "Build finished")
n.speak = HeraldSpeak()            // title, then body
n.presentation = .both
```

## Privacy and security

* Synthesis and playback are local. The worker is a child process of Herald talking over stdin/stdout.
* The text reaches the worker as a JSON string on stdin: nothing is interpolated into a shell command.
* Voice, language and speed are validated before they reach the worker.
* Audio files are accepted only when their bytes are a known audio format, at most 20 MB.
* Spoken text is stored in history like any other notification text.

## Developing against a second instance

`HERALD_PORT` and `HERALD_SUPPORT_DIR` start a build beside the installed Herald with its own port, token, history
and (for voice) its own preferences suite. `HERALD_TTS_WORKER` points a bare executable at a `tts_worker.py`.
