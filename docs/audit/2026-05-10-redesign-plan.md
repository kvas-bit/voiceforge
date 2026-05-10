# VoiceForge Redesign Plan (2026-05-10)

This plan maps the ElevenLabs reference surfaces from `2026-05-10-elevenlabs-research.md` onto native SwiftUI for macOS 14+, and resolves the audit issues from `2026-05-10-functionality-audit.md`.

## Guiding principles

1. **Native first.** Everything is `NavigationSplitView` + `Inspector` + `.toolbar` + `Settings` scene. No hand‑rolled HStack navigation, no `.sheet` for anything that should be a sidebar destination.
2. **Single window.** The existing `Generation + History`, `Settings`, and `Custom Voices` windows collapse into one `WindowGroup` whose sidebar destinations are *Studio*, *Voices*, *History*. `Settings` becomes a proper `Settings` scene reachable via ⌘, .
3. **The titlebar problem goes away.** `.windowStyle(.hiddenTitleBar)` on the `WindowGroup` + `.toolbarBackground(.hidden, for: .windowToolbar)` + `.containerBackground(.regularMaterial, for: .window)` + `NSWindow.titlebarAppearsTransparent` set via an `NSWindowDelegate` shim. The toolbar carries the wordmark, status pill, model picker, and a primary Generate button.
4. **Backend honesty.** Sliders that don't map to `mlx-speech` are still shown — they get persisted to `UserDefaults` and labelled as advisory ("will apply once a remote ElevenLabs backend is connected"). The sliders that *do* map (max-new-tokens) get plumbed end‑to‑end. The model picker is sourced from `mlx-speech tts --list-models` (cached at app start; falls back to a static list if the CLI is missing).
5. **Tags stay descriptive‑prose at the wire layer, ElevenLabs‑style in the UI.** The `[whispers]` / `[laughs]` chip the user types is rendered ElevenLabs‑style in the editor, and `PromptFormatter` continues to normalise them into the Fish‑S2‑Pro‑friendly text passed to `--text`. The alias table grows to cover the full ElevenLabs v3 tag list.

## Surface map

```
WindowGroup "VoiceForge"
├── NavigationSplitView
│   ├── sidebar (240 pt)
│   │   ├── Section "Workspace"
│   │   │   ├── Studio              [waveform.badge.mic]      (default)
│   │   │   ├── Voices              [person.crop.rectangle.stack]
│   │   │   └── History             [clock.arrow.circlepath]
│   │   └── Section "Account"
│   │       └── Subscription        [creditcard]              (placeholder)
│   ├── content
│   │   └── selected destination
│   └── inspector (toggle, 320 pt)
│       └── StudioInspector (only while Studio is selected)
└── .toolbar (unified)
    ├── leading: app wordmark + state pill
    ├── center:  segmented model picker
    └── trailing: voice picker menu, character counter, "Generate" primary button (⌘↩)

Settings scene
├── General        (output directory)
├── Generation     (defaults for stability/similarity/style/speaker boost, max tokens)
└── Advanced       (mlx-speech CLI path, model overrides)

MenuBarExtra (optional, behind a setting) — quick paste-and-generate
```

### Studio destination

A vertical layout inside the content column:

1. **Header (sticky):** project title (inline edit), last‑saved timestamp, share button stub. (`.safeAreaInset(edge: .top)` or just the toolbar.)
2. **Prompt editor (`StudioPromptEditor`):** the existing `NSTextView` upgraded so that:
   - Bracketed tags get an `NSTextAttachment`‑backed inline pill rendering (rounded background, slightly smaller font, ×‑on‑hover behaviour).
   - Typing `[` opens a floating `TagAutocompletePanel` (`NSPanel`, borderless) anchored at the caret rect; arrow keys + ↩ select, Esc closes, typing filters the categorised list, selecting an item replaces the `[` plus partial query with the chosen tag.
   - A footer row below the editor shows the live character count and a "Insert tag" button (⌘J) as a fallback.
3. **Bottom playback dock (`PlaybackDockView`):** pinned via `.safeAreaInset(edge: .bottom)`. Houses a waveform (rendered from an `AVAudioFile` sample buffer down‑sampled to ~200 bars), play/pause, scrub handle, current/total time, download, regenerate, reveal-in-finder, copy-prompt, delete.

The Studio inspector lives in the right `Inspector` rail and contains the controls below.

### Inspector (right rail)

