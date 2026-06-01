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
    private let fileManager: FileManager
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    public init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
        let baseDirectory = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let appDirectory = baseDirectory.appendingPathComponent("VoiceForge", isDirectory: true)
        try? fileManager.createDirectory(at: appDirectory, withIntermediateDirectories: true)
        fileURL = appDirectory.appendingPathComponent("history.json")
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    }

    public init(fileURL: URL, fileManager: FileManager = .default) {
        self.fileURL = fileURL
        self.fileManager = fileManager
        try? fileManager.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    }

    public func load() -> [GenerationHistoryItem] {
        guard let data = try? Data(contentsOf: fileURL) else {
            let recovered = Self.recoverEntriesFromDisk(existing: [], fileManager: fileManager)
            if !recovered.isEmpty {
                save(recovered)
            }
            return recovered
        }
        let decoded = (try? decoder.decode([GenerationHistoryItem].self, from: data)) ?? []
        let recovered = Self.recoverEntriesFromDisk(existing: decoded, fileManager: fileManager)
        if recovered != decoded {
            save(recovered)
        }
        return recovered
    }

    public func save(_ items: [GenerationHistoryItem]) {
        guard let data = try? encoder.encode(items) else {
            return
        }

        try? data.write(to: fileURL, options: .atomic)
    }

    public func delete(_ item: GenerationHistoryItem, from items: [GenerationHistoryItem]) -> [GenerationHistoryItem] {
        removeArtifacts(for: item)
        let updated = items.filter { $0.id != item.id }
        save(updated)
        return updated
    }

    public func clear(_ items: [GenerationHistoryItem]) {
        for item in items {
            removeArtifacts(for: item)
        }
        save([])
    }

    private func removeArtifacts(for item: GenerationHistoryItem) {
        let outputURL = URL(fileURLWithPath: item.outputPath)

        switch item.type {
        case .single:
            try? fileManager.removeItem(at: outputURL)
        case .conversation:
            let bundleURL = outputURL.hasDirectoryPath ? outputURL : outputURL.deletingLastPathComponent()
            try? fileManager.removeItem(at: bundleURL)
        }
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
    /// Rebuilds history entries from on-disk outputs when `history.json` is
    /// missing or incomplete. This keeps the History screen usable even if the
    /// manifest was truncated or overwritten.
    public static func recoverEntriesFromDisk(
        existing: [GenerationHistoryItem],
        applicationSupport: URL? = nil,
        fileManager: FileManager = .default
    ) -> [GenerationHistoryItem] {
        let resolvedAppSupport = applicationSupport ??
            fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appendingPathComponent("VoiceForge", isDirectory: true)
        guard let appSupport = resolvedAppSupport else {
            return existing
        }

        let outputsURL = appSupport.appendingPathComponent("outputs", isDirectory: true)
        let normalizedOutputsURL = outputsURL.resolvingSymlinksInPath().standardizedFileURL
        guard let enumerator = fileManager.enumerator(
            at: outputsURL,
            includingPropertiesForKeys: [.isRegularFileKey, .contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else {
            return existing
        }

        var mergedByKey: [String: GenerationHistoryItem] = [:]
        var recoveredConversationIDs = Set(existing.lazy.filter { $0.type == .conversation }.map(\.id))
        for item in existing {
            mergedByKey[historyKey(for: item)] = item
        }

        let jsonDecoder = JSONDecoder()
        for case let url as URL in enumerator {
            let path = url.path

            if path.hasSuffix("/conversation.json"),
               let data = try? Data(contentsOf: url),
               let manifest = try? jsonDecoder.decode(ConversationItem.self, from: data) {
                let existingConversation = existing.first(where: {
                    $0.type == .conversation && $0.conversationLines == manifest.lines
                })
                let item = GenerationHistoryItem(
                    id: existingConversation?.id ?? manifest.id,
                    createdAt: existingConversation?.createdAt ?? manifest.createdAt,
                    name: existingConversation?.name.isEmpty == false ? existingConversation!.name : manifest.name,
                    sourceText: manifest.lines.map(\.text).joined(separator: "\n---\n"),
                    formattedPrompt: existingConversation?.formattedPrompt ?? "",
                    referenceAudioPath: manifest.lines.first?.referenceAudioPath ?? "",
                    referenceText: manifest.lines.first?.referenceText ?? "",
                    outputPath: url.path,
                    type: .conversation,
                    conversationLines: manifest.lines
                )
                recoveredConversationIDs.insert(item.id)
                mergedByKey[historyKey(for: item)] = item
                continue
            }

            guard path.hasSuffix(".wav"),
                  url.deletingLastPathComponent().resolvingSymlinksInPath().standardizedFileURL == normalizedOutputsURL,
                  let uuid = UUID(uuidString: url.deletingPathExtension().lastPathComponent) else {
                continue
            }

            if recoveredConversationIDs.contains(uuid) {
                continue
            }

            let existingSingle = existing.first(where: { $0.type == .single && ($0.id == uuid || $0.outputPath == path) })
            let values = try? url.resourceValues(forKeys: [.contentModificationDateKey])
            let createdAt = existingSingle?.createdAt ?? values?.contentModificationDate ?? Date()
            let fallbackText = "Recovered generation"
            let item = GenerationHistoryItem(
                id: existingSingle?.id ?? uuid,
                createdAt: createdAt,
                name: existingSingle?.name ?? fallbackText,
                sourceText: existingSingle?.sourceText ?? fallbackText,
                formattedPrompt: existingSingle?.formattedPrompt ?? "",
                referenceAudioPath: existingSingle?.referenceAudioPath ?? "",
                referenceText: existingSingle?.referenceText ?? "",
                outputPath: path,
                type: .single,
                conversationLines: nil
            )
            mergedByKey[historyKey(for: item)] = item
        }

        for item in existing where item.type == .single && recoveredConversationIDs.contains(item.id) {
            mergedByKey.removeValue(forKey: historyKey(for: item))
        }

        return mergedByKey.values.sorted(by: { $0.createdAt > $1.createdAt })
    }

    private static func historyKey(for item: GenerationHistoryItem) -> String {
        switch item.type {
        case .single:
            return "single:\(item.outputPath)"
        case .conversation:
            if let lines = item.conversationLines {
                return "conversation:\(lines.map(\.id.uuidString).joined(separator: ","))"
            }
            return "conversation:\(item.outputPath)"
        }
    }

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
