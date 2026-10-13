import Foundation
import Testing
#if canImport(VoiceForgeCore)
@testable import VoiceForgeCore
#else
@testable import VoiceForge
#endif

struct Drama3ContractTests {
    @Test func previousTakeUsesContractCodesFieldAndHistoryRetainsCodesAndSeed() throws {
        let previous = PreviousTake(text: "A line", codesPath: "/tmp/take.npy")
        let encodedPrevious = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(previous)) as? [String: String])
        #expect(encodedPrevious == ["text": "A line", "codes": "/tmp/take.npy"])

        let history = GenerationHistoryItem(id: UUID(), createdAt: Date(), sourceText: "A line",
            formattedPrompt: "A line", referenceAudioPath: "/tmp/ref.wav", referenceText: "ref",
            outputPath: "/tmp/take.wav", model: TTSModel.drama3.rawValue, codesPath: previous.codesPath, seed: 42)
        let restored = try JSONDecoder().decode(GenerationHistoryItem.self, from: JSONEncoder().encode(history))
        #expect(restored.codesPath == "/tmp/take.npy")
        #expect(restored.seed == 42)
    }
}
