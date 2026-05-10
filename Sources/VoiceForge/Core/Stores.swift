import Foundation

public enum VoiceForgeStorageKeys {
    public static let referenceAudioPath = "voiceforge.referenceAudioPath"
    public static let referenceText = "voiceforge.referenceText"
    public static let emotionText = "voiceforge.emotionText"
    public static let voicePresets = "voiceforge.voicePresets"
}

public final class VoicePresetStore {
    private let defaults: UserDefaults
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    public func load() -> [VoicePreset] {
        guard let data = defaults.data(forKey: VoiceForgeStorageKeys.voicePresets) else {
            return []
        }

        return (try? decoder.decode([VoicePreset].self, from: data)) ?? []
    }

    public func save(_ presets: [VoicePreset]) {
        guard let data = try? encoder.encode(presets) else {
            return
        }
        defaults.set(data, forKey: VoiceForgeStorageKeys.voicePresets)
    }
}

public final class HistoryStore {
    private let fileURL: URL
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    public init(fileManager: FileManager = .default) {
        let baseDirectory = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let appDirectory = baseDirectory.appendingPathComponent("VoiceForge", isDirectory: true)
        try? fileManager.createDirectory(at: appDirectory, withIntermediateDirectories: true)
        fileURL = appDirectory.appendingPathComponent("history.json")
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    }

    public func load() -> [GenerationHistoryItem] {
        guard let data = try? Data(contentsOf: fileURL) else {
            return []
        }

        return (try? decoder.decode([GenerationHistoryItem].self, from: data)) ?? []
    }

    public func save(_ items: [GenerationHistoryItem]) {
        guard let data = try? encoder.encode(items) else {
            return
        }

        try? data.write(to: fileURL, options: .atomic)
    }
}
