import importlib.util
import io
import json
import os
import sys
import tempfile
import types
import unittest
from contextlib import redirect_stdout
from unittest.mock import patch
from pathlib import Path


HELPER = Path(__file__).parents[2] / "Sources/VoiceForge/Resources/mlx_persistent_server.py"


class FakeDrama3:
    def generate(self, text, **kwargs):
        import numpy as np
        return np.zeros(32, dtype=np.float32), 44100


class FakeS2:
    def generate(self, **kwargs):
        return types.SimpleNamespace(waveform=b"wave", sample_rate=44100)


class PersistentServerTests(unittest.TestCase):
    def test_protocol_switches_cached_models(self):
        spec = importlib.util.spec_from_file_location("vf_helper", HELPER)
        server = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(server)
        original_stdin = sys.stdin
        loads = []
        drama_loads = 0
        adapter = types.ModuleType("drama3_mlx.server_adapter")
        def load_drama():
            nonlocal drama_loads
            drama_loads += 1
            loads.append("drama-3")
            return FakeDrama3()
        adapter.load_model = load_drama
        def handle(req, emit):
            action = req["action"]
            emit({"event": "accepted", "id": req["id"]})
            if action == "generate_scene":
                emit({"event": "progress", "id": req["id"], "done": 1, "total": 1})
                Path(req["output"]).write_bytes(b"wav")
                emit({"event": "done", "id": req["id"], "output": req["output"], "line_outputs": req["line_outputs"], "line_times": [[0, .1]]})
            elif action == "generate":
                Path(req["output"]).write_bytes(b"wav")
                emit({"event": "done", "id": req["id"], "output": req["output"], "codes": req.get("save_codes")})
            elif action == "transcribe":
                emit({"event": "done", "id": req["id"], "text": "hello", "language": "en"})
            else:
                emit({"event": "done", "id": req["id"], "warnings": ["clipping"]})
        adapter.handle = handle
        tts = types.ModuleType("mlx_speech.tts")
        tts.load = lambda name: (loads.append(name) or FakeS2())
        audio = types.ModuleType("mlx_speech.audio")
        audio.write_wav = lambda path, waveform, sample_rate: Path(path).write_bytes(b"wav")
        soundfile = types.ModuleType("soundfile")
        soundfile.write = lambda path, waveform, sample_rate, subtype: Path(path).write_bytes(b"wav")
        sys.modules["drama3_mlx.server_adapter"] = adapter
        sys.modules["drama3_mlx"] = types.ModuleType("drama3_mlx")
        sys.modules["mlx_speech.tts"] = tts
        sys.modules["mlx_speech.audio"] = audio
        sys.modules["soundfile"] = soundfile
        prior_modules = {key: sys.modules.get(key) for key in ("drama3_mlx", "drama3_mlx.server_adapter", "mlx_speech", "mlx_speech.tts", "mlx_speech.audio", "soundfile")}
        sys.modules["mlx_speech"] = types.ModuleType("mlx_speech")
        try:
            with tempfile.TemporaryDirectory() as directory:
                out = Path(directory) / "out.wav"
                requests = [
                    {"action": "start", "id": "start", "model": "drama-3", "load_model": False},
                    {"action": "generate", "id": "a", "text": "hi", "ref_audio": "ref.wav", "ref_text": "hi", "output": str(out), "model": "drama-3"},
                    {"action": "generate", "id": "b", "text": "hi", "ref_audio": "ref.wav", "ref_text": "hi", "output": str(out), "model": "fish-s2-pro"},
                    {"action": "generate_scene", "id": "c", "output": str(out), "line_outputs": [str(Path(directory) / "line.wav")], "model": "drama-3", "speakers": [], "lines": []},
                    {"action": "generate", "id": "e", "text": "hi", "ref_audio": "ref.wav", "ref_text": "hi", "output": str(out), "model": "fish-s2-pro"},
                    {"action": "transcribe", "id": "d", "audio": "ref.wav", "model": "drama-3"},
                    {"action": "inspect_reference", "id": "f", "audio": "ref.wav", "text": "typed", "model": "drama-3"},
                ]
                server.model = server.write_wav = server.loaded_model = None
                server.sys.stdin = io.StringIO("\n".join(json.dumps(x) for x in requests))
                capture = io.StringIO()
                with patch.dict(os.environ, {"DRAMA3_FAKE": "1"}), redirect_stdout(capture):
                    server.main()
                events = [json.loads(line[6:]) for line in capture.getvalue().splitlines() if line.startswith("EVENT:")]
                loads_by_event = [event["model"] for event in events if event["event"] == "loading_model"]
                self.assertEqual(loads[0], "drama-3")
                self.assertEqual(loads[-1], "fish-s2-pro")
                self.assertIn("drama-3", loads)
                self.assertIn("fish-s2-pro", loads)
                self.assertEqual(loads_by_event, loads)
                self.assertFalse(any(event["event"] == "loading_model" and event["id"] in {"d", "f"} for event in events),
                                 "transcribe/inspect must not load or evict the TTS model")
                self.assertFalse(any(event["event"] == "loading_model" and event["id"] == "start" for event in events),
                                 "diagnostic prewarm must start the helper without loading TTS")
                self.assertEqual(server.loaded_model, "fish-s2-pro")
                self.assertTrue(any(event["event"] == "progress" and event["id"] == "c" for event in events), events)
                self.assertTrue(any(event["event"] == "done" and event.get("text") == "hello" for event in events), events)
                self.assertTrue(out.is_file())
        finally:
            sys.stdin = original_stdin
            for key, value in prior_modules.items():
                if value is None:
                    sys.modules.pop(key, None)
                else:
                    sys.modules[key] = value


if __name__ == "__main__":
    unittest.main()
