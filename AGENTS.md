# AGENTS.md — The Prophet (VoiceForge)

## Goal
[Fill in current task]

## Context
macOS SwiftUI app wrapping mlx-speech for Fish Audio S2 Pro voice cloning. Prompt formatting, emotion tags, history, presets, WAV playback.

- Stack: Swift Package + SwiftUI + mlx-speech
- Requires: macOS 14+, Xcode 26+, `mlx-speech` in PATH
- Build: `swift build` / `swift test`

## Constraints
- `mlx-speech` must be in PATH — check before debugging audio issues
- Output is WAV — do not change format without updating the full pipeline
- SwiftUI only, no AppKit

## Done when
- [ ] `swift build` succeeds
- [ ] Works with a real voice sample
- [ ] `swift test` passes
