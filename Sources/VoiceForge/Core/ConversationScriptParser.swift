import Foundation

// MARK: - Public types

/// A single parsed segment from a multi-voice script.
public struct ScriptSegment: Equatable, Sendable {
    /// 1-based line number in the source script.
    public let lineNumber: Int
    /// Display speaker name (first-used casing from the script).
    public let speaker: String
    /// Stable normalized key for grouping lines by speaker.
    /// Lowercased, whitespace-collapsed. Same physical speaker always produces the same key.
    public let speakerKey: String
    /// Dialogue text (may contain inline `[tags]`).
    public let text: String
    /// Whether this segment was produced by a continuation line (indented or no-colon).
    /// Continuation segments share the speaker of the preceding head segment.
    public let isContinuation: Bool

    public init(lineNumber: Int, speaker: String, speakerKey: String, text: String, isContinuation: Bool) {
        self.lineNumber = lineNumber
        self.speaker = speaker
        self.speakerKey = speakerKey
        self.text = text
        self.isContinuation = isContinuation
    }
}

/// A validation issue found during script parsing.
public struct ScriptIssue: Equatable, Sendable {
    public enum Kind: String, Equatable, Sendable {
        /// Line starts with `: text` but no speaker name was given.
        case missingSpeaker
        /// Line is `Speaker:` with nothing after the colon.
        case missingDialogue
        /// (Set by the caller) No voice/preset is assigned for this speaker.
        case missingVoice
    }

    public let kind: Kind
    public let lineNumber: Int
    /// The raw line text that triggered the issue.
    public let lineText: String

    public init(kind: Kind, lineNumber: Int, lineText: String) {
        self.kind = kind
        self.lineNumber = lineNumber
        self.lineText = lineText
    }
}

/// The complete result of parsing a multi-voice script.
public struct ScriptParseResult: Equatable, Sendable {
    public let segments: [ScriptSegment]
    public let issues: [ScriptIssue]
    /// Ordered unique speaker keys in first-appearance order.
    public let speakerKeys: [String]
    /// Normalized key → first-used display name.
    public let speakerDisplay: [String: String]

    public init(segments: [ScriptSegment], issues: [ScriptIssue], speakerKeys: [String], speakerDisplay: [String: String]) {
        self.segments = segments
        self.issues = issues
        self.speakerKeys = speakerKeys
        self.speakerDisplay = speakerDisplay
    }
}

// MARK: - Parser

/// Parses pasteable multi-voice scripts in the format:
///
/// ```
/// Speaker Name: dialogue text
///   continuation under same speaker
///
/// Next Speaker: more dialogue
/// ```
///
/// - `Speaker Name:` at the start of a line sets the speaker.
/// - Continuation lines (no colon, or indented) are kept as separate segments
///   with `isContinuation: true` and the same speaker key as the preceding head.
/// - Blank lines separate utterances (reset continuation context).
/// - Inline `[tags]` are preserved verbatim in the segment text.
/// - The parser never mutates source text — it extracts structured segments.
public struct ConversationScriptParser: Sendable {
    public init() {}

