import Foundation
import Testing
@testable import VoiceForge

@MainActor
struct AppViewModelTests {
    @Test func loadingHistoryClearsStaleValidationError() {
        let suiteName = "VoiceForgeAppViewModelTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)

        let viewModel = AppViewModel(defaults: defaults)
        viewModel.generationError = "Enter text to generate."

        let item = GenerationHistoryItem(
            id: UUID(uuidString: "11111111-2222-3333-4444-555555555555")!,
            createdAt: Date(timeIntervalSince1970: 1_700_000_100),
            sourceText: "Recovered script",
            formattedPrompt: "[whispering softly and quietly] Recovered script",
            referenceAudioPath: "/tmp/reference.wav",
            referenceText: "Recovered transcript",
            outputPath: "/tmp/recovered.wav"
        )

        viewModel.loadHistory(item)

        #expect(viewModel.generationError.isEmpty)
        #expect(viewModel.sourceText == "Recovered script")
        #expect(viewModel.referenceAudioPath == "/tmp/reference.wav")
        #expect(viewModel.referenceText == "Recovered transcript")
    }

    @Test func togglePreviewTracksTheActiveVoiceID() {
        let suiteName = "VoiceForgeAppViewModelTests-preview-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)

        let viewModel = AppViewModel(defaults: defaults)
        let voiceA = UUID()
        let voiceB = UUID()
        let bogusURL = URL(fileURLWithPath: "/nonexistent/clip.wav")

        // Starting state: nothing previewing.
        #expect(viewModel.previewingVoiceID == nil)
        #expect(!viewModel.isPreviewing(voiceID: voiceA))

        // Calling toggle once should mark voiceA as the previewing source even though the
        // bogus URL fails to load (AVAudioPlayer throws). The view-model should clear the id.
        viewModel.togglePreview(voiceID: voiceA, url: bogusURL)
        #expect(viewModel.previewingVoiceID == nil)
        #expect(!viewModel.isPreviewing(voiceID: voiceA))

        // Switching to voiceB before voiceA actually played should also stay nil and not crash.
        viewModel.togglePreview(voiceID: voiceB, url: bogusURL)
        #expect(viewModel.previewingVoiceID == nil)
        #expect(!viewModel.isPreviewing(voiceID: voiceB))
    }
}
