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
}
