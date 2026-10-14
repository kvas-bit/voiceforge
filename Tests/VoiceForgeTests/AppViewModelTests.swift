import Foundation
import Testing
#if canImport(VoiceForgeCore)
@testable import VoiceForgeCore
#endif
@testable import VoiceForge

@MainActor
struct AppViewModelTests {
    @Test func ttsModelDefaultsToDrama3AndPersistsSelection() throws {
        let suite = "VoiceForge-model-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let (store, cleanup) = try makeIsolatedHistoryStore()
        defer { cleanup() }
        let viewModel = AppViewModel(defaults: defaults, historyStore: store)
        #expect(TTSModel.default == .drama3)
        #expect(viewModel.selectedTTSModel == "drama-3")
        viewModel.selectedTTSModel = TTSModel.fishS2Pro.rawValue
        #expect(defaults.string(forKey: VoiceForgeStorageKeys.selectedTTSModel) == "fish-s2-pro")
    }

    @Test func drama3SettingsPersistAcrossViewModels() throws {
        let suite = "VoiceForge-drama-settings-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let (store, cleanup) = try makeIsolatedHistoryStore()
        defer { cleanup() }
        let first = AppViewModel(defaults: defaults, historyStore: store)
        #expect(first.drama3Temperature == 0.7)
        #expect(first.drama3TopP == 0.7)
        #expect(first.drama3TopK == 30)
        #expect(first.drama3Normalize)
        first.drama3Temperature = 0.9
        first.drama3TopP = 0.85
        first.drama3TopK = 24
        first.drama3Seed = "1234"
        first.drama3Normalize = false
        first.drama3AutoTokenBudget = false
        first.maxNewTokens = 2240
        let restored = AppViewModel(defaults: defaults, historyStore: store)
        #expect(restored.drama3Settings == Drama3Settings(temperature: 0.9, topP: 0.85, topK: 24, seed: 1234, normalize: false, maxNewTokens: 2240))
    }

    @Test func drama3ModelVariantPersistsAcrossViewModels() throws {
        let suite = "VoiceForge-drama-variant-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let (store, cleanup) = try makeIsolatedHistoryStore()
        defer { cleanup() }
        let service = SpeechGenerationService.__internalInit(executableURL: nil, renderRoot: nil, fileManager: .default,
            runner: { _, _, _ in ("", "", 0) }, usePersistent: false)
        let first = AppViewModel(defaults: defaults, historyStore: store, generationService: service)
        #expect(first.drama3ModelVariant == .standardQ4)
        first.selectDrama3ModelVariant(.highFidelityQ5)
        #expect(defaults.string(forKey: VoiceForgeStorageKeys.drama3ModelVariant) == "q5")
        let restored = AppViewModel(defaults: defaults, historyStore: store, generationService: service)
        #expect(restored.drama3ModelVariant == .highFidelityQ5)
        #expect(restored.drama3ModelVariant.checkpointDirectory.hasSuffix("/models/drama-3-q5"))
    }

    @Test func previewUsesSelectedModelFormatter() throws {
        let suite = "VoiceForge-preview-model-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let (store, cleanup) = try makeIsolatedHistoryStore()
        defer { cleanup() }
        let viewModel = AppViewModel(defaults: defaults, historyStore: store)
        viewModel.sourceText = "*soft* line\n[line]"
        viewModel.emotionText = "Whisper"
        #expect(viewModel.formattedPreview == "*soft* line\n[line]")
        viewModel.selectedTTSModel = TTSModel.fishS2Pro.rawValue
        #expect(viewModel.formattedPreview == "[whispering softly and quietly] [soft] line [line]")
    }

