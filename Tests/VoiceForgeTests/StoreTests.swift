import Foundation
import Testing
#if canImport(VoiceForgeCore)
@testable import VoiceForgeCore
#else
@testable import VoiceForge
#endif

struct StoreTests {
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

        let existing = [
            GenerationHistoryItem(
                id: UUID(),
                createdAt: Date(timeIntervalSince1970: 2345),
                name: "Only conversation",
                sourceText: line.text,
                formattedPrompt: "",
                referenceAudioPath: line.referenceAudioPath,
                referenceText: line.referenceText,
                outputPath: conversationDir.appendingPathComponent("conversation.json").path,
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
        #expect(recovered.contains(where: { $0.type == .conversation && $0.outputPath.hasSuffix("conversation.json") }))
        #expect(recovered.count == 2)
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
}
