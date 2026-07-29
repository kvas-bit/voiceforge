import Foundation

// MARK: - Protocol types

struct PersistentRequest: Codable {
    let action: String          // "start" | "generate"
    let id: String
    let text: String?
    let ref_audio: String?
    let ref_text: String?
    let output: String?
    let max_new_tokens: Int?
}
struct PersistentEvent: Codable {
    let event: String           // starting|loading_model|ready|accepted|generating|writing|done|error
    let id: String
    let output: String?
    let message: String?
}

// MARK: - Shebang parser

enum ShebangParser {
    /// Resolves the Python interpreter from the shebang of the given file.
    /// Supports absolute paths and `/usr/bin/env` forms.
    static func resolvePython(mlxPath: String, fileManager: FileManager = .default) -> URL? {
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: mlxPath)),
              let firstLine = String(decoding: data.prefix(128), as: UTF8.self)
                .split(separator: "\n").first,
              firstLine.hasPrefix("#!") else { return nil }
        var shebang = String(firstLine.dropFirst(2)).trimmingCharacters(in: .whitespaces)
        if shebang.hasPrefix("/usr/bin/env ") {
            let tool = shebang.replacingOccurrences(of: "/usr/bin/env ", with: "")
                .trimmingCharacters(in: .whitespaces)
            let which = Process()
            which.executableURL = URL(fileURLWithPath: "/usr/bin/which"); which.arguments = [tool]
            let p = Pipe(); which.standardOutput = p
            do { try which.run(); which.waitUntilExit()
                let found = String(decoding: p.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                if !found.isEmpty, fileManager.isExecutableFile(atPath: found) { return URL(fileURLWithPath: found) }
            } catch { }
            return nil
        }
        let url = URL(fileURLWithPath: shebang)
        return fileManager.isExecutableFile(atPath: url.path) ? url : nil
    }
}

// MARK: - Coordinator

