import Foundation

/// A voice configuration bound to a speaker key (normalized speaker name).
public struct SpeakerVoiceBinding: Equatable, Sendable, Codable {
    public var referenceAudioPath: String
    public var referenceText: String

    public init(referenceAudioPath: String, referenceText: String) {
        self.referenceAudioPath = referenceAudioPath
        self.referenceText = referenceText
    }
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

    public init(
        id: UUID = UUID(),
        text: String,
        referenceAudioPath: String,
        referenceText: String,
        outputPath: String? = nil,
        status: ConversationLineStatus = .pending,
        speakerKey: String? = nil
    ) {
        self.id = id
        self.text = text
        self.referenceAudioPath = referenceAudioPath
        self.referenceText = referenceText
        self.outputPath = outputPath
        self.status = status
        self.speakerKey = speakerKey
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

    public init(
        id: UUID = UUID(),
        createdAt: Date = Date(),
        name: String = "",
        lines: [ConversationLine],
        globalModel: String = "fish-s2-pro",
        globalMaxNewTokens: Int = 1500,
        globalEditType: String = "none"
    ) {
        self.id = id
        self.createdAt = createdAt
        self.name = name.isEmpty ? Self.autoName(from: lines) : name
        self.lines = lines
        self.globalModel = globalModel
        self.globalMaxNewTokens = globalMaxNewTokens
        self.globalEditType = globalEditType
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