A `Form` with sections:

1. **Voice** — large card: avatar circle + voice name + "Choose voice…" `Menu` listing presets and a "Manage voices" item that switches the sidebar to the Voices destination.
2. **Model** — `Picker` populated from `mlx-speech tts --list-models` (cached). Default `fish-s2-pro`.
3. **Tone / global emotion** — multi‑line text field (the current `emotionText`), with a row of one-click chips ("Whisper", "Excited", "Sad", "Announcer", "Calm", "Hesitant").
4. **Voice settings** — `DisclosureGroup`:
   - `Slider` "Stability" 0…1
   - `Slider` "Similarity" 0…1
   - `Slider` "Style exaggeration" 0…1
   - `Toggle` "Speaker boost"
   - Footnote: "Stored on this Mac. Pipes through once a remote ElevenLabs backend is connected."
5. **Generation** — `DisclosureGroup`:
   - `Slider` "Max new tokens" 256…4096 (maps to `--max-new-tokens`)
   - `Picker` "Edit type" {none, emotion, style, speed, denoise, vad, paralinguistic} (maps to `--edit-type`)
   - text field "Edit info" (maps to `--edit-info`)
6. **Output** — `Toggle` "Auto‑play after generation", `Picker` "Container" (WAV/MP3 — only WAV today), Reveal button.

### Voices destination

- Top bar with `.searchable` field, filter chips (gender / age / accent / use case — purely UI for now, applied to preset metadata once we add those fields).
- `LazyVGrid(columns: [.adaptive(minimum: 220)])` of voice cards. Each card:
  - 220 × 240, soft shadow, 16 pt radius, `Hovering` overlay with `play.fill` button to preview the reference clip via `AudioPlayerController`.
  - Three pills for whatever metadata exists (initially: "Reference", "Local preset").
  - Ellipsis menu: *Use in Studio*, *Edit*, *Duplicate*, *Delete*.
- Floating "+ New voice" button (bottom‑trailing) that opens a `.popover` with the existing "preset name + reference audio + reference transcript" form.

### History destination

- Two‑pane: `List` of history items on the left, detail view on the right with the prompt, formatted prompt, output path, full‑width waveform, play/pause, "Reuse in Studio".
- Right-click context menu on each list row: *Play*, *Reveal in Finder*, *Copy prompt*, *Delete*. Backspace deletes the selected row.

### Settings scene

`Settings { TabView { GeneralSettings(); GenerationSettings(); AdvancedSettings() } }`, opened by ⌘,. Replaces the current `.sheet` and removes the duplicate wordmark.

## Audio‑tag system

- **Catalogue.** A `TagCatalog` value type owning a list of `TagCategory(name, [Tag(label, descriptiveAlias)])`. The ElevenLabs‑style label is what the user types and what renders as a chip; the descriptive alias is what `PromptFormatter` emits to the CLI. Existing aliases preserved; new entries added for `whispers`, `laughs`, `laughs harder`, `sighs`, `exhales`, `crying`, `shouts`, `gulps`, `applause`, `gunshot`, `excited`, `curious`, `sarcastic`, `delighted`, `disappointed`, `dramatically`, `deadpan`, `hesitant`, `stutters`.
- **Round‑trip.** A `TagParser` exposes `parse(_ String) -> [TagSegment]` returning `.text(String) | .tag(name: String)` and `render([TagSegment]) -> String`. Stored canonical text is `[name] body…`. A round‑trip test (`tag parser round trip preserves segments`) goes in `TagParserTests`.
- **NSTextView rendering.** A `TagDecorator` walks `NSTextStorage` whenever it changes and applies `.backgroundColor` + `.font` + a custom `.tag` attribute over the `[…]` ranges. Cheaper than `NSTextAttachment` and survives editing well; the visual outcome is a chip‑shaped highlight rather than a fully replaced attachment, which is appropriate for a text editor that the user is still typing into. (We document the trade‑off in the file header.)
- **Autocomplete.** A `TagAutocompleteController` owns an `NSPanel`. The `PromptTextEditor.Coordinator` listens for `textDidChange` and `keyDown`; when the inserted character is `[` (or when the caret is inside an unterminated `[…`), it asks the controller to show, filters by the partial query, captures arrow keys/return/escape, and on commit calls `textView.insertText("\(tag.label)]", replacementRange:)`.

## Window chrome / "top bar" fix

Concretely the new `VoiceForgeApp` looks like:

