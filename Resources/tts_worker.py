#!/usr/bin/env python3
"""Herald TTS worker: keeps Kokoro loaded and answers one JSON request per line on stdin.

  python tts_worker.py <kokoro-v1.0.onnx> <voices-v1.0.bin>

Requests  : {"text": "...", "voice": "af_heart", "speed": 1.0, "lang": "en-us", "out": "/abs/path.wav"}
            {"cmd": "voices"}
Responses : {"ok": true, "out": "/abs/path.wav", "duration": 2.4}
            {"ok": true, "voices": ["af_heart", ...]}
            {"ok": false, "error": "..."}
The text is data only: it is never passed to a shell. stdout carries the protocol and nothing else
(library chatter is redirected to stderr).
"""
import json
import os
import sys

# Keep the protocol channel clean: anything a library prints goes to stderr.
_proto = os.fdopen(os.dup(sys.stdout.fileno()), "w", buffering=1, encoding="utf-8")
sys.stdout = sys.stderr

_kokoro = None


def reply(obj):
    _proto.write(json.dumps(obj, ensure_ascii=False) + "\n")
    _proto.flush()


def load(model, voices):
    global _kokoro
    if _kokoro is None:
        from kokoro_onnx import Kokoro
        _kokoro = Kokoro(model, voices)
    return _kokoro


def handle(req, model, voices):
    k = load(model, voices)
    if req.get("cmd") == "voices":
        return {"ok": True, "voices": sorted(k.get_voices())}
    text = req.get("text")
    out = req.get("out")
    if not isinstance(text, str) or not text.strip():
        return {"ok": False, "error": "text is required"}
    if not isinstance(out, str) or not os.path.isabs(out):
        return {"ok": False, "error": "out must be an absolute path"}
    voice = req.get("voice") or "af_heart"
    speed = min(2.0, max(0.5, float(req.get("speed") or 1.0)))
    lang = req.get("lang") or "en-us"
    import soundfile as sf
    samples, rate = k.create(text, voice=voice, speed=speed, lang=lang)
    sf.write(out, samples, rate)
    return {"ok": True, "out": out, "duration": round(len(samples) / float(rate), 3)}


def main():
    if len(sys.argv) < 3:
        reply({"ok": False, "error": "usage: tts_worker.py <model> <voices>"})
        return 2
    model, voices = sys.argv[1], sys.argv[2]
    for line in sys.stdin:
        line = line.strip()
        if not line:
            continue
        try:
            reply(handle(json.loads(line), model, voices))
        except Exception as e:  # keep the worker alive; report the failure to the caller
            reply({"ok": False, "error": "%s: %s" % (type(e).__name__, e)})
    return 0


if __name__ == "__main__":
    sys.exit(main())
