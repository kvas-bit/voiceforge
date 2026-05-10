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

/// Summary returned by `HistoryStore.migrateLegacyEntries(_:applicationSupport:fileManager:)`.
/// Useful for logging and for unit tests.
public struct HistoryMigrationSummary: Equatable, Sendable {
    public var relocated: Int
    public var dropped: Int
    public var unchanged: Int
}

extension HistoryStore {
    /// One-time migration that brings legacy history entries onto the per-uuid
    /// `<App Support>/VoiceForge/outputs/<id>.wav` layout.
    ///
    /// Behaviour per entry:
    /// - If `outputPath` already matches the canonical per-uuid URL: keep as-is
    ///   when the file still exists, drop if the file is gone.
    /// - If `outputPath` is a legacy path and the file on disk exists: copy it
    ///   to the canonical URL (creating the directory if needed) and rewrite
    ///   the entry's `outputPath`. Two entries that happened to share the same
    ///   legacy path both get their own canonical copy, so neither plays the
    ///   other's audio anymore.
    /// - If the legacy file is missing or the copy fails: drop the entry.
    ///
    /// Pass `applicationSupport` in tests to avoid touching the real folder.
    public static func migrateLegacyEntries(
        _ items: [GenerationHistoryItem],
        applicationSupport: URL? = nil,
        fileManager: FileManager = .default
    ) -> (items: [GenerationHistoryItem], summary: HistoryMigrationSummary) {
        let service = SpeechGenerationService()
        var result: [GenerationHistoryItem] = []
        var relocated = 0
        var dropped = 0
        var unchanged = 0

        for item in items {
            guard let canonical = try? service.outputURL(forID: item.id, applicationSupport: applicationSupport) else {
                dropped += 1
                continue
            }

            if item.outputPath == canonical.path {
                if fileManager.fileExists(atPath: canonical.path) {
                    result.append(item)
                    unchanged += 1
                } else {
                    dropped += 1
                }
                continue
            }

            let source = URL(fileURLWithPath: item.outputPath)
            guard fileManager.fileExists(atPath: source.path) else {
                dropped += 1
                continue
            }

            do {
                try fileManager.createDirectory(
                    at: canonical.deletingLastPathComponent(),
                    withIntermediateDirectories: true
                )
                if !fileManager.fileExists(atPath: canonical.path) {
                    try fileManager.copyItem(at: source, to: canonical)
                }
                result.append(item.withOutputPath(canonical.path))
                relocated += 1
            } catch {
                dropped += 1
            }
        }

        return (result, HistoryMigrationSummary(relocated: relocated, dropped: dropped, unchanged: unchanged))
    }
}
