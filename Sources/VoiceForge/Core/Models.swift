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

public struct GenerationHistoryItem: Codable, Equatable, Identifiable, Sendable {
    public let id: UUID
    public let createdAt: Date
    public let sourceText: String
    public let formattedPrompt: String
    public let referenceAudioPath: String
    public let referenceText: String
    public let outputPath: String

    public init(
        id: UUID,
        createdAt: Date,
        sourceText: String,
        formattedPrompt: String,
        referenceAudioPath: String,
        referenceText: String,
        outputPath: String
    ) {
        self.id = id
        self.createdAt = createdAt
        self.sourceText = sourceText
        self.formattedPrompt = formattedPrompt
        self.referenceAudioPath = referenceAudioPath
        self.referenceText = referenceText
        self.outputPath = outputPath
    }
}

public struct GenerationRequest: Sendable {
    public let sourceText: String
    public let emotionText: String
    public let referenceAudioPath: String
    public let referenceText: String

    public init(sourceText: String, emotionText: String, referenceAudioPath: String, referenceText: String) {
        self.sourceText = sourceText
        self.emotionText = emotionText
        self.referenceAudioPath = referenceAudioPath
        self.referenceText = referenceText
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
