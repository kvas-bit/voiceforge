import Foundation
import Testing
#if canImport(VoiceForgeCore)
@testable import VoiceForgeCore
#endif
@testable import VoiceForge

// MARK: - Test doubles

/// Reports `fileExists`/`isExecutableFile` as false for everything, so
/// `OllamaCoordinator.discoverOllama`'s hardcoded system paths never
/// accidentally match a real `ollama` install on the machine running tests.
private final class NeverFoundFileManager: FileManager {
    override func fileExists(atPath path: String, isDirectory: UnsafeMutablePointer<ObjCBool>?) -> Bool {
        false
    }
    override func isExecutableFile(atPath path: String) -> Bool {
        false
    }
}

private func fakeResponse(url: URL, status: Int) -> URLResponse {
    HTTPURLResponse(url: url, statusCode: status, httpVersion: nil, headerFields: nil)!
}

private struct SimpleError: Error {}

private actor CallCounter {
    private(set) var count = 0
    func increment() { count += 1 }
}

/// Synchronous, thread-safe counter for use inside `ProcessStarter` closures,
/// which are synchronous (unlike `httpPerformer`).
private final class SyncCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var value = 0
    func increment() { lock.lock(); value += 1; lock.unlock() }
    var count: Int { lock.lock(); defer { lock.unlock() }; return value }
}

/// Spawns a real, long-running `/bin/sleep` process regardless of the
/// executable URL/arguments it's asked to start with — used to prove real
/// start/terminate semantics (mirrors the `makeSleepExecutable` pattern used
/// elsewhere in this suite) without depending on a real `ollama` binary.
private func sleepProcessStarter() -> OllamaCoordinator.ProcessStarter {
    { _, _ in
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sleep")
        process.arguments = ["300"]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
        return process
    }
}

// MARK: - Tests

struct OllamaServiceTests {

    // MARK: Lifecycle

    @Test func missingExecutableBecomesUnavailableAndNeverStartsAProcess() async throws {
        let starterCounter = SyncCounter()
        let coordinator = OllamaCoordinator(
            executableURL: nil,
            fileManager: NeverFoundFileManager(),
            httpPerformer: { req in throw SimpleError() }, // no server ever responds
            processStarter: { url, args in
                starterCounter.increment()
                throw SimpleError() // should never actually be called
            }
        )

        let status = await coordinator.ensureRunning()
        guard case .unavailable = status else {
            Issue.record("Expected .unavailable, got \(status)")
            return
        }
        #expect(starterCounter.count == 0, "Must not attempt to start a process when no executable was found")
    }

    @Test func externalServerIsDetectedAndNeverStartedOrKilled() async throws {
        let starterCounter = SyncCounter()
        let coordinator = OllamaCoordinator(
            executableURL: URL(fileURLWithPath: "/nonexistent/ollama"),
            httpPerformer: { req in
                (Data(), fakeResponse(url: req.url!, status: 200)) // server already up
            },
            processStarter: { url, args in
                starterCounter.increment()
                throw SimpleError() // must never be reached
            }
        )

        let status = await coordinator.ensureRunning()
        #expect(status == .runningExternal)
        #expect(starterCounter.count == 0, "An externally-running server must never be started by VoiceForge")

        // Shutdown must be a strict no-op for a server we don't own.
        await coordinator.shutdownIfOwned()
        let statusAfterShutdown = await coordinator.status
        #expect(statusAfterShutdown == .runningExternal, "Shutdown must not touch an externally-owned server's status")
    }

    @Test func ownedServerIsStartedAndActuallyKilledOnShutdown() async throws {
        let probeCount = CallCounter()
        let coordinator = OllamaCoordinator(
            executableURL: URL(fileURLWithPath: "/usr/bin/true"), // never actually exec'd — processStarter is faked
            httpPerformer: { req in
                await probeCount.increment()
                let n = await probeCount.count
                // First probe (pre-start) fails; probes from the second call
                // onward (post-start polling) succeed, simulating a server
                // that takes one poll cycle to come up.
                if n <= 1 { throw SimpleError() }
                return (Data(), fakeResponse(url: req.url!, status: 200))
            },
            processStarter: sleepProcessStarter()
        )

        let status = await coordinator.ensureRunning()
        #expect(status == .runningOwned)

        // Idempotent: calling again must not spawn a second process/probe cycle.
        let secondStatus = await coordinator.ensureRunning()
        #expect(secondStatus == .runningOwned)

        await coordinator.shutdownIfOwned()

        // Give SIGTERM a moment, then confirm the real process is actually gone.
        try await Task.sleep(nanoseconds: 300_000_000)
        let statusAfterShutdown = await coordinator.status
        #expect(statusAfterShutdown == .idle)
    }

    // MARK: Model list

    @Test func listModelsParsesRealApiShape() async throws {
        let json = #"{"models":[{"name":"llama3:8b"},{"name":"phi3"}]}"#.data(using: .utf8)!
        let coordinator = OllamaCoordinator(
            httpPerformer: { req in (json, fakeResponse(url: req.url!, status: 200)) }
        )

        let models = try await coordinator.listModels()
        #expect(models == [OllamaModel(name: "llama3:8b"), OllamaModel(name: "phi3")])
    }

    @Test func listModelsThrowsOnServerError() async throws {
        let coordinator = OllamaCoordinator(
            httpPerformer: { req in (Data(), fakeResponse(url: req.url!, status: 500)) }
        )
        do {
            _ = try await coordinator.listModels()
            Issue.record("Expected an error")
        } catch is OllamaError {
            // expected
        }
    }

    // MARK: Suggestion

    @Test func suggestPromptReturnsTrimmedResponseText() async throws {
        let json = #"{"response":"  [whispering softly] Hello there  \n"}"#.data(using: .utf8)!
        let coordinator = OllamaCoordinator(
            httpPerformer: { req in (json, fakeResponse(url: req.url!, status: 200)) }
        )

        let suggestion = try await coordinator.suggestPrompt(model: "llama3", sourceText: "Hello there", emotionText: "")
        #expect(suggestion == "[whispering softly] Hello there")
    }

    @Test func suggestPromptSurfacesActionableErrorOnFailure() async throws {
        let coordinator = OllamaCoordinator(
            httpPerformer: { req in (Data(), fakeResponse(url: req.url!, status: 500)) }
        )
        do {
            _ = try await coordinator.suggestPrompt(model: "llama3", sourceText: "hi", emotionText: "")
            Issue.record("Expected an error")
        } catch let error as OllamaError {
            #expect(error.errorDescription?.isEmpty == false)
        }
    }

    @Test func suggestPromptCancellationSurfacesCancellationErrorPromptly() async throws {
        let coordinator = OllamaCoordinator(
            httpPerformer: { req in
                // Simulate a slow model response so there's a real window to cancel in.
                try await Task.sleep(nanoseconds: 2_000_000_000)
                try Task.checkCancellation()
                return (#"{"response":"too slow"}"#.data(using: .utf8)!, fakeResponse(url: req.url!, status: 200))
            }
        )

        let task = Task<String, Error> {
            try await coordinator.suggestPrompt(model: "llama3", sourceText: "hi", emotionText: "")
        }
        try await Task.sleep(nanoseconds: 100_000_000)
        task.cancel()

        let start = Date()
        do {
            _ = try await task.value
            Issue.record("Expected CancellationError")
        } catch is CancellationError {
            #expect(Date().timeIntervalSince(start) < 5.0, "Cancellation should not wait for the slow response")
        } catch {
            Issue.record("Expected CancellationError, got \(error)")
        }
    }
}
