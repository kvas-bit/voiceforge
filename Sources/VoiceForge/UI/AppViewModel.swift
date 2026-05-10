import AppKit
import Combine
import Foundation
#if canImport(VoiceForgeCore)
import VoiceForgeCore
#endif

@MainActor
final class AppViewModel: ObservableObject {
    @Published var sourceText = ""
    @Published var emotionText: String
    @Published var referenceAudioPath: String
    @Published var referenceText: String
    @Published var isGenerating = false
    @Published var generationError = ""
    @Published var lastFormattedPrompt = ""
    @Published var lastOutputURL: URL?
    @Published var history: [GenerationHistoryItem]
    @Published var presets: [VoicePreset]
    @Published var presetName = ""
    @Published var quickInsertText = ""
    @Published var insertTrigger = 0
    @Published var cliOutput = ""

    let quickTags = [
        "[excited]",
        "[whisper]",
        "[laugh]",
        "[sad]",
        "[angry]",
        "[professional broadcast tone]",
        "[speaking softly]"
    ]

    private let defaults: UserDefaults
    private let presetStore: VoicePresetStore
    private let historyStore: HistoryStore
    private let formatter = PromptFormatter()
    private let generationService = SpeechGenerationService()
    let audioPlayer = AudioPlayerController()
    private var cancellables = Set<AnyCancellable>()

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
        (try? generationService.defaultOutputURL().path) ?? "~/voiceforge/voiceforge_output.wav"
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
        try? audioPlayer.load(url: URL(fileURLWithPath: item.outputPath))
    }

    func generate() {
        persistReferenceFields()
        generationError = ""
        cliOutput = ""
        refreshPreview()
        isGenerating = true

        let request = GenerationRequest(
            sourceText: sourceText,
            emotionText: emotionText,
            referenceAudioPath: referenceAudioPath,
            referenceText: referenceText
        )
        let service = generationService

        Task {
            do {
                let result = try await service.generate(request: request)
                await MainActor.run {
                    self.completeGeneration(result)
                }
            } catch {
                await MainActor.run {
                    self.isGenerating = false
                    self.generationError = error.localizedDescription
                }
            }
        }
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

    func resetPersistedValues() {
        referenceAudioPath = ""
        referenceText = ""
        emotionText = ""
        persistReferenceFields()
    }

    private func completeGeneration(_ result: GenerationResult) {
        isGenerating = false
        lastFormattedPrompt = result.formattedPrompt
        lastOutputURL = result.outputURL
        cliOutput = [result.standardOutput, result.standardError]
            .filter { !$0.isEmpty }
            .joined(separator: "\n")

        let historyItem = GenerationHistoryItem(
            id: UUID(),
            createdAt: Date(),
            sourceText: sourceText,
            formattedPrompt: result.formattedPrompt,
            referenceAudioPath: referenceAudioPath,
            referenceText: referenceText,
            outputPath: result.outputURL.path
        )

        history.insert(historyItem, at: 0)
        historyStore.save(history)
        try? audioPlayer.load(url: result.outputURL)
    }
}
