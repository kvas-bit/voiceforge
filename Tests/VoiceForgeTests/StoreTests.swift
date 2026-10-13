import Foundation
import Testing
#if canImport(VoiceForgeCore)
@testable import VoiceForgeCore
#else
@testable import VoiceForge
#endif

struct StoreTests {
    @Test func deletingDrama3HistoryAlsoRemovesCodesArtifact() throws {
        let dir = makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = HistoryStore(fileURL: dir.appendingPathComponent("history.json"))
        let wav = dir.appendingPathComponent("take.wav")
        let codes = dir.appendingPathComponent("take.npy")
        try Data([1]).write(to: wav); try Data([2]).write(to: codes)
        let item = GenerationHistoryItem(id: UUID(), createdAt: Date(), sourceText: "take", formattedPrompt: "take",
            referenceAudioPath: "ref", referenceText: "ref", outputPath: wav.path, model: TTSModel.drama3.rawValue,
            codesPath: codes.path, seed: 2)
        _ = store.delete(item, from: [item])
        #expect(!FileManager.default.fileExists(atPath: wav.path))
        #expect(!FileManager.default.fileExists(atPath: codes.path))
    }

    @Test func conversationModelRoundTripsAndLegacyManifestDefaultsToS2Pro() throws {
        let item = ConversationItem(lines: [], globalModel: TTSModel.drama3.rawValue)
        let decoded = try JSONDecoder().decode(ConversationItem.self, from: JSONEncoder().encode(item))
        #expect(decoded.globalModel == TTSModel.drama3.rawValue)
        let legacy = #"{"id":"11111111-2222-3333-4444-555555555555","createdAt":0,"name":"Old","lines":[]}"#.data(using: .utf8)!
        let old = try JSONDecoder().decode(ConversationItem.self, from: legacy)
        #expect(old.globalModel == TTSModel.fishS2Pro.rawValue)
    }

    @Test func presetRoundTripPreservesReferenceData() throws {
        let preset = VoicePreset(
            name: "Kaden",
            referenceAudioPath: "/tmp/kaden.wav",
            referenceText: "Reference line"
        )

        let data = try JSONEncoder().encode([preset])
        let decoded = try JSONDecoder().decode([VoicePreset].self, from: data)

        #expect(decoded == [preset])
    }

