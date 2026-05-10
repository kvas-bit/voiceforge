# VoiceForge Design

## Goal

Build a native macOS SwiftUI app named `VoiceForge` that wraps `mlx-speech` for Fish Audio S2 Pro voice cloning, adds prompt formatting for emotion tags, persists reference inputs, previews the final formatted prompt, and supports playback plus saving of generated audio.

## Assumptions

- The user asked for fully autonomous execution, so this spec resolves open choices without further review.
- The app will target macOS 14 or newer and use SwiftUI with `WindowGroup` and `Window` scenes.
- The output path will follow the explicit requirement `~/voiceforge/voiceforge_output.wav`. The shell command example that points to `~/Desktop/voiceforge_output.wav` is treated as stale.
- The app will store persistent values with `UserDefaults` via `@AppStorage`.
- The "custom voices" window will start as a local voice/reference library shell with reusable saved presets, because no deeper voice-management behavior was specified.
- The app will run `mlx-speech` through `/bin/zsh -lc` so the user environment can resolve the CLI.

## Product Shape

The app uses three windows:

1. `Generate + History` is the primary workspace. It contains the multiline prompt editor, emotion quick-tag buttons, freeform emotion field, reference inputs, formatted preview, generate action, progress state, playback controls, save action, and a local session history list.
2. `Settings` contains the output location summary, CLI readiness guidance, and persistence-related app defaults.
3. `Custom Voices` stores reusable reference presets made from a reference audio path plus reference text so users can quickly reapply a voice setup.

The visual direction is a light, minimal interface with muted grays, generous whitespace, rounded cards, and restrained blue accents.

## Architecture

The app is a single macOS SwiftUI executable package with a small domain layer:

- `PromptFormatter` converts raw prompt text plus freeform emotion into the final prompt sent to `mlx-speech`.
- `VoiceForgeSettingsStore` persists reference audio, reference text, and lightweight preferences.
- `SpeechGenerationService` validates inputs, ensures `~/voiceforge` exists, builds the shell command, runs the process, and returns the output file URL plus the final prompt.
- `AudioPlayerController` wraps `AVAudioPlayer` for inline playback.
- `HistoryStore` tracks in-app generation records for the current machine.
- `PresetStore` persists reusable custom voice presets in `UserDefaults`.

The UI composes around a shared `AppViewModel` that exposes state for generation, history, playback, selected preset, preview text, and errors.

## Prompt Formatting Rules

The formatter will:

- Trim whitespace from the main text and freeform emotion input.
- If freeform emotion is present, prepend it as `[normalized emotion] `.
- Convert inline `*emotion*` spans to bracket tags.
- Lowercase tag content.
- Normalize a small alias set for better model phrasing:
  - `whisper` -> `whispering softly and quietly`
  - `speaking softly` -> `speaking softly`
  - `professional broadcast tone` -> `professional broadcast tone`
  - `excited` -> `excited and energetic`
  - `laugh` -> `laughing lightly`
  - `sad` -> `sad and subdued`
  - `angry` -> `angry and intense`
- Collapse duplicate tags while preserving first appearance order.
- Clean spacing around tags and between tags and words.

The preview shows the exact formatted string sent to `mlx-speech`.

## Generation Flow

1. User enters prompt text, optional freeform emotion, reference audio path, and reference text.
2. Preview updates live from formatter output.
3. On `Generate`, the app validates required fields.
4. The service creates `~/voiceforge` if needed and writes output to `~/voiceforge/voiceforge_output.wav`.
5. The app runs:

```bash
mlx-speech tts --model fish-s2-pro --text "<formatted prompt>" --reference-audio "<audio path>" --reference-text "<reference text>" -o ~/voiceforge/voiceforge_output.wav
```

6. While the process runs, the UI shows an indeterminate progress view and disables repeated submission.
7. On success, the app refreshes playback state and appends a history entry.
8. On failure, the app surfaces stderr in an inline error area.

## Persistence

- `referenceAudioPath` persists between launches.
- `referenceText` persists between launches.
- `emotionText` persists between launches for convenience.
- Custom voice presets persist as JSON in `UserDefaults`.
- History persists locally as JSON in Application Support so the history window survives relaunches.

## Testing Strategy

Automated tests will focus on the logic that is easiest to verify reliably:

- prompt formatting behavior
- duplicate-tag cleanup
- freeform emotion prefixing
- shell command argument construction
- output path resolution
- preset/history encoding behavior

UI verification will be done by compiling the app and manually launching it locally when possible.

## Risks

- `mlx-speech` may not be installed or available in the app launch environment. The app needs a clear error path.
- Sandboxed file-bookmark handling is out of scope for the first pass because the package app will run as a local developer app, not a hardened App Store sandboxed bundle.
- Cursor CLI, Gemini CLI, and Copilot routing instructions conflict with the current execution environment. They are treated as advisory, not required deliverables.
