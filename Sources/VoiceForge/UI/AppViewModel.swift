import AppKit
import AVFoundation
import Combine
import Foundation
#if canImport(VoiceForgeCore)
import VoiceForgeCore
#endif

enum SidebarDestination: String, CaseIterable, Hashable, Identifiable {
    case studio, voices, history, conversations
    var id: String { rawValue }
    var label: String {
        switch self {
        case .studio: return "Studio"
        case .voices: return "Voices"
        case .history: return "History"
        case .conversations: return "Conversations"
        }
    }
    var systemImage: String {
        switch self {
        case .studio: return "waveform.badge.mic"
        case .voices: return "person.crop.rectangle.stack"
        case .history: return "clock.arrow.circlepath"
        case .conversations: return "text.badge.plus"
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
    /// Id of the history entry whose audio is currently playing. Cleared on
    /// pause, stop, natural end, when a voice preview takes over, or when a
    /// new generation finishes. Tracking by id (instead of by URL) ensures two
    /// rows that happen to share the same `outputPath` don't both light up.
    @Published var currentPlayingHistoryID: UUID?
    @Published var isGenerating = false

    /// Current generation phase for indeterminate progress display.
    enum GenerationPhase: String {
        case idle, prewarming, generating, validating, completed, failed, cancelled
    }
    @Published var generationPhase: GenerationPhase = .idle

    /// Sentinel id used by the Studio "loose reference" preview button so the same
    /// `previewingVoiceID` field works for both saved presets and the unbound clip.
    static let looseReferencePreviewID = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
    @Published var generationError = ""
    @Published var lastOutputURL: URL?
    /// When set (via `loadHistory`), the next completed generation is stamped
    /// as a new version of this history entry, then this is cleared.
    @Published var regeneratingFromID: UUID?
    @Published var history: [GenerationHistoryItem]
    @Published var presets: [VoicePreset]
    @Published var selectedPresetID: UUID?
    @Published var presetName = ""
    @Published var quickInsertText = ""
    @Published var insertTrigger = 0
    @Published var quickWrapTag = ""
    @Published var wrapTrigger = 0
    @Published var cliOutput = ""

    // ElevenLabs-style voice settings. Persisted locally; advisory until a remote backend lands.
    @Published var stability: Double = 0.5
    @Published var similarity: Double = 0.75
    @Published var styleExaggeration: Double = 0.0
    @Published var speakerBoost: Bool = true

    @Published var selectedTTSModel: String {
        didSet { defaults.set(selectedTTSModel, forKey: VoiceForgeStorageKeys.selectedTTSModel) }
    }

    // Generation controls shared by both Fish models.
    @Published var maxNewTokens: Double = 1500 { didSet { persistDrama3Settings() } }

    // Conversation editor state
    @Published var conversationLines: [ConversationLine] = []
    @Published var conversationName: String = ""
    @Published var conversationIsGenerating: Bool = false
    @Published var conversationPlaybackState: ConversationPlaybackState = .idle
    @Published var conversationSceneMode = true
    @Published var sceneDirection = ""
    @Published var conversationProgress = ""
    @Published var conversationSceneOutputPath: String?
    @Published var conversationLineTimes: [[Double]]?
    @Published var loadedCheckpoint = ""
    @Published var additionalVoiceReferences: [VoiceReference] = []
    @Published var referenceDiagnostics: [String] = []
    @Published var referenceActionMessage = ""
    @Published var generateTakeCount = 1
    @Published var takeOutputURLs: [URL] = []
    @Published var selectedTakeIndex = 0
    private var pendingPreviousTakes: [PreviousTake] = []

    // Multi-voice script import state
    /// Paste buffer bound to the "Import script" text editor.
    @Published var conversationScriptDraft: String = ""
    /// Unique speaker keys from the last import, in first-appearance order.
    @Published var conversationSpeakerKeys: [String] = []
    /// Normalized speaker key → first-used display name from the last import.
    @Published var conversationSpeakerDisplayNames: [String: String] = [:]
    /// Validation issues (missing speaker/dialogue) from the last import.
    @Published var conversationScriptIssues: [ScriptIssue] = []

    let conversationPlayer: ConversationPlayer
    private var conversationGenerationTask: Task<Void, Never>?
    private var conversationModelUsed: String?
    private let scriptParser = ConversationScriptParser()

    let s2QuickTags = [
        "[whispers]",
        "[laughs]",
        "[sighs]",
        "[excited]",
        "[sad]",
        "[angry]",
        "[sarcastic]",
        "[announcer voice]"
    ]
    let drama3QuickTags = ["[laughs]", "[sighs]", "[coughs]", "[gasp]", "[pause]", "[whispers]", "Free direction…"]
    var quickTags: [String] { selectedTTSModel == TTSModel.drama3.rawValue ? drama3QuickTags : s2QuickTags }
    @Published var drama3Temperature: Double { didSet { persistDrama3Settings() } }
    @Published var drama3TopP: Double { didSet { persistDrama3Settings() } }
    @Published var drama3TopK: Int { didSet { persistDrama3Settings() } }
    @Published var drama3Seed = "" { didSet { persistDrama3Settings() } }
    @Published var drama3Normalize: Bool { didSet { persistDrama3Settings() } }
    @Published var drama3AutoTokenBudget: Bool { didSet { persistDrama3Settings() } }

    private let defaults: UserDefaults
    private let presetStore: VoicePresetStore
    private let historyStore: HistoryStore
    private let formatter = PromptFormatter()
    private var generationService: SpeechGenerationService
    let audioPlayer = AudioPlayerController()
    private var cancellables = Set<AnyCancellable>()
    private var generationTask: Task<Void, Never>?

    // MARK: - Ollama (optional local prompt intelligence, off by default)

    private let ollamaCoordinator: OllamaCoordinator
    private var promptSuggestionTask: Task<Void, Never>?
    @Published var ollamaEnabled: Bool
    @Published var ollamaStatus: OllamaStatus = .idle
    @Published var ollamaModels: [OllamaModel] = []
    @Published var selectedOllamaModel: String
    /// The most recent suggestion, shown separately from `sourceText` until
    /// the user explicitly applies it — generation never sees this on its own.
    @Published var promptSuggestion: String?
    @Published var isSuggestingPrompt: Bool = false
    @Published var promptSuggestionError: String?

    /// Convenience init for production.
    convenience init() {
        self.init(
            defaults: .standard, historyStore: HistoryStore(), generationService: SpeechGenerationService(),
            ollamaCoordinator: OllamaCoordinator()
        )
    }

    /// Designated initializer. All dependencies are explicit.
    init(
        defaults: UserDefaults, historyStore: HistoryStore,
        generationService: SpeechGenerationService = SpeechGenerationService(),
        ollamaCoordinator: OllamaCoordinator = OllamaCoordinator()
    ) {
        self.defaults = defaults
        self.ollamaCoordinator = ollamaCoordinator
        ollamaEnabled = defaults.bool(forKey: VoiceForgeStorageKeys.ollamaEnabled)
        selectedOllamaModel = defaults.string(forKey: VoiceForgeStorageKeys.selectedOllamaModel) ?? ""
        selectedTTSModel = TTSModel(rawValue: defaults.string(forKey: VoiceForgeStorageKeys.selectedTTSModel) ?? "")?.rawValue
            ?? TTSModel.default.rawValue
        let savedDramaSettings = defaults.data(forKey: VoiceForgeStorageKeys.drama3Settings)
            .flatMap { try? JSONDecoder().decode(Drama3Settings.self, from: $0) } ?? Drama3Settings()
        maxNewTokens = Double(savedDramaSettings.maxNewTokens ?? 1500)
        drama3Temperature = savedDramaSettings.temperature
        drama3TopP = savedDramaSettings.topP
        drama3TopK = savedDramaSettings.topK
        drama3Seed = savedDramaSettings.seed.map(String.init) ?? ""
        drama3Normalize = savedDramaSettings.normalize
        drama3AutoTokenBudget = savedDramaSettings.maxNewTokens == nil
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
        self.historyStore = historyStore
        self.generationService = generationService
        presets = presetStore.load()
        conversationPlayer = ConversationPlayer(audioPlayer: audioPlayer)
        let loaded = self.historyStore.load()
        // One-time cleanup of legacy entries that point at the old shared output
        // file (or that share an outputPath with another entry). Without this,
        // pre-migration histories cause every row to play the latest render and
        // every play button to light up at once.
        let migration = self.historyStore.migrateLegacy(loaded)
        history = migration.items.sorted {
            if $0.createdAt != $1.createdAt { return $0.createdAt > $1.createdAt }
            return $0.outputPath < $1.outputPath
        }
        if migration.summary.relocated + migration.summary.dropped > 0 {
            self.historyStore.save(history)
            print("[VoiceForge] history migration: relocated=\(migration.summary.relocated) dropped=\(migration.summary.dropped) unchanged=\(migration.summary.unchanged)")
        }
        sourceText = environment["VOICEFORGE_UITEST_SOURCE_TEXT"] ?? ""
        audioPlayer.objectWillChange
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.objectWillChange.send()
            }
            .store(in: &cancellables)
        // Clear per-row "playing" state when the clip ends on its own.
        audioPlayer.didFinish
            .receive(on: RunLoop.main)
            .sink { [weak self] in
                self?.currentPlayingHistoryID = nil
            }
            .store(in: &cancellables)
        conversationPlayer.$state
            .receive(on: RunLoop.main)
            .sink { [weak self] state in
                guard let self, self.conversationPlaybackState != state else { return }
                self.conversationPlaybackState = state
            }
            .store(in: &cancellables)
        // Prewarm the persistent helper in the background.
        let svc = generationService
        Task { _ = await svc.prewarmPersistentHelper(model: selectedTTSModel) }
        Task {
            let checkpoint = await svc.persistentCheckpoint(model: selectedTTSModel) ?? ""
            guard self.loadedCheckpoint != checkpoint else { return }
            self.loadedCheckpoint = checkpoint
        }

        // Resume Ollama only if the user previously enabled it — starting
        // (or detecting) the server only happens when actually needed.
        if ollamaEnabled {
            Task { await self.refreshOllamaStatus() }
        }
    }

    func shutdownService() async {
        await generationService.shutdownPersistentHelper()
    }

    // MARK: - Ollama

    /// Enables/disables local prompt intelligence. Enabling triggers
    /// discovery/startup in the background; disabling stops (only) a server
    /// this coordinator itself started, and clears cached state.
    func setOllamaEnabled(_ enabled: Bool) {
        ollamaEnabled = enabled
        defaults.set(enabled, forKey: VoiceForgeStorageKeys.ollamaEnabled)
        if enabled {
            Task { await refreshOllamaStatus() }
        } else {
            promptSuggestionTask?.cancel()
            promptSuggestionTask = nil
            isSuggestingPrompt = false
            promptSuggestion = nil
            promptSuggestionError = nil
            ollamaModels = []
            ollamaStatus = .idle
            let coordinator = ollamaCoordinator
            Task { await coordinator.shutdownIfOwned() }
        }
    }

    /// Ensures a server is reachable (starting one only if needed) and
    /// refreshes the installed-model list. Safe to call repeatedly, e.g. from
    /// a Settings "Refresh" action.
    func refreshOllamaStatus() async {
        guard ollamaEnabled else { return }
        let status = await ollamaCoordinator.ensureRunning()
        await MainActor.run { self.ollamaStatus = status }
        guard status == .runningOwned || status == .runningExternal else { return }
        guard let models = try? await ollamaCoordinator.listModels() else { return }
        await MainActor.run {
            self.ollamaModels = models
            if self.selectedOllamaModel.isEmpty || !models.contains(where: { $0.name == self.selectedOllamaModel }) {
                if let first = models.first {
                    self.selectOllamaModel(first.name)
                }
            }
        }
    }

    func selectOllamaModel(_ name: String) {
        selectedOllamaModel = name
        defaults.set(name, forKey: VoiceForgeStorageKeys.selectedOllamaModel)
    }

    func selectTTSModel(_ model: String) {
        guard TTSModel(rawValue: model) != nil, selectedTTSModel != model else { return }
        selectedTTSModel = model
        let service = generationService
        Task {
            await service.shutdownPersistentHelper()
            _ = await service.prewarmPersistentHelper(model: model)
        }
    }

    /// Asks the selected model to suggest a more expressive, Fish-compatible
    /// rewrite of the current script. The result is only ever stored in
    /// `promptSuggestion` — `sourceText` is untouched until `applyPromptSuggestion()`.
    func requestPromptSuggestion() {
        guard ollamaEnabled, !selectedOllamaModel.isEmpty else { return }
        let trimmed = sourceText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        promptSuggestionTask?.cancel()
        isSuggestingPrompt = true
        promptSuggestionError = nil
        promptSuggestion = nil

        let coordinator = ollamaCoordinator
        let model = selectedOllamaModel
        let text = sourceText
        let emotion = emotionText

        promptSuggestionTask = Task { [weak self] in
            do {
                let suggestion = try await coordinator.suggestPrompt(model: model, sourceText: text, emotionText: emotion)
                if Task.isCancelled { return }
                await MainActor.run {
                    self?.isSuggestingPrompt = false
                    self?.promptSuggestion = suggestion
                }
            } catch is CancellationError {
                await MainActor.run { self?.isSuggestingPrompt = false }
            } catch {
                if Task.isCancelled {
                    await MainActor.run { self?.isSuggestingPrompt = false }
                    return
                }
                await MainActor.run {
                    self?.isSuggestingPrompt = false
                    self?.promptSuggestionError = error.localizedDescription
                }
            }
        }
    }

    func cancelPromptSuggestion() {
        promptSuggestionTask?.cancel()
        promptSuggestionTask = nil
        isSuggestingPrompt = false
    }

    /// Explicitly copies the current suggestion into the script. This is the
    /// only path by which an Ollama suggestion ever reaches `sourceText`.
    func applyPromptSuggestion() {
        guard let suggestion = promptSuggestion else { return }
        sourceText = suggestion
        promptSuggestion = nil
    }

    func dismissPromptSuggestion() {
        promptSuggestion = nil
        promptSuggestionError = nil
    }

    func shutdownOllamaIfOwned() async {
        await ollamaCoordinator.shutdownIfOwned()
    }

    var formattedPreview: String {
        formatter.format(text: sourceText, emotion: emotionText, model: selectedTTSModel)
    }

    var drama3Settings: Drama3Settings {
        Drama3Settings(temperature: drama3Temperature, topP: drama3TopP, topK: drama3TopK,
                       seed: Int(drama3Seed), normalize: drama3Normalize,
                       maxNewTokens: drama3AutoTokenBudget ? nil : Int(maxNewTokens))
    }
    var canReviseDrama3: Bool { !pendingPreviousTakes.isEmpty }

    private func persistDrama3Settings() {
        let settings = Drama3Settings(temperature: drama3Temperature, topP: drama3TopP, topK: drama3TopK,
                                      seed: Int(drama3Seed), normalize: drama3Normalize,
                                      maxNewTokens: drama3AutoTokenBudget ? nil : Int(maxNewTokens))
        if let data = try? JSONEncoder().encode(settings) { defaults.set(data, forKey: VoiceForgeStorageKeys.drama3Settings) }
    }

    func setDrama3Preset(expressive: Bool) {
        drama3Temperature = expressive ? 1.0 : 0.7
        drama3TopP = expressive ? 0.9 : 0.7
        drama3TopK = 30
    }

    var outputLocationDescription: String {
        let root = (try? generationService.renderRootDirectory().appendingPathComponent("outputs").path)
        return root ?? "~/Library/Application Support/VoiceForge/outputs"
    }

    var hasConversationLines: Bool {
        !conversationLines.isEmpty
    }

    var conversationHasGeneratedAudio: Bool {
        hasConversationLines &&
        conversationLines.allSatisfy { $0.status == .completed && !($0.outputPath ?? "").isEmpty }
    }

    var conversationIsInPlaybackMode: Bool {
        hasConversationLines && (conversationPlaybackState != .idle || conversationHasGeneratedAudio)
    }

    func persistReferenceFields() {
        defaults.set(referenceAudioPath, forKey: VoiceForgeStorageKeys.referenceAudioPath)
        defaults.set(referenceText, forKey: VoiceForgeStorageKeys.referenceText)
        defaults.set(emotionText, forKey: VoiceForgeStorageKeys.emotionText)
    }

    func insertQuickTag(_ tag: String) {
        quickInsertText = tag == "Free direction…" ? "[describe the delivery] " : tag
        insertTrigger += 1
    }

    func wrapSelection(with tag: String) { quickWrapTag = tag; wrapTrigger += 1 }

    func chooseReferenceAudio() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.audio]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false

