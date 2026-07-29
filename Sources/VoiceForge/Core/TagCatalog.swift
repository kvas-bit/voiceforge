import Foundation

public struct AudioTag: Hashable, Sendable, Identifiable {
    public let label: String
    public let alias: String?
    public let category: String

    public var id: String { label }

    public init(label: String, alias: String? = nil, category: String) {
        self.label = label
        self.alias = alias
        self.category = category
    }
}

public enum TagCatalog {
    /// Normalises tag content for lookup (lowercased, whitespace-collapsed, trimmed).
    public static func normalizeTagContent(_ raw: String) -> String {
        raw.trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
    }

    /// Returns the canonical alias for a normalized tag label, or nil if unknown.
    public static func alias(for label: String) -> String? {
        aliasMap[label]
    }

    /// Typo correction via Levenshtein distance ≤ 2, returning the single unique
    /// matching `AudioTag` when there is exactly one candidate within threshold.
    /// Returns nil for ambiguous, too-short (< 3 chars), or no-match inputs.
    public static func correct(_ query: String) -> AudioTag? {
        let q = normalizeTagContent(query)
        guard q.count >= 3 else { return nil }
        // Only correct queries that begin with a letter — punctuation-prefixed
        // content (e.g. inner `[` from double brackets) would produce false
        // positives by matching the underlying word.
        guard q.first?.isLetter == true else { return nil }
        // Exact match (fast path)
        if let exact = all.first(where: { $0.label.lowercased() == q }) { return exact }
        // Levenshtein distance ≤ 2, must be unique
        let candidates = all.filter { $0.label.lowercased().levenshtein(q) <= 2 }
        return candidates.count == 1 ? candidates.first! : nil
    }

    /// Returns the raw inner content of every `[...]` tag in `text` that is
    /// neither in the alias map nor correctable.  Asterisk-delimited tags are
    /// NOT expanded — callers should pass the compiled prompt if they want
    /// asterisk-style tags evaluated.
    public static func unknownTags(in text: String) -> [String] {
        let pattern = #"\[([^\]]+)\]"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let nsRange = NSRange(text.startIndex..., in: text)
        var result: [String] = []
        for match in regex.matches(in: text, options: [], range: nsRange) {
            guard match.numberOfRanges > 1,
                  let tagRange = Range(match.range(at: 1), in: text) else { continue }
            let raw = String(text[tagRange])
            let compact = normalizeTagContent(raw)
            if compact.isEmpty { continue }
            if aliasMap[compact] != nil { continue }
            if correct(compact) != nil { continue }
            result.append(raw)
        }
        return result
    }

    public static let all: [AudioTag] = [
        // Voice-related (vocal sounds)
        AudioTag(label: "whispers", alias: "whispering softly and quietly", category: "Voice"),
        AudioTag(label: "laughs", alias: "laughing lightly", category: "Voice"),
        AudioTag(label: "laughs harder", alias: "laughing harder", category: "Voice"),
        AudioTag(label: "starts laughing", alias: "starting to laugh", category: "Voice"),
        AudioTag(label: "wheezing", alias: "wheezing", category: "Voice"),
        AudioTag(label: "sighs", alias: "sighing", category: "Voice"),
        AudioTag(label: "exhales", alias: "exhaling", category: "Voice"),
        AudioTag(label: "snorts", alias: "snorting", category: "Voice"),
        AudioTag(label: "crying", alias: "crying softly", category: "Voice"),
        AudioTag(label: "gulps", alias: "gulping", category: "Voice"),
        AudioTag(label: "swallows", alias: "swallowing", category: "Voice"),
        AudioTag(label: "shouts", alias: "shouting", category: "Voice"),

        // Emotion
        AudioTag(label: "excited", alias: "excited and energetic", category: "Emotion"),
        AudioTag(label: "curious", alias: "curious", category: "Emotion"),
        AudioTag(label: "sad", alias: "sad and subdued", category: "Emotion"),
        AudioTag(label: "happy", alias: "happy and warm", category: "Emotion"),
        AudioTag(label: "angry", alias: "angry and intense", category: "Emotion"),
        AudioTag(label: "sarcastic", alias: "sarcastic", category: "Emotion"),
        AudioTag(label: "disappointed", alias: "disappointed", category: "Emotion"),
        AudioTag(label: "delighted", alias: "delighted", category: "Emotion"),
        AudioTag(label: "mischievously", alias: "mischievously", category: "Emotion"),

        // Delivery / style
        AudioTag(label: "whispering", alias: "whispering softly and quietly", category: "Delivery"),
        AudioTag(label: "shouting", alias: "shouting", category: "Delivery"),
        AudioTag(label: "narrating", alias: "narrating calmly", category: "Delivery"),
        AudioTag(label: "announcer voice", alias: "professional broadcast tone", category: "Delivery"),
        AudioTag(label: "dramatically", alias: "dramatically", category: "Delivery"),
        AudioTag(label: "deadpan", alias: "deadpan", category: "Delivery"),
        AudioTag(label: "hesitant", alias: "hesitant", category: "Delivery"),
        AudioTag(label: "stutters", alias: "stuttering slightly", category: "Delivery"),
        AudioTag(label: "speaking softly", alias: "speaking softly", category: "Delivery"),
        AudioTag(label: "professional broadcast tone", alias: "professional broadcast tone", category: "Delivery"),

        // Sound effects
        AudioTag(label: "applause", alias: "applause", category: "Sound effect"),
        AudioTag(label: "clapping", alias: "clapping", category: "Sound effect"),
        AudioTag(label: "gunshot", alias: "gunshot", category: "Sound effect"),
        AudioTag(label: "explosion", alias: "explosion", category: "Sound effect")
    ]

