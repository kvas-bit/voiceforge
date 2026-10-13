# The Prophet — VoiceForge

**Matrix name:** The Prophet | Speaks truth through voice  
**Stack:** Swift Package / macOS SwiftUI + mlx-speech  
**Owner:** Kavi Vasudeo

## What it does
Native macOS app using Fish Audio Drama 3 by default, with Fish Audio S2 Pro selectable. Features prompt formatting, inline direction tags, history, presets, and WAV playback.

## Requirements
- macOS 14+
- Xcode 26+
- `mlx-speech` installed and in shell PATH; Drama 3 package injected into its Python environment

## Build
```bash
swift build
swift test
```

## Key paths
- `Sources/` — SwiftUI app source
- `docs/` — documentation

## Rules
- `mlx-speech` must be available in PATH at runtime. Install Drama 3 with `pipx inject mlx-speech -e ~/Projects/drama3` and select its checkpoint using `VOICEFORGE_DRAMA3_MODEL_DIR` or `~/Library/Application Support/VoiceForge/models/drama-3`.
- SwiftUI only, no AppKit fallback
- WAV output — do not change audio format without updating the whole pipeline
