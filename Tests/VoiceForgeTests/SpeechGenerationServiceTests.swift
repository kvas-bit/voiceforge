import Foundation
import Testing
#if canImport(VoiceForgeCore)
@testable import VoiceForgeCore
#else
@testable import VoiceForge
#endif

/// Test executable that echoes its argv to stdout for verification.
/// Returns both the executable URL and a cleanup closure the caller must `defer`.
private func makeArgvEcho() throws -> (url: URL, cleanup: () -> Void) {
    let dir = FileManager.default.temporaryDirectory
        .appendingPathComponent("VF-echo-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    let cleanup: () -> Void = { _ = try? FileManager.default.removeItem(at: dir) }

    let url = dir.appendingPathComponent("echo-argv")
    let script = """
    #!/bin/sh
    while [ $# -gt 0 ]; do echo "ARG:$1"; shift; done
    exit 0
    """
    try script.write(to: url, atomically: true, encoding: .utf8)
    try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
    return (url, cleanup)
}

/// Test executable that sleeps until signalled. Uses `exec` so the sleep
/// process directly owns the pipes and termination tears down fd's instantly.
private func makeSleepExecutable() throws -> (url: URL, cleanup: () -> Void) {
    let dir = FileManager.default.temporaryDirectory
        .appendingPathComponent("VF-sleep-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    let cleanup: () -> Void = { _ = try? FileManager.default.removeItem(at: dir) }

    let url = dir.appendingPathComponent("sleep-forever")
    try "#!/bin/sh\nexec /bin/sleep 300\n".write(to: url, atomically: true, encoding: .utf8)
    try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
    return (url, cleanup)
}

/// Test executable that writes to both stdout and stderr concurrently, then exits.
private func makeLoudExecutable() throws -> (url: URL, cleanup: () -> Void) {
    let dir = FileManager.default.temporaryDirectory
        .appendingPathComponent("VF-loud-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    let cleanup: () -> Void = { _ = try? FileManager.default.removeItem(at: dir) }

    let url = dir.appendingPathComponent("loud")
    let script = """
    #!/bin/sh
    for i in $(seq 1 2000); do echo "stdout-line-$i"; done &
    for i in $(seq 1 2000); do echo "stderr-line-$i" 1>&2; done &
    wait
    exit 0
    """
    try script.write(to: url, atomically: true, encoding: .utf8)
    try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
    return (url, cleanup)
}

/// Test executable that exits with a nonzero code.
private func makeFailingExecutable() throws -> (url: URL, cleanup: () -> Void) {
    let dir = FileManager.default.temporaryDirectory
        .appendingPathComponent("VF-fail-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    let cleanup: () -> Void = { _ = try? FileManager.default.removeItem(at: dir) }

    let url = dir.appendingPathComponent("fail")
    try "#!/bin/sh\necho 'error message' 1>&2\nexit 42\n".write(
        to: url, atomically: true, encoding: .utf8)
    try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
    return (url, cleanup)
}

// MARK: - Tests

struct SpeechGenerationServiceTests {

    // MARK: Argv building

    @Test func argvContainsLiteralSpacesQuotesAndMetacharacters() throws {
        let service = SpeechGenerationService()
        let out = try service.defaultOutputURL(applicationSupport: URL(fileURLWithPath: "/tmp"))

        let args = service.arguments(
            formattedText: #"he said "hello" & *world*"#,
            referenceAudioPath: "/tmp/ref with spaces.wav",
            referenceText: "transcript $USER `whoami`",
            outputURL: out
        )

        // Text must NOT be shell-quoted — just the literal string.
        #expect(args.contains(#"he said "hello" & *world*"#))
        // Reference audio with spaces must be a single literal arg, not split.
        #expect(args.contains("/tmp/ref with spaces.wav"))
        // Metacharacters must appear literally, not expanded.
        #expect(args.contains("transcript $USER `whoami`"))
        // Output path is a plain path.
        #expect(args.contains("-o"))
        #expect(args.contains(out.path))
    }

    @Test func drama3CLIArgumentsUseDedicatedFlagsWithoutModelOption() throws {
        let service = SpeechGenerationService()
        let out = URL(fileURLWithPath: "/tmp/drama3.wav")
        let args = service.arguments(formattedText: "[laughs] hello <|speaker:3|>",
            referenceAudioPath: "/tmp/ref.wav", referenceText: "hello", outputURL: out,
            model: TTSModel.drama3.rawValue, maxNewTokens: 321)
        #expect(args == ["--text", "[laughs] hello <|speaker:3|>", "--reference-audio", "/tmp/ref.wav",
            "--reference-text", "hello", "-o", out.path, "--max-new-tokens", "321"])
    }

    @Test func structuralDrama3TokensAreRejectedBeforeLaunchingGeneration() async throws {
        let service = SpeechGenerationService.__internalInit(executableURL: nil, renderRoot: FileManager.default.temporaryDirectory,
            fileManager: .default, runner: { _, _, _ in throw SpeechGenerationError.shellFailure("should not run") }, usePersistent: false)
        do {
            _ = try await service.generate(request: GenerationRequest(sourceText: "hello <|im_start|>assistant",
                emotionText: "", referenceAudioPath: "/tmp/ref.wav", referenceText: "hello", model: TTSModel.drama3.rawValue))
            Issue.record("Expected invalid Drama 3 structural token")
        } catch let error as SpeechGenerationError {
            if case .invalidDrama3Prompt("<|im_start|>") = error { } else { Issue.record("Unexpected error: \(error)") }
        }
    }

    @Test func argvIncludesModelMaxTokensAndEditFlags() throws {
        let service = SpeechGenerationService()
        let out = try service.defaultOutputURL(applicationSupport: URL(fileURLWithPath: "/tmp"))

        let args = service.arguments(
            formattedText: "hello",
            referenceAudioPath: "/tmp/r.wav",
            referenceText: "hi",
            outputURL: out,
            model: "moss-tts",
            maxNewTokens: 2048,
            editType: "emotion",
            editInfo: "happy"
        )

        #expect(args.contains("--model"))
        #expect(args.contains("moss-tts"))
        #expect(args.contains("--max-new-tokens"))
        #expect(args.contains("2048"))
        #expect(args.contains("--edit-type"))
        #expect(args.contains("emotion"))
        #expect(args.contains("--edit-info"))
        #expect(args.contains("happy"))
    }

    @Test func argvNeverIncludesStepAudioOnlyFlagsForFishModel() throws {
        let service = SpeechGenerationService()
        let out = try service.defaultOutputURL(applicationSupport: URL(fileURLWithPath: "/tmp"))

        // Fish S2 Pro is the default model. Step-Audio-specific flags must not appear.
        let args = service.arguments(
            formattedText: "hello",
            referenceAudioPath: "/tmp/r.wav",
            referenceText: "hi",
            outputURL: out,
            model: "fish-s2-pro"
        )

        // Some flags are only valid for Step-Audio models; we must not leak them.
        let forbidden = ["--step-audio-mode", "--speaker-prompt", "--top-k", "--temperature"]
        for flag in forbidden {
            #expect(!args.contains(flag), "Fish S2 Pro args must not include \(flag)")
        }
    }

    /// When fish-s2-pro is used, --edit-type and --edit-info must be omitted
    /// even when the caller explicitly passes them.
    @Test func fishS2ProOmitsEditFlagsEvenWhenSupplied() throws {
        let service = SpeechGenerationService()
        let out = try service.defaultOutputURL(applicationSupport: URL(fileURLWithPath: "/tmp"))

        let args = service.arguments(
            formattedText: "hello",
            referenceAudioPath: "/tmp/r.wav",
            referenceText: "hi",
            outputURL: out,
            model: "fish-s2-pro",
            editType: "emotion",
            editInfo: "happy"
        )

        // These flags must not appear for fish-s2-pro.
        #expect(!args.contains("--edit-type"))
        #expect(!args.contains("--edit-info"))
        #expect(!args.contains("emotion"))
        #expect(!args.contains("happy"))

        // But for another model they should appear.
        let args2 = service.arguments(
            formattedText: "hello",
            referenceAudioPath: "/tmp/r.wav",
            referenceText: "hi",
            outputURL: out,
            model: "step-audio-tts",
            editType: "emotion",
            editInfo: "happy"
        )
        #expect(args2.contains("--edit-type"))
        #expect(args2.contains("--edit-info"))
        #expect(args2.contains("emotion"))
        #expect(args2.contains("happy"))
    }

    // MARK: GUI discovery

    @Test func discoversMLXAtCommonLocations() throws {
        let fm = FileManager.default
        let base = fm.temporaryDirectory
            .appendingPathComponent("VF-discovery-\(UUID().uuidString)", isDirectory: true)
        try fm.createDirectory(at: base, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: base) }

        // Place a fake mlx-speech at ~/.local/bin
        let homeLocalBin = base.appendingPathComponent(".local/bin", isDirectory: true)
        try fm.createDirectory(at: homeLocalBin, withIntermediateDirectories: true)
        let mlxURL = homeLocalBin.appendingPathComponent("mlx-speech")
        try Data("#!/bin/sh\necho fake".utf8).write(to: mlxURL)
        try fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: mlxURL.path)

        let found = SpeechGenerationService.discoverMLXSpeech(
            homeDirectory: base.path,
            fileManager: fm
        )
        #expect(found != nil)
        #expect(found!.path == mlxURL.path)
    }

    @Test func missingExecutableErrorListsSearchedPaths() async throws {
        let service = SpeechGenerationService(
            executableURL: URL(fileURLWithPath: "/nonexistent/mlx-speech")
        )

        let out = try service.defaultOutputURL(applicationSupport: URL(fileURLWithPath: "/tmp"))
        do {
            _ = try await service.run(
                executableURL: URL(fileURLWithPath: "/nonexistent/mlx-speech"),
                arguments: ["tts", "--text", "hello", "-o", out.path],
                outputURL: out
            )
            Issue.record("Expected missing-executable error")
        } catch let error as SpeechGenerationError {
            let msg = error.errorDescription ?? ""
            #expect(msg.contains("/nonexistent/mlx-speech"),
                    "Error message should mention the missing path, got: \(msg)")
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }

    // MARK: Process execution

    @Test func directExecutionPassesArgvLiterally() async throws {
        let (echoBin, cleanupEcho) = try makeArgvEcho()
        defer { cleanupEcho() }
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("VF-dirExec-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmp) }

        let out = tmp.appendingPathComponent("out.wav")
        let service = SpeechGenerationService()

        let result = try await service.run(
            executableURL: echoBin,
            arguments: ["tts", "--text", #"spaces & quotes "test""#, "-o", out.path],
            outputURL: out
        )

        let lines = result.standardOutput.split(separator: "\n").map(String.init)
        #expect(lines.contains("ARG:tts"))
        #expect(lines.contains(#"ARG:spaces & quotes "test""#))
        #expect(lines.contains("ARG:-o"))
        #expect(lines.contains("ARG:\(out.path)"))
    }

    @Test func largeConcurrentStdoutAndStderrDoesNotDeadlock() async throws {
        let (loudBin, cleanupLoud) = try makeLoudExecutable()
        defer { cleanupLoud() }
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("VF-loudTest-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmp) }

        let out = tmp.appendingPathComponent("out.wav")
        let service = SpeechGenerationService()

        let result = try await service.run(
            executableURL: loudBin,
            arguments: [],
            outputURL: out
        )

        // Both stdout and stderr must be fully captured.
        #expect(result.standardOutput.contains("stdout-line-1"))
        #expect(result.standardOutput.contains("stdout-line-2000"))
        #expect(result.standardError.contains("stderr-line-1"))
        #expect(result.standardError.contains("stderr-line-2000"))
    }

    @Test func nonzeroExitCodePropagatesStderrAsError() async throws {
        let (failBin, cleanupFail) = try makeFailingExecutable()
        defer { cleanupFail() }
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("VF-failTest-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmp) }

        let out = tmp.appendingPathComponent("out.wav")
        let service = SpeechGenerationService()

        do {
            _ = try await service.run(
                executableURL: failBin,
                arguments: [],
                outputURL: out
            )
            Issue.record("Expected shellFailure for nonzero exit")
        } catch let error as SpeechGenerationError {
            #expect(error.errorDescription?.contains("error message") == true,
                    "Error should contain stderr: \(error.errorDescription ?? "")")
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }

    // MARK: Cancellation

    @Test func cancelBeforeProcessStartsThrowsCancellationError() async throws {
        let (sleepBin, cleanupSleep) = try makeSleepExecutable()
        defer { cleanupSleep() }
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("VF-cxlPre-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmp) }

        let out = tmp.appendingPathComponent("out.wav")
        let service = SpeechGenerationService()

        let task = Task<GenerationResult, Error> {
            try await service.run(
                executableURL: sleepBin,
                arguments: [],
                outputURL: out
            )
        }
        // Cancel immediately — before the process is even stored.
        task.cancel()

        do {
            _ = try await task.value
            Issue.record("Expected CancellationError")
        } catch is CancellationError {
            // expected
        } catch {
            Issue.record("Expected CancellationError, got \(error)")
        }
    }

    @Test func cancelInFlightProcessTerminatesChildReliably() async throws {
        let (sleepBin, cleanupSleep) = try makeSleepExecutable()
        defer { cleanupSleep() }
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("VF-cxlFlight-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmp) }

        let out = tmp.appendingPathComponent("out.wav")
        let service = SpeechGenerationService()

        let task = Task<GenerationResult, Error> {
            try await service.run(
                executableURL: sleepBin,
                arguments: [],
                outputURL: out
            )
        }

        // Let the child start, then cancel.
        try await Task.sleep(nanoseconds: 200_000_000)
        task.cancel()

        let start = Date()
        do {
            _ = try await task.value
            Issue.record("Expected CancellationError")
        } catch is CancellationError {
            // Must complete quickly (< 5s, not 300s sleep).
            #expect(Date().timeIntervalSince(start) < 5.0,
                    "Cancellation should complete quickly, took \(Date().timeIntervalSince(start))s")
        } catch {
            Issue.record("Expected CancellationError, got \(error)")
        }
    }

    // MARK: Output isolation

    @Test func outputIsIsolatedUnderInjectedRenderRoot() async throws {
        let fm = FileManager.default
        let base = fm.temporaryDirectory
            .appendingPathComponent("VF-iso-\(UUID().uuidString)", isDirectory: true)
        try fm.createDirectory(at: base, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: base) }

        let root = base.appendingPathComponent("CustomRoot", isDirectory: true)
        let service = SpeechGenerationService(renderRoot: root, fileManager: fm)
        let id = UUID()
        let url = try service.outputURL(forID: id)

        #expect(url.path.hasPrefix(root.path))
        #expect(url.path.hasSuffix("\(id.uuidString).wav"))
    }

    // MARK: WAV validation

    @Test func validatesWAVHeaderAfterSuccess() async throws {
        let fm = FileManager.default
        let tmp = fm.temporaryDirectory
            .appendingPathComponent("VF-wav-\(UUID().uuidString)", isDirectory: true)
        try fm.createDirectory(at: tmp, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: tmp) }

        let out = tmp.appendingPathComponent("out.wav")
        // Write valid WAV before the "process" runs (echo-argv doesn't write WAV).
        try writeSilentWAV(to: out)

        let service = SpeechGenerationService(fileManager: fm)
        // validateWAVOutput should succeed.
        try service.validateWAVOutput(at: out)
    }

    @Test func missingOutputFileThrowsAfterSuccess() throws {
        let fm = FileManager.default
        let tmp = fm.temporaryDirectory
            .appendingPathComponent("VF-noOut-\(UUID().uuidString)", isDirectory: true)
        try fm.createDirectory(at: tmp, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: tmp) }

        let out = tmp.appendingPathComponent("missing.wav")
        let service = SpeechGenerationService(fileManager: fm)

        do {
            try service.validateWAVOutput(at: out)
            Issue.record("Expected missing-output error")
        } catch let error as SpeechGenerationError {
            #expect(error.errorDescription?.contains("no audio file") == true)
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }

    @Test func invalidNonWAVOutputThrows() throws {
        let fm = FileManager.default
        let tmp = fm.temporaryDirectory
            .appendingPathComponent("VF-badWav-\(UUID().uuidString)", isDirectory: true)
        try fm.createDirectory(at: tmp, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: tmp) }

        let out = tmp.appendingPathComponent("bad.wav")
        try Data("not a wav".utf8).write(to: out)
        let service = SpeechGenerationService(fileManager: fm)

        do {
            try service.validateWAVOutput(at: out)
            Issue.record("Expected invalid-WAV error")
        } catch let error as SpeechGenerationError {
            // "not a valid WAV" is just 12 bytes — caught by minimum-size check.
            #expect(error.errorDescription?.contains("too small") == true ||
                    error.errorDescription?.contains("no audio file") == true,
                    "Unexpected message: \(error.errorDescription ?? "")")
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }

    @Test func emptyWAVFileIsInvalid() throws {
        let fm = FileManager.default
        let tmp = fm.temporaryDirectory
            .appendingPathComponent("VF-emptyWav-\(UUID().uuidString)", isDirectory: true)
        try fm.createDirectory(at: tmp, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: tmp) }

        let out = tmp.appendingPathComponent("empty.wav")
        try Data().write(to: out)
        let service = SpeechGenerationService(fileManager: fm)

        do {
            try service.validateWAVOutput(at: out)
            Issue.record("Expected invalid-WAV error for empty file")
        } catch is SpeechGenerationError {
            // expected
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }

    @Test func riffWithoutWAVEMarkerAtOffset8Throws() throws {
        let fm = FileManager.default
        let tmp = fm.temporaryDirectory
            .appendingPathComponent("VF-riffOnly-\(UUID().uuidString)", isDirectory: true)
        try fm.createDirectory(at: tmp, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: tmp) }

        let out = tmp.appendingPathComponent("bad.wav")
        // Write "RIFF" then garbage (not "WAVE") at offset 8.  Pad to 44+ bytes
        // so it passes the minimum-size check and hits the WAVE marker validation.
        var data = Data([0x52, 0x49, 0x46, 0x46]) // RIFF
        data.append(Data(repeating: 0, count: 4))  // fake chunk size
        data.append(Data([0x42, 0x41, 0x44, 0x00])) // not WAVE
        data.append(Data(repeating: 0, count: 32))  // pad to ≥ 44 bytes
        try data.write(to: out)

        let service = SpeechGenerationService(fileManager: fm)
        do {
            try service.validateWAVOutput(at: out)
            Issue.record("Expected invalid-WAV for RIFF-but-not-WAVE")
        } catch let error as SpeechGenerationError {
            #expect(error.errorDescription?.contains("WAVE marker") == true,
                    "Error should mention WAVE marker: \(error.errorDescription ?? "")")
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }

    // MARK: Unique output

    @Test func uniqueOutputPathPerGenerationID() throws {
        let service = SpeechGenerationService()
        let base = URL(fileURLWithPath: "/tmp")
        let id1 = UUID()
        let id2 = UUID()
        let url1 = try service.outputURL(forID: id1, applicationSupport: base)
        let url2 = try service.outputURL(forID: id2, applicationSupport: base)
        #expect(url1 != url2)
        #expect(url1.path.hasSuffix("\(id1.uuidString).wav"))
        #expect(url2.path.hasSuffix("\(id2.uuidString).wav"))
    }

    @Test func partialOutputCleanedOnRunFailure() async throws {
        let fm = FileManager.default
        let base = fm.temporaryDirectory
            .appendingPathComponent("VF-cleanup-\(UUID().uuidString)", isDirectory: true)
        try fm.createDirectory(at: base, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: base) }

        let id = UUID()
        let service = SpeechGenerationService(
            executableURL: URL(fileURLWithPath: "/bin/echo"),
            renderRoot: base,
            fileManager: fm,
            runner: { _, arguments, _ in
                let outputFlag = try #require(arguments.firstIndex(of: "-o"))
                let outputPath = try #require(arguments[safe: outputFlag + 1])
                try Data("partial output".utf8).write(
                    to: URL(fileURLWithPath: outputPath),
                    options: .atomic
                )
                return ("", "synthetic generation failure", 42)
            }
        )
        let expectedOut = try service.outputURL(forID: id)

        do {
            _ = try await service.generate(
                request: GenerationRequest(
                    id: id,
                    sourceText: "Test",
                    emotionText: "",
                    referenceAudioPath: "/tmp/reference.wav",
                    referenceText: "Reference"
                )
            )
            Issue.record("Expected failure")
        } catch let error as SpeechGenerationError {
            #expect(error.errorDescription?.contains("synthetic generation failure") == true)
        } catch {
            Issue.record("Unexpected error: \(error)")
        }

        #expect(!fm.fileExists(atPath: expectedOut.path),
                "Partial output survived failure at \(expectedOut.path)")
    }
}

private extension Array {
    subscript(safe index: Index) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
