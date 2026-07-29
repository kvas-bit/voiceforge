import Foundation
import Testing
#if canImport(VoiceForgeCore)
@testable import VoiceForgeCore
#else
@testable import VoiceForge
#endif

struct ConversationScriptParserTests {
    private let parser = ConversationScriptParser()

    // MARK: - Basic parsing

    @Test func parsesSingleSpeakerSingleLine() {
        let result = parser.parse("Alice: Hello world")
        #expect(result.segments.count == 1)
        #expect(result.segments[0].speaker == "Alice")
        #expect(result.segments[0].text == "Hello world")
        #expect(result.segments[0].speakerKey == "alice")
        #expect(result.segments[0].isContinuation == false)
        #expect(result.issues.isEmpty)
    }

    @Test func parsesMultipleSpeakers() {
        let script = """
        Alice: First line
        Bob: Second line
        """
        let result = parser.parse(script)
        #expect(result.segments.count == 2)
        #expect(result.segments[0].speaker == "Alice")
        #expect(result.segments[1].speaker == "Bob")
        #expect(result.speakerKeys == ["alice", "bob"])
        #expect(result.issues.isEmpty)
    }

    @Test func parsesSpeakerWithMultipleColonsInDialogue() {
        let result = parser.parse("Alice: Let's talk about: colons")
        #expect(result.segments.count == 1)
        #expect(result.segments[0].text == "Let's talk about: colons")
        #expect(result.issues.isEmpty)
    }

    // MARK: - Continuation lines

    @Test func continuationIndentedLine() {
        let script = """
        Alice: First part
          still Alice
        """
        let result = parser.parse(script)
        #expect(result.segments.count == 2)
        #expect(result.segments[0].text == "First part")
        #expect(result.segments[0].isContinuation == false)
        #expect(result.segments[1].text == "still Alice")
        #expect(result.segments[1].isContinuation == true)
        #expect(result.segments[1].speaker == "Alice")
        #expect(result.issues.isEmpty)
    }

    @Test func continuationNoColon() {
        let script = """
        Alice: First line
        continues here
        """
        let result = parser.parse(script)
        #expect(result.segments.count == 2)
        #expect(result.segments[0].text == "First line")
        #expect(result.segments[0].isContinuation == false)
        #expect(result.segments[1].text == "continues here")
        #expect(result.segments[1].isContinuation == true)
        #expect(result.segments[1].speaker == "Alice")
    }

    @Test func continuationMultipleLevels() {
        let script = """
        Alice: Start
          deeper
            deepest
        """
        let result = parser.parse(script)
        #expect(result.segments.count == 3)
        #expect(result.segments[0].text == "Start")
        #expect(result.segments[0].isContinuation == false)
        #expect(result.segments[1].text == "deeper")
        #expect(result.segments[1].isContinuation == true)
        #expect(result.segments[2].text == "deepest")
        #expect(result.segments[2].isContinuation == true)
        #expect(result.segments[1].speakerKey == "alice")
        #expect(result.segments[2].speakerKey == "alice")
    }

    // MARK: - Blank lines reset continuation

    @Test func blankLineResetsContinuation() {
        let script = """
        Alice: First

        Bob: Second
        """
        let result = parser.parse(script)
        #expect(result.segments.count == 2)
        #expect(result.segments[0].speaker == "Alice")
        #expect(result.segments[1].speaker == "Bob")
    }

    @Test func blankLinePreventsIndentedContinuation() {
        let script = """
        Alice: First

          orphan line
        """
        let result = parser.parse(script)
        #expect(result.segments.count == 2)
        #expect(result.segments[0].speaker == "Alice")
        #expect(result.segments[1].speakerKey == "__unattributed__")
        #expect(result.segments[1].text == "orphan line")
    }

    // MARK: - Validation issues

    @Test func missingSpeakerDetected() {
        let result = parser.parse(": dialogue with no speaker")
        #expect(result.issues.count == 1)
        #expect(result.issues[0].kind == .missingSpeaker)
        #expect(result.issues[0].lineNumber == 1)
        // Falls back to unattributed segment.
        #expect(result.segments.count == 1)
        #expect(result.segments[0].speakerKey == "__unattributed__")
    }

    @Test func missingDialogueDetected() {
        let result = parser.parse("Alice:")
        #expect(result.issues.count == 1)
        #expect(result.issues[0].kind == .missingDialogue)
        #expect(result.issues[0].lineNumber == 1)
        // Segment is still produced with empty text.
        #expect(result.segments.count == 1)
        #expect(result.segments[0].speaker == "Alice")
        #expect(result.segments[0].text == "")
    }

    @Test func missingDialogueWithWhitespaceAfterColon() {
        let result = parser.parse("Alice:   ")
        #expect(result.issues.count == 1)
        #expect(result.issues[0].kind == .missingDialogue)
        #expect(result.segments[0].text == "")
    }

    // MARK: - Speaker name normalization

    @Test func normalizeSpeakerCollapsesWhitespace() {
        #expect(ConversationScriptParser.normalizeSpeakerName("  Dr.  Smith  ") == "dr. smith")
    }

