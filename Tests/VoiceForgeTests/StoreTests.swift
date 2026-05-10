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
            name: "Greeting take",
            sourceText: "hello",
            formattedPrompt: "[excited and energetic] hello",
            referenceAudioPath: "/tmp/ref.wav",
            referenceText: "hello",
            outputPath: "/tmp/out.wav"
        )

        let data = try JSONEncoder().encode([item])
        let decoded = try JSONDecoder().decode([GenerationHistoryItem].self, from: data)

        #expect(decoded == [item])
        #expect(decoded.first?.name == "Greeting take")
    }

    @Test func historyAutoNameStripsTagsAndTruncates() {
        let name = GenerationHistoryItem.autoName(from: "[whispers] Greetings, dear listener — welcome to the broadcast today.")
        #expect(!name.contains("["))
        #expect(name.count <= 41) // 40 + ellipsis
        #expect(name.hasPrefix("Greetings"))
    }

    @Test func historyAutoNameFallsBackForEmptyPrompt() {
        let name = GenerationHistoryItem.autoName(from: "[whispers]   [laughs]")
        #expect(name == "Untitled generation")
    }

    @Test func historyDecodesLegacyEntriesWithoutNameField() throws {
        let legacyJSON = #"""
        [
          {
            "id": "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE",
            "createdAt": 0,
            "sourceText": "hello world",
            "formattedPrompt": "hello world",
            "referenceAudioPath": "/tmp/ref.wav",
            "referenceText": "hello",
            "outputPath": "/tmp/out.wav"
          }
        ]
        """#
        let data = Data(legacyJSON.utf8)
        let decoded = try JSONDecoder().decode([GenerationHistoryItem].self, from: data)
        #expect(decoded.first?.name == "hello world")
    }

    @Test func uniqueOutputURLPerGenerationID() throws {
        let service = SpeechGenerationService()
        let home = URL(fileURLWithPath: "/Users/tester")
        let id1 = UUID()
        let id2 = UUID()
        let url1 = try service.outputURL(forID: id1, homeDirectory: home)
        let url2 = try service.outputURL(forID: id2, homeDirectory: home)
        #expect(url1 != url2)
        #expect(url1.path == "/Users/tester/voiceforge/outputs/\(id1.uuidString).wav")
        #expect(url2.path.hasSuffix(".wav"))
    }
}
