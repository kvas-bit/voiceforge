# VoiceForge

VoiceForge is a native macOS SwiftUI app that wraps `mlx-speech` for Fish Audio S2 Pro voice cloning with prompt formatting, inline emotion tags, history, presets, and WAV playback.

## Requirements

- macOS 14 or newer
- Xcode 26 or newer
- `mlx-speech` installed and available in your shell path

## First-time setup

The default model (`fish-s2-pro`) is downloaded automatically from Hugging Face the first time you generate speech. No manual download is needed — just run the app and start generating.

If you want to download the model ahead of time, run:

```bash
mlx-speech tts --model fish-s2-pro --text "Hello" -o /tmp/test.wav
```

To see all available models:

```bash
mlx-speech tts --list-models
```

VoiceForge supports these models out of the box:
- `fish-s2-pro` (default)
- `moss-tts`
- `step-audio-tts`
- `kokoro-multilingual`

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
