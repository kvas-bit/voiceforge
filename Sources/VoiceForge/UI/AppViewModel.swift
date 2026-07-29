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

    // Backend knobs — Fish S2 Pro is the only model. Max tokens and text input
    // flow through to mlx-speech; edit-type is not used by Fish.
    @Published var maxNewTokens: Double = 1500

    // Conversation editor state
    @Published var conversationLines: [ConversationLine] = []
    @Published var conversationName: String = ""
    @Published var conversationIsGenerating: Bool = false
    @Published var conversationPlaybackState: ConversationPlaybackState = .idle

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
    private let scriptParser = ConversationScriptParser()

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
    private var generationService: SpeechGenerationService
    let audioPlayer = AudioPlayerController()
    private var cancellables = Set<AnyCancellable>()
    private var generationTask: Task<Void, Never>?

    /// Convenience init for production.
    convenience init() {
        self.init(defaults: .standard, historyStore: HistoryStore(), generationService: SpeechGenerationService())
    }

    /// Designated initializer. All dependencies are explicit.
    init(defaults: UserDefaults, historyStore: HistoryStore, generationService: SpeechGenerationService = SpeechGenerationService()) {
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
        lastFormattedPrompt = ""
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
                self?.conversationPlaybackState = state
            }
            .store(in: &cancellables)
        refreshPreview()

        // Prewarm the persistent helper in the background.
        let svc = generationService
        Task { _ = await svc.prewarmPersistentHelper() }
    }

    func shutdownService() async {
        await generationService.shutdownPersistentHelper()
    }

    var formattedPreview: String {
        formatter.format(text: sourceText, emotion: emotionText)
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
        currentPlayingHistoryID = nil
        // Do NOT auto-play; the user can hit the dock or row play button.
        audioPlayer.stop()
    }

    func generate() {
        persistReferenceFields()
        generationError = ""
        cliOutput = ""
        refreshPreview()
        isGenerating = true
        generationPhase = .prewarming

        let requestID = UUID()
        pendingGenerationID = requestID

        let request = GenerationRequest(
            id: requestID,
            sourceText: sourceText,
            emotionText: emotionText,
            referenceAudioPath: referenceAudioPath,
            referenceText: referenceText,
            model: "fish-s2-pro",
            maxNewTokens: Int(maxNewTokens)
        )
        let service = generationService

        generationTask?.cancel()
        generationTask = Task { [weak self] in
            do {
                await MainActor.run { self?.generationPhase = .generating }
                let result = try await service.generate(request: request)
                if Task.isCancelled { return }
                await MainActor.run { self?.generationPhase = .validating }
                // Service already validates WAV internally; no separate step needed.
                await MainActor.run {
                    self?.completeGeneration(result, id: requestID)
                }
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

    private func completeGeneration(_ result: GenerationResult, id: UUID) {
        isGenerating = false
        generationPhase = .completed
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
        }
    }

    /// Assigns a manual (non-preset) reference clip/transcript to every current
    /// line spoken by `speakerKey`.
    func assignReferenceToSpeaker(referenceAudioPath: String, referenceText: String, speakerKey: String) {
        for i in conversationLines.indices where conversationLines[i].speakerKey == speakerKey {
            conversationLines[i].referenceAudioPath = referenceAudioPath
            conversationLines[i].referenceText = referenceText
        }
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
                .allSatisfy { !$0.referenceAudioPath.isEmpty && !$0.referenceText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
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
    }

    func generateConversation() {
        guard !conversationLines.isEmpty else { return }

        // Validate all lines
        for line in conversationLines {
            if line.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
               line.referenceAudioPath.isEmpty ||
               line.referenceText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                generationError = "All lines must have script text and a complete voice setup."
                return
            }
        }

        generationError = ""
        conversationIsGenerating = true
        conversationPlayer.stop()

        // Reset all statuses
        for i in 0..<conversationLines.count {
            conversationLines[i].status = .pending
            conversationLines[i].outputPath = nil
        }

        conversationGenerationTask?.cancel()
        conversationGenerationTask = Task { [weak self] in
            await self?.generateConversationLines()
        }
    }

    private func generateConversationLines() async {
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
            globalModel: "fish-s2-pro",
            globalMaxNewTokens: Int(maxNewTokens),
            globalEditType: "none"
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
            conversationLines: linesCopy
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
                    globalEditType: manifest.globalEditType
                )
            }

            return ConversationItem(
                name: item.name,
                lines: lines,
                globalModel: "fish-s2-pro",
                globalMaxNewTokens: Int(maxNewTokens),
                globalEditType: "none"
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
            globalEditType: manifest.globalEditType
        )
    }

    private func loadConversationManifest(at path: String) -> ConversationItem? {
        let url = URL(fileURLWithPath: path)
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(ConversationItem.self, from: data)
    }
}
