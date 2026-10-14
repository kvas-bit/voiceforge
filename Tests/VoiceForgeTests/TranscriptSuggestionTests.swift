import Testing
#if canImport(VoiceForgeCore)
@testable import VoiceForgeCore
#else
@testable import VoiceForge
#endif

@Suite struct TranscriptSuggestionTests {
    @Test func suggestionFillsEmptyTranscript() {
        let suggestion = TranscriptSuggestion(text: "Whisper words", wordErrorRate: nil)
        #expect(suggestion.transcriptValue(preserving: "") == "Whisper words")
        #expect(suggestion.transcriptValue(preserving: "  \n") == "Whisper words")
    }

    @Test func suggestionPreservesTypedTranscriptAndReportsMismatch() {
        let typed = "My exact, carefully typed words."
        let suggestion = TranscriptSuggestion(text: "Whisper heard something else", wordErrorRate: 0.75)
        #expect(suggestion.transcriptValue(preserving: typed) == typed)
        #expect(suggestion.materiallyDifferent)
        #expect(!TranscriptSuggestion(text: "nearby", wordErrorRate: 0.2).materiallyDifferent)
    }

    @Test func minorWERShowsAlignedWordDifferencesWithoutChangingTypedText() {
        let typed = "Al sent the date on 1st June"
        let suggestion = TranscriptSuggestion(text: "AI sent the day on first June", wordErrorRate: 0.036)
        #expect(suggestion.hasPossibleDifferences)
        #expect(suggestion.differenceSummary(comparedTo: typed) == "Al → AI, date → day, 1st → first")
        #expect(suggestion.transcriptValue(preserving: typed) == typed)
        #expect(TranscriptSuggestion(text: "nearby", wordErrorRate: 0.3).hasPossibleDifferences)
        #expect(TranscriptSuggestion(text: "same", wordErrorRate: 0).differenceSummary(comparedTo: "same") == nil)
        #expect(TranscriptSuggestion(text: "far", wordErrorRate: 0.31).differenceSummary(comparedTo: "typed") == nil)
    }
}