    @Test func normalizeSpeakerLowercases() {
        #expect(ConversationScriptParser.normalizeSpeakerName("ALICE") == "alice")
    }

    @Test func sameSpeakerDifferentCasingMapsToSameKey() {
        let script = """
        Narrator: Hello
        NARRATOR: Still me
        """
        let result = parser.parse(script)
        #expect(result.segments.count == 2)
        #expect(result.segments[0].speaker == "Narrator")
        // Second occurrence keeps first display name.
        #expect(result.segments[1].speaker == "Narrator")
        #expect(result.segments[0].speakerKey == "narrator")
        #expect(result.segments[1].speakerKey == "narrator")
        #expect(result.speakerKeys.count == 1)
    }

    // MARK: - Round-trip

    @Test func roundTripProducesIdenticalSegments() {
        let script = """
        Alice: Hello there
          how are you?

        Bob: I am fine
        Charlie: Great
        """
        let first = parser.parse(script)
        let rendered = parser.render(first.segments)
        let second = parser.parse(rendered)
        #expect(first.segments == second.segments)
        #expect(first.speakerKeys == second.speakerKeys)
    }

    @Test func roundTripEmptyScript() {
        let result = parser.parse("")
        #expect(result.segments.isEmpty)
        #expect(result.issues.isEmpty)
        #expect(result.speakerKeys.isEmpty)
        // Render empty → parse empty.
        let rendered = parser.render(result.segments)
        let second = parser.parse(rendered)
        #expect(second.segments.isEmpty)
    }

    @Test func preservesInlineTagsInDialogue() {
        let result = parser.parse("Alice: Hello [whispers] world")
        #expect(result.segments.count == 1)
        #expect(result.segments[0].text == "Hello [whispers] world")
        #expect(result.segments[0].speaker == "Alice")
    }

    @Test func preservesTagsAcrossContinuations() {
        let script = """
        Alice: Start [whispers]
          still [laughs]
        """
        let result = parser.parse(script)
        #expect(result.segments.count == 2)
        #expect(result.segments[0].text == "Start [whispers]")
        #expect(result.segments[1].text == "still [laughs]")
        #expect(result.segments[1].isContinuation == true)
    }

    // MARK: - Edge cases

    @Test func unattributedFirstLineNoColon() {
        let result = parser.parse("just some text")
        #expect(result.segments.count == 1)
        #expect(result.segments[0].speakerKey == "__unattributed__")
        #expect(result.segments[0].text == "just some text")
    }

    @Test func multipleBlankLinesAreSkipped() {
        let script = """
        Alice: first



        Bob: second
        """
        let result = parser.parse(script)
        #expect(result.segments.count == 2)
        #expect(result.issues.isEmpty)
    }

    @Test func speakerNameWithPeriodAndTitle() {
        let result = parser.parse("Dr. Smith, PhD: Welcome")
        #expect(result.segments[0].speaker == "Dr. Smith, PhD")
        #expect(result.segments[0].speakerKey == "dr. smith, phd")
    }

    @Test func makeConversationLinesProducesExpectedCount() {
        let script = """
        Alice: Line one
        Bob: Line two
        """
        let result = parser.parse(script)
        let lines = parser.makeConversationLines(from: result.segments)
        #expect(lines.count == 2)
        #expect(lines[0].text == "Line one")
        #expect(lines[1].text == "Line two")
        // Voice fields are empty — caller assigns them.
        #expect(lines[0].referenceAudioPath == "")
        #expect(lines[0].referenceText == "")
        #expect(lines[0].status == .pending)
    }

    @Test func makeConversationLinesMergesContinuations() {
        let script = """
        Alice: Start
          continuation
        Bob: New turn
        """
        let result = parser.parse(script)
        let lines = parser.makeConversationLines(from: result.segments)
        #expect(lines.count == 2)
        #expect(lines[0].text == "Start\ncontinuation")
        #expect(lines[1].text == "New turn")
    }

    @Test func renderThenParsePreservesSpeakerOrder() {
        let script = """
        Zed: Last
        Alpha: First
        """
        let first = parser.parse(script)
        let rendered = parser.render(first.segments)
        let second = parser.parse(rendered)
        #expect(second.speakerKeys == first.speakerKeys)
        #expect(second.speakerKeys == ["zed", "alpha"])
    }

    @Test func unattributedAfterBlankLineFollowedByIndented() {
        // Blank line, then an indented line with no prior speaker.
        let result = parser.parse("\n  orphan")
        #expect(result.segments.count == 1)
        #expect(result.segments[0].speakerKey == "__unattributed__")
        #expect(result.segments[0].text == "orphan")
    }

    @Test func speakerKeyStableAcrossMultipleScripts() {
        let a = parser.parse("Narrator: Hello")
        let b = parser.parse("narrator: Hello")
        #expect(a.segments[0].speakerKey == b.segments[0].speakerKey)
        #expect(a.segments[0].speakerKey == "narrator")
    }
}
