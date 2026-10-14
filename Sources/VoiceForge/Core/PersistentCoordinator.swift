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
    let model: String?
    let references: [PersistentReference]?
    let temperature: Double?
    let top_p: Double?
    let top_k: Int?
    let seed: Int?
    let normalize: Bool?
    let previous_takes: [PreviousTake]?
    let save_codes: String?
    let speakers: [PersistentSpeaker]?
    let lines: [PersistentLine]?
    let direction: String?
    let line_outputs: [String]?
    let language: String?
    let audio: String?
    let load_model: Bool?

    init(action: String, id: String, text: String? = nil, ref_audio: String? = nil,
         ref_text: String? = nil, output: String? = nil, max_new_tokens: Int? = nil,
         model: String? = nil, references: [PersistentReference]? = nil,
         temperature: Double? = nil, top_p: Double? = nil, top_k: Int? = nil,
         seed: Int? = nil, normalize: Bool? = nil, previous_takes: [PreviousTake]? = nil,
         save_codes: String? = nil, speakers: [PersistentSpeaker]? = nil,
         lines: [PersistentLine]? = nil, direction: String? = nil,
         line_outputs: [String]? = nil, language: String? = nil, audio: String? = nil, load_model: Bool? = nil) {
        self.action = action; self.id = id; self.text = text; self.ref_audio = ref_audio
        self.ref_text = ref_text; self.output = output; self.max_new_tokens = max_new_tokens
        self.model = model; self.references = references; self.temperature = temperature
        self.top_p = top_p; self.top_k = top_k; self.seed = seed; self.normalize = normalize
        self.previous_takes = previous_takes; self.save_codes = save_codes; self.speakers = speakers
        self.lines = lines; self.direction = direction; self.line_outputs = line_outputs; self.language = language; self.audio = audio
        self.load_model = load_model
    }

    private enum CodingKeys: String, CodingKey {
        case action, id, text, ref_audio, ref_text, output, max_new_tokens, model, references
        case temperature, top_p, top_k, seed, normalize, previous_takes, save_codes, speakers, lines
        case direction, line_outputs, language, audio, load_model
    }
    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(action, forKey: .action); try c.encode(id, forKey: .id)
        try c.encodeIfPresent(text, forKey: .text); try c.encodeIfPresent(ref_audio, forKey: .ref_audio)
        try c.encodeIfPresent(ref_text, forKey: .ref_text); try c.encodeIfPresent(output, forKey: .output)
        if model == TTSModel.drama3.rawValue { try c.encode(max_new_tokens, forKey: .max_new_tokens) }
        else { try c.encodeIfPresent(max_new_tokens, forKey: .max_new_tokens) }
        try c.encodeIfPresent(model, forKey: .model)
        try c.encodeIfPresent(references, forKey: .references); try c.encodeIfPresent(temperature, forKey: .temperature)
        try c.encodeIfPresent(top_p, forKey: .top_p); try c.encodeIfPresent(top_k, forKey: .top_k)
        try c.encodeIfPresent(seed, forKey: .seed); try c.encodeIfPresent(normalize, forKey: .normalize)
        try c.encodeIfPresent(previous_takes, forKey: .previous_takes); try c.encodeIfPresent(save_codes, forKey: .save_codes)
        try c.encodeIfPresent(speakers, forKey: .speakers); try c.encodeIfPresent(lines, forKey: .lines)
        try c.encodeIfPresent(direction, forKey: .direction); try c.encodeIfPresent(line_outputs, forKey: .line_outputs)
        try c.encodeIfPresent(language, forKey: .language); try c.encodeIfPresent(audio, forKey: .audio)
        try c.encodeIfPresent(load_model, forKey: .load_model)
    }
}
struct PersistentReference: Codable { let audio: String; let text: String }
struct PersistentSpeaker: Codable { let id: Int; let name: String; let description: String?; let references: [PersistentReference] }
struct PersistentLine: Codable { let speaker: Int; let text: String }
public struct PersistentEvent: Codable, Sendable {
    public let event: String           // starting|loading_model|ready|accepted|generating|writing|done|error
    public let id: String
    let output: String?
    let message: String?
    public let checkpoint: String?
    let line_outputs: [String]?
    let line_times: [[Double]]?
    let codes: String?
    let duration: Double?
    let sample_rate: Int?
    let text: String?
    let language: String?
    let warnings: [String]?
    let done: Int?
    let total: Int?
    let phase: String?
    let channels: Int?
    let peak: Double?
    let clipping_ratio: Double?
    let silence_ratio: Double?
    let lufs: Double?
    let wer: Double?
    public let attempt: Int?
    public let reason: String?
    public let attempts: [PersistentAttempt]?
}
public struct PersistentAttempt: Codable, Sendable { public let attempt: Int?; public let reason: String? }

