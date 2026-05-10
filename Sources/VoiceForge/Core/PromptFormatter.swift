import Foundation

public struct PromptFormatter: Sendable {
    private let aliasMap: [String: String] = [
        "whisper": "whispering softly and quietly",
        "speaking softly": "speaking softly",
        "professional broadcast tone": "professional broadcast tone",
        "excited": "excited and energetic",
        "laugh": "laughing lightly",
        "sad": "sad and subdued",
        "angry": "angry and intense"
    ]

    public init() {}

    public func format(text: String, emotion: String) -> String {
        let normalizedText = normalizeAsteriskTags(in: text)
        var seen = Set<String>()
        var fragments: [String] = []

        let trimmedEmotion = normalizeTag(emotion)
        if !trimmedEmotion.isEmpty {
            fragments.append("[\(trimmedEmotion)]")
            seen.insert(trimmedEmotion)
        }

        fragments.append(rebuildInlineTags(in: normalizedText, seen: &seen))
        return cleanSpacing(in: fragments.joined(separator: " "))
    }

    private func normalizeAsteriskTags(in text: String) -> String {
        let pattern = #"\*([^*]+)\*"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return text
        }

        let range = NSRange(text.startIndex..., in: text)
        return regex.stringByReplacingMatches(
            in: text,
            options: [],
            range: range,
            withTemplate: "[$1]"
        )
    }

    private func rebuildInlineTags(in text: String, seen: inout Set<String>) -> String {
        let pattern = #"\[([^\]]+)\]"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return text
        }

        let nsRange = NSRange(text.startIndex..., in: text)
        let matches = regex.matches(in: text, options: [], range: nsRange)
        var rebuilt = ""
        var cursor = text.startIndex

        for match in matches {
            guard
                match.numberOfRanges > 1,
                let fullRange = Range(match.range(at: 0), in: text),
                let tagRange = Range(match.range(at: 1), in: text)
            else {
                continue
            }

            rebuilt += String(text[cursor..<fullRange.lowerBound])

            let normalized = normalizeTag(String(text[tagRange]))
            if !normalized.isEmpty && !seen.contains(normalized) {
                rebuilt += "[\(normalized)]"
                seen.insert(normalized)
            }

            cursor = fullRange.upperBound
        }

        rebuilt += String(text[cursor...])
        return rebuilt
    }

    private func normalizeTag(_ raw: String) -> String {
        let compact = raw
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)

        if compact.isEmpty {
            return ""
        }

        return aliasMap[compact] ?? compact
    }

    private func cleanSpacing(in text: String) -> String {
        text
            .replacingOccurrences(of: #"\s+\]"#, with: "]", options: .regularExpression)
            .replacingOccurrences(of: #"\[\s+"#, with: "[", options: .regularExpression)
            .replacingOccurrences(of: #"\]\s+\["#, with: "] [", options: .regularExpression)
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
