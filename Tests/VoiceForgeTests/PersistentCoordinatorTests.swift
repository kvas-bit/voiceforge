import Foundation
import Testing
#if canImport(VoiceForgeCore)
@testable import VoiceForgeCore
#else
@testable import VoiceForge
#endif

// MARK: - Fake helper that branches on text content

private func makeFakeHelper(
    capturePath: String,
    launchCountPath: String
) throws -> (sh: URL, script: URL, cleanup: () -> Void) {
    let dir = FileManager.default.temporaryDirectory
        .appendingPathComponent("VF-helper-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    let cleanup: () -> Void = { _ = try? FileManager.default.removeItem(at: dir) }
    let script = dir.appendingPathComponent("fake-helper")
    let sh = """
    #!/bin/sh
    CAPTURE='\(capturePath)'
    LCOUNT='\(launchCountPath)'
    mkdir -p "$(dirname "$LCOUNT")"
    if [ -f "$LCOUNT" ]; then c=$(cat "$LCOUNT"); echo $((c + 1)) > "$LCOUNT"; else echo 1 > "$LCOUNT"; fi
    while IFS= read -r line; do
        echo "$line" >> "$CAPTURE"
        action=$(echo "$line" | grep -o '"action":"[^"]*"' | cut -d'"' -f4)
        id=$(echo "$line" | grep -o '"id":"[^"]*"' | cut -d'"' -f4)
        out=$(echo "$line" | grep -o '"output":"[^"]*"' | cut -d'"' -f4)
        text=$(echo "$line" | grep -o '"text":"[^"]*"' | cut -d'"' -f4)
        if [ "$action" = "start" ]; then
            echo "EVENT:{\\"event\\":\\"starting\\",\\"id\\":\\"$id\\"}"
            echo "EVENT:{\\"event\\":\\"loading_model\\",\\"id\\":\\"$id\\"}"
            echo "EVENT:{\\"event\\":\\"ready\\",\\"id\\":\\"$id\\"}"
        elif [ "$text" = "BLOCK" ]; then
            echo "EVENT:{\\"event\\":\\"accepted\\",\\"id\\":\\"$id\\"}"
            echo "EVENT:{\\"event\\":\\"generating\\",\\"id\\":\\"$id\\"}"
            touch "$out"
            exec sleep 300
        elif [ "$text" = "ERROR_POST" ]; then
            echo "EVENT:{\\"event\\":\\"accepted\\",\\"id\\":\\"$id\\"}"
            echo "EVENT:{\\"event\\":\\"error\\",\\"id\\":\\"$id\\",\\"message\\":\\"post-accept crash\\"}"
        elif [ "$action" = "generate" ]; then
            echo "EVENT:{\\"event\\":\\"accepted\\",\\"id\\":\\"$id\\"}"
            echo "EVENT:{\\"event\\":\\"generating\\",\\"id\\":\\"$id\\"}"
            echo "EVENT:{\\"event\\":\\"done\\",\\"id\\":\\"$id\\",\\"output\\":\\"$out\\"}"
        fi
    done
    """
    try sh.write(to: script, atomically: true, encoding: .utf8)
    try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: script.path)
    return (URL(fileURLWithPath: "/bin/sh"), script, cleanup)
}

// MARK: - Helpers

private func readCaptureLines(_ path: String) throws -> [String] {
    try String(contentsOfFile: path, encoding: .utf8).split(separator: "\n").map(String.init)
}
private func readLaunchCount(_ path: String) -> Int {
    (try? Int(String(contentsOfFile: path, encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines))) ?? 0
}

// Create a fake registry wired for tests.
private func makeFakeRegistry(capture: String, lc: String) throws -> (reg: CoordinatorRegistry, cleanup: () -> Void) {
    let (sh, script, c1) = try makeFakeHelper(capturePath: capture, launchCountPath: lc)
    let reg = CoordinatorRegistry(
        resolver: { _ in (sh, script.path) },
        fallbackHelperPath: script.path,
        fileManager: .default)
    return (reg, c1)
}

