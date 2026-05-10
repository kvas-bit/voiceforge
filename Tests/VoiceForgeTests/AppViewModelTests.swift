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

    @Test func togglePlayHistoryResolvesItemSpecificURL() throws {
        let suiteName = "VoiceForgeAppViewModelTests-history-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)

        let viewModel = AppViewModel(defaults: defaults)
        let dir = makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }

        let urlA = dir.appendingPathComponent("a.wav")
        let urlB = dir.appendingPathComponent("b.wav")
        try writeSilentWAV(to: urlA)
        try writeSilentWAV(to: urlB)

        let itemA = GenerationHistoryItem(
            id: UUID(), createdAt: Date(), name: "A",
            sourceText: "a", formattedPrompt: "a",
            referenceAudioPath: "/tmp/r.wav", referenceText: "r",
            outputPath: urlA.path
        )
        let itemB = GenerationHistoryItem(
            id: UUID(), createdAt: Date(), name: "B",
            sourceText: "b", formattedPrompt: "b",
            referenceAudioPath: "/tmp/r.wav", referenceText: "r",
            outputPath: urlB.path
        )

        // Toggling item A loads item A — not the last-known output URL.
        viewModel.togglePlayHistory(itemA)
        #expect(viewModel.audioPlayer.currentURL == urlA)
        #expect(viewModel.lastOutputURL == urlA)

        // Toggling item B must swap the player to B's URL, proving each history
        // entry resolves to its own path rather than a shared "current output".
        viewModel.togglePlayHistory(itemB)
        #expect(viewModel.audioPlayer.currentURL == urlB)
        #expect(viewModel.lastOutputURL == urlB)

        // Toggling B again while loaded should pause (not reload) — currentURL stays B.
        viewModel.togglePlayHistory(itemB)
        #expect(viewModel.audioPlayer.currentURL == urlB)
    }

    @Test func isPlayingHistoryIsKeyedOnIdNotURL() throws {
        let suiteName = "VoiceForgeAppViewModelTests-keyedID-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)

        let viewModel = AppViewModel(defaults: defaults)
        let dir = makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }

        // Two distinct history rows that legacy data would have pointed at the
        // exact same outputPath. Before the id-keyed fix both would light up
        // whenever either played.
        let sharedURL = dir.appendingPathComponent("shared.wav")
        try writeSilentWAV(to: sharedURL)

        let rowA = GenerationHistoryItem(
            id: UUID(), createdAt: Date(), name: "A",
            sourceText: "a", formattedPrompt: "a",
            referenceAudioPath: "/tmp/r.wav", referenceText: "r",
            outputPath: sharedURL.path
        )
        let rowB = GenerationHistoryItem(
            id: UUID(), createdAt: Date(), name: "B",
            sourceText: "b", formattedPrompt: "b",
            referenceAudioPath: "/tmp/r.wav", referenceText: "r",
            outputPath: sharedURL.path
        )

        viewModel.togglePlayHistory(rowA)
        // Whatever the audio engine decided about isPlaying, only row A's id
        // should be the active one; row B (sharing the URL) must not light up.
        #expect(!viewModel.isPlayingHistory(rowB))
        // A reports the same state as the underlying player.
        #expect(viewModel.isPlayingHistory(rowA) == viewModel.audioPlayer.isPlaying)

        // Toggling row B swaps the active id over to B.
        viewModel.togglePlayHistory(rowB)
        #expect(!viewModel.isPlayingHistory(rowA))
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
