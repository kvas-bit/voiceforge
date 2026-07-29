import Foundation

public struct PromptFormatter: Sendable {
    private let aliasMap: [String: String]

    public init(aliasMap: [String: String] = TagCatalog.aliasMap) {
        self.aliasMap = aliasMap
    }

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
        let compact = TagCatalog.normalizeTagContent(raw)

        if compact.isEmpty {
            return ""
        }

        if let alias = aliasMap[compact] {
            return alias
        }
        // Typo correction: unique Levenshtein match within ≤ 2 edits.
        if let corrected = TagCatalog.correct(compact),
           let alias = aliasMap[corrected.label.lowercased()] {
            return alias
        }
        return compact
    }

    private func cleanSpacing(in text: String) -> String {
        text
            .replacingOccurrences(of: #"\s+\]"#, with: "]", options: .regularExpression)
            .replacingOccurrences(of: #"\[\s+"#, with: "[", options: .regularExpression)
            // Adjacent brackets with no gap: [a][b] → [a] [b]
            .replacingOccurrences(of: #"\]\["#, with: "] [", options: .regularExpression)
            .replacingOccurrences(of: #"\]\s+\["#, with: "] [", options: .regularExpression)
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
