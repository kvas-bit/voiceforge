import Foundation
import Testing
#if canImport(VoiceForgeCore)
@testable import VoiceForgeCore
#else
@testable import VoiceForge
#endif

struct TagCatalogTests {
    @Test func parserSplitsTextAndTags() {
        let parser = TagParser()
        let segments = parser.parse("Hello [whispers] world [sighs]")
        #expect(segments == [
            .text("Hello "),
            .tag("whispers"),
            .text(" world "),
            .tag("sighs")
        ])
    }

    @Test func parserRoundTripPreservesInput() {
        let parser = TagParser()
        let input = "[excited] Onwards we [laughs harder] go."
        #expect(parser.render(parser.parse(input)) == input)
    }

    @Test func parserKeepsUnterminatedBracketAsText() {
        let parser = TagParser()
        let segments = parser.parse("Hello [whispers and onwards")
        #expect(segments == [.text("Hello [whispers and onwards")])
    }

    @Test func suggestionsPrefixMatchFirst() {
        let suggestions = TagCatalog.suggestions(matching: "whi", limit: 4)
        #expect(suggestions.first?.label == "whispering")
        #expect(suggestions.contains(where: { $0.label == "whispers" }))
    }

    @Test func aliasMapExpandsElevenLabsStyleTagsForPromptFormatter() {
        let formatter = PromptFormatter()
        let result = formatter.format(text: "Hello [whispers] world.", emotion: "")
        #expect(result == "Hello [whispering softly and quietly] world.")
    }

    @Test func legacyShortAliasesAreStillSupported() {
        let formatter = PromptFormatter()
        let result = formatter.format(text: "[whisper] hi [laugh] there", emotion: "")
        #expect(result == "[whispering softly and quietly] hi [laughing lightly] there")
    }

    // MARK: - Typo correction

    @Test func typoCorrectionCorrectsSingleEdit() {
        #expect(TagCatalog.correct("excitd")?.label == "excited")
    }

    @Test func typoCorrectionHandlesInsertion() {
        #expect(TagCatalog.correct("whisper")?.label == "whispers")
    }

    @Test func typoCorrectionAmbiguousReturnsNil() {
        // "shorts" is distance 1 from both "shouts" (sub u→r) and "snorts" (sub h→n).
        #expect(TagCatalog.correct("shorts") == nil)
    }

    @Test func typoCorrectionTooShortReturnsNil() {
        #expect(TagCatalog.correct("x") == nil)
    }

    @Test func typoCorrectionExactMatchReturnsTag() {
        let result = TagCatalog.correct("happy")
        #expect(result?.label == "happy")
    }

    @Test func typoCorrectionSubstitution() {
        // "anry" → "angry" (swap 'g'→nil, 'r'→'n'? Actually anagram — distance?)
        // "anry" vs "angry": delete 'g' (1), substitute 'n'→'r' (1) = 2
        #expect(TagCatalog.correct("anry")?.label == "angry")
    }

    @Test func typoCorrectionNoMatchReturnsNil() {
        #expect(TagCatalog.correct("zzzzz") == nil)
    }

    // MARK: - Unknown tag detection

    @Test func unknownTagsDetectsUnknown() {
        let result = TagCatalog.unknownTags(in: "[whoosh] hi [laughs]")
        #expect(result == ["whoosh"])
    }

    @Test func unknownTagsEmptyForAllKnown() {
        let result = TagCatalog.unknownTags(in: "[laughs] hi [sighs]")
        #expect(result.isEmpty)
    }

    @Test func unknownTagsIgnoresEmptyBrackets() {
        let result = TagCatalog.unknownTags(in: "[] hi")
        #expect(result.isEmpty)
    }

    @Test func unknownTagsCorrectableIsNotUnknown() {
        let result = TagCatalog.unknownTags(in: "[excitd] go")
        #expect(result.isEmpty)
    }
}