    /// Parse a script string into structured segments and validation issues.
    public func parse(_ script: String) -> ScriptParseResult {
        let lines = splitLines(script)
        var segments: [ScriptSegment] = []
        var issues: [ScriptIssue] = []
        var speakerOrder: [String] = []
        var speakerDisplay: [String: String] = [:]
        var lastHeadSegment: ScriptSegment? = nil  // last non-continuation segment
        var blankSinceLastSegment = false

        for (index, rawLine) in lines.enumerated() {
            let lineNumber = index + 1
            let trimmed = rawLine.trimmingCharacters(in: .whitespaces)

            // Blank line: reset continuation context.
            guard !trimmed.isEmpty else {
                blankSinceLastSegment = true
                continue
            }

            let isIndented = !rawLine.isEmpty && rawLine.first?.isWhitespace == true

            // Continuation candidate: indented line OR line without a colon.
            if isIndented || !trimmed.contains(":") {
                if !blankSinceLastSegment, let head = lastHeadSegment {
                    // Keep as a separate continuation segment.
                    let seg = ScriptSegment(
                        lineNumber: lineNumber,
                        speaker: head.speaker,
                        speakerKey: head.speakerKey,
                        text: trimmed,
                        isContinuation: true
                    )
                    segments.append(seg)
                    blankSinceLastSegment = false
                    continue
                }
                // No preceding head segment or blank in between — unattributed.
                appendUnattributed(&segments, &speakerOrder, &speakerDisplay,
                                   lineNumber: lineNumber, text: trimmed,
                                   lastHeadSegment: &lastHeadSegment,
                                   blankSinceLastSegment: &blankSinceLastSegment)
                continue
            }

            // Line has a colon: extract `Speaker: dialogue`.
            guard let colonIndex = trimmed.firstIndex(of: ":") else {
                appendUnattributed(&segments, &speakerOrder, &speakerDisplay,
                                   lineNumber: lineNumber, text: trimmed,
                                   lastHeadSegment: &lastHeadSegment,
                                   blankSinceLastSegment: &blankSinceLastSegment)
                continue
            }

            let beforeColon = trimmed[..<colonIndex].trimmingCharacters(in: .whitespaces)
            let afterColon = trimmed[trimmed.index(after: colonIndex)...]
                .trimmingCharacters(in: .whitespaces)

            if beforeColon.isEmpty {
                // `: dialogue` — speaker name missing.
                issues.append(ScriptIssue(kind: .missingSpeaker, lineNumber: lineNumber, lineText: trimmed))
                appendUnattributed(&segments, &speakerOrder, &speakerDisplay,
                                   lineNumber: lineNumber, text: afterColon,
                                   lastHeadSegment: &lastHeadSegment,
                                   blankSinceLastSegment: &blankSinceLastSegment)
                continue
            }

            if afterColon.isEmpty {
                issues.append(ScriptIssue(kind: .missingDialogue, lineNumber: lineNumber, lineText: trimmed))
            }

            let speakerKey = Self.normalizeSpeakerName(String(beforeColon))

            if speakerDisplay[speakerKey] == nil {
                speakerDisplay[speakerKey] = String(beforeColon)
                speakerOrder.append(speakerKey)
            }

            let displayName = speakerDisplay[speakerKey] ?? String(beforeColon)
            let segment = ScriptSegment(
                lineNumber: lineNumber,
                speaker: displayName,
                speakerKey: speakerKey,
                text: afterColon,
                isContinuation: false
            )
            segments.append(segment)
            lastHeadSegment = segment
            blankSinceLastSegment = false
        }

        return ScriptParseResult(
            segments: segments,
            issues: issues,
            speakerKeys: speakerOrder,
            speakerDisplay: speakerDisplay
        )
    }

    /// Stable speaker key: lowercased, whitespace-collapsed, trimmed.
    public static func normalizeSpeakerName(_ name: String) -> String {
        name.trimmingCharacters(in: .whitespaces)
            .lowercased()
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
    }

    /// Render segments back to script format (deterministic round-trip).
    /// Continuation segments are indented with two spaces. A blank line is
    /// reinserted whenever a continuation is followed by a new head segment,
    /// since that's the only place `parse` treats a blank line as significant
    /// (it resets continuation context) — reproducing it exactly is required
    /// for `parse(render(segments)) == segments`, line numbers included.
    public func render(_ segments: [ScriptSegment]) -> String {
        var lines: [String] = []
        for (index, seg) in segments.enumerated() {
            if index > 0, segments[index - 1].isContinuation, !seg.isContinuation {
                lines.append("")
            }
            if seg.isContinuation {
                lines.append("  " + seg.text)
            } else {
                lines.append("\(seg.speaker): \(seg.text)")
            }
        }
        return lines.joined(separator: "\n")
    }

    /// Convert parsed segments into `ConversationLine` objects, merging
    /// continuations with their preceding head segment so each speaker turn
    /// becomes one line. Voice fields are left empty for the caller to fill.
    public func makeConversationLines(from segments: [ScriptSegment]) -> [ConversationLine] {
        var lines: [ConversationLine] = []
        var currentText = ""
        var currentSpeakerKey: String?
        for seg in segments {
            if seg.isContinuation {
                if !currentText.isEmpty { currentText += "\n" }
                currentText += seg.text
            } else {
                if !currentText.isEmpty {
                    lines.append(ConversationLine(
                        text: currentText, referenceAudioPath: "", referenceText: "",
                        speakerKey: currentSpeakerKey
                    ))
                }
                currentText = seg.text
                currentSpeakerKey = seg.speakerKey
            }
        }
        if !currentText.isEmpty {
            lines.append(ConversationLine(
                text: currentText, referenceAudioPath: "", referenceText: "",
                speakerKey: currentSpeakerKey
            ))
        }
        return lines
    }

    // MARK: - Private

    private func splitLines(_ text: String) -> [String] {
        text.components(separatedBy: .newlines)
    }

    private func appendUnattributed(
        _ segments: inout [ScriptSegment],
        _ speakerOrder: inout [String],
        _ speakerDisplay: inout [String: String],
        lineNumber: Int,
        text: String,
        lastHeadSegment: inout ScriptSegment?,
        blankSinceLastSegment: inout Bool
    ) {
        let key = "__unattributed__"
        if speakerDisplay[key] == nil {
            speakerDisplay[key] = "(unattributed)"
            speakerOrder.append(key)
        }
        let segment = ScriptSegment(
            lineNumber: lineNumber,
            speaker: "(unattributed)",
            speakerKey: key,
            text: text,
            isContinuation: false
        )
        segments.append(segment)
        lastHeadSegment = segment
        blankSinceLastSegment = false
    }
}
