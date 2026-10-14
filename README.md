# VoiceForge

VoiceForge is a native macOS SwiftUI app for Fish Audio Drama 3 voice cloning, with Fish Audio S2 Pro still selectable in Settings. It includes prompt formatting, inline direction tags, multi-speaker scenes, takes and revisions, history, presets, and WAV playback.

## Requirements

- macOS 14 or newer, Apple Silicon (Drama 3 Standard peaks around 31 GB of memory; 48 GB recommended)
- Xcode 26 or newer
- `mlx-speech` installed and available in your shell path

## First-time setup

Drama 3 is the default model. It runs from the MLX port in `~/Projects/drama3`, installed into mlx-speech's Python environment:

```bash
pipx inject mlx-speech -e ~/Projects/drama3
pipx inject mlx-speech mlx-whisper          # auto-transcribe and reference checks
pipx runpip mlx-speech install -U 'mlx>=0.32.3' 'mlx-lm>=0.32'
```

Checkpoints are linked into `~/Library/Application Support/VoiceForge/models/`:

| Folder | Settings > Model > Drama 3 quality | Peak memory |
|---|---|---:|
| `drama-3-q4` → `~/Projects/drama3/models/q4` | Standard (default) | ~31 GB |
| `drama-3-q5` → `~/Projects/drama3/models/q5` | High fidelity | ~36 GB |
| `drama-3` → `drama-3-q4` | fallback | |

`VOICEFORGE_DRAMA3_MODEL_DIR` overrides the folder. Fish S2 Pro stays selectable in Settings and loads through mlx-speech (`mlx-speech tts --model fish-s2-pro --text "Hello there." -o /tmp/test.wav` downloads and warms it).

## Using Drama 3

- **Directions:** point tags such as `[laughs]` or `[sighs]`, scoped tags such as `<whisper>…</whisper>` (select words and use the tag buttons), and free-form style prefixes such as `[voice cracking, trying not to cry]`. Text is sent verbatim; repeated tags are kept.
- **Voices:** one or more reference clips per voice, each with an exact transcript. Type it yourself or use Auto-transcribe; VoiceForge flags transcripts that differ from what Whisper hears.
- **Takes and revisions:** generate up to four takes and pick one, or revise a take with its earlier audio as context.
- **Scenes:** in Conversations, cast each speaker once and render the whole script with continuity between lines; per-line clips are kept.
- **Reliability:** if a take stalls in silence, the engine retries automatically and the status shows "Retrying take".
- **Sampling:** temperature / top-p / top-k default to the Fish cloud values (0.7 / 0.7 / 30), with an Expressive preset (1.0 / 0.9 / 30).

## Build

```bash
swift build
```

## Test

```bash
swift test
DRAMA3_FAKE=1 ~/.local/pipx/venvs/mlx-speech/bin/python -m unittest discover -s Tests/python
xcodebuild test -project VoiceForge.xcodeproj -scheme VoiceForge -destination 'platform=macOS,arch=arm64' \
  -only-testing:VoiceForgeUITests -parallel-testing-enabled NO
```

Two UI tests render with the real Drama 3 model and are skipped unless enabled. They read reference clips from `~/Projects/drama3/eval/refs` (`kayden.wav`, `kayden.txt`, `en0.wav`; override with `VOICEFORGE_REAL_MODEL_REFS`):

```bash
VOICEFORGE_REAL_MODEL_UITEST=1 TEST_RUNNER_VOICEFORGE_REAL_MODEL_UITEST=1 \
TEST_RUNNER_VOICEFORGE_REAL_KAYDEN_TEXT="$(cat ~/Projects/drama3/eval/refs/kayden.txt)" \
xcodebuild test -project VoiceForge.xcodeproj -scheme VoiceForge -destination 'platform=macOS,arch=arm64' \
  -only-testing:VoiceForgeUITests/VoiceForgeUITests/testRealDrama3SingleGeneration \
  -only-testing:VoiceForgeUITests/VoiceForgeUITests/testRealDrama3ConversationSceneGeneration \
  -parallel-testing-enabled NO
```

## Output

Renders are written to `~/Library/Application Support/VoiceForge/outputs/` (scenes in a `scene-<id>/` folder with `scene.wav` and per-line clips). Use the app's Save Output button to export a copy elsewhere.
