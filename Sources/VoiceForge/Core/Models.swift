import Foundation

public struct VoicePreset: Codable, Equatable, Identifiable, Sendable {
    public let id: UUID
    public var name: String
    public var referenceAudioPath: String
    public var referenceText: String

    public init(
        id: UUID = UUID(),
        name: String,
        referenceAudioPath: String,
        referenceText: String
    ) {
        self.id = id
        self.name = name
        self.referenceAudioPath = referenceAudioPath
        self.referenceText = referenceText
    }
}

public enum HistoryItemType: String, Codable, Sendable {
    case single
    case conversation
}

public struct GenerationHistoryItem: Codable, Equatable, Identifiable, Sendable {
    public let id: UUID
    public let createdAt: Date
    public var name: String
    public let sourceText: String
    public let formattedPrompt: String
    public let referenceAudioPath: String
    public let referenceText: String
    public let outputPath: String
    public let type: HistoryItemType
    public let conversationLines: [ConversationLine]?

    public init(
        id: UUID,
        createdAt: Date,
        name: String = "",
        sourceText: String,
        formattedPrompt: String,
        referenceAudioPath: String,
        referenceText: String,
        outputPath: String,
        type: HistoryItemType = .single,
        conversationLines: [ConversationLine]? = nil
    ) {
        self.id = id
        self.createdAt = createdAt
        self.name = name.isEmpty ? Self.autoName(from: sourceText) : name
        self.sourceText = sourceText
        self.formattedPrompt = formattedPrompt
        self.referenceAudioPath = referenceAudioPath
        self.referenceText = referenceText
        self.outputPath = outputPath
        self.type = type
        self.conversationLines = conversationLines
    }

    /// Returns a copy with a new `outputPath`. Used by the history migration
    /// path to relocate legacy entries from the old shared singleton file to
    /// their canonical per-uuid path.
    public func withOutputPath(_ newPath: String) -> GenerationHistoryItem {
        GenerationHistoryItem(
            id: id,
            createdAt: createdAt,
            name: name,
            sourceText: sourceText,
            formattedPrompt: formattedPrompt,
            referenceAudioPath: referenceAudioPath,
            referenceText: referenceText,
            outputPath: newPath,
            type: type,
            conversationLines: conversationLines
        )
    }

    /// Smart auto-name from prompt: strip [tags], trim, cap at 40 chars.
    public static func autoName(from sourceText: String, limit: Int = 40) -> String {
        let stripped = sourceText
            .replacingOccurrences(of: #"\[[^\]]*\]"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !stripped.isEmpty else { return "Untitled generation" }
        if stripped.count <= limit { return stripped }
        let idx = stripped.index(stripped.startIndex, offsetBy: limit)
        return String(stripped[..<idx]).trimmingCharacters(in: .whitespacesAndNewlines) + "…"
    }

    // Codable migration: pre-existing history JSON has no `name` field, so default to autoName.
    private enum CodingKeys: String, CodingKey {
        case id, createdAt, name, sourceText, formattedPrompt, referenceAudioPath, referenceText, outputPath, type, conversationLines
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try c.decode(UUID.self, forKey: .id)
        self.createdAt = try c.decode(Date.self, forKey: .createdAt)
        self.sourceText = try c.decode(String.self, forKey: .sourceText)
        self.formattedPrompt = try c.decode(String.self, forKey: .formattedPrompt)
        self.referenceAudioPath = try c.decode(String.self, forKey: .referenceAudioPath)
        self.referenceText = try c.decode(String.self, forKey: .referenceText)
        self.outputPath = try c.decode(String.self, forKey: .outputPath)
        let decodedName = try c.decodeIfPresent(String.self, forKey: .name) ?? ""
        self.name = decodedName.isEmpty ? Self.autoName(from: sourceText) : decodedName
        self.type = try c.decodeIfPresent(HistoryItemType.self, forKey: .type) ?? .single
        self.conversationLines = try c.decodeIfPresent([ConversationLine].self, forKey: .conversationLines)
    }
}

public struct GenerationRequest: Sendable {
    public let id: UUID
    public let sourceText: String
    public let emotionText: String
    public let referenceAudioPath: String
    public let referenceText: String
    public let model: String
    public let maxNewTokens: Int?
    public let editType: String?
    public let editInfo: String?

    public init(
        id: UUID = UUID(),
        sourceText: String,
        emotionText: String,
        referenceAudioPath: String,
        referenceText: String,
        model: String = "fish-s2-pro",
        maxNewTokens: Int? = nil,
        editType: String? = nil,
        editInfo: String? = nil
    ) {
        self.id = id
        self.sourceText = sourceText
        self.emotionText = emotionText
        self.referenceAudioPath = referenceAudioPath
        self.referenceText = referenceText
        self.model = model
        self.maxNewTokens = maxNewTokens
        self.editType = editType
        self.editInfo = editInfo
    }
}

public struct GenerationResult: Sendable {
    public let formattedPrompt: String
    public let outputURL: URL
    public let standardOutput: String
    public let standardError: String

    public init(formattedPrompt: String, outputURL: URL, standardOutput: String, standardError: String) {
        self.formattedPrompt = formattedPrompt
        self.outputURL = outputURL
        self.standardOutput = standardOutput
        self.standardError = standardError
    }
}
