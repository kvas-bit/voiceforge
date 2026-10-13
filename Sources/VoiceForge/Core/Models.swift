import Foundation

public enum TTSModel: String, CaseIterable, Codable, Identifiable, Sendable {
    case drama3 = "drama-3"
    case fishS2Pro = "fish-s2-pro"
    public var id: String { rawValue }
    public var displayName: String {
        switch self { case .drama3: "Fish Audio Drama 3"; case .fishS2Pro: "Fish Audio S2 Pro" }
    }
}

public struct VoicePreset: Codable, Equatable, Identifiable, Sendable {
    public let id: UUID
    public var name: String
    public var referenceAudioPath: String
    public var referenceText: String
    public var additionalReferences: [VoiceReference]

    public init(
        id: UUID = UUID(),
        name: String,
        referenceAudioPath: String,
        referenceText: String,
        additionalReferences: [VoiceReference] = []
    ) {
        self.id = id
        self.name = name
        self.referenceAudioPath = referenceAudioPath
        self.referenceText = referenceText
        self.additionalReferences = additionalReferences
    }

    private enum CodingKeys: String, CodingKey { case id, name, referenceAudioPath, referenceText, additionalReferences }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        referenceAudioPath = try c.decode(String.self, forKey: .referenceAudioPath)
        referenceText = try c.decode(String.self, forKey: .referenceText)
        additionalReferences = try c.decodeIfPresent([VoiceReference].self, forKey: .additionalReferences) ?? []
    }
}

public struct VoiceReference: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    public var audioPath: String
    public var text: String
    public init(id: UUID = UUID(), audioPath: String, text: String) {
        self.id = id; self.audioPath = audioPath; self.text = text
    }
}

public struct Drama3Settings: Codable, Equatable, Sendable {
    public var temperature: Double
    public var topP: Double
    public var topK: Int
    public var seed: Int?
    public var normalize: Bool
    public var maxNewTokens: Int?
    public init(temperature: Double = 0.7, topP: Double = 0.7, topK: Int = 30,
                seed: Int? = nil, normalize: Bool = true, maxNewTokens: Int? = nil) {
        self.temperature = temperature; self.topP = topP; self.topK = topK
        self.seed = seed; self.normalize = normalize; self.maxNewTokens = maxNewTokens
    }
}

public struct ReferenceInspection: Sendable {
    public let duration: Double?
    public let sampleRate: Int?
    public let channels: Int?
    public let peak: Double?
    public let clippingRatio: Double?
    public let silenceRatio: Double?
    public let lufs: Double?
    public let warnings: [String]
    public init(duration: Double?, sampleRate: Int?, channels: Int?, peak: Double?, clippingRatio: Double?, silenceRatio: Double?, lufs: Double?, warnings: [String]) {
        self.duration = duration; self.sampleRate = sampleRate; self.channels = channels
        self.peak = peak; self.clippingRatio = clippingRatio; self.silenceRatio = silenceRatio
        self.lufs = lufs; self.warnings = warnings
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
    /// The `id` of the history entry this one was regenerated from, if any.
    /// Set when the user loads an existing generation into Studio, edits it,
    /// and generates again — the edit always produces a brand-new entry (the
    /// original is never mutated or deleted); this field is just the lean
    /// breadcrumb linking the new version back to its source.
    public let regeneratedFromID: UUID?
    public let model: String?
    public let codesPath: String?
    public let seed: Int?

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
        conversationLines: [ConversationLine]? = nil,
        regeneratedFromID: UUID? = nil,
        model: String? = nil, codesPath: String? = nil, seed: Int? = nil
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
        self.regeneratedFromID = regeneratedFromID
        self.model = model
        self.codesPath = codesPath; self.seed = seed
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
            conversationLines: conversationLines,
            regeneratedFromID: regeneratedFromID,
            model: model, codesPath: codesPath, seed: seed
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
        case id, createdAt, name, sourceText, formattedPrompt, referenceAudioPath, referenceText, outputPath, type, conversationLines, regeneratedFromID, model, codesPath, seed
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
        self.regeneratedFromID = try c.decodeIfPresent(UUID.self, forKey: .regeneratedFromID)
        self.model = try c.decodeIfPresent(String.self, forKey: .model)
        self.codesPath = try c.decodeIfPresent(String.self, forKey: .codesPath)
        self.seed = try c.decodeIfPresent(Int.self, forKey: .seed)
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
    public let references: [VoiceReference]
    public let drama3Settings: Drama3Settings
    public let previousTakes: [PreviousTake]
    public let saveCodesPath: String?

    public init(
        id: UUID = UUID(),
        sourceText: String,
        emotionText: String,
        referenceAudioPath: String,
        referenceText: String,
        model: String = TTSModel.default.rawValue,
        maxNewTokens: Int? = nil,
        editType: String? = nil,
        editInfo: String? = nil,
        references: [VoiceReference] = [], drama3Settings: Drama3Settings = Drama3Settings(),
        previousTakes: [PreviousTake] = [], saveCodesPath: String? = nil
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
        self.references = references
        self.drama3Settings = drama3Settings
        self.previousTakes = previousTakes
        self.saveCodesPath = saveCodesPath
    }
}

public struct PreviousTake: Codable, Equatable, Sendable {
    public var text: String
    public var codesPath: String
    public init(text: String, codesPath: String) { self.text = text; self.codesPath = codesPath }
    private enum CodingKeys: String, CodingKey { case text; case codesPath = "codes" }
}

public extension TTSModel {
    static let `default`: TTSModel = .drama3
}

public struct GenerationResult: Sendable {
    public let formattedPrompt: String
    public let outputURL: URL
    public let standardOutput: String
    public let standardError: String
    public let codesURL: URL?
    public let duration: Double?
    public let sampleRate: Int?

    public init(formattedPrompt: String, outputURL: URL, standardOutput: String, standardError: String,
                codesURL: URL? = nil, duration: Double? = nil, sampleRate: Int? = nil) {
        self.formattedPrompt = formattedPrompt
        self.outputURL = outputURL
        self.standardOutput = standardOutput
        self.standardError = standardError
        self.codesURL = codesURL; self.duration = duration; self.sampleRate = sampleRate
    }
}
