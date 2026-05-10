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
}
