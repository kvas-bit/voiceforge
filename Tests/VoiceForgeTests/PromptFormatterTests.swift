import Foundation
import Testing
#if canImport(VoiceForgeCore)
@testable import VoiceForgeCore
#else
@testable import VoiceForge
#endif

struct PromptFormatterTests {
    @Test func drama3PreservesInlineDirectionsAndSpeakerTags() {
        let output = PromptFormatter().format(text: "[laughs] hello [quietly, like a secret] <|speaker:3|>",
            emotion: "whispers", model: TTSModel.drama3.rawValue)
        #expect(output == "[whispers] [laughs] hello [quietly, like a secret] <|speaker:3|>")
        #expect(!output.contains("<|im_start|>"))
    }

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

    // MARK: - Typo correction via formatter

    @Test func formatCorrectsTypoInSource() {
        let formatter = PromptFormatter()
        let result = formatter.format(text: "[excitd] hi", emotion: "")
        #expect(result == "[excited and energetic] hi")
    }

    @Test func formatPassesThroughUnknownTag() {
        let formatter = PromptFormatter()
        let result = formatter.format(text: "[whoosh] hi", emotion: "")
        // unknown tags are passed through unchanged
        #expect(result == "[whoosh] hi")
    }

    // MARK: - Adjacent / nested / unterminated brackets

    @Test func formatAdjacentBracketsInsertSpaces() {
        let formatter = PromptFormatter()
        let result = formatter.format(text: "[whispers][laughs]", emotion: "")
        #expect(result == "[whispering softly and quietly] [laughing lightly]")
    }

    @Test func formatDoubleBracketsNoCrash() {
        let formatter = PromptFormatter()
        // [[whispers]] — the outer brackets capture "[whispers" as tag content.
        // Since it starts with `[` the correct guard rejects it, and the
        // unknown content is passed through unchanged.
        let result = formatter.format(text: "[[whispers]]", emotion: "")
        #expect(result == "[[whispers]]")
    }

    @Test func formatStrayClosingBracketPreserved() {
        let formatter = PromptFormatter()
        // A stray `]` with no matching `[` is literal text, preserved as-is.
        let result = formatter.format(text: "hello] world", emotion: "")
        #expect(result == "hello] world")
    }

    @Test func formatNewlineInsideTagTreatedAsLiteral() {
        let formatter = PromptFormatter()
        let result = formatter.format(text: "hello [whispers\nsighs] world", emotion: "")
        // Tag spanning a newline — regex [^\]]+ doesn't stop at \n, but
        // normalizeTag lowercases and collapses whitespace:
        // "whispers\nsighs" → "whispers sighs" → not in aliasMap → passed through.
        // The formatter produces "[whispers sighs]" (unknown, preserved).
        #expect(result.contains("[whispers sighs]"))
        #expect(result.contains("world"))
    }

    @Test func formatUntaggedSourceUnchanged() {
        let formatter = PromptFormatter()
        let result = formatter.format(text: "hello world", emotion: "")
        #expect(result == "hello world")
    }

    @Test func formatDeduplicatesRepeatedTags() {
        let formatter = PromptFormatter()
        let result = formatter.format(text: "[sighs] a [sighs] b", emotion: "")
        // Both "sighs" resolve to the same alias → deduped by seen-set.
        #expect(result == "[sighing] a b")
    }

    @Test func formatEmotionAndInlineTagsMerge() {
        let formatter = PromptFormatter()
        let result = formatter.format(text: "go [laughs]", emotion: "excited")
        #expect(result == "[excited and energetic] go [laughing lightly]")
    }

    @Test func formatDeterministicSameArgsSameResult() {
        let formatter = PromptFormatter()
        let a = formatter.format(text: "[whispers] test", emotion: "sad")
        let b = formatter.format(text: "[whispers] test", emotion: "sad")
        #expect(a == b)
    }
}
