import AppKit
import Combine
import Foundation
#if canImport(VoiceForgeCore)
import VoiceForgeCore
#endif

enum SidebarDestination: String, CaseIterable, Hashable, Identifiable {
    case studio, voices, history
    var id: String { rawValue }
    var label: String {
        switch self {
        case .studio: return "Studio"
        case .voices: return "Voices"
        case .history: return "History"
        }
    }
    var systemImage: String {
        switch self {
        case .studio: return "waveform.badge.mic"
        case .voices: return "person.crop.rectangle.stack"
        case .history: return "clock.arrow.circlepath"
        }
    }
}

@MainActor
final class AppViewModel: ObservableObject {
    @Published var destination: SidebarDestination = .studio
    @Published var inspectorVisible: Bool = true
    @Published var sourceText = ""
    @Published var emotionText: String
    @Published var referenceAudioPath: String
    @Published var referenceText: String
    @Published var pendingGenerationID: UUID?
    @Published var previewingVoiceID: UUID?
    @Published var isGenerating = false

    /// Sentinel id used by the Studio "loose reference" preview button so the same
    /// `previewingVoiceID` field works for both saved presets and the unbound clip.
    static let looseReferencePreviewID = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
    @Published var generationError = ""
    @Published var lastFormattedPrompt = ""
    @Published var lastOutputURL: URL?
    @Published var history: [GenerationHistoryItem]
    @Published var presets: [VoicePreset]
    @Published var selectedPresetID: UUID?
    @Published var presetName = ""
    @Published var quickInsertText = ""
    @Published var insertTrigger = 0
    @Published var cliOutput = ""

    // ElevenLabs-style voice settings. Persisted locally; advisory until a remote backend lands.
    @Published var stability: Double = 0.5
    @Published var similarity: Double = 0.75
    @Published var styleExaggeration: Double = 0.0
    @Published var speakerBoost: Bool = true

    // Backend knobs that DO flow through to `mlx-speech`.
    @Published var model: String = "fish-s2-pro"
    @Published var maxNewTokens: Double = 1500
    @Published var editType: String = "none"

    let availableModels = ["fish-s2-pro", "moss-tts", "step-audio-tts", "kokoro-multilingual"]
    let editTypes = ["none", "emotion", "style", "speed", "denoise", "vad", "paralinguistic"]

    let quickTags = [
        "[whispers]",
        "[laughs]",
        "[sighs]",
        "[excited]",
        "[sad]",
        "[angry]",
        "[sarcastic]",
        "[announcer voice]"
    ]

