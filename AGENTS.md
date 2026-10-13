# AGENTS.md — The Prophet (VoiceForge)

## Goal
Fish Audio Drama 3 is the default TTS model; Fish Audio S2 Pro remains selectable.

## Context
macOS SwiftUI app using Drama 3 MLX by default and mlx-speech for selectable Fish S2 Pro. Prompt formatting, inline direction tags, history, presets, WAV playback.

- Stack: Swift Package + SwiftUI + mlx-speech
- Requires: macOS 14+, Xcode 26+, `mlx-speech` in PATH with `drama3_mlx` injected in its environment
- Build: `swift build` / `swift test`

Drama 3 checkpoint resolution: `VOICEFORGE_DRAMA3_MODEL_DIR`, then `~/Library/Application Support/VoiceForge/models/drama-3`.
Setup: `pipx inject mlx-speech -e ~/Projects/drama3` and ensure `mlx>=0.32.3`, `mlx-lm>=0.32` in that environment.

## Constraints
- `mlx-speech` must be in PATH — check before debugging audio issues. Drama 3 is the default.
- Output is WAV — do not change format without updating the full pipeline
- SwiftUI only, no AppKit

## Done when
- [ ] `swift build` succeeds
- [ ] Works with a real voice sample for each selected model
- [ ] `swift test` passes