// Helper to build a SpeechGenerationService with fake registry.
private func makeFakeService(
    fakeReg: CoordinatorRegistry,
    renderRoot: URL,
    runnerCount: ActorCounter? = nil
) -> SpeechGenerationService {
    // Runner that writes a valid WAV to the output arg so CLI fallback succeeds.
    let runner: @Sendable (URL, [String], ProcessBox) async throws -> (String, String, Int32) = { _, args, _ in
        await runnerCount?.inc()
        // Find the -o output path in args and write a minimal valid WAV.
        if let oIdx = args.firstIndex(of: "-o"), oIdx + 1 < args.count {
            let outPath = args[oIdx + 1]
            try writeSilentWAV(to: URL(fileURLWithPath: outPath))
        }
        return ("ok", "", 0)
    }
    return SpeechGenerationService.__internalInit(
        executableURL: URL(fileURLWithPath: "/bin/sh"),
        renderRoot: renderRoot,
        fileManager: .default,
        runner: runner,
        usePersistent: true,
        coordinatorRegistry: fakeReg
    )
}

actor ActorCounter {
    var count = 0
    func inc() { count += 1 }
    func getCount() -> Int { count }
}

// MARK: - Tests

struct PersistentCoordinatorTests {

    @Test func modelIsCarriedOnStartAndGenerateRequests() async throws {
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("VF-model-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmp) }
        let capture = tmp.appendingPathComponent("requests.jsonl").path
        let (registry, cleanup) = try makeFakeRegistry(capture: capture, lc: tmp.appendingPathComponent("launch-count").path)
        defer { cleanup() }
        let coordinator = registry.getOrCreate()
        #expect(await coordinator.prewarmOnce(model: "drama-3"))
        _ = try await coordinator.generate(id: "switch", text: "hello", referenceAudio: "/r.wav",
            referenceText: "hello", output: tmp.appendingPathComponent("out.wav").path,
            model: "fish-s2-pro")
        let requests = try readCaptureLines(capture)
        #expect(requests[0].contains(#""model":"drama-3""#))
        #expect(requests[1].contains(#""model":"fish-s2-pro""#))
    }

    @Test func oneProcessLoadsModelOnceAcrossTwoRequests() async throws {
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("VF-once-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmp) }
        let cap = tmp.appendingPathComponent("capture.jsonl").path
        let lc = tmp.appendingPathComponent("launch-count").path

        let (reg, cleanup) = try makeFakeRegistry(capture: cap, lc: lc); defer { cleanup() }
        let c = reg.getOrCreate()
        _ = await c.prewarmOnce()
        _ = try await c.generate(id: "a", text: "alpha", referenceAudio: "/r.wav", referenceText: "r", output: tmp.appendingPathComponent("a.wav").path)
        _ = try await c.generate(id: "b", text: "bravo", referenceAudio: "/r.wav", referenceText: "r", output: tmp.appendingPathComponent("b.wav").path)
        #expect(readLaunchCount(lc) == 1, "Should load model once for two requests")
    }

    @Test func maxNewTokensPassedThroughProtocol() async throws {
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("VF-tok-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmp) }
        let cap = tmp.appendingPathComponent("capture.jsonl").path
        let lc = tmp.appendingPathComponent("launch-count").path
        let (reg, cleanup) = try makeFakeRegistry(capture: cap, lc: lc); defer { cleanup() }
        let c = reg.getOrCreate(); _ = await c.prewarmOnce()
        _ = try await c.generate(id: "t", text: "x", referenceAudio: "/r.wav", referenceText: "r", output: tmp.appendingPathComponent("t.wav").path, maxNewTokens: 2048)
        let lines = try readCaptureLines(cap)
        #expect(lines.last!.contains(#""max_new_tokens":2048"#))
    }

    @Test func capturesUnicodePayload() async throws {
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("VF-uni-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmp) }
        let cap = tmp.appendingPathComponent("capture.jsonl").path
        let lc = tmp.appendingPathComponent("launch-count").path
        let (reg, cleanup) = try makeFakeRegistry(capture: cap, lc: lc); defer { cleanup() }
        let c = reg.getOrCreate(); _ = await c.prewarmOnce()
        let text = "héllo \"wörld\""
        _ = try await c.generate(id: "u", text: text, referenceAudio: "/r.wav", referenceText: "r", output: tmp.appendingPathComponent("u.wav").path)
        let lines = try readCaptureLines(cap)
        #expect(lines.last!.contains("héllo") || lines.last!.contains(#"\"wörld\""#) || lines.last!.contains("wörld"))
    }

    @Test func prewarmIdempotent() async throws {
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("VF-idem-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmp) }
        let (reg, cleanup) = try makeFakeRegistry(capture: tmp.appendingPathComponent("cap.jsonl").path, lc: tmp.appendingPathComponent("lc").path); defer { cleanup() }
        let c = reg.getOrCreate()
        #expect(await c.prewarmOnce()); #expect(await c.prewarmOnce())
    }

    @Test func concurrentRequestsSerializeWithoutDeadlock() async throws {
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("VF-conc-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmp) }
        let (reg, cleanup) = try makeFakeRegistry(capture: tmp.appendingPathComponent("cap.jsonl").path, lc: tmp.appendingPathComponent("lc").path); defer { cleanup() }
        let c = reg.getOrCreate(); _ = await c.prewarmOnce()
        async let r1 = c.generate(id: "c1", text: "a", referenceAudio: "/r.wav", referenceText: "r", output: tmp.appendingPathComponent("c1.wav").path)
        async let r2 = c.generate(id: "c2", text: "b", referenceAudio: "/r.wav", referenceText: "r", output: tmp.appendingPathComponent("c2.wav").path)
        async let r3 = c.generate(id: "c3", text: "c", referenceAudio: "/r.wav", referenceText: "r", output: tmp.appendingPathComponent("c3.wav").path)
        let (o1, o2, o3) = try await (r1, r2, r3)
        #expect(o1.hasSuffix("c1.wav")); #expect(o2.hasSuffix("c2.wav")); #expect(o3.hasSuffix("c3.wav"))
    }

    // MARK: - Cancellation (helper kill + partial removed + restart)

    @Test func cancellationKillsHelperRemovesPartialAndNextRequestStartsFresh() async throws {
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("VF-cxl-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmp) }
        let cap = tmp.appendingPathComponent("capture.jsonl").path
        let lc = tmp.appendingPathComponent("launch-count").path

        let (reg, cleanup) = try makeFakeRegistry(capture: cap, lc: lc); defer { cleanup() }
        let svc = makeFakeService(fakeReg: reg, renderRoot: tmp)

        // Prewarm — launch count 1.
        let ready = await svc.prewarmPersistentHelper()
        #expect(ready)
        #expect(readLaunchCount(lc) == 1)

        let partialID = UUID()
        let partialOut = tmp.appendingPathComponent("\(partialID.uuidString).wav")

        // Send a BLOCK request — helper touches partial output then exec sleep.
        let blockReq = GenerationRequest(
            id: partialID, sourceText: "BLOCK", emotionText: "",
            referenceAudioPath: "/tmp/r.wav", referenceText: "r",
            model: "fish-s2-pro")

        let genTask = Task<GenerationResult, Error> {
            try await svc.generate(request: blockReq)
        }
        // Let helper accept and start blocking.
        try await Task.sleep(nanoseconds: 200_000_000)

        genTask.cancel()
        let start = Date()
        do {
            _ = try await genTask.value
            Issue.record("Expected CancellationError")
        } catch is CancellationError {
            #expect(Date().timeIntervalSince(start) < 5.0, "Cancellation should complete within 5s")
        } catch {
            Issue.record("Expected CancellationError, got \(error)")
        }

        // Partial output must be removed.
        #expect(!FileManager.default.fileExists(atPath: partialOut.path),
                "Partial output \(partialOut.path) should be cleaned up")

        // Next request starts a fresh helper.
        let ready2 = await svc.prewarmPersistentHelper()
        #expect(ready2)
        #expect(readLaunchCount(lc) == 2, "Should launch a second helper after kill")
    }

    // MARK: - Queued follower survives active request's cancellation

    /// Regression for the cancel-with-queued-follower race: an active request
    /// that's already been accepted blocks the helper; cancelling it tears the
    /// whole coordinator down (kills the process, closes `stdinHandle`). A
    /// second request that was already queued behind it must not try to write
    /// to that now-closed `FileHandle` (which previously surfaced a raw,
    /// non-actionable POSIX error) — it must see a clean `.notReady`/
    /// `.preAcceptFailure` and fall back to CLI exactly once, with no trace of
    /// the first request's partial output left behind, and the helper must be
    /// restartable afterward.
    @Test func queuedFollowerFallsBackCleanlyWhenActiveRequestIsCancelled() async throws {
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("VF-cxlQueue-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmp) }
        let cap = tmp.appendingPathComponent("capture.jsonl").path
        let lc = tmp.appendingPathComponent("launch-count").path

        let (reg, cleanup) = try makeFakeRegistry(capture: cap, lc: lc); defer { cleanup() }
        let counter = ActorCounter()
        let svc = makeFakeService(fakeReg: reg, renderRoot: tmp, runnerCount: counter)

        // Prewarm — launch count 1.
        let ready = await svc.prewarmPersistentHelper()
        #expect(ready)
        #expect(readLaunchCount(lc) == 1)

        let activeID = UUID()
        let activePartialOut = tmp.appendingPathComponent("\(activeID.uuidString).wav")

        // Active request: gets accepted, then blocks the helper (exec sleep 300).
        let activeReq = GenerationRequest(
            id: activeID, sourceText: "BLOCK", emotionText: "",
            referenceAudioPath: "/tmp/r.wav", referenceText: "r",
            model: "fish-s2-pro")
        let activeTask = Task<GenerationResult, Error> {
            try await svc.generate(request: activeReq)
        }

        // Let the active request get accepted and start blocking before queuing
        // the follower behind it.
        try await Task.sleep(nanoseconds: 200_000_000)

        let queuedID = UUID()
        let queuedReq = GenerationRequest(
            id: queuedID, sourceText: "hello from the queue", emotionText: "",
            referenceAudioPath: "/tmp/r.wav", referenceText: "r",
            model: "fish-s2-pro")
        let queuedTask = Task<GenerationResult, Error> {
            try await svc.generate(request: queuedReq)
        }

        // Let the follower actually enter the coordinator's requestQueue
        // (it must observe isPrepared==true and block on activeRequest) before
        // we cancel the active one out from under it.
        try await Task.sleep(nanoseconds: 100_000_000)

        activeTask.cancel()

        // Active request must surface CancellationError, not hang.
        let start = Date()
        do {
            _ = try await activeTask.value
            Issue.record("Expected CancellationError for the active/cancelled request")
        } catch is CancellationError {
            #expect(Date().timeIntervalSince(start) < 5.0, "Cancellation should complete quickly")
        } catch {
            Issue.record("Expected CancellationError, got \(error)")
        }

        // Queued follower must complete via clean CLI fallback — not hang, not
        // throw a raw FileHandle/POSIX error, not silently produce no output.
        let queuedResult: GenerationResult
        do {
            queuedResult = try await queuedTask.value
        } catch {
            Issue.record("Queued follower should have fallen back to CLI cleanly, got \(error)")
            return
        }

        // Exactly one CLI fallback — for the queued follower. The active
        // request never reaches CLI fallback (it was accepted, then cancelled).
        let runnerInvocations = await counter.getCount()
        #expect(runnerInvocations == 1, "CLI runner should be invoked exactly once, for the queued follower")

        // The follower's own output must be a real, complete file — not a
        // leftover partial.
        #expect(FileManager.default.fileExists(atPath: queuedResult.outputURL.path),
                "Queued follower's fallback output should exist")

        // The cancelled active request's partial output must not survive.
        #expect(!FileManager.default.fileExists(atPath: activePartialOut.path),
                "Active request's partial output should be cleaned up, not leaked")

        // Helper must be restartable after the forced shutdown.
        let ready2 = await svc.prewarmPersistentHelper()
        #expect(ready2)
        #expect(readLaunchCount(lc) == 2, "Should launch a fresh helper after the forced shutdown")
    }

    // MARK: - Pre-accept fallback

    @Test func preAcceptFailureFallsBackToCLIOnce() async throws {
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("VF-pref-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmp) }

        // Use a Registry that always fails to resolve → prewarm returns false.
        let deadReg = CoordinatorRegistry(
            resolver: { _ in nil },
            fallbackHelperPath: "/dev/null",
            fileManager: .default
        )
        let counter = ActorCounter()
        let svc = makeFakeService(fakeReg: deadReg, renderRoot: tmp, runnerCount: counter)

        let req = GenerationRequest(id: UUID(), sourceText: "test", emotionText: "",
            referenceAudioPath: "/tmp/r.wav", referenceText: "r", model: "fish-s2-pro")
        _ = try await svc.generate(request: req)

        let c = await counter.getCount()
        #expect(c == 1, "CLI runner should have been invoked exactly once")
    }

    // MARK: - Post-accept no-retry

    @Test func postAcceptFailureDoesNotRetryViaCLI() async throws {
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("VF-post-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmp) }
        let cap = tmp.appendingPathComponent("capture.jsonl").path
        let lc = tmp.appendingPathComponent("launch-count").path

        let (reg, cleanup) = try makeFakeRegistry(capture: cap, lc: lc); defer { cleanup() }
        let counter = ActorCounter()
        let svc = makeFakeService(fakeReg: reg, renderRoot: tmp, runnerCount: counter)

        // Prewarm.
        _ = await svc.prewarmPersistentHelper()

        // ERROR_POST: helper emits accepted, then error.
        let req = GenerationRequest(id: UUID(), sourceText: "ERROR_POST", emotionText: "",
            referenceAudioPath: "/tmp/r.wav", referenceText: "r", model: "fish-s2-pro")
        do {
            _ = try await svc.generate(request: req)
            Issue.record("Expected postAcceptFailure")
        } catch let e as PersistentError {
            switch e {
            case .postAcceptFailure: break // expected
            case .preAcceptFailure: Issue.record("Got preAcceptFailure, expected postAcceptFailure")
            default: Issue.record("Unexpected error: \(e)")
            }
        } catch {
            Issue.record("Unexpected error type: \(error)")
        }

        let c = await counter.getCount()
        #expect(c == 0, "CLI runner must NOT have been called after post-accept failure")
    }

    @Test func cancelBeforeAcceptedNeverLaunchesCLI() async throws {
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("VF-cba-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmp) }

        // Dead registry — prewarm fails, so generate uses CLI fallback.
        // But cancellation must prevent the CLI from running.
        let deadReg = CoordinatorRegistry(
            resolver: { _ in nil },
            fallbackHelperPath: "/dev/null",
            fileManager: .default
        )
        let counter = ActorCounter()
        let svc = makeFakeService(fakeReg: deadReg, renderRoot: tmp, runnerCount: counter)

        let req = GenerationRequest(id: UUID(), sourceText: "test", emotionText: "",
            referenceAudioPath: "/tmp/r.wav", referenceText: "r", model: "fish-s2-pro")

        let genTask = Task<GenerationResult, Error> {
            try await svc.generate(request: req)
        }
        // Cancel before the task gets to the CLI path.
        genTask.cancel()

        do {
            _ = try await genTask.value
            Issue.record("Expected CancellationError")
        } catch is CancellationError {
            // expected
        } catch {
            Issue.record("Expected CancellationError, got \(error)")
        }

        let c = await counter.getCount()
        #expect(c == 0, "CLI runner must NOT be called when cancelled before fallback")
    }
}