/// Manages one persistent helper process. Prepares once, serializes requests,
/// supports prewarm+shutdown lifecycle, and handles cancellation.
actor PersistentGenerationCoordinator {

    private var process: Process?
    private var stdinHandle: FileHandle?
    private var stdoutHandle: FileHandle?
    private var isPrepared = false
    private var preparing = false      // reentrancy guard
    /// Tasks waiting for the preparation to complete.
    private var preparationWaiters: [CheckedContinuation<Bool, Never>] = []
    private let helperPath: String
    private let executableURL: URL
    private let jsonEncoder = JSONEncoder()
    private let jsonDecoder = JSONDecoder()
    private var lineBuffer = Data()

    /// Serial request queue — pending Tasks wait for their turn.
    private var requestQueue: [CheckedContinuation<PersistentGenerationCoordinator, Never>] = []
    private var activeRequest = false

    init(helperPath: String, executableURL: URL) {
        self.helperPath = helperPath
        self.executableURL = executableURL
    }

    // MARK: - Lifecycle

    /// Start the helper and warm the model once. Idempotent.
    func prewarmOnce() async -> Bool {
        if isPrepared { return true }
        if preparing {
            // Another caller is already preparing — await its result.
            return await withCheckedContinuation { preparationWaiters.append($0) }
        }
        preparing = true
        defer {
            preparing = false
            let ok = isPrepared
            for w in preparationWaiters { w.resume(returning: ok) }
            preparationWaiters.removeAll()
        }
        guard await startHelper() else { return false }
        defer { if !isPrepared { shutdown() } }
        do {
            let startReq = PersistentRequest(action: "start", id: "prewarm",
                text: nil, ref_audio: nil, ref_text: nil, output: nil, max_new_tokens: nil)
            try stdinHandle?.write(contentsOf: encodeLine(startReq))
            while let event = try await readNextEvent() {
                if event.event == "ready" && event.id == "prewarm" { isPrepared = true; return true }
                if event.event == "error" { return false }
            }
        } catch { }
        return false
    }

    /// Queued generate. Blocks until its turn, then sends the request and
    /// waits for done/error. Multiple callers are serialized safely.
    ///
    /// Readiness (`isPrepared`/`stdinHandle`) is captured *before* queuing but
    /// re-checked *after* being dequeued — a caller ahead in line may have been
    /// cancelled and torn down the whole helper (`shutdown()`) while this call
    /// was waiting its turn, which would otherwise leave it writing to a closed
    /// `FileHandle` and surfacing a raw, non-actionable error instead of a clean
    /// `PersistentError.notReady` that the caller can fall back to CLI on.
    func generate(
        id: String, text: String, referenceAudio: String,
        referenceText: String, output: String, maxNewTokens: Int? = nil
    ) async throws -> String {
        guard isPrepared else { throw PersistentError.notReady }

        // Wait for turn in the queue.
        let coordinator: PersistentGenerationCoordinator = await withCheckedContinuation { cont in
            if !activeRequest { activeRequest = true; cont.resume(returning: self); return }
            requestQueue.append(cont)
        }
        defer {
            if requestQueue.isEmpty { activeRequest = false }
            else { requestQueue.removeFirst().resume(returning: self) }
        }

        // Re-check readiness after dequeuing: the request ahead of us may have
        // been cancelled and shut the helper down while we were waiting.
        guard isPrepared, let stdin = stdinHandle else { throw PersistentError.notReady }

        // Check cancellation before sending request.
        try Task.checkCancellation()

        let req = PersistentRequest(action: "generate", id: id,
            text: text, ref_audio: referenceAudio, ref_text: referenceText,
            output: output, max_new_tokens: maxNewTokens)
        try stdin.write(contentsOf: encodeLine(req))

        var accepted = false
        while let event = try await coordinator.readNextEvent() {
            guard event.id == id else { continue }
            switch event.event {
            case "accepted": accepted = true; continue
            case "done":
                try Task.checkCancellation()
                return event.output ?? output
            case "error":
                throw accepted
                    ? PersistentError.postAcceptFailure(event.message ?? "")
                    : PersistentError.preAcceptFailure(event.message ?? "")
            default: continue
            }
        }
        // EOF — map to appropriate error.
        throw accepted
            ? PersistentError.postAcceptFailure("helper exited unexpectedly")
            : PersistentError.preAcceptFailure("helper exited before accepting request")
    }

    /// Graceful shutdown — close stdin, terminate.
    func shutdown() {
        let proc = process; process = nil
        isPrepared = false; preparing = false
        lineBuffer = Data()
        try? stdinHandle?.close(); stdinHandle = nil; stdoutHandle = nil
        guard let proc, proc.isRunning else { return }
        proc.terminate()
        let pid = proc.processIdentifier
        DispatchQueue.global(qos: .userInitiated).asyncAfter(deadline: .now() + 1.0) {
            if proc.isRunning { kill(pid, SIGKILL) }
        }
    }

    deinit { try? stdinHandle?.close(); process?.terminate() }

    // MARK: - Private

    private func startHelper() async -> Bool {
        let proc = Process()
        proc.executableURL = executableURL; proc.arguments = [helperPath]
        let sin = Pipe(); let sout = Pipe(); let serr = Pipe()
        proc.standardInput = sin; proc.standardOutput = sout; proc.standardError = serr
        do { try proc.run() } catch { return false }
        process = proc; stdinHandle = sin.fileHandleForWriting; stdoutHandle = sout.fileHandleForReading
        Task.detached { _ = serr.fileHandleForReading.readDataToEndOfFile() }
        return true
    }

    private func readNextEvent() async throws -> PersistentEvent? {
        while true {
            if let nl = lineBuffer.firstIndex(of: 0x0A) {
                let ld = lineBuffer[..<nl]; lineBuffer.removeSubrange(...nl)
                if let e = try? parseEvent(ld) { return e }
                continue
            }
            guard let h = stdoutHandle else { return nil }
            let ch: Data = await withCheckedContinuation { c in
                DispatchQueue.global(qos: .userInitiated).async { c.resume(returning: h.availableData) }
            }
            if ch.isEmpty { return nil }
            lineBuffer.append(ch)
        }
    }

    private func parseEvent(_ data: Data) throws -> PersistentEvent? {
        let line = String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        guard line.hasPrefix("EVENT:"),
              let jd = String(line.dropFirst(6)).data(using: .utf8) else { return nil }
        return try jsonDecoder.decode(PersistentEvent.self, from: jd)
    }

    private func encodeLine(_ req: PersistentRequest) -> Data {
        (String(decoding: try! jsonEncoder.encode(req), as: UTF8.self) + "\n").data(using: .utf8)!
    }
}

enum PersistentError: Error {
    case notReady, encodingFailed
    case preAcceptFailure(String)
    case postAcceptFailure(String)
}

// MARK: - Registry (thread-safe, lazily resolved)

public final class CoordinatorRegistry: @unchecked Sendable {
    private let lock = NSLock()
    private var coordinator: PersistentGenerationCoordinator?
    private let fileManager: FileManager
    private let defaultHelperPath: String

    /// A resolver that produces (executableURL, helperPath) for the coordinator.
    /// Called lazily on first access so the production `init` doesn't need the
    /// mlx-speech path upfront.
    typealias Resolver = @Sendable (FileManager) -> (executableURL: URL, helperPath: String)?

    private let resolver: Resolver

    init(resolver: @escaping Resolver, fallbackHelperPath: String, fileManager: FileManager) {
        self.resolver = resolver
        self.defaultHelperPath = fallbackHelperPath
        self.fileManager = fileManager
    }

    func getOrCreate() -> PersistentGenerationCoordinator {
        lock.lock(); defer { lock.unlock() }
        if let c = coordinator { return c }
        // If resolver fails, use a clearly invalid path so startHelper→prewarmOnce return false.
        let cfg = resolver(fileManager) ?? (URL(fileURLWithPath: "/dev/null"), defaultHelperPath)
        let c = PersistentGenerationCoordinator(helperPath: cfg.helperPath, executableURL: cfg.executableURL)
        coordinator = c; return c
    }

    func shutdownCurrent() async {
        let c = exchangeCoordinator(nil); await c?.shutdown()
    }

    private func exchangeCoordinator(_ newValue: PersistentGenerationCoordinator?) -> PersistentGenerationCoordinator? {
        lock.lock(); defer { lock.unlock() }
        let old = coordinator; coordinator = newValue; return old
    }
}