// MARK: - Shebang parser

enum ShebangParser {
    /// Resolves the Python interpreter from the shebang of the given file.
    /// Supports absolute paths and `/usr/bin/env` forms.
    static func resolvePython(mlxPath: String, fileManager: FileManager = .default) -> URL? {
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: mlxPath)),
              let firstLine = String(decoding: data.prefix(128), as: UTF8.self)
                .split(separator: "\n").first,
              firstLine.hasPrefix("#!") else { return nil }
        let shebang = String(firstLine.dropFirst(2)).trimmingCharacters(in: .whitespaces)
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
    private(set) var checkpoint: String?
    private var preparing = false      // reentrancy guard
    /// Tasks waiting for the preparation to complete.
    private var preparationWaiters: [CheckedContinuation<Bool, Never>] = []
    private let helperPath: String
    private let executableURL: URL
    private let drama3ModelDirectory: String?
    private let jsonEncoder = JSONEncoder()
    private let jsonDecoder = JSONDecoder()
    private var lineBuffer = Data()

    /// Serial request queue — pending Tasks wait for their turn.
    private var requestQueue: [CheckedContinuation<PersistentGenerationCoordinator, Never>] = []
    private var activeRequest = false

    init(helperPath: String, executableURL: URL, drama3ModelDirectory: String? = nil) {
        self.helperPath = helperPath
        self.executableURL = executableURL
        self.drama3ModelDirectory = drama3ModelDirectory
    }

    // MARK: - Lifecycle

    /// Start the helper and warm the model once. Idempotent.
    func prewarmOnce(model: String = TTSModel.default.rawValue, loadModel: Bool = true) async -> Bool {
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
            let startReq = PersistentRequest(action: "start", id: "prewarm", model: model, load_model: loadModel)
            try stdinHandle?.write(contentsOf: encodeLine(startReq))
            while let event = try await readNextEvent() {
                if event.event == "ready" && event.id == "prewarm" { checkpoint = event.checkpoint; isPrepared = true; return true }
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
        referenceText: String, output: String, model: String = TTSModel.default.rawValue, maxNewTokens: Int? = nil,
        references: [VoiceReference] = [], settings: Drama3Settings = Drama3Settings(),
        previousTakes: [PreviousTake] = [], saveCodes: String? = nil,
        onEvent: (@Sendable (PersistentEvent) -> Void)? = nil
    ) async throws -> PersistentEvent {
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
            output: output,
            max_new_tokens: model == TTSModel.drama3.rawValue ? settings.maxNewTokens ?? maxNewTokens : maxNewTokens,
            model: model,
            references: model == TTSModel.drama3.rawValue ? references.map { PersistentReference(audio: $0.audioPath, text: $0.text) } : nil,
            temperature: model == TTSModel.drama3.rawValue ? settings.temperature : nil,
            top_p: model == TTSModel.drama3.rawValue ? settings.topP : nil,
            top_k: model == TTSModel.drama3.rawValue ? settings.topK : nil,
            seed: model == TTSModel.drama3.rawValue ? settings.seed : nil,
            normalize: model == TTSModel.drama3.rawValue ? settings.normalize : nil,
            previous_takes: model == TTSModel.drama3.rawValue ? previousTakes : nil,
            save_codes: model == TTSModel.drama3.rawValue ? saveCodes : nil)
        try stdin.write(contentsOf: encodeLine(req))

        var accepted = false
        while let event = try await coordinator.readNextEvent() {
            guard event.id == id else { continue }
            switch event.event {
            case "accepted": accepted = true; continue
            case "ready": checkpoint = event.checkpoint; onEvent?(event); continue
            case "done":
                onEvent?(event)
                try Task.checkCancellation()
                return event
            case "retry": onEvent?(event); continue
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

    func send(_ req: PersistentRequest, id: String, onEvent: (@Sendable (PersistentEvent) -> Void)? = nil) async throws -> PersistentEvent {
        guard isPrepared else { throw PersistentError.notReady }
        let coordinator: PersistentGenerationCoordinator = await withCheckedContinuation { cont in
            if !activeRequest { activeRequest = true; cont.resume(returning: self) }
            else { requestQueue.append(cont) }
        }
        defer {
            if requestQueue.isEmpty { activeRequest = false }
            else { requestQueue.removeFirst().resume(returning: self) }
        }
        guard isPrepared, let stdin = stdinHandle else { throw PersistentError.notReady }
        try Task.checkCancellation(); try stdin.write(contentsOf: encodeLine(req))
        var accepted = false
        while let event = try await coordinator.readNextEvent() {
            guard event.id == id else { continue }
            if event.event == "ready" { checkpoint = event.checkpoint }
            onEvent?(event)
            if event.event == "accepted" { accepted = true }
            if event.event == "done" { try Task.checkCancellation(); return event }
            if event.event == "error" {
                throw accepted ? PersistentError.postAcceptFailure(event.message ?? "") : PersistentError.preAcceptFailure(event.message ?? "")
            }
        }
        throw accepted ? PersistentError.postAcceptFailure("helper exited unexpectedly") : PersistentError.preAcceptFailure("helper exited before accepting request")
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
        if let drama3ModelDirectory {
            var environment = ProcessInfo.processInfo.environment
            environment["VOICEFORGE_DRAMA3_MODEL_DIR"] = drama3ModelDirectory
            proc.environment = environment
        }
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
    private var drama3ModelDirectory: String?

    /// A resolver that produces (executableURL, helperPath) for the coordinator.
    /// Called lazily on first access so the production `init` doesn't need the
    /// mlx-speech path upfront.
    typealias Resolver = @Sendable (FileManager) -> (executableURL: URL, helperPath: String)?

    private let resolver: Resolver

    init(resolver: @escaping Resolver, fallbackHelperPath: String, fileManager: FileManager, drama3ModelDirectory: String? = nil) {
        self.resolver = resolver
        self.defaultHelperPath = fallbackHelperPath
        self.fileManager = fileManager
        self.drama3ModelDirectory = drama3ModelDirectory
    }

    func getOrCreate() -> PersistentGenerationCoordinator {
        lock.lock(); defer { lock.unlock() }
        if let c = coordinator { return c }
        // If resolver fails, use a clearly invalid path so startHelper→prewarmOnce return false.
        let cfg = resolver(fileManager) ?? (URL(fileURLWithPath: "/dev/null"), defaultHelperPath)
        let c = PersistentGenerationCoordinator(helperPath: cfg.helperPath, executableURL: cfg.executableURL,
                                                drama3ModelDirectory: drama3ModelDirectory)
        coordinator = c; return c
    }

    func shutdownCurrent() async {
        let c = exchangeCoordinator(nil); await c?.shutdown()
    }

    func configureDrama3ModelDirectory(_ directory: String) {
        lock.lock()
        drama3ModelDirectory = directory
        let old = coordinator
        coordinator = nil
        lock.unlock()
        if let old { Task { await old.shutdown() } }
    }

    private func exchangeCoordinator(_ newValue: PersistentGenerationCoordinator?) -> PersistentGenerationCoordinator? {
        lock.lock(); defer { lock.unlock() }
        let old = coordinator; coordinator = newValue; return old
    }
}