    @Test func historyRoundTripPreservesFinalPromptAndOutputURL() throws {
        let item = GenerationHistoryItem(
            id: UUID(uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE")!,
            createdAt: Date(timeIntervalSince1970: 1_700_000_000),
            name: "Greeting take",
            sourceText: "hello",
            formattedPrompt: "[excited and energetic] hello",
            referenceAudioPath: "/tmp/ref.wav",
            referenceText: "hello",
            outputPath: "/tmp/out.wav"
        )

        let data = try JSONEncoder().encode([item])
        let decoded = try JSONDecoder().decode([GenerationHistoryItem].self, from: data)

        #expect(decoded == [item])
        #expect(decoded.first?.name == "Greeting take")
    }

    @Test func historyAutoNameStripsTagsAndTruncates() {
        let name = GenerationHistoryItem.autoName(from: "[whispers] Greetings, dear listener — welcome to the broadcast today.")
        #expect(!name.contains("["))
        #expect(name.count <= 41) // 40 + ellipsis
        #expect(name.hasPrefix("Greetings"))
    }

    @Test func historyAutoNameFallsBackForEmptyPrompt() {
        let name = GenerationHistoryItem.autoName(from: "[whispers]   [laughs]")
        #expect(name == "Untitled generation")
    }

    @Test func historyDecodesLegacyEntriesWithoutNameField() throws {
        let legacyJSON = #"""
        [
          {
            "id": "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE",
            "createdAt": 0,
            "sourceText": "hello world",
            "formattedPrompt": "hello world",
            "referenceAudioPath": "/tmp/ref.wav",
            "referenceText": "hello",
            "outputPath": "/tmp/out.wav"
          }
        ]
        """#
        let data = Data(legacyJSON.utf8)
        let decoded = try JSONDecoder().decode([GenerationHistoryItem].self, from: data)
        #expect(decoded.first?.name == "hello world")
    }

    @Test func legacyHistoryMigrationRelocatesCollidingEntries() throws {
        let fm = FileManager.default
        let appSupport = fm.temporaryDirectory
            .appendingPathComponent("VoiceForgeMigrationTests-\(UUID().uuidString)", isDirectory: true)
        try fm.createDirectory(at: appSupport, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: appSupport) }

        // (a) Two legacy entries sharing the same singleton output. The source file exists.
        let legacyDir = appSupport.appendingPathComponent("legacy", isDirectory: true)
        try fm.createDirectory(at: legacyDir, withIntermediateDirectories: true)
        let sharedSource = legacyDir.appendingPathComponent("voiceforge_output.wav")
        try Data([0x01]).write(to: sharedSource)

        let collidingA = GenerationHistoryItem(
            id: UUID(), createdAt: Date(timeIntervalSince1970: 1), name: "first",
            sourceText: "first", formattedPrompt: "first",
            referenceAudioPath: "/tmp/ref.wav", referenceText: "ref",
            outputPath: sharedSource.path
        )
        let collidingB = GenerationHistoryItem(
            id: UUID(), createdAt: Date(timeIntervalSince1970: 2), name: "second",
            sourceText: "second", formattedPrompt: "second",
            referenceAudioPath: "/tmp/ref.wav", referenceText: "ref",
            outputPath: sharedSource.path
        )

        // (b) An entry already at its canonical path with a real file on disk.
        let serviceForCanonical = SpeechGenerationService()
        let modernID = UUID()
        let modernURL = try serviceForCanonical.outputURL(forID: modernID, applicationSupport: appSupport)
        try fm.createDirectory(at: modernURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data([0x02]).write(to: modernURL)
        let modern = GenerationHistoryItem(
            id: modernID, createdAt: Date(timeIntervalSince1970: 3), name: "modern",
            sourceText: "modern", formattedPrompt: "modern",
            referenceAudioPath: "/tmp/ref.wav", referenceText: "ref",
            outputPath: modernURL.path
        )

        // (c) An entry pointing at a file that no longer exists.
        let orphan = GenerationHistoryItem(
            id: UUID(), createdAt: Date(timeIntervalSince1970: 4), name: "orphan",
            sourceText: "orphan", formattedPrompt: "orphan",
            referenceAudioPath: "/tmp/ref.wav", referenceText: "ref",
            outputPath: legacyDir.appendingPathComponent("gone.wav").path
        )

        let (migrated, summary) = HistoryStore.migrateLegacyEntries(
            [collidingA, collidingB, modern, orphan],
            applicationSupport: appSupport
        )

        // The orphan is dropped.
        #expect(!migrated.contains(where: { $0.id == orphan.id }))
        #expect(summary.dropped == 1)

        // The modern entry survives untouched at its canonical path.
        let modernMigrated = try #require(migrated.first(where: { $0.id == modernID }))
        #expect(modernMigrated.outputPath == modernURL.path)
        #expect(summary.unchanged == 1)

        // Both colliding entries are kept and each gets its own canonical file
        // so they no longer share audio.
        let migratedA = try #require(migrated.first(where: { $0.id == collidingA.id }))
        let migratedB = try #require(migrated.first(where: { $0.id == collidingB.id }))
        #expect(migratedA.outputPath != migratedB.outputPath)
        #expect(migratedA.outputPath.hasSuffix("\(collidingA.id.uuidString).wav"))
        #expect(migratedB.outputPath.hasSuffix("\(collidingB.id.uuidString).wav"))
        #expect(fm.fileExists(atPath: migratedA.outputPath))
        #expect(fm.fileExists(atPath: migratedB.outputPath))
        #expect(summary.relocated == 2)
    }

    @Test func mockGenerationProducesUniqueOutputPathsAndFiles() async throws {
        let fm = FileManager.default
        let workdir = fm.temporaryDirectory
            .appendingPathComponent("VoiceForgeGenTests-\(UUID().uuidString)", isDirectory: true)
        try fm.createDirectory(at: workdir, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: workdir) }

        // Reference WAV that mlx-speech would normally read; the mock path
        // doesn't read it but the validation step requires the path to be set.
        let referenceWAV = workdir.appendingPathComponent("ref.wav")
        try Data([0x00]).write(to: referenceWAV)

        // The service hard-codes its output root via FileManager.url(for:.applicationSupportDirectory),
        // so we can only assert the paths *it* picks are distinct and on disk.
        let service = SpeechGenerationService()
        let arguments = ProcessInfo.processInfo.arguments
        guard arguments.contains("--uitest-mock-generation") else {
            // The mock path keys off a process-level launch flag we cannot inject
            // mid-test. Skip the on-disk assertions and just verify the URL
            // helper returns distinct paths for distinct ids.
            let urlA = try service.outputURL(forID: UUID())
            let urlB = try service.outputURL(forID: UUID())
            #expect(urlA != urlB)
            return
        }

        let reqA = GenerationRequest(
            sourceText: "alpha", emotionText: "",
            referenceAudioPath: referenceWAV.path, referenceText: "alpha"
        )
        let reqB = GenerationRequest(
            sourceText: "bravo", emotionText: "",
            referenceAudioPath: referenceWAV.path, referenceText: "bravo"
        )
        let resA = try await service.generate(request: reqA)
        let resB = try await service.generate(request: reqB)
        #expect(resA.outputURL != resB.outputURL)
        #expect(fm.fileExists(atPath: resA.outputURL.path))
        #expect(fm.fileExists(atPath: resB.outputURL.path))
    }

    @Test func uniqueOutputURLPerGenerationID() throws {
        let service = SpeechGenerationService()
        let base = URL(fileURLWithPath: "/Users/tester/Library/Application Support")
        let id1 = UUID()
        let id2 = UUID()
        let url1 = try service.outputURL(forID: id1, applicationSupport: base)
        let url2 = try service.outputURL(forID: id2, applicationSupport: base)
        #expect(url1 != url2)
        #expect(url1.path == "/Users/tester/Library/Application Support/VoiceForge/outputs/\(id1.uuidString).wav")
        #expect(url2.path.hasSuffix(".wav"))
        // Default WAV path now lives under the same VoiceForge root.
        let defaultURL = try service.defaultOutputURL(applicationSupport: base)
        #expect(defaultURL.path == "/Users/tester/Library/Application Support/VoiceForge/voiceforge_output.wav")
    }

    @Test func diskRecoveryRebuildsSinglesAndConversationsWhenHistoryIsIncomplete() throws {
        let fm = FileManager.default
        let home = fm.temporaryDirectory
            .appendingPathComponent("VoiceForgeHistoryRecovery-\(UUID().uuidString)", isDirectory: true)
        let appSupport = home.appendingPathComponent("Library/Application Support/VoiceForge", isDirectory: true)
        let outputs = appSupport.appendingPathComponent("outputs", isDirectory: true)
        try fm.createDirectory(at: outputs, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: home) }

        let singleID = UUID()
        let singleURL = outputs.appendingPathComponent("\(singleID.uuidString).wav")
        try writeSilentWAV(to: singleURL)

        let conversationID = UUID()
        let conversationDir = outputs.appendingPathComponent(conversationID.uuidString, isDirectory: true)
        try fm.createDirectory(at: conversationDir, withIntermediateDirectories: true)
        let lineURL = conversationDir.appendingPathComponent("line-1.wav")
        try writeSilentWAV(to: lineURL)
        let line = ConversationLine(
            text: "Recovered conversation line",
            referenceAudioPath: "/tmp/ref.wav",
            referenceText: "Recovered transcript",
            outputPath: lineURL.path,
            status: .completed
        )
        let manifest = ConversationItem(
            id: conversationID,
            createdAt: Date(timeIntervalSince1970: 1234),
            name: "Recovered conversation",
            lines: [line]
        )
        try JSONEncoder().encode(manifest).write(to: conversationDir.appendingPathComponent("conversation.json"))

        let existingConvPath = conversationDir.appendingPathComponent("conversation.json").path
        let existing = [
            GenerationHistoryItem(
                // Matches the manifest's own id, as real (non-corrupted) data
                // always does — recovery associates by this id, never by
                // `conversationLines` content equality.
                id: conversationID,
                createdAt: Date(timeIntervalSince1970: 2345),
                name: "Only conversation",
                sourceText: line.text,
                formattedPrompt: "",
                referenceAudioPath: line.referenceAudioPath,
                referenceText: line.referenceText,
                outputPath: existingConvPath,
                type: .conversation,
                conversationLines: [line]
            )
        ]

        let recovered = HistoryStore.recoverEntriesFromDisk(
            existing: existing,
            applicationSupport: appSupport,
            fileManager: fm
        )
        let normalizedSinglePath = singleURL.resolvingSymlinksInPath().standardizedFileURL.path

        #expect(recovered.contains(where: {
            $0.type == .single &&
            URL(fileURLWithPath: $0.outputPath).resolvingSymlinksInPath().standardizedFileURL.path == normalizedSinglePath
        }))
        // Conversation must preserve the exact saved outputPath, not merely
        // match by suffix — otherwise /var vs /private/var alias spellings
        // would cause a pointless manifest rewrite.
        let conv = try #require(recovered.first(where: { $0.type == .conversation }))
        #expect(conv.outputPath == existingConvPath)
        #expect(conv.id == existing[0].id)
        #expect(recovered.count == 2)
    }

    @Test func loadDoesNotRewriteManifestForOrderingOnlyDifference() throws {
        let fm = FileManager.default
        let root = fm.temporaryDirectory
            .appendingPathComponent("VoiceForgeOrderingOnly-\(UUID().uuidString)", isDirectory: true)
        let outputs = root.appendingPathComponent("outputs", isDirectory: true)
        try fm.createDirectory(at: outputs, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: root) }

        let laterLexicalID = UUID(uuidString: "ECCD2F38-58E6-4357-9D50-374C59418056")!
        let earlierLexicalID = UUID(uuidString: "736C3EED-E4D1-4C6C-9BD5-64A271B8A4E5")!
        let timestamp = Date(timeIntervalSince1970: 800_145_832.2024353)

        func item(_ id: UUID) -> GenerationHistoryItem {
            GenerationHistoryItem(
                id: id, createdAt: timestamp, name: "Recovered generation",
                sourceText: "Recovered generation", formattedPrompt: "",
                referenceAudioPath: "", referenceText: "",
                outputPath: outputs.appendingPathComponent("\(id.uuidString).wav").path
            )
        }

        for id in [laterLexicalID, earlierLexicalID] {
            try writeSilentWAV(to: outputs.appendingPathComponent("\(id.uuidString).wav"))
        }

        let historyURL = root.appendingPathComponent("history.json")
        let store = HistoryStore(fileURL: historyURL)
        store.save([item(laterLexicalID), item(earlierLexicalID)])
        let originalBytes = try Data(contentsOf: historyURL)

        let loaded = store.load()

        #expect(Set(loaded.map(\.id)) == Set([laterLexicalID, earlierLexicalID]))
        #expect(try Data(contentsOf: historyURL) == originalBytes,
                "Startup recovery must not rewrite history.json merely to reorder equivalent entries")
    }

    @Test func loadDoesNotImportOrphanOutputsWhenManifestIsValid() throws {
        let fm = FileManager.default
        let root = fm.temporaryDirectory
            .appendingPathComponent("VoiceForgeValidManifest-\(UUID().uuidString)", isDirectory: true)
        let outputs = root.appendingPathComponent("outputs", isDirectory: true)
        try fm.createDirectory(at: outputs, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: root) }

        let knownID = UUID()
        let orphanID = UUID()
        let knownURL = outputs.appendingPathComponent("\(knownID.uuidString).wav")
        let orphanURL = outputs.appendingPathComponent("\(orphanID.uuidString).wav")
        try writeSilentWAV(to: knownURL)
        try writeSilentWAV(to: orphanURL)

        let known = GenerationHistoryItem(
            id: knownID, createdAt: Date(timeIntervalSince1970: 1_000),
            name: "Known", sourceText: "Known",
            formattedPrompt: "Known", referenceAudioPath: "",
            referenceText: "", outputPath: knownURL.path
        )
        let historyURL = root.appendingPathComponent("history.json")
        let store = HistoryStore(fileURL: historyURL)
        store.save([known])
        let originalBytes = try Data(contentsOf: historyURL)

        let loaded = store.load()

        #expect(loaded == [known])
        #expect(try Data(contentsOf: historyURL) == originalBytes,
                "A valid manifest is authoritative; startup must not import unrelated orphan files")
    }

    @Test func deletingSingleRemovesBackingFileSoItDoesNotReappearOnRecovery() throws {
        let fm = FileManager.default
        let root = fm.temporaryDirectory
            .appendingPathComponent("VoiceForgeDeleteSingle-\(UUID().uuidString)", isDirectory: true)
        let appSupport = root.appendingPathComponent("Library/Application Support/VoiceForge", isDirectory: true)
        let outputs = appSupport.appendingPathComponent("outputs", isDirectory: true)
        try fm.createDirectory(at: outputs, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: root) }

        let outputURL = outputs.appendingPathComponent("\(UUID().uuidString).wav")
        try writeSilentWAV(to: outputURL)

        let item = GenerationHistoryItem(
            id: UUID(),
            createdAt: Date(timeIntervalSince1970: 100),
            name: "Delete me",
            sourceText: "Delete me",
            formattedPrompt: "Delete me",
            referenceAudioPath: "/tmp/ref.wav",
            referenceText: "ref",
            outputPath: outputURL.path
        )

        let store = HistoryStore(fileURL: appSupport.appendingPathComponent("history.json"), fileManager: fm)
        let updated = store.delete(item, from: [item])

        #expect(updated.isEmpty)
        #expect(!fm.fileExists(atPath: outputURL.path))

        let recovered = HistoryStore.recoverEntriesFromDisk(
            existing: updated,
            applicationSupport: appSupport,
            fileManager: fm
        )
        #expect(recovered.isEmpty)
    }

    @Test func deletingConversationRemovesBundleSoItDoesNotReappearOnRecovery() throws {
        let fm = FileManager.default
        let root = fm.temporaryDirectory
            .appendingPathComponent("VoiceForgeDeleteConversation-\(UUID().uuidString)", isDirectory: true)
        let appSupport = root.appendingPathComponent("Library/Application Support/VoiceForge", isDirectory: true)
        let outputs = appSupport.appendingPathComponent("outputs", isDirectory: true)
        try fm.createDirectory(at: outputs, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: root) }

        let conversationID = UUID()
        let conversationDir = outputs.appendingPathComponent(conversationID.uuidString, isDirectory: true)
        try fm.createDirectory(at: conversationDir, withIntermediateDirectories: true)
        let lineURL = conversationDir.appendingPathComponent("line-1.wav")
        try writeSilentWAV(to: lineURL)
        let line = ConversationLine(
            text: "Delete this conversation",
            referenceAudioPath: "/tmp/ref.wav",
            referenceText: "ref",
            outputPath: lineURL.path,
            status: .completed
        )
        let manifestURL = conversationDir.appendingPathComponent("conversation.json")
        let manifest = ConversationItem(
            id: conversationID,
            createdAt: Date(timeIntervalSince1970: 200),
            name: "Conversation to delete",
            lines: [line]
        )
        try JSONEncoder().encode(manifest).write(to: manifestURL)

        let item = GenerationHistoryItem(
            id: conversationID,
            createdAt: Date(timeIntervalSince1970: 200),
            name: "Conversation to delete",
            sourceText: line.text,
            formattedPrompt: "",
            referenceAudioPath: line.referenceAudioPath,
            referenceText: line.referenceText,
            outputPath: manifestURL.path,
            type: .conversation,
            conversationLines: [line]
        )

        let store = HistoryStore(fileURL: appSupport.appendingPathComponent("history.json"), fileManager: fm)
        let updated = store.delete(item, from: [item])

        #expect(updated.isEmpty)
        #expect(!fm.fileExists(atPath: conversationDir.path))

        let recovered = HistoryStore.recoverEntriesFromDisk(
            existing: updated,
            applicationSupport: appSupport,
            fileManager: fm
        )
        #expect(recovered.isEmpty)
    }


    @Test func diskRecoveryPrefersConversationBundleOverTopLevelWAVWithSameID() throws {
        let fm = FileManager.default
        let home = fm.temporaryDirectory
            .appendingPathComponent("VoiceForgeHistoryRecoveryCollision-\(UUID().uuidString)", isDirectory: true)
        let appSupport = home.appendingPathComponent("Library/Application Support/VoiceForge", isDirectory: true)
        let outputs = appSupport.appendingPathComponent("outputs", isDirectory: true)
        try fm.createDirectory(at: outputs, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: home) }

        let sharedID = UUID()
        let topLevelWAV = outputs.appendingPathComponent("\(sharedID.uuidString).wav")
        try writeSilentWAV(to: topLevelWAV)

        let conversationDir = outputs.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try fm.createDirectory(at: conversationDir, withIntermediateDirectories: true)
        let lineURL = conversationDir.appendingPathComponent("line-1.wav")
        try writeSilentWAV(to: lineURL)
        let line = ConversationLine(
            text: "Collision line",
            referenceAudioPath: "/tmp/ref.wav",
            referenceText: "Collision transcript",
            outputPath: lineURL.path,
            status: .completed
        )
        let manifest = ConversationItem(
            id: sharedID,
            createdAt: Date(timeIntervalSince1970: 500),
            name: "Recovered conversation",
            lines: [line]
        )
        let manifestURL = conversationDir.appendingPathComponent("conversation.json")
        try JSONEncoder().encode(manifest).write(to: manifestURL)

        let existing = [
            GenerationHistoryItem(
                id: sharedID,
                createdAt: Date(timeIntervalSince1970: 600),
                name: "Broken conversation",
                sourceText: line.text,
                formattedPrompt: "",
                referenceAudioPath: line.referenceAudioPath,
                referenceText: line.referenceText,
                outputPath: topLevelWAV.path,
                type: .conversation,
                conversationLines: [line]
            )
        ]

        let recovered = HistoryStore.recoverEntriesFromDisk(
            existing: existing,
            applicationSupport: appSupport,
            fileManager: fm
        )

        #expect(recovered.count == 1)
        let recoveredConversation = try #require(recovered.first)
        #expect(recoveredConversation.type == .conversation)
        #expect(recoveredConversation.id == sharedID)
        #expect(
            URL(fileURLWithPath: recoveredConversation.outputPath).resolvingSymlinksInPath().standardizedFileURL.path ==
            manifestURL.resolvingSymlinksInPath().standardizedFileURL.path
        )
    }

    @Test func diskRecoveryRemovesStaleSingleWhenHistoryAlreadyContainsSameIDConversation() throws {
        let fm = FileManager.default
        let home = fm.temporaryDirectory
            .appendingPathComponent("VoiceForgeHistoryRecoveryExistingCollision-\(UUID().uuidString)", isDirectory: true)
        let appSupport = home.appendingPathComponent("Library/Application Support/VoiceForge", isDirectory: true)
        let outputs = appSupport.appendingPathComponent("outputs", isDirectory: true)
        try fm.createDirectory(at: outputs, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: home) }

        let sharedID = UUID()
        let topLevelWAV = outputs.appendingPathComponent("\(sharedID.uuidString).wav")
        try writeSilentWAV(to: topLevelWAV)

        let conversationDir = outputs.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try fm.createDirectory(at: conversationDir, withIntermediateDirectories: true)
        let lineURL = conversationDir.appendingPathComponent("line-1.wav")
        try writeSilentWAV(to: lineURL)
        let line = ConversationLine(
            text: "Existing collision line",
            referenceAudioPath: "/tmp/ref.wav",
            referenceText: "Existing collision transcript",
            outputPath: lineURL.path,
            status: .completed
        )
        let manifestURL = conversationDir.appendingPathComponent("conversation.json")
        let manifest = ConversationItem(
            id: sharedID,
            createdAt: Date(timeIntervalSince1970: 700),
            name: "Recovered conversation",
            lines: [line]
        )
        try JSONEncoder().encode(manifest).write(to: manifestURL)

        let existing = [
            GenerationHistoryItem(
                id: sharedID,
                createdAt: Date(timeIntervalSince1970: 701),
                name: "Existing conversation",
                sourceText: line.text,
                formattedPrompt: "",
                referenceAudioPath: line.referenceAudioPath,
                referenceText: line.referenceText,
                outputPath: manifestURL.path,
                type: .conversation,
                conversationLines: [line]
            ),
            GenerationHistoryItem(
                id: sharedID,
                createdAt: Date(timeIntervalSince1970: 702),
                name: "Stale single",
                sourceText: "Should disappear",
                formattedPrompt: "",
                referenceAudioPath: "",
                referenceText: "",
                outputPath: topLevelWAV.path,
                type: .single
            )
        ]

        let recovered = HistoryStore.recoverEntriesFromDisk(
            existing: existing,
            applicationSupport: appSupport,
            fileManager: fm
        )

        #expect(recovered.count == 1)
        let remaining = try #require(recovered.first)
        #expect(remaining.type == .conversation)
        #expect(remaining.id == sharedID)
    }

    @Test func migrationPreservesConversationManifestWithoutCreatingWAV() throws {
        let fm = FileManager.default
        let base = fm.temporaryDirectory
            .appendingPathComponent("VoiceForgeMigrationConv-\(UUID().uuidString)", isDirectory: true)
        try fm.createDirectory(at: base, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: base) }

        let outputsDir = base.appendingPathComponent("VoiceForge/outputs", isDirectory: true)
        let convID = UUID()
        let convDir = outputsDir.appendingPathComponent(convID.uuidString, isDirectory: true)
        try fm.createDirectory(at: convDir, withIntermediateDirectories: true)

        let line = ConversationLine(
            text: "Migration line", referenceAudioPath: "/tmp/ref.wav",
            referenceText: "ref", outputPath: convDir.appendingPathComponent("line.wav").path,
            status: .completed
        )
        try writeSilentWAV(to: convDir.appendingPathComponent("line.wav"))
        let manifest = ConversationItem(id: convID, createdAt: Date(timeIntervalSince1970: 100),
                                         name: "Keep me", lines: [line])
        let manifestURL = convDir.appendingPathComponent("conversation.json")
        try JSONEncoder().encode(manifest).write(to: manifestURL)

        let item = GenerationHistoryItem(
            id: convID, createdAt: Date(timeIntervalSince1970: 100), name: "Keep me",
            sourceText: line.text, formattedPrompt: "",
            referenceAudioPath: line.referenceAudioPath, referenceText: line.referenceText,
            outputPath: manifestURL.path, type: .conversation, conversationLines: [line]
        )

        let (migrated, summary) = HistoryStore.migrateLegacyEntries(
            [item], applicationSupport: base, fileManager: fm
        )

        #expect(summary.unchanged == 1)
        #expect(summary.relocated == 0)
        #expect(summary.dropped == 0)

        let kept = try #require(migrated.first)
        #expect(kept.type == .conversation)
        #expect(URL(fileURLWithPath: kept.outputPath).standardizedFileURL == manifestURL.standardizedFileURL)
        #expect(fm.fileExists(atPath: manifestURL.path))
        // Manifest still valid JSON.
        #expect(try JSONDecoder().decode(ConversationItem.self, from: Data(contentsOf: manifestURL)).id == convID)
        // No stray .wav copy at the canonical single-voice location.
        #expect(!fm.fileExists(atPath: outputsDir.appendingPathComponent("\(convID.uuidString).wav").path))
    }

    @Test func migrationIsIdempotentOnSecondPass() throws {
        let fm = FileManager.default
        let base = fm.temporaryDirectory
            .appendingPathComponent("VoiceForgeMigrationIdem-\(UUID().uuidString)", isDirectory: true)
        try fm.createDirectory(at: base, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: base) }

        let outputsDir = base.appendingPathComponent("VoiceForge/outputs", isDirectory: true)

        let legacyDir = base.appendingPathComponent("legacy", isDirectory: true)
        try fm.createDirectory(at: legacyDir, withIntermediateDirectories: true)
        let sharedWAV = legacyDir.appendingPathComponent("voiceforge_output.wav")
        try Data([0x01]).write(to: sharedWAV)

        let singleA = GenerationHistoryItem(
            id: UUID(), createdAt: Date(timeIntervalSince1970: 1), name: "first",
            sourceText: "a", formattedPrompt: "a",
            referenceAudioPath: "/tmp/ref.wav", referenceText: "ref",
            outputPath: sharedWAV.path
        )
        let singleB = GenerationHistoryItem(
            id: UUID(), createdAt: Date(timeIntervalSince1970: 2), name: "second",
            sourceText: "b", formattedPrompt: "b",
            referenceAudioPath: "/tmp/ref.wav", referenceText: "ref",
            outputPath: sharedWAV.path
        )

        let convID = UUID()
        let convDir = outputsDir.appendingPathComponent(convID.uuidString, isDirectory: true)
        try fm.createDirectory(at: convDir, withIntermediateDirectories: true)
        let line = ConversationLine(
            text: "idem line", referenceAudioPath: "/tmp/ref.wav", referenceText: "ref",
            outputPath: convDir.appendingPathComponent("line.wav").path, status: .completed
        )
        try writeSilentWAV(to: convDir.appendingPathComponent("line.wav"))
        let manifestURL = convDir.appendingPathComponent("conversation.json")
        try JSONEncoder().encode(ConversationItem(id: convID, createdAt: Date(timeIntervalSince1970: 3),
                                                   name: "chat", lines: [line])).write(to: manifestURL)

        let convItem = GenerationHistoryItem(
            id: convID, createdAt: Date(timeIntervalSince1970: 3), name: "chat",
            sourceText: line.text, formattedPrompt: "",
            referenceAudioPath: line.referenceAudioPath, referenceText: line.referenceText,
            outputPath: manifestURL.path, type: .conversation, conversationLines: [line]
        )

        let (firstOut, firstSummary) = HistoryStore.migrateLegacyEntries(
            [singleA, singleB, convItem], applicationSupport: base, fileManager: fm
        )
        #expect(firstSummary.relocated == 2)
        #expect(firstSummary.dropped == 0)
        #expect(firstSummary.unchanged == 1)
        #expect(firstOut.count == 3)
        #expect(URL(fileURLWithPath: firstOut.first(where: { $0.id == singleA.id })!.outputPath).lastPathComponent == "\(singleA.id.uuidString).wav")

        let (secondOut, secondSummary) = HistoryStore.migrateLegacyEntries(
            firstOut, applicationSupport: base, fileManager: fm
        )
        #expect(secondSummary.relocated == 0)
        #expect(secondSummary.dropped == 0)
        #expect(secondSummary.unchanged == 3)
        #expect(secondOut.count == 3)
        #expect(secondOut == firstOut)
    }

    /// Recovery must return the same list regardless of enumeration order.
    /// With equal timestamps the tiebreaker is ascending `outputPath`.
    @Test func recoveryDeterministicForEqualTimestamps() throws {
        let fm = FileManager.default
        let home = fm.temporaryDirectory
            .appendingPathComponent("VoiceForgeRecoveryDet-\(UUID().uuidString)", isDirectory: true)
        let outputs = home.appendingPathComponent("VoiceForge/outputs", isDirectory: true)
        try fm.createDirectory(at: outputs, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: home) }

        let idAlpha = UUID(uuidString: "11111111-1111-1111-1111-111111111111")!
        let idZeta  = UUID(uuidString: "99999999-9999-9999-9999-999999999999")!
        let wavAlpha = outputs.appendingPathComponent("\(idAlpha.uuidString).wav")
        let wavZeta  = outputs.appendingPathComponent("\(idZeta.uuidString).wav")

        try writeSilentWAV(to: wavZeta) // reverse order
        try writeSilentWAV(to: wavAlpha)

        let epoch = Date(timeIntervalSince1970: 1_000_000_000)
        try fm.setAttributes([.modificationDate: epoch], ofItemAtPath: wavAlpha.path)
        try fm.setAttributes([.modificationDate: epoch], ofItemAtPath: wavZeta.path)

        let vfRoot = home.appendingPathComponent("VoiceForge", isDirectory: true)
        let first = HistoryStore.recoverEntriesFromDisk(existing: [], applicationSupport: vfRoot, fileManager: fm)
        let second = HistoryStore.recoverEntriesFromDisk(existing: [], applicationSupport: vfRoot, fileManager: fm)

        #expect(first == second)
        #expect(first.count == 2)
        // Ascending outputPath for equal timestamps: alpha < zeta.
        let norm0 = URL(fileURLWithPath: first[0].outputPath).resolvingSymlinksInPath().standardizedFileURL.path
        let norm1 = URL(fileURLWithPath: first[1].outputPath).resolvingSymlinksInPath().standardizedFileURL.path
        #expect(norm0 == wavAlpha.resolvingSymlinksInPath().standardizedFileURL.path)
        #expect(norm1 == wavZeta.resolvingSymlinksInPath().standardizedFileURL.path)
    }

    /// Load, recover, and migrate all stay under the store's exact root regardless
    /// of directory name; no sibling `VoiceForge` directory is created.
    @Test func historyStoreRespectsExactStorageRoot() throws {
        let fm = FileManager.default
        let base = fm.temporaryDirectory
            .appendingPathComponent("VF-ArbitraryName-\(UUID().uuidString)", isDirectory: true)
        try fm.createDirectory(at: base, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: base) }

        let myRoot = base.appendingPathComponent("my-voice-dir", isDirectory: true)
        try fm.createDirectory(at: myRoot, withIntermediateDirectories: true)
        let outputsDir = myRoot.appendingPathComponent("outputs", isDirectory: true)
        try fm.createDirectory(at: outputsDir, withIntermediateDirectories: true)

        // Legacy WAV outside the store's root.
        let legacyDir = base.appendingPathComponent("old", isDirectory: true)
        try fm.createDirectory(at: legacyDir, withIntermediateDirectories: true)
        let legacyWAV = legacyDir.appendingPathComponent("test.wav")
        try Data([0x01]).write(to: legacyWAV)

        let legacyID = UUID()
        let store = HistoryStore(fileURL: myRoot.appendingPathComponent("history.json"), fileManager: fm)
        store.save([GenerationHistoryItem(
            id: legacyID, createdAt: Date(timeIntervalSince1970: 1), name: "legacy",
            sourceText: "s", formattedPrompt: "s",
            referenceAudioPath: "/tmp/r.wav", referenceText: "r",
            outputPath: legacyWAV.path
        )])
        let loaded = store.load()
        #expect(loaded.count == 1)

        let (migrated, summary) = store.migrateLegacy(loaded)
        #expect(summary.relocated == 1)
        #expect(summary.unchanged == 0)
        let expected = outputsDir.appendingPathComponent("\(legacyID.uuidString).wav").path
        #expect(URL(fileURLWithPath: migrated.first!.outputPath).resolvingSymlinksInPath().standardizedFileURL.path ==
                URL(fileURLWithPath: expected).resolvingSymlinksInPath().standardizedFileURL.path)
        #expect(fm.fileExists(atPath: expected))
        #expect(!fm.fileExists(atPath: base.appendingPathComponent("VoiceForge", isDirectory: true).path),
                "leaked a 'VoiceForge' dir outside the store's root")
    }

    @Test func deleteAndClearCannotTouchPathsOutsideStorageRoot() throws {
        let fm = FileManager.default
        let base = fm.temporaryDirectory
            .appendingPathComponent("VF-Jail-\(UUID().uuidString)", isDirectory: true)
        try fm.createDirectory(at: base, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: base) }

        let vfDir = base.appendingPathComponent("VoiceForge", isDirectory: true)
        try fm.createDirectory(at: vfDir, withIntermediateDirectories: true)
        try fm.createDirectory(at: vfDir.appendingPathComponent("outputs", isDirectory: true), withIntermediateDirectories: true)
        let historyURL = vfDir.appendingPathComponent("history.json")
        let store = HistoryStore(fileURL: historyURL, fileManager: fm)

        let sentinelURL = base.appendingPathComponent("outside-sentinel.txt")
        try Data("do-not-delete".utf8).write(to: sentinelURL)
        let sentinelPoison = GenerationHistoryItem(
            id: UUID(), createdAt: Date(), name: "poison",
            sourceText: "x", formattedPrompt: "x",
            referenceAudioPath: "/tmp/r.wav", referenceText: "r",
            outputPath: sentinelURL.path
        )

        #expect(store.delete(sentinelPoison, from: [sentinelPoison]).isEmpty)
        #expect(fm.fileExists(atPath: sentinelURL.path), "delete removed outside file")

        store.save([sentinelPoison])
        store.clear([sentinelPoison])
        #expect(fm.fileExists(atPath: sentinelURL.path), "clear removed outside file")
        #expect(store.load().isEmpty)

        // Poisoned conversation: outputPath at <storageRoot>/conversation.json would
        // make bundleURL == storageRoot — must not delete the root dir.
        let convRootURL = vfDir.appendingPathComponent("conversation.json")
        try Data("{\"lines\":[],\"name\":\"x\"}".utf8).write(to: convRootURL)
        let convPoison = GenerationHistoryItem(
            id: UUID(), createdAt: Date(), name: "conv-poison",
            sourceText: "x", formattedPrompt: "x",
            referenceAudioPath: "/tmp/r.wav", referenceText: "r",
            outputPath: convRootURL.path, type: .conversation, conversationLines: []
        )
        store.save([convPoison])
        #expect(store.delete(convPoison, from: [convPoison]).isEmpty)
        #expect(fm.fileExists(atPath: vfDir.path), "delete removed storageRoot!")
        #expect(fm.fileExists(atPath: historyURL.path), "delete removed history.json!")
    }

    @Test func isolatedStoreIsObliviousToSiblingProductionTree() throws {
        let fm = FileManager.default
        let base = fm.temporaryDirectory
            .appendingPathComponent("VF-Canary-\(UUID().uuidString)", isDirectory: true)
        try fm.createDirectory(at: base, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: base) }

        let isoRoot = base.appendingPathComponent("isolated", isDirectory: true)
        try fm.createDirectory(at: isoRoot, withIntermediateDirectories: true)
        let isoOutputs = isoRoot.appendingPathComponent("outputs", isDirectory: true)
        try fm.createDirectory(at: isoOutputs, withIntermediateDirectories: true)
        let store = HistoryStore(fileURL: isoRoot.appendingPathComponent("history.json"), fileManager: fm)

        // Sibling production-like tree with a decoy WAV.
        let prodOutputs = base.appendingPathComponent("VoiceForge/outputs", isDirectory: true)
        try fm.createDirectory(at: prodOutputs, withIntermediateDirectories: true)
        let decoyWAV = prodOutputs.appendingPathComponent("\(UUID().uuidString).wav")
        try writeSilentWAV(to: decoyWAV)
        let decoyBytes = try Data(contentsOf: decoyWAV)
        let decoySentinel = Date(timeIntervalSince1970: 946_684_800)
        try fm.setAttributes([.modificationDate: decoySentinel], ofItemAtPath: decoyWAV.path)

        let myID = UUID()
        let myWAV = isoOutputs.appendingPathComponent("\(myID.uuidString).wav")
        try writeSilentWAV(to: myWAV)
        store.save([GenerationHistoryItem(
            id: myID, createdAt: Date(timeIntervalSince1970: 100), name: "mine",
            sourceText: "s", formattedPrompt: "s",
            referenceAudioPath: "/tmp/r.wav", referenceText: "r",
            outputPath: myWAV.path
        )])

        let loaded = store.load()
        #expect(loaded.count == 1)
        #expect(loaded[0].id == myID)

        let (_, summary) = store.migrateLegacy(loaded)
        #expect(summary.unchanged == 1)

        #expect(fm.fileExists(atPath: decoyWAV.path))
        #expect(try Data(contentsOf: decoyWAV) == decoyBytes)
        #expect(abs(
            (try fm.attributesOfItem(atPath: decoyWAV.path)[.modificationDate] as! Date)
                .timeIntervalSince(decoySentinel)
        ) < 1.0)

        let outputContents = try fm.contentsOfDirectory(atPath: prodOutputs.path)
        #expect(outputContents.count == 1) // only the decoy WAV
    }
}
