import importlib.util
import io
import json
import sys
import tempfile
import types
import unittest
from contextlib import redirect_stdout
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
        adapter = types.ModuleType("drama3_mlx.server_adapter")
        adapter.load_model = lambda: (loads.append("drama-3") or FakeDrama3())
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
                    {"action": "start", "id": "start", "model": "drama-3"},
                    {"action": "generate", "id": "a", "text": "hi", "ref_audio": "ref.wav", "ref_text": "hi", "output": str(out), "model": "drama-3"},
                    {"action": "generate", "id": "b", "text": "hi", "ref_audio": "ref.wav", "ref_text": "hi", "output": str(out), "model": "fish-s2-pro"},
                    {"action": "generate", "id": "c", "text": "hi", "ref_audio": "ref.wav", "ref_text": "hi", "output": str(out), "model": "drama-3"},
                ]
                server.model = server.write_wav = server.loaded_model = None
                server.sys.stdin = io.StringIO("\n".join(json.dumps(x) for x in requests))
                capture = io.StringIO()
                with redirect_stdout(capture):
                    server.main()
                events = [json.loads(line[6:]) for line in capture.getvalue().splitlines() if line.startswith("EVENT:")]
                loads_by_event = [event["model"] for event in events if event["event"] == "loading_model"]
                self.assertEqual(loads, ["drama-3", "fish-s2-pro", "drama-3"])
                self.assertEqual(loads_by_event, loads)
                self.assertTrue(any(event["event"] == "done" and event["id"] == "c" for event in events), events)
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
