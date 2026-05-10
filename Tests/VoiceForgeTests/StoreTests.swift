import Foundation
import Testing
#if canImport(VoiceForgeCore)
@testable import VoiceForgeCore
#else
@testable import VoiceForge
#endif

struct StoreTests {
    @Test func presetRoundTripPreservesReferenceData() throws {
        let preset = VoicePreset(
            name: "Kaden",
            referenceAudioPath: "/tmp/kaden.wav",
            referenceText: "Reference line"
        )

        let data = try JSONEncoder().encode([preset])
        let decoded = try JSONDecoder().decode([VoicePreset].self, from: data)

        #expect(decoded == [preset])
    }

    @Test func historyRoundTripPreservesFinalPromptAndOutputURL() throws {
        let item = GenerationHistoryItem(
            id: UUID(uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE")!,
            createdAt: Date(timeIntervalSince1970: 1_700_000_000),
            sourceText: "hello",
            formattedPrompt: "[excited and energetic] hello",
            referenceAudioPath: "/tmp/ref.wav",
            referenceText: "hello",
            outputPath: "/tmp/out.wav"
        )

        let data = try JSONEncoder().encode([item])
        let decoded = try JSONDecoder().decode([GenerationHistoryItem].self, from: data)

        #expect(decoded == [item])
    }
}