        if panel.runModal() == .OK, let url = panel.url {
            referenceAudioPath = url.path
            persistReferenceFields()
            inspectMainReference()
        }
    }

    func inspectMainReference() {
        guard !referenceAudioPath.isEmpty else { return }
        Task {
            do {
                let info = try await generationService.inspectReference(audio: referenceAudioPath, text: referenceText)
                await MainActor.run { self.referenceDiagnostics = info.warnings }
            } catch {
                await MainActor.run { self.referenceDiagnostics = [error.localizedDescription] }
            }
        }
    }

    func inspectReferenceClip(_ clip: VoiceReference) {
        Task {
            do {
                let info = try await generationService.inspectReference(audio: clip.audioPath, text: clip.text)
                await MainActor.run { self.referenceDiagnostics = info.warnings }
            } catch {
                await MainActor.run { self.referenceDiagnostics = [error.localizedDescription] }
            }
        }
    }

    func applyPreset(_ preset: VoicePreset) {
        referenceAudioPath = preset.referenceAudioPath
        referenceText = preset.referenceText
        additionalVoiceReferences = preset.additionalReferences
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
            referenceText: referenceText,
            additionalReferences: additionalVoiceReferences
        )

        presets.insert(preset, at: 0)
        presetStore.save(presets)
        presetName = ""
        additionalVoiceReferences = []
    }

    func addVoiceReference(path: String) {
        Task {
            do {
                let info = try await generationService.inspectReference(audio: path)
                await MainActor.run {
                    let warnings = info.warnings
                    self.referenceDiagnostics = warnings
                    self.additionalVoiceReferences.append(VoiceReference(audioPath: path, text: ""))
                    self.referenceActionMessage = warnings.isEmpty ? "Reference looks good" : warnings.joined(separator: " · ")
                }
            } catch {
                await MainActor.run { self.referenceActionMessage = error.localizedDescription }
            }
        }
    }

    func autoTranscribeReference(path: String, applyToMain: Bool = false, additionalIndex: Int? = nil) {
        Task {
            do {
                let text = try await generationService.transcribe(audio: path)
                await MainActor.run {
                    if let additionalIndex, self.additionalVoiceReferences.indices.contains(additionalIndex) {
                        self.additionalVoiceReferences[additionalIndex].text = text
                    } else if applyToMain { self.referenceText = text }
                    self.referenceActionMessage = "Transcript ready"
                }
            } catch {
                await MainActor.run { self.referenceActionMessage = error.localizedDescription }
            }
        }
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
        lastOutputURL = URL(fileURLWithPath: item.outputPath)
        previewingVoiceID = nil
        currentPlayingHistoryID = nil
        // Marks the *next* generate() as a new version of this entry. The
        // original is never mutated or deleted — generate() always inserts a
        // fresh history item; this just carries the breadcrumb back to it.
        regeneratingFromID = item.id
        pendingPreviousTakes = item.codesPath.map { [PreviousTake(text: item.sourceText, codesPath: $0)] } ?? []
        // Do NOT auto-play; the user can hit the dock or row play button.
        audioPlayer.stop()
    }

    /// Detaches from "regenerating a version of X" so the next `generate()`
    /// starts an unrelated, standalone entry instead.
    func clearRegenerationSource() {
        regeneratingFromID = nil
        pendingPreviousTakes = []
    }

    func generate() {
        persistReferenceFields()
        generationError = ""
        cliOutput = ""
        isGenerating = true
        generationPhase = .prewarming

        takeOutputURLs = []
        selectedTakeIndex = 0
        let count = selectedTTSModel == TTSModel.drama3.rawValue ? min(4, max(1, generateTakeCount)) : 1
        let baseSettings = drama3Settings
        let priorTakes = pendingPreviousTakes
        let takeSeedBase = baseSettings.seed ?? Int.random(in: 1...Int.max - count)
        let text = sourceText, tone = emotionText, refPath = referenceAudioPath, refText = referenceText
        let refs = [VoiceReference(audioPath: referenceAudioPath, text: referenceText)] + additionalVoiceReferences
        let model = selectedTTSModel
        let autoBudget = drama3AutoTokenBudget
        let manualBudget = Int(maxNewTokens)
        let service = generationService

        generationTask?.cancel()
        generationTask = Task { [weak self] in
            do {
                for index in 0..<count {
                    if Task.isCancelled { return }
                    let seed = takeSeedBase
                    let settings = Drama3Settings(temperature: baseSettings.temperature, topP: baseSettings.topP,
                        topK: baseSettings.topK, seed: seed &+ index, normalize: baseSettings.normalize,
                        maxNewTokens: baseSettings.maxNewTokens)
                    let requestID = UUID()
                    let request = GenerationRequest(id: requestID, sourceText: text, emotionText: tone,
                        referenceAudioPath: refPath, referenceText: refText, model: model,
                        maxNewTokens: model == TTSModel.drama3.rawValue && autoBudget ? nil : manualBudget,
                        references: refs, drama3Settings: settings, previousTakes: priorTakes)
                    await MainActor.run { self?.pendingGenerationID = requestID; self?.generationPhase = .generating }
                    let result = try await service.generate(request: request)
                    if Task.isCancelled { return }
                    await MainActor.run {
                        self?.takeOutputURLs.append(result.outputURL)
                        self?.completeGeneration(result, id: requestID, model: model, seed: settings.seed)
                        if index + 1 < count {
                            self?.isGenerating = true
                            self?.generationPhase = .generating
                        }
                    }
                }
                await MainActor.run { self?.regeneratingFromID = nil; self?.pendingPreviousTakes = [] }
            } catch is CancellationError {
                await MainActor.run {
                    self?.isGenerating = false
                    self?.pendingGenerationID = nil
                    self?.generationError = ""
                    self?.generationPhase = .cancelled
                    self?.cliOutput = "Generation cancelled."
                }
            } catch {
                await MainActor.run {
                    self?.isGenerating = false
                    self?.pendingGenerationID = nil
                    self?.generationError = error.localizedDescription
                    self?.generationPhase = .failed
                }
            }
        }
    }

    func selectTake(at index: Int) {
        guard takeOutputURLs.indices.contains(index) else { return }
        selectedTakeIndex = index; lastOutputURL = takeOutputURLs[index]
        try? audioPlayer.play(url: takeOutputURLs[index])
    }

    /// Returns true while `voiceID` is the actively previewing voice and the player is running.
    func isPreviewing(voiceID: UUID) -> Bool {
        previewingVoiceID == voiceID && audioPlayer.isPlaying
    }

    /// Toggle preview playback for a given voice. Stops any other voice already previewing.
    /// Pass `forcedReload` when the underlying clip path may have changed since the last call.
    func togglePreview(voiceID: UUID, url: URL) {
        // Voice previews take over the shared player, so any in-flight history
        // playback must release its "currently playing" marker.
        currentPlayingHistoryID = nil

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
        generationPhase = .cancelled
        isGenerating = false
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
        if currentPlayingHistoryID == item.id {
            audioPlayer.stop()
            currentPlayingHistoryID = nil
        }
        if lastOutputURL?.path == item.outputPath {
            lastOutputURL = nil
        }
        history = historyStore.delete(item, from: history)
    }

    func clearHistory() {
        audioPlayer.stop()
        currentPlayingHistoryID = nil
        lastOutputURL = nil
        historyStore.clear(history)
        history = []
    }

    func copyPrompt(_ item: GenerationHistoryItem) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(item.formattedPrompt, forType: .string)
    }

    /// True iff this specific history entry's audio is the one currently
    /// playing. Keyed on the history entry's id rather than its URL so two
    /// rows that share an outputPath don't both report "playing" — that was
    /// the cause of all play buttons lighting up at the same time.
    func isPlayingHistory(_ item: GenerationHistoryItem) -> Bool {
        currentPlayingHistoryID == item.id && audioPlayer.isPlaying
    }

    /// Play/pause toggle that resolves the URL from the *specific* history item.
    /// - If this item is already playing: pause (don't reload, so the playhead
    ///   survives) and clear `currentPlayingHistoryID`.
    /// - If this item is loaded but paused: resume and mark it as the active id.
    /// - Otherwise (different item, or first play): swap to the new clip.
    /// Any active voice preview is cancelled because the shared player can only
    /// host one stream at a time.
    func togglePlayHistory(_ item: GenerationHistoryItem) {
        if item.type == .conversation {
            loadConversation(item)
            if conversationHasGeneratedAudio {
                startConversationPlayback(from: 0)
            }
            return
        }

        let url = URL(fileURLWithPath: item.outputPath)
        previewingVoiceID = nil

        if currentPlayingHistoryID == item.id, audioPlayer.currentURL == url {
            if audioPlayer.isPlaying {
                audioPlayer.pause()
                currentPlayingHistoryID = nil
            } else {
                try? audioPlayer.play(url: url)
                currentPlayingHistoryID = item.id
            }
        } else {
            try? audioPlayer.play(url: url)
            currentPlayingHistoryID = audioPlayer.isPlaying ? item.id : nil
        }
        lastOutputURL = url
    }

    /// Kept for backward compatibility with existing menus/UITests that expected
    /// an unconditional play. New call sites should prefer `togglePlayHistory`.
    func playHistory(_ item: GenerationHistoryItem) {
        togglePlayHistory(item)
    }

    /// Copies or merges the generation’s audio into the user’s **Downloads** folder.
    /// For single items: copies the WAV. For conversations: merges all lines into one WAV.
    func downloadHistoryItemToDownloads(_ item: GenerationHistoryItem) {
        generationError = ""
        if item.type == .conversation {
            downloadConversationToDownloads(item)
            return
        }
        let source = URL(fileURLWithPath: item.outputPath)
        guard FileManager.default.fileExists(atPath: source.path) else {
            generationError = "This audio file is missing from disk."
            return
        }
        guard let downloadsDirectory = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first else {
            generationError = "Could not open your Downloads folder."
            return
        }
        let stem = Self.downloadsSafeFileStem(for: item)
        let destination = Self.uniqueFileURL(directory: downloadsDirectory, stem: stem, extension: "wav")
        do {
            try FileManager.default.copyItem(at: source, to: destination)
            NSWorkspace.shared.activateFileViewerSelecting([destination])
        } catch {
            generationError = error.localizedDescription
        }
    }

    /// Merges all completed lines of a conversation history item into a single WAV in Downloads.
    private func downloadConversationToDownloads(_ item: GenerationHistoryItem) {
        let lines = item.conversationLines ?? []
        let paths = lines.compactMap(\.outputPath).filter {
            !$0.isEmpty && FileManager.default.fileExists(atPath: $0)
        }
        guard !paths.isEmpty else {
            generationError = "No generated audio found for this conversation."
            return
        }
        guard let downloadsDir = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first else {
            generationError = "Could not open your Downloads folder."
            return
        }
        let stem = Self.downloadsSafeFileStem(for: item)
        let destination = Self.uniqueFileURL(directory: downloadsDir, stem: stem, extension: "wav")
        do {
            try mergeWAVFiles(paths: paths, to: destination)
            NSWorkspace.shared.activateFileViewerSelecting([destination])
        } catch {
            generationError = error.localizedDescription
        }
    }

    /// Merges all completed lines of the current active conversation into a single WAV in Downloads.
    func downloadCurrentConversationToDownloads() {
        generationError = ""
        let paths = conversationLines
            .filter { $0.status == .completed }
            .compactMap(\.outputPath)
            .filter { !$0.isEmpty && FileManager.default.fileExists(atPath: $0) }
        guard !paths.isEmpty else {
            generationError = "No generated audio found for this conversation."
            return
        }
        guard let downloadsDir = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first else {
            generationError = "Could not open your Downloads folder."
            return
        }
        var name = conversationName.trimmingCharacters(in: .whitespacesAndNewlines)
        if name.isEmpty { name = ConversationItem.autoName(from: conversationLines) }
        let stem = Self.sanitizeFileStem(name)
        let destination = Self.uniqueFileURL(directory: downloadsDir, stem: stem, extension: "wav")
        do {
            try mergeWAVFiles(paths: paths, to: destination)
            NSWorkspace.shared.activateFileViewerSelecting([destination])
        } catch {
            generationError = error.localizedDescription
        }
    }

    /// Reads each WAV sequentially and writes them into a single output file.
    private func mergeWAVFiles(paths: [String], to destination: URL) throws {
        guard let firstPath = paths.first else { return }
        let firstFile = try AVAudioFile(forReading: URL(fileURLWithPath: firstPath))
        let outputFile = try AVAudioFile(forWriting: destination, settings: firstFile.fileFormat.settings)
        for path in paths {
            let inputFile = try AVAudioFile(forReading: URL(fileURLWithPath: path))
            let frameCount = AVAudioFrameCount(inputFile.length)
            guard frameCount > 0,
                  let buffer = AVAudioPCMBuffer(pcmFormat: inputFile.processingFormat, frameCapacity: frameCount)
            else { continue }
            try inputFile.read(into: buffer)
            try outputFile.write(from: buffer)
        }
    }

    private static func downloadsSafeFileStem(for item: GenerationHistoryItem) -> String {
        var name = item.name.trimmingCharacters(in: .whitespacesAndNewlines)
        if name.isEmpty {
            name = GenerationHistoryItem.autoName(from: item.sourceText).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return sanitizeFileStem(name)
    }

    static func sanitizeFileStem(_ raw: String) -> String {
        var stem = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if stem.isEmpty { stem = "VoiceForge" }
        let banned = CharacterSet(charactersIn: #"\/:*?"<>|"#)
        var sanitized = ""
        for ch in stem {
            if ch.unicodeScalars.contains(where: { banned.contains($0) }) {
                sanitized.append("_")
            } else {
                sanitized.append(ch)
            }
        }
        stem = sanitized.trimmingCharacters(in: .whitespacesAndNewlines)
        while stem.contains("__") {
            stem = stem.replacingOccurrences(of: "__", with: "_")
        }
        if stem.isEmpty { stem = "VoiceForge" }
        if stem.count > 120 {
            stem = String(stem.prefix(120)).trimmingCharacters(in: .whitespaces)
        }
        return stem
    }

    private static func uniqueFileURL(directory: URL, stem: String, extension ext: String) -> URL {
        let normalizedExt = ext.hasPrefix(".") ? String(ext.dropFirst()) : ext
        var candidate = directory.appendingPathComponent("\(stem).\(normalizedExt)")
        var index = 2
        while FileManager.default.fileExists(atPath: candidate.path) {
            candidate = directory.appendingPathComponent("\(stem) \(index).\(normalizedExt)")
            index += 1
        }
        return candidate
    }

    func resetPersistedValues() {
        referenceAudioPath = ""
        referenceText = ""
        emotionText = ""
        persistReferenceFields()
    }

    private func completeGeneration(_ result: GenerationResult, id: UUID, model: String, seed: Int? = nil) {
        isGenerating = false
        generationPhase = .completed
        pendingGenerationID = nil
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
            outputPath: result.outputURL.path,
            regeneratedFromID: regeneratingFromID,
            model: model,
            codesPath: result.codesURL?.path,
            seed: seed
        )

        history.insert(historyItem, at: 0)
        historyStore.save(history)
        previewingVoiceID = nil
        currentPlayingHistoryID = nil
        try? audioPlayer.load(url: result.outputURL)
    }

    // MARK: - Conversation Methods

    func addConversationLine() {
        let line = ConversationLine(
            text: "",
            referenceAudioPath: referenceAudioPath,
            referenceText: referenceText
        )
        conversationLines.append(line)
    }

    func removeConversationLine(at index: Int) {
        guard index >= 0, index < conversationLines.count else { return }
        conversationLines.remove(at: index)
    }

    func updateConversationLineText(at index: Int, text: String) {
        guard index >= 0, index < conversationLines.count else { return }
        conversationLines[index].text = text
    }

    func updateConversationLineReferenceText(at index: Int, text: String) {
        guard index >= 0, index < conversationLines.count else { return }
        conversationLines[index].referenceText = text
    }

    func applyPresetToConversationLine(at index: Int, preset: VoicePreset) {
        guard index >= 0, index < conversationLines.count else { return }
        conversationLines[index].referenceAudioPath = preset.referenceAudioPath
        conversationLines[index].referenceText = preset.referenceText
        conversationLines[index].additionalReferences = preset.additionalReferences
    }

    // MARK: - Multi-voice script import

    /// Parses a pasted multi-voice script and replaces the current conversation
    /// with one line per speaker turn, each tagged with its `speakerKey` so a
    /// single voice assignment (`assignPresetToSpeaker`) can fan out to every
    /// line spoken by that character. Voice fields start empty — `generateConversation()`
    /// already refuses to run until every line has a complete voice setup, so
    /// nothing generates with a missing binding.
    func importConversationScript(_ script: String) {
        let result = scriptParser.parse(script)
        conversationLines = scriptParser.makeConversationLines(from: result.segments)
        conversationSpeakerKeys = result.speakerKeys
        conversationSpeakerDisplayNames = result.speakerDisplay
        conversationScriptIssues = result.issues
        conversationName = ""
        conversationPlayer.stop()
    }

    /// Assigns a saved preset's voice to every current line spoken by `speakerKey`.
    func assignPresetToSpeaker(_ preset: VoicePreset, speakerKey: String) {
        for i in conversationLines.indices where conversationLines[i].speakerKey == speakerKey {
            conversationLines[i].referenceAudioPath = preset.referenceAudioPath
            conversationLines[i].referenceText = preset.referenceText
            conversationLines[i].additionalReferences = preset.additionalReferences
        }
    }

    /// Assigns a manual (non-preset) reference clip/transcript to every current
    /// line spoken by `speakerKey`.
    func assignReferenceToSpeaker(referenceAudioPath: String, referenceText: String, speakerKey: String) {
        for i in conversationLines.indices where conversationLines[i].speakerKey == speakerKey {
            conversationLines[i].referenceAudioPath = referenceAudioPath
            conversationLines[i].referenceText = referenceText
            conversationLines[i].additionalReferences = []
        }
    }

    func setCharacterDescription(_ value: String, speakerKey: String) {
        for i in conversationLines.indices where conversationLines[i].speakerKey == speakerKey {
            conversationLines[i].characterDescription = value
        }
    }

    func characterDescription(for speakerKey: String) -> String {
        conversationLines.first(where: { $0.speakerKey == speakerKey })?.characterDescription ?? ""
    }

    /// The voice currently bound to `speakerKey`, read from its first matching
    /// line — `nil` if that speaker has no lines or hasn't been assigned yet.
    func voiceBinding(forSpeakerKey speakerKey: String) -> SpeakerVoiceBinding? {
        guard let line = conversationLines.first(where: { $0.speakerKey == speakerKey }),
              !line.referenceAudioPath.isEmpty else { return nil }
        return SpeakerVoiceBinding(referenceAudioPath: line.referenceAudioPath, referenceText: line.referenceText)
    }

    /// True once every speaker introduced by the last import has a complete
    /// voice setup on all of their lines. Empty-speaker-list conversations
    /// (manually built, not imported) are trivially true here.
    var allSpeakersAssigned: Bool {
        conversationSpeakerKeys.allSatisfy { key in
            conversationLines
                .filter { $0.speakerKey == key }
                .allSatisfy { line in
                    let primaryReady = !line.referenceAudioPath.isEmpty && !line.referenceText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    return (primaryReady || !line.additionalReferences.isEmpty) && line.additionalReferences.allSatisfy { !$0.audioPath.isEmpty && !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
                }
        }
    }

    func applyCurrentReferenceToConversationLine(at index: Int) {
        guard index >= 0, index < conversationLines.count else { return }
        conversationLines[index].referenceAudioPath = referenceAudioPath
        conversationLines[index].referenceText = referenceText
    }

    func clearVoiceFromConversationLine(at index: Int) {
        guard index >= 0, index < conversationLines.count else { return }
        conversationLines[index].referenceAudioPath = ""
        conversationLines[index].referenceText = ""
        conversationLines[index].additionalReferences = []
    }

    func generateConversation() {
        guard !conversationLines.isEmpty else { return }

        // Validate all lines
        for line in conversationLines {
            let hasReference = ((!line.referenceAudioPath.isEmpty && !line.referenceText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) || !line.additionalReferences.isEmpty) && line.additionalReferences.allSatisfy { !$0.audioPath.isEmpty && !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            if line.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !hasReference {
                generationError = "All lines must have script text and a complete voice setup."
                return
            }
        }

        generationError = ""
        conversationIsGenerating = true
        conversationPlayer.stop()
        conversationSceneOutputPath = nil
        conversationLineTimes = nil
        conversationProgress = ""

        // Reset all statuses
        for i in 0..<conversationLines.count {
            conversationLines[i].status = .pending
            conversationLines[i].outputPath = nil
        }

        conversationGenerationTask?.cancel()
        let model = selectedTTSModel
        conversationModelUsed = model
        conversationGenerationTask = Task { [weak self] in
            if model == TTSModel.drama3.rawValue && self?.conversationSceneMode == true {
                await self?.generateConversationScene()
            } else {
                await self?.generateConversationLines(model: model)
            }
        }
    }

    private func generateConversationScene() async {
        let keys = conversationSpeakerKeys.isEmpty ? ["speaker-0"] : conversationSpeakerKeys
        let keyIDs = Dictionary(uniqueKeysWithValues: keys.enumerated().map { ($1, $0) })
        let speakers = keys.enumerated().compactMap { id, key -> SceneSpeaker? in
            guard let line = conversationLines.first(where: { ($0.speakerKey ?? keys[0]) == key }) else { return nil }
            var refs = line.additionalReferences
            if !line.referenceAudioPath.isEmpty, !refs.contains(where: { $0.audioPath == line.referenceAudioPath }) {
                refs.insert(VoiceReference(audioPath: line.referenceAudioPath, text: line.referenceText), at: 0)
            }
            return SceneSpeaker(id: id, name: conversationSpeakerDisplayNames[key] ?? key,
                               description: line.characterDescription, references: refs)
        }
        let lines = conversationLines.map { SceneLine(speaker: keyIDs[$0.speakerKey ?? keys[0]] ?? 0, text: $0.text) }
        conversationProgress = "Preparing scene…"
        do {
            let result = try await generationService.generateScene(speakers: speakers, lines: lines,
                direction: sceneDirection, settings: drama3Settings) { [weak self] done, total in
                    Task { @MainActor in self?.conversationProgress = "Rendering scene · \(done)/\(total)" }
                }
            guard !Task.isCancelled else { return }
            for i in conversationLines.indices {
                conversationLines[i].outputPath = result.lineOutputURLs.indices.contains(i) ? result.lineOutputURLs[i].path : nil
                conversationLines[i].status = conversationLines[i].outputPath == nil ? .failed : .completed
            }
            conversationSceneOutputPath = result.outputURL.path
            conversationLineTimes = result.lineTimes
            conversationProgress = "Scene ready"
            conversationIsGenerating = false
            saveConversationToHistory()
            playConversationScene()
        } catch {
            conversationIsGenerating = false
            conversationProgress = ""
            generationError = error.localizedDescription
            for i in conversationLines.indices { conversationLines[i].status = .failed }
        }
    }

    func playConversationScene() {
        guard let path = conversationSceneOutputPath else { return }
        try? audioPlayer.play(url: URL(fileURLWithPath: path))
    }

    private func generateConversationLines(model: String) async {
        let service = generationService

        for i in 0..<conversationLines.count {
            if Task.isCancelled {
                await MainActor.run {
                    self.conversationIsGenerating = false
                    self.conversationPlayer.stop()
                }
                return
            }

            await MainActor.run {
                self.conversationLines[i].status = .generating
            }

            let line = conversationLines[i]

            let request = GenerationRequest(
                id: UUID(),
                sourceText: line.text,
                emotionText: "",
                referenceAudioPath: line.referenceAudioPath,
                referenceText: line.referenceText,
                model: model,
                maxNewTokens: Int(maxNewTokens)
            )

            do {
                let result = try await service.generate(request: request)
                if Task.isCancelled { return }

                await MainActor.run {
                    self.conversationLines[i].outputPath = result.outputURL.path
                    self.conversationLines[i].status = .completed
                }
            } catch {
                if Task.isCancelled { return }

                await MainActor.run {
                    self.conversationLines[i].status = .failed
                    self.generationError = error.localizedDescription
                }
                break
            }
        }

        await MainActor.run {
            self.conversationIsGenerating = false
            let hasAllCompleted = self.conversationLines.allSatisfy { $0.status == .completed }
            if hasAllCompleted {
                // Auto-save to history
                self.saveConversationToHistory()
                // Start playback
                self.startConversationPlayback(from: 0)
            }
        }
    }

    func cancelConversationGeneration() {
        conversationGenerationTask?.cancel()
        conversationGenerationTask = nil
        conversationIsGenerating = false
        conversationPlayer.stop()
    }

    func resetConversation() {
        cancelConversationGeneration()
        conversationLines = []
        conversationName = ""
        conversationScriptDraft = ""
        conversationSpeakerKeys = []
        conversationSpeakerDisplayNames = [:]
        conversationSceneOutputPath = nil
        conversationLineTimes = nil
        conversationScriptIssues = []
        conversationPlayer.stop()
    }

    func saveConversationToHistory() {
        let linesCopy = conversationLines
        let name = conversationName.isEmpty
            ? ConversationItem.autoName(from: linesCopy)
            : conversationName

        // Create conversation output directory
        let conversationID = UUID()
        guard let outputsDir = try? generationService.renderRootDirectory()
            .appendingPathComponent("outputs") else {
            generationError = "Could not create a storage directory for this conversation."
            return
        }
        let conversationDir = outputsDir.appendingPathComponent(conversationID.uuidString, isDirectory: true)
        try? FileManager.default.createDirectory(at: conversationDir, withIntermediateDirectories: true)

        // Save conversation JSON manifest
        let manifest = ConversationItem(
            id: conversationID,
            createdAt: Date(),
            name: name,
            lines: linesCopy,
            globalModel: conversationModelUsed ?? selectedTTSModel,
            globalMaxNewTokens: Int(maxNewTokens),
            globalEditType: "none",
            sceneDirection: sceneDirection,
            sceneOutputPath: conversationSceneOutputPath,
            lineTimes: conversationLineTimes
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = .prettyPrinted
        if let data = try? encoder.encode(manifest) {
            let manifestURL = conversationDir.appendingPathComponent("conversation.json")
            try? data.write(to: manifestURL)
        }

        // Create history entry
        let sourceText = linesCopy.map { $0.text }.joined(separator: "\n---\n")
        let historyItem = GenerationHistoryItem(
            id: UUID(),
            createdAt: Date(),
            name: name,
            sourceText: sourceText,
            formattedPrompt: "",
            referenceAudioPath: linesCopy.first?.referenceAudioPath ?? "",
            referenceText: linesCopy.first?.referenceText ?? "",
            outputPath: conversationDir.appendingPathComponent("conversation.json").path,
            type: .conversation,
            conversationLines: linesCopy,
            model: conversationModelUsed ?? selectedTTSModel,
            codesPath: conversationSceneOutputPath.map { URL(fileURLWithPath: $0).deletingLastPathComponent().appendingPathComponent("scene.npy").path }
        )

        history.insert(historyItem, at: 0)
        historyStore.save(history)
    }

    func loadConversation(_ item: GenerationHistoryItem) {
        guard item.type == .conversation else { return }
        guard let conversation = resolvedConversation(from: item) else {
            generationError = "This conversation could not be loaded from history."
            return
        }
        conversationPlayer.stop()
        conversationLines = conversation.lines
        conversationName = conversation.name
        conversationSceneOutputPath = conversation.sceneOutputPath
        conversationLineTimes = conversation.lineTimes
        maxNewTokens = Double(conversation.globalMaxNewTokens)
        destination = .conversations
    }

    func toggleConversationLinePlayback(at index: Int) {
        guard index >= 0, index < conversationLines.count else { return }
        guard !(conversationLines[index].outputPath ?? "").isEmpty else { return }

        switch conversationPlaybackState {
        case .playing(let currentIndex) where currentIndex == index:
            conversationPlayer.pause()
            conversationPlaybackState = conversationPlayer.state
        case .paused(let currentIndex) where currentIndex == index:
            conversationPlayer.resume()
            conversationPlaybackState = conversationPlayer.state
        default:
            startConversationPlayback(from: index)
        }
    }

    private func startConversationPlayback(from index: Int) {
        guard conversationHasGeneratedAudio, index >= 0, index < conversationLines.count else { return }
        previewingVoiceID = nil
        currentPlayingHistoryID = nil
        lastOutputURL = nil
        conversationPlayer.play(lines: conversationLines, fromIndex: index)
        conversationPlaybackState = conversationPlayer.state
    }

    private func resolvedConversation(from item: GenerationHistoryItem) -> ConversationItem? {
        if let lines = item.conversationLines {
            if let manifest = loadConversationManifest(at: item.outputPath) {
                return ConversationItem(
                    id: manifest.id,
                    createdAt: manifest.createdAt,
                    name: item.name.isEmpty ? manifest.name : item.name,
                    lines: lines,
                    globalModel: manifest.globalModel,
                    globalMaxNewTokens: manifest.globalMaxNewTokens,
                    globalEditType: manifest.globalEditType,
                    sceneDirection: manifest.sceneDirection,
                    sceneOutputPath: manifest.sceneOutputPath,
                    lineTimes: manifest.lineTimes
                )
            }

            return ConversationItem(
                name: item.name,
                lines: lines,
                globalModel: TTSModel.fishS2Pro.rawValue,
                globalMaxNewTokens: Int(maxNewTokens),
                globalEditType: "none",
                sceneOutputPath: item.codesPath.map { URL(fileURLWithPath: $0).deletingLastPathComponent().appendingPathComponent("scene.wav").path }
            )
        }

        guard let manifest = loadConversationManifest(at: item.outputPath) else { return nil }
        return ConversationItem(
            id: manifest.id,
            createdAt: manifest.createdAt,
            name: item.name.isEmpty ? manifest.name : item.name,
            lines: manifest.lines,
            globalModel: manifest.globalModel,
            globalMaxNewTokens: manifest.globalMaxNewTokens,
            globalEditType: manifest.globalEditType,
            sceneDirection: manifest.sceneDirection,
            sceneOutputPath: manifest.sceneOutputPath,
            lineTimes: manifest.lineTimes
        )
    }

    private func loadConversationManifest(at path: String) -> ConversationItem? {
        let url = URL(fileURLWithPath: path)
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(ConversationItem.self, from: data)
    }
}
