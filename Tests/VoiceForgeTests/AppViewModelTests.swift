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
}