    public static let aliasMap: [String: String] = {
        var map: [String: String] = [:]
        for tag in all {
            if let alias = tag.alias {
                map[tag.label.lowercased()] = alias
            }
        }
        // Legacy short aliases (kept for backward compatibility with existing tests/history).
        map["whisper"] = "whispering softly and quietly"
        map["laugh"] = "laughing lightly"
        return map
    }()

    public static func suggestions(matching query: String, limit: Int = 8) -> [AudioTag] {
        let q = query.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return Array(all.prefix(limit)) }

        let scored: [(AudioTag, Int)] = all.compactMap { tag in
            let label = tag.label.lowercased()
            if label.hasPrefix(q) { return (tag, 0) }
            if label.contains(q) { return (tag, 1) }
            if let alias = tag.alias?.lowercased(), alias.contains(q) { return (tag, 2) }
            return nil
        }

        return scored
            .sorted { ($0.1, $0.0.label) < ($1.1, $1.0.label) }
            .prefix(limit)
            .map(\.0)
    }
}

// MARK: - Levenshtein distance (file-private, used by TagCatalog.correct)

private extension String {
    /// Classic Wagner–Fischer Levenshtein distance. Used for typo-tolerant
    /// tag matching inside `TagCatalog.correct(_:)`.
    func levenshtein(_ other: String) -> Int {
        let a = Array(self)
        let b = Array(other)
        var dist = [[Int]](repeating: [Int](repeating: 0, count: b.count + 1), count: a.count + 1)
        for i in 0...a.count { dist[i][0] = i }
        for j in 0...b.count { dist[0][j] = j }
        for i in 1...a.count {
            for j in 1...b.count {
                if a[i - 1] == b[j - 1] {
                    dist[i][j] = dist[i - 1][j - 1]
                } else {
                    dist[i][j] = Swift.min(dist[i - 1][j] + 1, dist[i][j - 1] + 1, dist[i - 1][j - 1] + 1)
                }
            }
        }
        return dist[a.count][b.count]
    }
}

/// A parsed segment of a prompt: either plain text or a `[tag]` token.
public enum TagSegment: Equatable, Sendable {
    case text(String)
    case tag(String)
}

public struct TagParser: Sendable {
    public init() {}

    /// Parses `Hello [whispers] world` into `[.text("Hello "), .tag("whispers"), .text(" world")]`.
    public func parse(_ input: String) -> [TagSegment] {
        var segments: [TagSegment] = []
        var buffer = ""
        var iterator = input.unicodeScalars.makeIterator()

        while let scalar = iterator.next() {
            if scalar == "[" {
                var tag = ""
                var closed = false
                while let next = iterator.next() {
                    if next == "]" {
                        closed = true
                        break
                    }
                    tag.unicodeScalars.append(next)
                }
                if closed {
                    if !buffer.isEmpty {
                        segments.append(.text(buffer))
                        buffer = ""
                    }
                    segments.append(.tag(tag))
                } else {
                    buffer.append("[")
                    buffer.append(tag)
                }
            } else {
                buffer.unicodeScalars.append(scalar)
            }
        }
        if !buffer.isEmpty {
            segments.append(.text(buffer))
        }
        return segments
    }

    public func render(_ segments: [TagSegment]) -> String {
        segments.map { segment in
            switch segment {
            case .text(let value): return value
            case .tag(let name): return "[\(name)]"
            }
        }.joined()
    }
}
