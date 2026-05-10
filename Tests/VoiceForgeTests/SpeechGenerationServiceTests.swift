import Foundation
import Testing
#if canImport(VoiceForgeCore)
@testable import VoiceForgeCore
#else
@testable import VoiceForge
#endif

struct SpeechGenerationServiceTests {
    @Test func buildsFishCommandWithVoiceforgeOutputPath() throws {
        let service = SpeechGenerationService()
        let outputURL = try service.defaultOutputURL(homeDirectory: URL(fileURLWithPath: "/Users/tester"))

        let command = service.command(
            formattedText: "[whispering softly and quietly] hello",
            referenceAudioPath: "/tmp/ref.wav",
            referenceText: "hello there",
            outputURL: outputURL
        )

        #expect(outputURL.path == "/Users/tester/voiceforge/voiceforge_output.wav")
        #expect(command == """
        mlx-speech tts --model fish-s2-pro --text "[whispering softly and quietly] hello" --reference-audio "/tmp/ref.wav" --reference-text "hello there" -o "/Users/tester/voiceforge/voiceforge_output.wav"
        """)
    }

    @Test func includesMaxTokensAndEditTypeWhenProvided() throws {
        let service = SpeechGenerationService()
        let outputURL = try service.defaultOutputURL(homeDirectory: URL(fileURLWithPath: "/Users/tester"))

        let command = service.command(
            formattedText: "hello",
            referenceAudioPath: "/tmp/ref.wav",
            referenceText: "hi",
            outputURL: outputURL,
            model: "moss-tts",
            maxNewTokens: 2048,
            editType: "emotion",
            editInfo: "happy"
        )

        #expect(command.contains("--model moss-tts"))
        #expect(command.contains("--max-new-tokens 2048"))
        #expect(command.contains("--edit-type emotion"))
        #expect(command.contains("--edit-info \"happy\""))
    }
}
