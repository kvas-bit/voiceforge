# VoiceForge

VoiceForge is a native macOS SwiftUI app for Fish Audio Drama 3 voice cloning, with Fish Audio S2 Pro still selectable in Settings. It includes prompt formatting, inline direction tags, history, presets, and WAV playback.

## Requirements

- macOS 14 or newer
- Xcode 26 or newer
- `mlx-speech` installed and available in your shell path

## First-time setup

Drama 3 is the default. It uses the MLX checkpoint selected by the orchestrator at `~/Library/Application Support/VoiceForge/models/drama-3`, or by `VOICEFORGE_DRAMA3_MODEL_DIR`. Install the Drama 3 package into mlx-speech's Python environment:

```bash
pipx inject mlx-speech -e ~/Projects/drama3
pipx runpip mlx-speech install -U 'mlx>=0.32.3' 'mlx-lm>=0.32'
```

Fish S2 Pro remains selectable in Settings and continues to load through mlx-speech. To download/warm it ahead of time:

```bash
mlx-speech tts --model fish-s2-pro --text "Hello there." -o /tmp/test.wav
```

To see all available models:

```bash
mlx-speech tts --list-models
```

VoiceForge supports `drama-3` (default) and `fish-s2-pro`.

You can switch models in the app's settings.

## Build

```bash
swift build
```

## Test

```bash
swift test
```

## Output

Generated speech always writes to:

```text
~/voiceforge/voiceforge_output.wav
```

Use the app's `Save Output` button to export a copy elsewhere.
