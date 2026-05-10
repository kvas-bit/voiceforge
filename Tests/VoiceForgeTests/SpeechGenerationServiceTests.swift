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

    @Test func cancellingInFlightTaskSurfacesCancellationError() async throws {
        let service = SpeechGenerationService()
        let dummyURL = URL(fileURLWithPath: "/tmp/voiceforge-cancel-test.wav")

        let task = Task<GenerationResult, Error> {
            try await service.run(
                command: "sleep 30",
                formattedPrompt: "irrelevant",
                outputURL: dummyURL
            )
        }

        // Give the child process a moment to actually spawn before cancelling.
        try await Task.sleep(nanoseconds: 200_000_000)
        task.cancel()

        do {
            _ = try await task.value
            Issue.record("Expected the cancelled task to throw, but it returned a result")
        } catch is CancellationError {
            // expected
        } catch {
            Issue.record("Expected CancellationError, got \(error)")
        }
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
