#!/usr/bin/env python3
"""Persistent Fish S2 Pro generation server (JSON-lines protocol).

Reads JSON requests from stdin, writes EVENT-prefixed JSON responses to stdout.
Loads the model once and reuses it for all requests.

Protocol (stdout):
  EVENT:{"event":"starting","id":"..."}
  EVENT:{"event":"loading_model","id":"..."}
  EVENT:{"event":"ready","id":"..."}
  EVENT:{"event":"generating","id":"..."}
  EVENT:{"event":"writing","id":"..."}
  EVENT:{"event":"done","id":"...","output":"/path/to.wav"}
  EVENT:{"event":"error","id":"...","message":"..."}

Protocol (stdin):
  {"action":"start","id":"..."}
  {"action":"generate","id":"...","text":"...","ref_audio":"...","ref_text":"...","output":"..."}

Depends on mlx-speech >= 0.4.0.
"""

import json
import sys
import io
from pathlib import Path


def log_event(event_type, req_id, **kwargs):
    """Emit a single EVENT line to stdout and flush immediately."""
    payload = {"event": event_type, "id": req_id}
    payload.update(kwargs)
    sys.stdout.write("EVENT:" + json.dumps(payload, ensure_ascii=False) + "\n")
    sys.stdout.flush()


def main():
    for line in sys.stdin:
        line = line.strip()
        if not line:
            continue
        try:
            req = json.loads(line)
        except json.JSONDecodeError:
            log_event("error", "unknown", message="Invalid JSON request")
            continue

        action = req.get("action", "")
        req_id = req.get("id", "unknown")

        if action == "start":
            # Explicit startup handshake — emit lifecycle events and signal ready.
            log_event("starting", req_id)

            # Redirect library stdout while loading so noise doesn't corrupt protocol.
            saved_stdout = sys.stdout
            sys.stdout = io.StringIO()
            try:
                from mlx_speech.tts import load
                from mlx_speech.audio import write_wav
            except ImportError as e:
                sys.stdout = saved_stdout
                log_event("error", req_id, message=f"import failed: {e}")
                sys.exit(1)
            sys.stdout = saved_stdout

            log_event("loading_model", req_id)
            try:
                model = load("fish-s2-pro")
            except Exception as e:
                log_event("error", req_id, message=f"Model load failed: {e}")
                sys.exit(1)
            log_event("ready", req_id)
            continue

        if action == "generate":
            text = req.get("text", "")
            ref_audio = req.get("ref_audio", "")
            ref_text = req.get("ref_text", "")
            output = req.get("output", "")

            if not text or not ref_audio or not ref_text or not output:
                log_event("error", req_id, message="Missing required fields")
                continue

            # Acknowledge immediately so the caller knows the request was accepted.
            log_event("accepted", req_id)

            try:
                log_event("generating", req_id)
                kwargs = dict(text=text, reference_audio=ref_audio,
                              reference_text=ref_text)
                if req.get("max_new_tokens") is not None:
                    kwargs["max_new_tokens"] = req["max_new_tokens"]
                result = model.generate(**kwargs)
                log_event("writing", req_id)
                write_wav(Path(output), result.waveform,
                          sample_rate=result.sample_rate)
                log_event("done", req_id, output=output)
            except Exception as e:
                log_event("error", req_id, message=str(e))


if __name__ == "__main__":
    main()
