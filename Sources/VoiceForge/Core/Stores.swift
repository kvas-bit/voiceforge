import Foundation

public enum VoiceForgeStorageKeys {
    public static let referenceAudioPath = "voiceforge.referenceAudioPath"
    public static let referenceText = "voiceforge.referenceText"
    public static let emotionText = "voiceforge.emotionText"
    public static let voicePresets = "voiceforge.voicePresets"
    /// Off by default — local Ollama prompt intelligence is strictly opt-in.
    public static let ollamaEnabled = "voiceforge.ollamaEnabled"
    public static let selectedOllamaModel = "voiceforge.selectedOllamaModel"
    public static let selectedTTSModel = "voiceforge.selectedTTSModel"
    public static let drama3Settings = "voiceforge.drama3Settings"
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

    /// The VoiceForge directory that contains `history.json` and the `outputs/` folder.
    /// Every storage operation (load, save, recovery, migration, delete, clear) uses
    /// this root so a custom `fileURL` never reaches the real Application Support tree.
    var storageRoot: URL { fileURL.deletingLastPathComponent() }

    public init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
        let baseDirectory = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let appDirectory = baseDirectory.appendingPathComponent("VoiceForge", isDirectory: true)
        try? fileManager.createDirectory(at: appDirectory, withIntermediateDirectories: true)
        fileURL = appDirectory.appendingPathComponent("history.json")
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    }

    /// Construct a `HistoryStore` whose manifest and recovery root are pinned to the
    /// directory containing `fileURL`. The `outputs/` scan during load always uses
    /// `fileURL.deletingLastPathComponent()` as the VoiceForge root.
    public init(fileURL: URL, fileManager: FileManager = .default) {
        self.fileURL = fileURL
        self.fileManager = fileManager
        try? fileManager.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    }

    public func load() -> [GenerationHistoryItem] {
        guard let data = try? Data(contentsOf: fileURL) else {
            let recovered = Self.recoverEntriesFromDisk(
                existing: [],
                applicationSupport: storageRoot,
                fileManager: fileManager
            )
            if !recovered.isEmpty {
                save(recovered)
            }
            return recovered
        }
        if let decoded = try? decoder.decode([GenerationHistoryItem].self, from: data) {
            // A valid manifest is authoritative. Scanning outputs on every launch
            // can import abandoned, test, or partial files and silently rewrite
            // user history. Disk recovery remains available for a missing or
            // unreadable manifest and through recoverEntriesFromDisk itself.
            return decoded
        }

        let recovered = Self.recoverEntriesFromDisk(
            existing: [],
            applicationSupport: storageRoot,
            fileManager: fileManager
        )
        if !recovered.isEmpty {
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
            .resolvingSymlinksInPath().standardizedFileURL
        let root = storageRoot.resolvingSymlinksInPath().standardizedFileURL
        guard outputURL.path.hasPrefix(root.path + "/") else {
            // Outside storageRoot — refuse to remove.
            return
        }

        switch item.type {
        case .single:
            try? fileManager.removeItem(at: outputURL)
            removeCodesArtifact(item.codesPath, root: root)
        case .conversation:
            let bundleURL = outputURL.hasDirectoryPath ? outputURL : outputURL.deletingLastPathComponent()
            let bundleResolved = bundleURL.resolvingSymlinksInPath().standardizedFileURL
            // Require the bundle directory—not merely the manifest file—to be a
            // strict descendant of storageRoot.  If the manifest path is
            // <storageRoot>/conversation.json the bundle would equal storageRoot
            // itself, which must never be deleted.
            guard bundleResolved.path.hasPrefix(root.path + "/") else { return }
            try? fileManager.removeItem(at: bundleResolved)
            if let codesPath = item.codesPath {
                let codesURL = URL(fileURLWithPath: codesPath).resolvingSymlinksInPath().standardizedFileURL
                let sceneDir = codesURL.deletingLastPathComponent()
                if sceneDir.lastPathComponent.hasPrefix("scene-"), sceneDir.path.hasPrefix(root.path + "/") {
                    try? fileManager.removeItem(at: sceneDir)
                } else {
                    removeCodesArtifact(codesPath, root: root)
                }
            }
        }
    }

    private func removeCodesArtifact(_ path: String?, root: URL) {
        guard let path else { return }
        let url = URL(fileURLWithPath: path).resolvingSymlinksInPath().standardizedFileURL
        guard url.path.hasPrefix(root.path + "/"), url.pathExtension == "npy" else { return }
        try? fileManager.removeItem(at: url)
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
    /// Returns the canonical path (resolved symlinks + standardized) so that
    /// `/var/…` and `/private/var/…` (macOS alias spellings) compare equal.
    /// Used everywhere a path is compared, deduplicated, or used as a map key.
    private static func normalizedPath(_ path: String) -> String {
        URL(fileURLWithPath: path).resolvingSymlinksInPath().standardizedFileURL.path
    }

    /// Instance helper that pins canonical paths under the store's own
    /// `<storageRoot>/outputs/<id>.wav`. Delegates to the shared root-based
    /// implementation so the two code paths stay in sync.
    public func migrateLegacy(_ items: [GenerationHistoryItem]) -> (
        items: [GenerationHistoryItem], summary: HistoryMigrationSummary
    ) {
        return Self._migrate(
            items,
            voiceForgeRoot: storageRoot,
            fileManager: fileManager
        )
    }

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
                // Match by the manifest's own `id` — a per-conversation,
                // globally-unique identifier that's explicitly meant to
                // carry identity (astronomically unlikely to collide by
                // chance). Matching by `conversationLines` *content*
                // equality (the previous approach) is unsound: two distinct
                // conversations can legitimately have identical `lines`
                // (confirmed in production: repeated mock/test generations
                // produced conversations with equal line content), which
                // caused recovery to splice an unrelated on-disk manifest's
                // path onto an existing entry it had nothing to do with.
                let existingConversation = existing.first(where: {
                    $0.type == .conversation && $0.id == manifest.id
                })
                // Preserve the exact saved outputPath only when both paths
                // resolve to the same physical file — this keeps alias
                // spellings (/var vs /private/var) stable without repairing
                // stale entries that point at a WAV instead of the manifest.
                let preservedPath: String
                if let existingConv = existingConversation,
                   URL(fileURLWithPath: existingConv.outputPath).resolvingSymlinksInPath().standardizedFileURL
                    == url.resolvingSymlinksInPath().standardizedFileURL {
                    preservedPath = existingConv.outputPath
                } else {
                    preservedPath = url.path
                }
                let item = GenerationHistoryItem(
                    id: existingConversation?.id ?? manifest.id,
                    createdAt: existingConversation?.createdAt ?? manifest.createdAt,
                    name: existingConversation?.name.isEmpty == false ? existingConversation!.name : manifest.name,
                    sourceText: manifest.lines.map(\.text).joined(separator: "\n---\n"),
                    formattedPrompt: existingConversation?.formattedPrompt ?? "",
                    referenceAudioPath: manifest.lines.first?.referenceAudioPath ?? "",
                    referenceText: manifest.lines.first?.referenceText ?? "",
                    outputPath: preservedPath,
                    type: .conversation,
                    conversationLines: manifest.lines,
                    codesPath: existingConversation?.codesPath ?? manifest.sceneOutputPath.map {
                        URL(fileURLWithPath: $0).deletingLastPathComponent().appendingPathComponent("scene.npy").path
                    }
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

            // Match an existing single by UUID (normalizing paths so alias
            // spellings like /private/var/ vs /var/ don't miss).
            let normPath = normalizedPath(path)
            let existingSingle = existing.first(where: { item in
                item.type == .single && (
                    item.id == uuid ||
                    normalizedPath(item.outputPath) == normPath
                )
            })
            // Preserve the saved outputPath when the same physical file is found,
            // so a read-only recovery doesn't rewrite the manifest purely due to
            // alias spelling differences.
            let preservedOutputPath = existingSingle?.outputPath ?? path
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
                outputPath: preservedOutputPath,
                type: .single,
                conversationLines: nil
            )
            mergedByKey[historyKey(for: item)] = item
        }

        for item in existing where item.type == .single && recoveredConversationIDs.contains(item.id) {
            mergedByKey.removeValue(forKey: historyKey(for: item))
        }

        return mergedByKey.values.sorted {
            if $0.createdAt != $1.createdAt { return $0.createdAt > $1.createdAt }
            // Total-order tiebreaker on canonical paths, stable regardless of
            // dictionary enumeration or filesystem readdir order.
            return normalizedPath($0.outputPath) < normalizedPath($1.outputPath)
        }
    }

    private static func historyKey(for item: GenerationHistoryItem) -> String {
        switch item.type {
        case .single:
            return "single:\(normalizedPath(item.outputPath))"
        case .conversation:
            // Key by the conversation's own stable identity (its top-level
            // `id`, which recovery derives from the on-disk folder UUID),
            // never by `conversationLines` content — two distinct
            // conversations can have identical lines (confirmed in
            // production: repeated mock/test generations produced
            // conversations with equal line content and equal line ids),
            // which previously collapsed unrelated entries into one
            // dictionary slot and silently dropped one of them.
            return "conversation:\(item.id.uuidString)"
        }
    }

    /// One-time migration that brings legacy history entries onto the per-uuid
    /// `<VoiceForge>/outputs/<id>.wav` layout.
    ///
    /// When `item.outputPath` and the canonical URL resolve to the same file
    /// (e.g. `/var/…` vs `/private/var/…`) the entry is counted unchanged.
    ///
    /// Pass `applicationSupport` in tests to avoid touching the real folder.
    public static func migrateLegacyEntries(
        _ items: [GenerationHistoryItem],
        applicationSupport: URL? = nil,
        fileManager: FileManager = .default
    ) -> (items: [GenerationHistoryItem], summary: HistoryMigrationSummary) {
        let vfRoot = try? SpeechGenerationService.renderRootDirectory(applicationSupport: applicationSupport)
        return _migrate(items, voiceForgeRoot: vfRoot, fileManager: fileManager)
    }

    /// Root-based migration: canonical paths live under `<voiceForgeRoot>/outputs/<id>.wav`.
    /// Conversation entries are never relocated; singles with equal normalized paths
    /// are treated as unchanged.
    private static func _migrate(
        _ items: [GenerationHistoryItem],
        voiceForgeRoot: URL?,
        fileManager: FileManager
    ) -> (items: [GenerationHistoryItem], summary: HistoryMigrationSummary) {
        var result: [GenerationHistoryItem] = []
        var relocated = 0
        var dropped = 0
        var unchanged = 0

        for item in items {
            // Conversation items keep their existing outputPath (a JSON manifest);
            // they must never be canonicalized to a .wav path or copied as WAV.
            if item.type == .conversation {
                if fileManager.fileExists(atPath: item.outputPath) {
                    result.append(item)
                    unchanged += 1
                } else {
                    dropped += 1
                }
                continue
            }

            // Compute canonical .wav path under <voiceForgeRoot>/outputs/.
            guard let root = voiceForgeRoot else {
                dropped += 1
                continue
            }
            let canonical = root
                .appendingPathComponent("outputs", isDirectory: true)
                .appendingPathComponent("\(item.id.uuidString).wav")

            // Same physical file via different spelling? Count unchanged.
            let itemResolved = URL(fileURLWithPath: item.outputPath).resolvingSymlinksInPath().standardizedFileURL
            let canonicalResolved = canonical.resolvingSymlinksInPath().standardizedFileURL
            if itemResolved == canonicalResolved {
                if fileManager.fileExists(atPath: item.outputPath) {
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