    @Test func completedConversationCanEnterEditingPresentationWithoutChangingPlaybackData() {
        #expect(ConversationPresentation.isPlaybackMode(
            modelIsInPlaybackMode: true,
            isEditingCompletedConversation: false
        ))
        #expect(!ConversationPresentation.isPlaybackMode(
            modelIsInPlaybackMode: true,
            isEditingCompletedConversation: true
        ))
        #expect(!ConversationPresentation.isPlaybackMode(
            modelIsInPlaybackMode: false,
            isEditingCompletedConversation: false
        ))
    }

    @Test func loadingHistoryClearsStaleValidationError() throws {
        let suiteName = "VoiceForgeAppViewModelTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let (store, cleanup) = try makeIsolatedHistoryStore()
        defer { cleanup() }

        let viewModel = AppViewModel(defaults: defaults, historyStore: store)
        viewModel.generationError = "Enter text to generate."

        let item = GenerationHistoryItem(
            id: UUID(uuidString: "11111111-2222-3333-4444-555555555555")!,
            createdAt: Date(timeIntervalSince1970: 1_700_000_100),
            sourceText: "Recovered script",
            formattedPrompt: "[whispering softly and quietly] Recovered script",
            referenceAudioPath: "/tmp/reference.wav",
            referenceText: "Recovered transcript",
            outputPath: "/tmp/recovered.wav"
        )

        viewModel.loadHistory(item)

        #expect(viewModel.generationError.isEmpty)
        #expect(viewModel.sourceText == "Recovered script")
        #expect(viewModel.referenceAudioPath == "/tmp/reference.wav")
        #expect(viewModel.referenceText == "Recovered transcript")
    }

    @Test func togglePlayHistoryResolvesItemSpecificURL() throws {
        let suiteName = "VoiceForgeAppViewModelTests-history-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let (store, cleanup) = try makeIsolatedHistoryStore()
        defer { cleanup() }

        let viewModel = AppViewModel(defaults: defaults, historyStore: store)
        let dir = makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }

        let urlA = dir.appendingPathComponent("a.wav")
        let urlB = dir.appendingPathComponent("b.wav")
        try writeSilentWAV(to: urlA)
        try writeSilentWAV(to: urlB)

        let itemA = GenerationHistoryItem(
            id: UUID(), createdAt: Date(), name: "A",
            sourceText: "a", formattedPrompt: "a",
            referenceAudioPath: "/tmp/r.wav", referenceText: "r",
            outputPath: urlA.path
        )
        let itemB = GenerationHistoryItem(
            id: UUID(), createdAt: Date(), name: "B",
            sourceText: "b", formattedPrompt: "b",
            referenceAudioPath: "/tmp/r.wav", referenceText: "r",
            outputPath: urlB.path
        )

        // Toggling item A loads item A — not the last-known output URL.
        viewModel.togglePlayHistory(itemA)
        #expect(viewModel.audioPlayer.currentURL == urlA)
        #expect(viewModel.lastOutputURL == urlA)

        // Toggling item B must swap the player to B's URL, proving each history
        // entry resolves to its own path rather than a shared "current output".
        viewModel.togglePlayHistory(itemB)
        #expect(viewModel.audioPlayer.currentURL == urlB)
        #expect(viewModel.lastOutputURL == urlB)

        // Toggling B again while loaded should pause (not reload) — currentURL stays B.
        viewModel.togglePlayHistory(itemB)
        #expect(viewModel.audioPlayer.currentURL == urlB)
    }

    @Test func isPlayingHistoryIsKeyedOnIdNotURL() throws {
        let suiteName = "VoiceForgeAppViewModelTests-keyedID-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let (store, cleanup) = try makeIsolatedHistoryStore()
        defer { cleanup() }

        let viewModel = AppViewModel(defaults: defaults, historyStore: store)
        let dir = makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }

        // Two distinct history rows that legacy data would have pointed at the
        // exact same outputPath. Before the id-keyed fix both would light up
        // whenever either played.
        let sharedURL = dir.appendingPathComponent("shared.wav")
        try writeSilentWAV(to: sharedURL)

        let rowA = GenerationHistoryItem(
            id: UUID(), createdAt: Date(), name: "A",
            sourceText: "a", formattedPrompt: "a",
            referenceAudioPath: "/tmp/r.wav", referenceText: "r",
            outputPath: sharedURL.path
        )
        let rowB = GenerationHistoryItem(
            id: UUID(), createdAt: Date(), name: "B",
            sourceText: "b", formattedPrompt: "b",
            referenceAudioPath: "/tmp/r.wav", referenceText: "r",
            outputPath: sharedURL.path
        )

        viewModel.togglePlayHistory(rowA)
        // Whatever the audio engine decided about isPlaying, only row A's id
        // should be the active one; row B (sharing the URL) must not light up.
        #expect(!viewModel.isPlayingHistory(rowB))
        // A reports the same state as the underlying player.
        #expect(viewModel.isPlayingHistory(rowA) == viewModel.audioPlayer.isPlaying)

        // Toggling row B swaps the active id over to B.
        viewModel.togglePlayHistory(rowB)
        #expect(!viewModel.isPlayingHistory(rowA))
    }

    @Test func togglePreviewTracksTheActiveVoiceID() throws {
        let suiteName = "VoiceForgeAppViewModelTests-preview-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let (store, cleanup) = try makeIsolatedHistoryStore()
        defer { cleanup() }

        let viewModel = AppViewModel(defaults: defaults, historyStore: store)
        let voiceA = UUID()
        let voiceB = UUID()
        let bogusURL = URL(fileURLWithPath: "/nonexistent/clip.wav")

        // Starting state: nothing previewing.
        #expect(viewModel.previewingVoiceID == nil)
        #expect(!viewModel.isPreviewing(voiceID: voiceA))

        // Calling toggle once should mark voiceA as the previewing source even though the
        // bogus URL fails to load (AVAudioPlayer throws). The view-model should clear the id.
        viewModel.togglePreview(voiceID: voiceA, url: bogusURL)
        #expect(viewModel.previewingVoiceID == nil)
        #expect(!viewModel.isPreviewing(voiceID: voiceA))

        // Switching to voiceB before voiceA actually played should also stay nil and not crash.
        viewModel.togglePreview(voiceID: voiceB, url: bogusURL)
        #expect(viewModel.previewingVoiceID == nil)
        #expect(!viewModel.isPreviewing(voiceID: voiceB))
    }

    @Test func conversationPlaybackModeStaysIdleForEmptyDraft() throws {
        let suiteName = "VoiceForgeAppViewModelTests-conversation-empty-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let (store, cleanup) = try makeIsolatedHistoryStore()
        defer { cleanup() }

        let viewModel = AppViewModel(defaults: defaults, historyStore: store)

        #expect(!viewModel.hasConversationLines)
        #expect(!viewModel.conversationHasGeneratedAudio)
        #expect(!viewModel.conversationIsInPlaybackMode)
    }

    @Test func loadConversationUsesManifestSettingsAndTargetsConversations() throws {
        let suiteName = "VoiceForgeAppViewModelTests-conversation-load-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let (store, cleanup) = try makeIsolatedHistoryStore()
        defer { cleanup() }

        let viewModel = AppViewModel(defaults: defaults, historyStore: store)
        let dir = makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }

        let manifestURL = dir.appendingPathComponent("conversation.json")
        let manifest = ConversationItem(
            name: "Office Hours",
            lines: [
                ConversationLine(
                    text: "Professor, can you explain the assignment?",
                    referenceAudioPath: "/tmp/ref.wav",
                    referenceText: "Reference transcript",
                    outputPath: "/tmp/line1.wav",
                    status: .completed
                )
            ],
            globalModel: "kokoro-multilingual",
            globalMaxNewTokens: 2048,
            globalEditType: "style"
        )
        try JSONEncoder().encode(manifest).write(to: manifestURL)

        let historyItem = GenerationHistoryItem(
            id: UUID(),
            createdAt: Date(),
            name: "Saved chat",
            sourceText: "Professor, can you explain the assignment?",
            formattedPrompt: "",
            referenceAudioPath: "",
            referenceText: "",
            outputPath: manifestURL.path,
            type: .conversation
        )

        viewModel.loadConversation(historyItem)

        #expect(viewModel.destination == .conversations)
        #expect(viewModel.conversationName == "Saved chat")
        #expect(viewModel.maxNewTokens == 2048)
        #expect(viewModel.conversationLines == manifest.lines)
        #expect(viewModel.conversationHasGeneratedAudio)
    }

    @Test func togglePlayHistoryForConversationLoadsConversationInsteadOfJSONAudio() throws {
        let suiteName = "VoiceForgeAppViewModelTests-conversation-history-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let (store, cleanup) = try makeIsolatedHistoryStore()
        defer { cleanup() }

        let viewModel = AppViewModel(defaults: defaults, historyStore: store)
        let dir = makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }

        let lineURL = dir.appendingPathComponent("line.wav")
        try writeSilentWAV(to: lineURL)

        let manifestURL = dir.appendingPathComponent("conversation.json")
        let line = ConversationLine(
            text: "Welcome back.",
            referenceAudioPath: "/tmp/ref.wav",
            referenceText: "Reference transcript",
            outputPath: lineURL.path,
            status: .completed
        )
        let manifest = ConversationItem(
            name: "Briefing",
            lines: [line],
            globalModel: "fish-s2-pro",
            globalMaxNewTokens: 1500,
            globalEditType: "none"
        )
        try JSONEncoder().encode(manifest).write(to: manifestURL)

        let historyItem = GenerationHistoryItem(
            id: UUID(),
            createdAt: Date(),
            name: "Briefing",
            sourceText: line.text,
            formattedPrompt: "",
            referenceAudioPath: line.referenceAudioPath,
            referenceText: line.referenceText,
            outputPath: manifestURL.path,
            type: .conversation,
            conversationLines: [line]
        )

        viewModel.togglePlayHistory(historyItem)

        #expect(viewModel.destination == .conversations)
        #expect(viewModel.audioPlayer.currentURL != manifestURL)
        #expect(viewModel.conversationLines == [line])
        #expect(viewModel.conversationPlaybackState != .idle)
        #expect(viewModel.conversationPlayer.currentLineIndex == 0)
    }

    /// Two AppViewModel constructions against already-migrated storage must not
    /// redundantly rewrite the manifest.
    @Test func secondAppViewModelConstructionDoesNotRewriteMigratedManifest() throws {
        let fm = FileManager.default
        let suiteName = "VoiceForgeAppVMTests-doubleInit-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let (store, cleanup) = try makeIsolatedHistoryStore()
        defer { cleanup() }
        let itemID = UUID()
        let wavURL = store.storageRoot
            .appendingPathComponent("outputs", isDirectory: true)
            .appendingPathComponent("\(itemID.uuidString).wav")
        try fm.createDirectory(at: wavURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try writeSilentWAV(to: wavURL)

        let canonicalItem = GenerationHistoryItem(
            id: itemID,
            createdAt: Date(timeIntervalSince1970: 1_700_000_000),
            name: "Canonical",
            sourceText: "canonical text",
            formattedPrompt: "canonical text",
            referenceAudioPath: "/tmp/ref.wav",
            referenceText: "ref",
            outputPath: wavURL.path
        )
        store.save([canonicalItem])

        let historyURL = store.storageRoot.appendingPathComponent("history.json")
        #expect(fm.fileExists(atPath: historyURL.path))

        // Confirm migration sees the canonical item as unchanged.
        let (_, summary) = store.migrateLegacy(store.load())
        #expect(summary.relocated == 0)
        #expect(summary.dropped == 0)
        #expect(summary.unchanged == 1)

        // --- Construction #1 + sentinel ---
        _ = AppViewModel(defaults: defaults, historyStore: store)
        let bytesBefore = try Data(contentsOf: historyURL)
        let sentinel = Date(timeIntervalSince1970: 946_684_800)
        try fm.setAttributes([.modificationDate: sentinel], ofItemAtPath: historyURL.path)

        // --- Construction #2 ---
        _ = AppViewModel(defaults: defaults, historyStore: store)

        let bytesAfter = try Data(contentsOf: historyURL)
        let mtimeAfter = try fm.attributesOfItem(atPath: historyURL.path)[.modificationDate] as! Date
        #expect(bytesBefore == bytesAfter)
        #expect(abs(mtimeAfter.timeIntervalSince(sentinel)) < 1.0,
                "AppViewModel init #2 rewrote the manifest")
    }

    /// An AppViewModel with isolated defaults/store must not observe or mutate a
    /// sibling "production-like" VoiceForge tree.
    @Test func isolatedViewModelDoesNotTouchSiblingProductionTree() throws {
        let fm = FileManager.default
        let base = fm.temporaryDirectory
            .appendingPathComponent("VF-AppVM-Canary-\(UUID().uuidString)", isDirectory: true)
        try fm.createDirectory(at: base, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: base) }

        let suiteName = "VF-AppVM-Canary-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let (store, cleanup) = try makeIsolatedHistoryStore()
        defer { cleanup() }

        // Sibling production-like tree with a decoy WAV.
        let prodRoot = base.appendingPathComponent("VoiceForge", isDirectory: true)
        let prodOutputs = prodRoot.appendingPathComponent("outputs", isDirectory: true)
        try fm.createDirectory(at: prodOutputs, withIntermediateDirectories: true)
        let decoyWAV = prodOutputs.appendingPathComponent("\(UUID().uuidString).wav")
        try writeSilentWAV(to: decoyWAV)
        let decoyBytes = try Data(contentsOf: decoyWAV)
        let decoySentinel = Date(timeIntervalSince1970: 946_684_800)
        try fm.setAttributes([.modificationDate: decoySentinel], ofItemAtPath: decoyWAV.path)

        // Construct AppViewModel — must not discover or touch the sibling decoy.
        let viewModel = AppViewModel(defaults: defaults, historyStore: store)
        #expect(viewModel.history.isEmpty)

        // Decoy file, bytes, and mtime must be untouched.
        #expect(fm.fileExists(atPath: decoyWAV.path))
        #expect(try Data(contentsOf: decoyWAV) == decoyBytes)
        let decoyMtime = try fm.attributesOfItem(atPath: decoyWAV.path)[.modificationDate] as! Date
        #expect(abs(decoyMtime.timeIntervalSince(decoySentinel)) < 1.0)
    }

    /// Regression for a real production data-safety bug: two existing
    /// conversation-type history entries have legacy, non-canonical
    /// (flat-.wav-shaped) `outputPath`s and — as happens naturally with
    /// repeated similar mock/test generations — *content-identical*
    /// `conversationLines`. Two genuinely unrelated, orphaned on-disk
    /// `outputs/<uuid>/conversation.json` folders happen to have that same
    /// line content. Startup recovery must identify conversations by their
    /// on-disk folder UUID (their actual, unambiguous identity), never by
    /// `conversationLines` content equality — otherwise an orphaned
    /// manifest's path gets spliced onto an unrelated existing entry, which
    /// is exactly what shipped and corrupted a live `history.json`.
    @Test func recoveryNeverCrossAssociatesConversationsByContentEquality() throws {
        let fm = FileManager.default
        let (store, cleanup) = try makeIsolatedHistoryStore()
        defer { cleanup() }
        let outputsDir = store.storageRoot.appendingPathComponent("outputs", isDirectory: true)

        // Shared line content — deliberately identical across two otherwise
        // unrelated conversations, reproducing the real collision.
        func sharedLines() -> [ConversationLine] {
            [ConversationLine(
                id: UUID(uuidString: "0DE80DCC-5F52-4DD0-866A-37ED74CCEB15")!,
                text: "Welcome back to VoiceForge.",
                referenceAudioPath: "/tmp/mock.wav",
                referenceText: "Mock transcript",
                outputPath: "/tmp/mock-line.wav",
                status: .completed
            )]
        }

        let existingID1 = UUID(uuidString: "74D40A98-0E7B-4E6F-BF60-76D32503CC91")!
        let existingID2 = UUID(uuidString: "EB3E8BFA-A387-4F0A-B0DC-F85A6819CB9A")!
        // Legacy, non-canonical outputPath shape (flat .wav, not
        // outputs/<id>/conversation.json) — matches the real corrupted data.
        let legacyOutputPath1 = outputsDir.appendingPathComponent("\(existingID1.uuidString).wav").path
        let legacyOutputPath2 = outputsDir.appendingPathComponent("\(existingID2.uuidString).wav").path

        let existing1 = GenerationHistoryItem(
            id: existingID1, createdAt: Date(timeIntervalSince1970: 801_058_820),
            name: "Hey dad! I love you so much",
            sourceText: "Welcome back to VoiceForge.", formattedPrompt: "",
            referenceAudioPath: "/tmp/mock.wav", referenceText: "Mock transcript",
            outputPath: legacyOutputPath1, type: .conversation, conversationLines: sharedLines()
        )
        let existing2 = GenerationHistoryItem(
            id: existingID2, createdAt: Date(timeIntervalSince1970: 800_934_986),
            name: "History conversation",
            sourceText: "Welcome back to VoiceForge.", formattedPrompt: "",
            referenceAudioPath: "/tmp/mock.wav", referenceText: "Mock transcript",
            outputPath: legacyOutputPath2, type: .conversation, conversationLines: sharedLines()
        )
        store.save([existing1, existing2])
        // The legacy files must actually exist, or `migrateLegacy` (called
        // right after `load()` in `AppViewModel.init`) would drop these
        // conversation entries as missing rather than exercising recovery.
        try Data([0x00]).write(to: URL(fileURLWithPath: legacyOutputPath1))
        try Data([0x00]).write(to: URL(fileURLWithPath: legacyOutputPath2))

        // Two genuinely orphaned on-disk conversation folders — different
        // ids, never referenced by history.json — whose manifests happen to
        // share the exact same line content as the existing entries above.
        let orphanID1 = UUID(uuidString: "C45D0B53-B635-4F9C-9B6E-634B9AAFCAB3")!
        let orphanID2 = UUID(uuidString: "6541D849-4415-453F-A141-DFFC0FD70374")!
        for orphanID in [orphanID1, orphanID2] {
            let dir = outputsDir.appendingPathComponent(orphanID.uuidString, isDirectory: true)
            try fm.createDirectory(at: dir, withIntermediateDirectories: true)
            let manifest = ConversationItem(
                id: orphanID, createdAt: Date(timeIntervalSince1970: 700_000_000),
                name: "Orphaned", lines: sharedLines()
            )
            try JSONEncoder().encode(manifest).write(to: dir.appendingPathComponent("conversation.json"))
        }

        // Explicit recovery still recovers every orphan under its own identity
        // without cross-associating equal-content conversations.
        let explicitlyRecovered = HistoryStore.recoverEntriesFromDisk(
            existing: [existing1, existing2],
            applicationSupport: store.storageRoot
        )
        let recoveredByID = Dictionary(uniqueKeysWithValues: explicitlyRecovered.map { ($0.id, $0) })
        #expect(recoveredByID[existingID1]?.outputPath == legacyOutputPath1)
        #expect(recoveredByID[existingID2]?.outputPath == legacyOutputPath2)
        #expect(recoveredByID[orphanID1] != nil)
        #expect(recoveredByID[orphanID2] != nil)
        #expect(explicitlyRecovered.count == 4)

        let suiteName = "VF-CrossAssoc-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let historyURL = store.storageRoot.appendingPathComponent("history.json")
        let bytesBeforeStart = try Data(contentsOf: historyURL)

        // Normal startup treats a valid manifest as authoritative.
        let vm1 = AppViewModel(defaults: defaults, historyStore: store)
        let byID1 = Dictionary(uniqueKeysWithValues: vm1.history.map { ($0.id, $0) })

        // The two originally-existing entries must survive with their own
        // identity and their own (legacy) outputPath untouched — never
        // spliced onto an orphan's path.
        #expect(byID1[existingID1]?.outputPath == legacyOutputPath1)
        #expect(byID1[existingID2]?.outputPath == legacyOutputPath2)

        #expect(byID1[orphanID1] == nil)
        #expect(byID1[orphanID2] == nil)
        #expect(vm1.history.count == 2)

        let bytesAfterFirst = try Data(contentsOf: historyURL)
        #expect(bytesAfterFirst == bytesBeforeStart, "Startup must not import orphaned outputs into a valid manifest")

        // --- Second construction: must be fully stable (idempotent) ---
        let vm2 = AppViewModel(defaults: defaults, historyStore: store)
        let byID2 = Dictionary(uniqueKeysWithValues: vm2.history.map { ($0.id, $0) })

        #expect(byID2[existingID1]?.outputPath == legacyOutputPath1)
        #expect(byID2[existingID2]?.outputPath == legacyOutputPath2)
        #expect(byID2[orphanID1] == nil)
        #expect(byID2[orphanID2] == nil)
        #expect(vm2.history.count == 2)

        let bytesAfterSecond = try Data(contentsOf: historyURL)
        #expect(bytesAfterFirst == bytesAfterSecond, "Second startup must not rewrite history.json at all")
    }
}
