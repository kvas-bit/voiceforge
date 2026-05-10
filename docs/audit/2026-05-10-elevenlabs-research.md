# ElevenLabs UI / UX Research (2026)

Source links (current product surfaces, all under <https://elevenlabs.io>):

- Marketing home and product index — <https://elevenlabs.io/>
- Studio (text‑to‑speech workspace) — <https://elevenlabs.io/app/speech-synthesis>
- Voice Library — <https://elevenlabs.io/app/voice-library>
- Voices (my voices) — <https://elevenlabs.io/app/voice-lab>
- Projects (long‑form) — <https://elevenlabs.io/app/projects>
- Dubbing — <https://elevenlabs.io/app/dubbing>
- Sound Effects — <https://elevenlabs.io/app/sound-effects>
- Conversational AI — <https://elevenlabs.io/app/conversational-ai>
- History — <https://elevenlabs.io/app/history>
- Subscription / Usage — <https://elevenlabs.io/app/subscription>
- Audio tag reference — <https://elevenlabs.io/docs/best-practices/prompting/v3-prompting-guide>
- Voice settings reference — <https://elevenlabs.io/docs/product/speech-synthesis/voice-settings>

Where the documentation has shifted between v2 / v2.5 / v3 of the Eleven model family, the description below reflects the v3 Studio surface as it stood in 2026.

## 1. Top‑level information architecture

The signed‑in app is a single web SPA at `app.elevenlabs.io` with three regions:

1. **Primary left rail (collapsible).** Roughly 240 px wide when expanded, ~60 px when collapsed to icons only. Hosts the workspace switcher at top, then a list of product surfaces with SF‑Symbols‑style line icons + label. Order, top to bottom:
   - Home
   - **Studio** (text‑to‑speech, the default landing for most users)
   - **Voices** — submenu: *My Voices*, *Voice Library*, *Voice Design*
   - **Projects** (long‑form / chaptered narration)
   - **Dubbing**
   - **Sound Effects**
   - **Conversational AI** — submenu: *Agents*, *Knowledge Base*, *Phone numbers*
   - **History**
   - **Usage**
   - Subscription & Settings sit pinned at the bottom, separated by a thin divider.
2. **Secondary nav within a surface.** On surfaces that have sub‑sections (Voices, Conversational AI, Projects), the secondary tabs render as pill segments at the top of the canvas, not as a second sidebar.
3. **Main canvas.** Always edge‑to‑edge background; sections sit on soft cards (1 px border + ~12 px radius + very subtle shadow).
4. **Command palette.** ⌘K opens a Linear‑style palette anchored centre‑top with sections for "Navigate to…", "Create…", "Recent generations", "Documentation".

## 2. Studio (text‑to‑speech workspace)

The Studio surface is the spiritual ancestor of what VoiceForge should be. It has three columns:

### Left: text editor (~55 % of the canvas width)

- A tall, serif‑adjacent, large‑font editor (Inter / SF Pro at ~18 px, line height ~1.55) on a near‑white card.
- At the top‑left corner, the project / generation title is editable inline (click‑to‑rename).
- Audio tags render as **inline rounded chips** with a slightly darker background than the surrounding text, the bracketed name in a slightly smaller weight, and a tiny "×" appearing on hover for removal. Visually they sit on the text baseline, not above it.
- Typing `[` opens a **floating autocomplete menu** anchored at the caret. The menu lists categorised tags:
  - **Voice‑related:** `[whispers]`, `[shouts]`, `[laughs]`, `[laughs harder]`, `[starts laughing]`, `[wheezing]`, `[sighs]`, `[exhales]`, `[snorts]`, `[crying]`, `[mischievously]`.
  - **Emotion:** `[excited]`, `[curious]`, `[sad]`, `[happy]`, `[angry]`, `[sarcastic]`, `[disappointed]`, `[delighted]`.
  - **Delivery:** `[shouting]`, `[whispering]`, `[narrating]`, `[announcer voice]`, `[dramatically]`, `[deadpan]`, `[hesitant]`, `[stutters]`.
  - **Sound effects:** `[gunshot]`, `[applause]`, `[clapping]`, `[explosion]`, `[swallows]`, `[gulps]`.
  - Selecting an entry replaces the `[` plus any partial query with the tag *as a chip*, leaves the caret immediately after the chip, and resumes normal typing.
  - The menu also supports arrow‑key navigation and ↩ to commit.
- A live **character counter** sits in the editor's footer at bottom‑right, with the format `12,345 / 40,000` and turns orange at 90 % and red at 100 % of the plan quota.
- A small **segment toolbar** floats over a text selection: "Regenerate segment", "Add break", "Add pause length", "Insert audio tag", "Translate".

### Right: voice / generation settings panel (~280 px wide)

A vertical stack of cards with these controls, in roughly this order:

1. **Voice picker.** Avatar + name + role descriptor ("Adam — Deep narrator"). Clicking opens a popover with a search field, "My Voices" / "Library" tabs, and a vertical list of voices with avatar + name + tags (Gender, Age, Accent, Use case) + a small play icon to preview the voice.
2. **Model picker.** Dropdown listing `Eleven v3`, `Eleven Multilingual v2`, `Eleven Turbo v2.5`, `Eleven Flash v2.5`. Each row carries a short blurb (latency vs quality).
3. **Voice settings card** — collapsible, headlined "Voice settings", with:
   - **Stability** slider, 0 – 100. Labels: "More variable" → "More stable".
   - **Similarity** slider, 0 – 100. Labels: "Low" → "High". A subtitle warns about extreme values amplifying source artefacts.
   - **Style exaggeration** slider, 0 – 100. Labels: "None" → "Exaggerated".
   - **Speaker boost** toggle. Subtitle: "Boost the similarity to the original speaker. Slightly increases compute."
4. **Pronunciation dictionaries** (lexicon) selector.
5. **Output format** dropdown — MP3 (44.1 kHz / 128 kbps default), MP3 22 kHz, PCM 16 kHz, μ‑law 8 kHz.

The bottom of the right column is anchored by a large, full‑width **"Generate speech"** primary button. Below it, the cost preview ("~ 412 characters · ~$0.18 · ~0.4 credits"). After generation completes, the button morphs into a "Generate again" / "Regenerate" pair.

### Bottom (full‑width playback dock, ~80 px tall)

Pinned to the bottom of the canvas regardless of scroll, with:

- A waveform (light‑grey idle bars + accent‑filled progress) spanning ~70 % of the dock.
- Transport: a circular play/pause on the left, current‑time and total‑time labels, a scrub handle on the waveform itself.
- Right‑side actions: download (MP3/WAV/PCM split menu), share link, "Add to project", "Regenerate", overflow ("Open in Voice Lab", "Delete generation").

### Top inline (sticky title bar of the Studio canvas)

- Breadcrumb: workspace → "Studio".
- Project title (inline edit).
- Right side: collaborator avatars, a "Share" button, a "History" button, a status pill ("Saved 3 s ago").

## 3. Voice Library

- Grid of square‑rounded **voice cards** at roughly 220 × 240 px. Each card has:
  - An avatar (real photo for community voices, abstract gradient for stock voices).
  - The voice name in semibold.
  - One‑line descriptor.
  - Three to four metadata pills: gender, age band, accent, primary use case.
  - On hover, the card shows a centred play button + a horizontal waveform that scrubs through a sample on the same card; clicking once auto‑plays, clicking again pauses; releasing hover keeps the card highlighted until clicked away.
  - A heart icon at top‑right to favourite.
  - An ellipsis menu with "Add to my voices", "View details", "Report".
- **Filter bar** at the top of the canvas: search field, gender (Female / Male / Neutral), age (Young / Middle Aged / Old), accent (American / British / Australian / Indian / …), use case (Narration / News / Conversational / Characters & Animation / Social media / Audiobook), language. Active filters render as removable chips below the search field.
- A "Featured" / "Trending" / "Recently added" toggle row sits to the right of the filter bar.
- "Add to my voices" yanks the voice into the user's **My Voices** view, which is the same grid but scoped to saved voices and surfaces them in the Voice picker inside Studio.

## 4. Voice Design

A guided form: language → gender → age → accent → loudness → tempo → unique character. Below the form, an editable text prompt ("a calm, breathy voice in their early thirties with a soft Irish lilt") that gets fed to the voice‑design model. Output is a 3‑voice preview grid; user picks one and it becomes a saved voice.

## 5. Conversational AI / Agents

- Left sidebar's "Conversational AI" expands to "Agents" + "Knowledge Base" + "Phone numbers".
- An Agent has: name, language, first message, prompt, voice, LLM provider (`gpt-4o`, `claude`, `gemini`), and tools (web search, custom HTTP, transfer to human). Right side has a real‑time test pane with a microphone button.

## 6. Visual language

- **Palette.** Neutral white surfaces with a soft warm gray (`#F7F7F5`) page background; cards on `#FFFFFF` with a 1 px `#E6E6E6` border and a ~6 % shadow. Dark mode is a near‑black `#0B0B0F` with cards on `#15151B` and a slightly brighter border. Accents are restrained: a primary black‑on‑white button (or white‑on‑black in dark mode) for the main action, a violet `#7C3AED`‑adjacent for secondary/notice tints, occasional teal for "AI" affordances.
- **Type.** Inter / system sans‑serif for body, tighter tracking on display sizes. No serif except occasionally in marketing.
- **Spacing.** Generous: ~24 px section padding, ~16 px between cards in the right column, ~32 px between the editor and the side panel.
- **Iconography.** Lucide / Phosphor line icons at 18 – 20 px, 1.5 px stroke.
- **Affordance vocabulary.** Waveforms everywhere (cards, dock, segment scrubber), playhead is a thin tall accent‑coloured rule, hover‑to‑play is the dominant interaction.
- **Motion.** Subtle — 120 – 180 ms eases on dropdowns, 80 ms on hover state changes, the segment toolbar fades in over ~120 ms.

## 7. Navigation patterns we want to steal

1. The collapsible left rail with icon + label, terminating in a settings/subscription footer.
2. The ⌘K palette with sections for Navigate / Create / Recent.
3. The pinned bottom playback dock that survives scroll.
4. The right inspector that *is* the generation settings, not a separate "settings page".
5. The autocomplete‑on‑`[` pattern for audio tags, with chip rendering inline.
6. The "regenerate this segment" overlay on text selection.
7. Voice cards as the primary unit in the Voice Library, with hover‑preview.
8. Filter chips that detach from the filter bar (so they're easy to remove individually).

## 8. macOS native translation cheatsheet

| ElevenLabs surface | Native SwiftUI counterpart |
| --- | --- |
| Left rail | `NavigationSplitView` sidebar |
| Right settings panel | `Inspector` (macOS 14+) |
| ⌘K command palette | `.searchable` + `.keyboardShortcut("k", modifiers: .command)` overlay, or `MenuBarExtra` for a global one |
| Bottom playback dock | `.safeAreaInset(edge: .bottom)` carrying a fixed‑height dock view |
| Hover‑to‑play voice card | `.onHover { … }` + `Image(systemName: "play.fill")` overlay |
| Inline tag chip | `NSTextAttachment` subclass with a custom `NSTextAttachmentCell`, or a `Text` builder that interleaves `Text` + `Label` chips when rendering history |
| Tag autocomplete | a floating `NSPanel` anchored to the caret rect, populated from a static tag catalogue |
| Voice picker popover | `Menu { … } label: { … }` or `.popover` with a `List` |
| Settings → ⌘, | `Settings { … }` scene |
| Title bar | `.windowStyle(.hiddenTitleBar)` + `.toolbar { … }` for the unified bar |
| Container vibrancy | `.containerBackground(.regularMaterial, for: .window)` (macOS 14+) |
| Voice library cards | `LazyVGrid` with `.adaptive(minimum: 220)` |
| History | `.navigationSplitViewColumnWidth` content column + `List` with context menus |

This mapping is what the redesign plan turns into a concrete implementation.
