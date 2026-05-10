# VoiceForge Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a native macOS SwiftUI app that wraps `mlx-speech`, formats emotion-tagged prompts, persists reference inputs, and plays plus saves generated WAV output.

**Architecture:** Use a Swift Package macOS executable with a small service layer for prompt formatting, persistence, shell execution, audio playback, and history. Keep the UI in focused SwiftUI view files connected through one observable view model.

**Tech Stack:** Swift 6, SwiftUI, AVFoundation, Foundation, XCTest, Swift Package Manager

---

### Task 1: Scaffold Package Layout

**Files:**
- Create: `Package.swift`
- Create: `Sources/VoiceForge/VoiceForgeApp.swift`
- Create: `Tests/VoiceForgeTests/PromptFormatterTests.swift`

- [ ] Step 1: Initialize executable package
- [ ] Step 2: Set macOS platform, product name, and test target
- [ ] Step 3: Add placeholder app entry and failing test

### Task 2: Implement Core Formatting Logic

**Files:**
- Create: `Sources/VoiceForge/Core/PromptFormatter.swift`
- Modify: `Tests/VoiceForgeTests/PromptFormatterTests.swift`

- [ ] Step 1: Write failing tests for freeform emotion prefixing and `*tag*` conversion
- [ ] Step 2: Implement minimal formatter
- [ ] Step 3: Add tests for duplicate removal, lowercase normalization, and alias expansion

### Task 3: Implement Persistence and Models

**Files:**
- Create: `Sources/VoiceForge/Core/Models.swift`
- Create: `Sources/VoiceForge/Core/Stores.swift`
- Create: `Tests/VoiceForgeTests/StoreTests.swift`

- [ ] Step 1: Write failing tests for JSON persistence helpers
- [ ] Step 2: Implement presets/history models and stores
- [ ] Step 3: Add `UserDefaults`-backed settings helpers

### Task 4: Implement CLI Runner and Playback

**Files:**
- Create: `Sources/VoiceForge/Core/SpeechGenerationService.swift`
- Create: `Sources/VoiceForge/Core/AudioPlayerController.swift`
- Create: `Tests/VoiceForgeTests/SpeechGenerationServiceTests.swift`

- [ ] Step 1: Write failing tests for command argument construction and output path resolution
- [ ] Step 2: Implement the generation service and output directory creation
- [ ] Step 3: Add audio playback wrapper for generated WAV files

### Task 5: Build the SwiftUI Surface

**Files:**
- Create: `Sources/VoiceForge/UI/AppViewModel.swift`
- Create: `Sources/VoiceForge/UI/GenerationWindowView.swift`
- Create: `Sources/VoiceForge/UI/SettingsWindowView.swift`
- Create: `Sources/VoiceForge/UI/CustomVoicesWindowView.swift`
- Create: `Sources/VoiceForge/UI/Components/PromptTextEditor.swift`

- [ ] Step 1: Create the observable view model
- [ ] Step 2: Build the primary generation window with preview, history, progress, playback, and save actions
- [ ] Step 3: Build settings and custom voices windows
- [ ] Step 4: Wire shared state through app scenes

### Task 6: Verify and Audit

**Files:**
- Modify: `README.md`

- [ ] Step 1: Add quickstart instructions covering `mlx-speech` expectations and output path
- [ ] Step 2: Run `swift test`
- [ ] Step 3: Run `swift build`
- [ ] Step 4: Audit every requested feature against source files and command output
