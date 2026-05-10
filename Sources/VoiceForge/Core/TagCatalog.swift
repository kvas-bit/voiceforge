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