    private let defaults: UserDefaults
    private let presetStore: VoicePresetStore
    private let historyStore: HistoryStore
    private let formatter = PromptFormatter()
    private let generationService = SpeechGenerationService()
    let audioPlayer = AudioPlayerController()
    private var cancellables = Set<AnyCancellable>()
    private var generationTask: Task<Void, Never>?

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let environment = ProcessInfo.processInfo.environment
        referenceAudioPath = environment["VOICEFORGE_UITEST_REFERENCE_AUDIO"]
            ?? defaults.string(forKey: VoiceForgeStorageKeys.referenceAudioPath)
            ?? ""
        referenceText = environment["VOICEFORGE_UITEST_REFERENCE_TEXT"]
            ?? defaults.string(forKey: VoiceForgeStorageKeys.referenceText)
            ?? ""
        emotionText = environment["VOICEFORGE_UITEST_EMOTION_TEXT"]
            ?? defaults.string(forKey: VoiceForgeStorageKeys.emotionText)
            ?? ""
        presetStore = VoicePresetStore(defaults: defaults)
        historyStore = HistoryStore()
        presets = presetStore.load()
        history = historyStore.load().sorted(by: { $0.createdAt > $1.createdAt })
        sourceText = environment["VOICEFORGE_UITEST_SOURCE_TEXT"] ?? ""
        lastFormattedPrompt = ""
        audioPlayer.objectWillChange
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.objectWillChange.send()
            }
            .store(in: &cancellables)
        refreshPreview()
    }

    var formattedPreview: String {
        formatter.format(text: sourceText, emotion: emotionText)
    }

    var outputLocationDescription: String {
        let root = (try? SpeechGenerationService.renderRootDirectory().appendingPathComponent("outputs").path)
        return root ?? "~/Library/Application Support/VoiceForge/outputs"
    }

    func refreshPreview() {
        lastFormattedPrompt = formattedPreview
    }

    func persistReferenceFields() {
        defaults.set(referenceAudioPath, forKey: VoiceForgeStorageKeys.referenceAudioPath)
        defaults.set(referenceText, forKey: VoiceForgeStorageKeys.referenceText)
        defaults.set(emotionText, forKey: VoiceForgeStorageKeys.emotionText)
        refreshPreview()
    }

    func insertQuickTag(_ tag: String) {
        quickInsertText = tag
        insertTrigger += 1
    }

    func chooseReferenceAudio() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.audio]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false

        if panel.runModal() == .OK, let url = panel.url {
            referenceAudioPath = url.path
            persistReferenceFields()
        }
    }

    func applyPreset(_ preset: VoicePreset) {
        referenceAudioPath = preset.referenceAudioPath
        referenceText = preset.referenceText
        persistReferenceFields()
    }

    func saveCurrentAsPreset() {
        let trimmedName = presetName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else {
            return
        }

        let preset = VoicePreset(
            name: trimmedName,
            referenceAudioPath: referenceAudioPath,
            referenceText: referenceText
        )

        presets.insert(preset, at: 0)
        presetStore.save(presets)
        presetName = ""
    }

    func deletePresets(at offsets: IndexSet) {
        presets.remove(atOffsets: offsets)
        presetStore.save(presets)
    }

    func loadHistory(_ item: GenerationHistoryItem) {
        sourceText = item.sourceText
        referenceAudioPath = item.referenceAudioPath
        referenceText = item.referenceText
        generationError = ""
        persistReferenceFields()
        lastFormattedPrompt = item.formattedPrompt
        lastOutputURL = URL(fileURLWithPath: item.outputPath)
        previewingVoiceID = nil
        try? audioPlayer.load(url: URL(fileURLWithPath: item.outputPath))
    }

    func generate() {
        persistReferenceFields()
        generationError = ""
        cliOutput = ""
        refreshPreview()
        isGenerating = true

        let requestID = UUID()
        pendingGenerationID = requestID

        let request = GenerationRequest(
            id: requestID,
            sourceText: sourceText,
            emotionText: emotionText,
            referenceAudioPath: referenceAudioPath,
            referenceText: referenceText,
            model: model,
            maxNewTokens: Int(maxNewTokens),
            editType: editType == "none" ? nil : editType,
            editInfo: nil
        )
        let service = generationService

        generationTask?.cancel()
        generationTask = Task { [weak self] in
            do {
                let result = try await service.generate(request: request)
                if Task.isCancelled { return }
                await MainActor.run {
                    self?.completeGeneration(result, id: requestID)
                }
            } catch is CancellationError {
                await MainActor.run {
                    self?.isGenerating = false
                    self?.pendingGenerationID = nil
                    self?.generationError = ""
                    self?.cliOutput = "Generation cancelled."
                }
            } catch {
                await MainActor.run {
                    self?.isGenerating = false
                    self?.pendingGenerationID = nil
                    self?.generationError = error.localizedDescription
                }
            }
        }
    }

    /// Returns true while `voiceID` is the actively previewing voice and the player is running.
    func isPreviewing(voiceID: UUID) -> Bool {
        previewingVoiceID == voiceID && audioPlayer.isPlaying
    }

    /// Toggle preview playback for a given voice. Stops any other voice already previewing.
    /// Pass `forcedReload` when the underlying clip path may have changed since the last call.
    func togglePreview(voiceID: UUID, url: URL) {
        // Same card, currently playing -> pause without unloading.
        if previewingVoiceID == voiceID, audioPlayer.isPlaying {
            audioPlayer.togglePlayback()
            return
        }
        // Same card, paused -> resume.
        if previewingVoiceID == voiceID, !audioPlayer.isPlaying {
            audioPlayer.togglePlayback()
            return
        }
        // Different card (or first time) -> stop, load, play.
        audioPlayer.stop()
        do {
            try audioPlayer.load(url: url)
            previewingVoiceID = voiceID
            audioPlayer.togglePlayback()
        } catch {
            previewingVoiceID = nil
        }
    }

    func cancelGeneration() {
        generationTask?.cancel()
        generationTask = nil
    }

    func renameHistory(_ item: GenerationHistoryItem, to newName: String) {
        let trimmed = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let index = history.firstIndex(where: { $0.id == item.id }) else { return }
        var updated = history[index]
        updated.name = trimmed.isEmpty
            ? GenerationHistoryItem.autoName(from: updated.sourceText)
            : trimmed
        history[index] = updated
        historyStore.save(history)
    }

    func saveOutputAs() {
        guard let lastOutputURL else {
            return
        }

        let panel = NSSavePanel()
        panel.allowedContentTypes = [.wav]
        panel.nameFieldStringValue = lastOutputURL.lastPathComponent

        if panel.runModal() == .OK, let destination = panel.url {
            do {
                if FileManager.default.fileExists(atPath: destination.path) {
                    try FileManager.default.removeItem(at: destination)
                }
                try FileManager.default.copyItem(at: lastOutputURL, to: destination)
            } catch {
                generationError = error.localizedDescription
            }
        }
    }

    func revealOutputInFinder() {
        guard let lastOutputURL else {
            return
        }
        NSWorkspace.shared.activateFileViewerSelecting([lastOutputURL])
    }

    func deleteHistory(_ item: GenerationHistoryItem) {
        history.removeAll { $0.id == item.id }
        historyStore.save(history)
    }

    func clearHistory() {
        history = []
        historyStore.save(history)
    }

    func copyPrompt(_ item: GenerationHistoryItem) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(item.formattedPrompt, forType: .string)
    }

    /// True while `item`'s audio is the one currently playing through the shared
    /// player. Used by the History row Play button to flip its SF Symbol.
    func isPlayingHistory(_ item: GenerationHistoryItem) -> Bool {
        audioPlayer.isPlaying(url: URL(fileURLWithPath: item.outputPath))
    }

    /// Play/pause toggle that resolves the URL from the *specific* history item.
    /// - If the player is already playing this item: pause it (don't reload, so
    ///   the playhead survives).
    /// - If the player is loaded with this item but paused: resume.
    /// - Otherwise (different item, or first play): swap to the new clip.
    /// Any active voice preview is cancelled because the shared player can only
    /// host one stream at a time.
    func togglePlayHistory(_ item: GenerationHistoryItem) {
        let url = URL(fileURLWithPath: item.outputPath)
        previewingVoiceID = nil

        if audioPlayer.currentURL == url {
            if audioPlayer.isPlaying {
                audioPlayer.pause()
            } else {
                try? audioPlayer.play(url: url)
            }
        } else {
            try? audioPlayer.play(url: url)
        }
        lastOutputURL = url
    }

    /// Kept for backward compatibility with existing menus/UITests that expected
    /// an unconditional play. New call sites should prefer `togglePlayHistory`.
    func playHistory(_ item: GenerationHistoryItem) {
        togglePlayHistory(item)
    }

    func resetPersistedValues() {
        referenceAudioPath = ""
        referenceText = ""
        emotionText = ""
        persistReferenceFields()
    }

    private func completeGeneration(_ result: GenerationResult, id: UUID) {
        isGenerating = false
        pendingGenerationID = nil
        lastFormattedPrompt = result.formattedPrompt
        lastOutputURL = result.outputURL
        cliOutput = [result.standardOutput, result.standardError]
            .filter { !$0.isEmpty }
            .joined(separator: "\n")

        let historyItem = GenerationHistoryItem(
            id: id,
            createdAt: Date(),
            name: GenerationHistoryItem.autoName(from: sourceText),
            sourceText: sourceText,
            formattedPrompt: result.formattedPrompt,
            referenceAudioPath: referenceAudioPath,
            referenceText: referenceText,
            outputPath: result.outputURL.path
        )

        history.insert(historyItem, at: 0)
        historyStore.save(history)
        previewingVoiceID = nil
        try? audioPlayer.load(url: result.outputURL)
    }
}
