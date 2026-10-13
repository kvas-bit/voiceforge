#!/usr/bin/env python3
"""JSON-lines TTS helper for mlx-speech and Drama 3."""
import contextlib
import gc
import io
import json
import sys
from pathlib import Path


def log_event(event, req_id, **fields):
    sys.stdout.write("EVENT:" + json.dumps({"event": event, "id": req_id, **fields}, ensure_ascii=False) + "\n")
    sys.stdout.flush()


def load_model(model_name, req_id):
    global model, write_wav, loaded_model
    if loaded_model == model_name:
        return
    if loaded_model is not None:
        del model
        model = None
        loaded_model = None
        write_wav = None
        gc.collect()
        try:
            import mlx.core as mx
            mx.clear_cache()
        except Exception:
            pass
    log_event("loading_model", req_id, model=model_name)
    saved = sys.stdout
    try:
        with contextlib.redirect_stdout(io.StringIO()):
            if model_name == "drama-3":
                from drama3_mlx.server_adapter import load_model as drama_load
                model = drama_load()
                write_wav = None
            else:
                from mlx_speech.tts import load
                from mlx_speech.audio import write_wav as mlx_write_wav
                model = load(model_name)
                write_wav = mlx_write_wav
        loaded_model = model_name
    except Exception as exc:
        sys.stdout = saved
        raise RuntimeError(f"Could not load {model_name}: {exc}") from exc
    sys.stdout = saved
    fields = {}
    if model_name == "drama-3":
        try:
            from drama3_mlx.server_adapter import resolve_model_dir
            fields["checkpoint"] = str(resolve_model_dir())
        except Exception:
            pass
    log_event("ready", req_id, model=model_name, **fields)


model = None
write_wav = None
loaded_model = None


def main():
    for line in sys.stdin:
        try:
            req = json.loads(line)
        except (json.JSONDecodeError, TypeError):
            log_event("error", "unknown", message="Invalid JSON request")
            continue
        action, req_id = req.get("action"), req.get("id", "unknown")
        model_name = req.get("model", "fish-s2-pro")
        if action == "start":
            log_event("starting", req_id)
            try:
                load_model(model_name, req_id)
            except Exception as exc:
                log_event("error", req_id, message=str(exc))
                continue
            continue
        if model_name == "drama-3" and action in {"generate", "generate_scene", "transcribe", "inspect_reference"}:
            try:
                load_model(model_name, req_id)
                from drama3_mlx.server_adapter import handle
                handle(req, lambda event: log_event(event.pop("event"), event.pop("id", req_id), **event))
            except Exception as exc:
                log_event("error", req_id, message=str(exc))
            continue
        if action != "generate":
            log_event("error", req_id, message="Unknown action")
            continue
        text, ref_audio, ref_text, output = (req.get(key, "") for key in ("text", "ref_audio", "ref_text", "output"))
        if not all((text, ref_audio, ref_text, output)):
            log_event("error", req_id, message="Missing required fields")
            continue
        try:
            load_model(model_name, req_id)
        except Exception as exc:
            log_event("error", req_id, message=str(exc))
            continue
        log_event("accepted", req_id)
        try:
            log_event("generating", req_id)
            with contextlib.redirect_stdout(io.StringIO()):
                if model_name == "drama-3":
                    kwargs = {"ref_audio": ref_audio, "ref_text": ref_text}
                    if req.get("max_new_tokens") is not None:
                        kwargs["max_new_tokens"] = req["max_new_tokens"]
                    waveform, sample_rate = model.generate(text, **kwargs)
                else:
                    kwargs = dict(text=text, reference_audio=ref_audio, reference_text=ref_text)
                    if req.get("max_new_tokens") is not None:
                        kwargs["max_new_tokens"] = req["max_new_tokens"]
                    result = model.generate(**kwargs)
            log_event("writing", req_id)
            if model_name == "drama-3":
                import soundfile as sf
                sf.write(output, waveform, sample_rate, subtype="PCM_16")
            else:
                write_wav(Path(output), result.waveform, sample_rate=result.sample_rate)
            log_event("done", req_id, output=output)
        except Exception as exc:
            log_event("error", req_id, message=str(exc))


if __name__ == "__main__":
    main()
