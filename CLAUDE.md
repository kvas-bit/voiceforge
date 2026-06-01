# The Prophet — VoiceForge

**Matrix name:** The Prophet | Speaks truth through voice  
**Stack:** Swift Package / macOS SwiftUI + mlx-speech  
**Owner:** Kavi Vasudeo

## What it does
Native macOS app wrapping mlx-speech for Fish Audio S2 Pro voice cloning. Features prompt formatting, inline emotion tags, history, presets, and WAV playback.

## Requirements
- macOS 14+
- Xcode 26+
- `mlx-speech` installed and in shell PATH

## Build
```bash
swift build
swift test
```

## Key paths
- `Sources/` — SwiftUI app source
- `docs/` — documentation

## Rules
- `mlx-speech` must be available in PATH at runtime — check before debugging audio issues
- SwiftUI only, no AppKit fallback
- WAV output — do not change audio format without updating the whole pipeline
