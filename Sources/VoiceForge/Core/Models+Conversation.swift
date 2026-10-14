import Foundation

/// A voice configuration bound to a speaker key (normalized speaker name).
public struct SpeakerVoiceBinding: Equatable, Sendable, Codable {
    public var referenceAudioPath: String
    public var referenceText: String
    public var additionalReferences: [VoiceReference]

    public init(referenceAudioPath: String, referenceText: String, additionalReferences: [VoiceReference] = []) {
        self.referenceAudioPath = referenceAudioPath
        self.referenceText = referenceText
        self.additionalReferences = additionalReferences
    }
}

public struct SceneSpeaker: Sendable {
    public var id: Int
    public var name: String
    public var description: String?
    public var references: [VoiceReference]
    public init(id: Int, name: String, description: String? = nil, references: [VoiceReference]) {
        self.id = id; self.name = name; self.description = description; self.references = references
    }
}

public struct SceneLine: Sendable {
    public var speaker: Int
    public var text: String
    public init(speaker: Int, text: String) { self.speaker = speaker; self.text = text }
}

public struct SceneGenerationResult: Sendable {
    public var outputURL: URL
    public var lineOutputURLs: [URL]
    public var lineTimes: [[Double]]?
    public var codesURL: URL?
}

public enum ConversationPresentation {
    public static func isPlaybackMode(
        modelIsInPlaybackMode: Bool,
        isEditingCompletedConversation: Bool
    ) -> Bool {
        modelIsInPlaybackMode && !isEditingCompletedConversation
    }
}

public enum ConversationLineStatus: String, Codable, Sendable {
    case pending, generating, completed, failed
}

public struct ConversationLine: Codable, Equatable, Identifiable, Sendable {
    public let id: UUID
    public var text: String
    public var referenceAudioPath: String
    public var referenceText: String
    public var outputPath: String?
    public var status: ConversationLineStatus
    /// Stable speaker key from script import. Nil for manually added lines.
    /// Populated by `ConversationScriptParser` segments; used by the voice-
    /// binding system to assign voices per speaker.
    public var speakerKey: String?
    public var additionalReferences: [VoiceReference]
    public var characterDescription: String?

    public init(
        id: UUID = UUID(),
        text: String,
        referenceAudioPath: String,
        referenceText: String,
        outputPath: String? = nil,
        status: ConversationLineStatus = .pending,
        speakerKey: String? = nil,
        additionalReferences: [VoiceReference] = [], characterDescription: String? = nil
    ) {
        self.id = id
        self.text = text
        self.referenceAudioPath = referenceAudioPath
        self.referenceText = referenceText
        self.outputPath = outputPath
        self.status = status
        self.speakerKey = speakerKey
        self.additionalReferences = additionalReferences; self.characterDescription = characterDescription
    }

    private enum CodingKeys: String, CodingKey { case id, text, referenceAudioPath, referenceText, outputPath, status, speakerKey, additionalReferences, characterDescription }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id); text = try c.decode(String.self, forKey: .text)
        referenceAudioPath = try c.decodeIfPresent(String.self, forKey: .referenceAudioPath) ?? ""
        referenceText = try c.decodeIfPresent(String.self, forKey: .referenceText) ?? ""
        outputPath = try c.decodeIfPresent(String.self, forKey: .outputPath)
        status = try c.decodeIfPresent(ConversationLineStatus.self, forKey: .status) ?? .pending
        speakerKey = try c.decodeIfPresent(String.self, forKey: .speakerKey)
        additionalReferences = try c.decodeIfPresent([VoiceReference].self, forKey: .additionalReferences) ?? []
        characterDescription = try c.decodeIfPresent(String.self, forKey: .characterDescription)
    }
}

public struct ConversationItem: Codable, Equatable, Identifiable, Sendable {
    public let id: UUID
    public let createdAt: Date
    public var name: String
    public var lines: [ConversationLine]
    public var globalModel: String
    public var globalMaxNewTokens: Int
    public var globalEditType: String
    public var sceneDirection: String
    public var sceneOutputPath: String?
    public var lineTimes: [[Double]]?

    public init(
        id: UUID = UUID(),
        createdAt: Date = Date(),
        name: String = "",
        lines: [ConversationLine],
        globalModel: String = TTSModel.default.rawValue,
        globalMaxNewTokens: Int = 1500,
        globalEditType: String = "none",
        sceneDirection: String = "", sceneOutputPath: String? = nil, lineTimes: [[Double]]? = nil
    ) {
        self.id = id
        self.createdAt = createdAt
        self.name = name.isEmpty ? Self.autoName(from: lines) : name
        self.lines = lines
        self.globalModel = globalModel
        self.globalMaxNewTokens = globalMaxNewTokens
        self.globalEditType = globalEditType
        self.sceneDirection = sceneDirection; self.sceneOutputPath = sceneOutputPath; self.lineTimes = lineTimes
    }

    private enum CodingKeys: String, CodingKey { case id, createdAt, name, lines, globalModel, globalMaxNewTokens, globalEditType, sceneDirection, sceneOutputPath, lineTimes }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        createdAt = try c.decode(Date.self, forKey: .createdAt)
        name = try c.decode(String.self, forKey: .name)
        lines = try c.decode([ConversationLine].self, forKey: .lines)
        globalModel = try c.decodeIfPresent(String.self, forKey: .globalModel) ?? TTSModel.fishS2Pro.rawValue
        globalMaxNewTokens = try c.decodeIfPresent(Int.self, forKey: .globalMaxNewTokens) ?? 1500
        globalEditType = try c.decodeIfPresent(String.self, forKey: .globalEditType) ?? "none"
        sceneDirection = try c.decodeIfPresent(String.self, forKey: .sceneDirection) ?? ""
        sceneOutputPath = try c.decodeIfPresent(String.self, forKey: .sceneOutputPath)
        lineTimes = try c.decodeIfPresent([[Double]].self, forKey: .lineTimes)
    }

    public static func autoName(from lines: [ConversationLine], limit: Int = 40) -> String {
        let first = lines.first?.text ?? "Conversation"
        let stripped = first
            .replacingOccurrences(of: #"\[[^\]]*\]"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !stripped.isEmpty else { return "Untitled conversation" }
        if stripped.count <= limit { return stripped }
        let idx = stripped.index(stripped.startIndex, offsetBy: limit)
        return String(stripped[..<idx]).trimmingCharacters(in: .whitespacesAndNewlines) + "…"
    }
}
