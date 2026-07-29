import Foundation
import Testing
@testable import VoiceForge

@MainActor
struct AppViewModelTests {
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
}
