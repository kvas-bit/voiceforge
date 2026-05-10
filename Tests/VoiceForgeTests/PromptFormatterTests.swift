import Foundation
import Testing
#if canImport(VoiceForgeCore)
@testable import VoiceForgeCore
#else
@testable import VoiceForge
#endif

struct PromptFormatterTests {
    @Test func prependsFreeformEmotionAndExpandsAliases() {
        let formatter = PromptFormatter()

        let result = formatter.format(
            text: "This is the line.",
            emotion: "Whisper"
        )

        #expect(result == "[whispering softly and quietly] This is the line.")
    }

    @Test func convertsAsteriskTagsAndDeduplicatesThem() {
        let formatter = PromptFormatter()

        let result = formatter.format(
            text: "*Excited* Start now [excited] and then *laugh*",
            emotion: ""
        )

        #expect(
            result == "[excited and energetic] Start now and then [laughing lightly]"
        )
    }

    @Test func lowercasesTagsAndCleansSpacing() {
        let formatter = PromptFormatter()

        let result = formatter.format(
            text: " [WHISPER]   keep going   *SAD* ",
            emotion: " Professional Broadcast Tone "
        )

        #expect(
            result == "[professional broadcast tone] [whispering softly and quietly] keep going [sad and subdued]"
        )
    }
}