```swift
WindowGroup("VoiceForge", id: "main") {
    RootView()
        .environmentObject(viewModel)
        .frame(minWidth: 1100, minHeight: 720)
        .containerBackground(.regularMaterial, for: .window)
}
.defaultSize(width: 1320, height: 860)
.windowStyle(.hiddenTitleBar)
.windowToolbarStyle(.unified(showsTitle: false))
.commands { VoiceForgeCommands() }

Settings { SettingsScene().environmentObject(viewModel) }
```

`RootView` is the `NavigationSplitView`. Because the titlebar is hidden, the traffic lights float over the sidebar's top‑left corner; we add `.safeAreaInset(edge: .top)` of ~28 pt in the sidebar so the Studio/Voices/History rows don't slide under them.

## Keyboard shortcuts

| Shortcut | Action |
| --- | --- |
| ⌘↩ | Generate |
| ⌘L | Focus prompt editor |
| ⌘J | Insert audio tag (opens picker) |
| ⌘P | Play / pause last generation |
| ⌘. | Cancel current generation |
| ⌘[ / ⌘] | Previous / next history entry |
| ⌘1 / ⌘2 / ⌘3 | Switch to Studio / Voices / History |
| ⌘, | Open Settings |
| ⌘K | Open command palette |

All wired through `.commands { CommandMenu("VoiceForge") { … } }` and `.keyboardShortcut(…)` on the relevant buttons.

## Command palette

A modeless overlay opened by ⌘K via a `@FocusedValue`‑driven boolean. Backed by a `CommandRegistry` that exposes:

- Navigate: Studio / Voices / History / Settings.
- Create: New voice preset, New generation (clears prompt).
- Recent: last 8 history items by title.
- Tags: every entry from `TagCatalog` so the user can splice one in without typing `[`.

Implementation is a `ZStack` overlay with a `TextField` + filtered `List`; not part of the must‑land scope for this PR but the architecture leaves room (`CommandRegistry` + the `.commands` wiring land now; the visual palette is a stub view that we ship feature‑flagged).

## Theming

Existing `VoiceForgeTheme` colours stay but we add:

- `surface`, `surfaceElevated`, `border`, `borderStrong` mapped from `.regularMaterial` + `Color(nsColor: .separatorColor)` so dark mode looks correct.
- `accent` shifts from the existing royal blue to a slightly desaturated `Color.accentColor`‑driven gradient so it works in both light and dark.
- The gradient `VoiceForgeBackground` view is dropped in favour of `containerBackground(.regularMaterial)` — vibrancy is now the background, not a hand‑painted gradient.

## Implementation order (matches the commits we ship)

1. **Window chrome + Settings scene + skeleton NavigationSplitView.** The "top bar" problem disappears here.
2. **Tag catalogue + parser + tests.** Round‑trip + alias expansion regression.
3. **Studio prompt editor v2** (chip rendering + autocomplete).
4. **Studio inspector + model picker + sliders + Generate wiring.**
5. **Playback dock.**
6. **Voices destination (grid + new‑voice popover).**
7. **History destination (two‑pane).**
8. **Keyboard shortcuts + command stubs.**
9. **Polish + audit doc cross‑links.**

## Tests we will add

- `TagParserTests`: round‑trip of mixed text + bracket segments, asterisk normalisation parity with the legacy `PromptFormatter`, autocomplete filter ordering, alias expansion for the full v3 catalogue.
- `AppViewModelTests` (extended): max‑tokens / edit‑type round‑trip through `UserDefaults`, switching sidebar destinations preserves prompt text.
- `SpeechGenerationServiceTests` (extended): command string includes `--max-new-tokens` when set, `--edit-type` / `--edit-info` when present.

UI tests in `UITests/VoiceForgeUITests` stay green because the accessibility identifiers they hit (`generateButton`, `referenceAudioPathField`, `referenceTextField`, `emotionField`, `sourceTextEditor`, `formattedPreviewText`, `historyList`, `historyReuseButton-…`, `historyEntry-…`, `playOutputButton`, `saveOutputButton`, `revealOutputButton`, `openSettingsButton`, `openCustomVoicesButton`, `resetReferenceFieldsButton`, `presetNameField`, `saveCurrentReferenceButton`, `customVoicesList`, `usePresetButton-…`, `quickTag-…`, `settingsOutputPathText`) get re‑attached to their counterparts in the new UI.
