# VoiceForge

VoiceForge is a native macOS SwiftUI app that wraps `mlx-speech` for Fish Audio S2 Pro voice cloning with prompt formatting, inline emotion tags, history, presets, and WAV playback.

## Requirements

- macOS 14 or newer
- Xcode 26 or newer
- `mlx-speech` installed and available in your shell path

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
