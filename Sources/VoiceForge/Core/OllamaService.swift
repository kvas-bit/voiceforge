import Foundation

// MARK: - Types

public struct OllamaModel: Codable, Equatable, Sendable, Identifiable, Hashable {
    public var id: String { name }
    public let name: String

    public init(name: String) {
        self.name = name
    }
}

public enum OllamaStatus: Equatable, Sendable {
    case idle
    case starting
    /// A local server is reachable and VoiceForge started it — shutdown will
    /// stop it.
    case runningOwned
    /// A local server is reachable but VoiceForge did not start it — it is
    /// never touched, including at shutdown.
    case runningExternal
    case unavailable(String)
}

public enum OllamaError: LocalizedError, Equatable, Sendable {
    case missingExecutable([String])
    case serverUnavailable(String)
    case invalidResponse(String)
    case requestFailed(String)

    public var errorDescription: String? {
        switch self {
        case .missingExecutable(let searched):
            let list = searched.map { "  • \($0)" }.joined(separator: "\n")
            return "ollama not found. Searched:\n\(list)"
        case .serverUnavailable(let detail):
            return "Ollama server is unavailable: \(detail)"
        case .invalidResponse(let detail):
            return "Unexpected response from Ollama: \(detail)"
        case .requestFailed(let detail):
            return "Ollama request failed: \(detail)"
        }
    }
}

// MARK: - Coordinator

/// Manages an optional, local, off-by-default Ollama integration.
///
/// Discovery, "is a server already running", "did VoiceForge start this
/// process", and shutdown are all handled here so the rest of the app only
/// ever sees a `status` and a couple of async calls. VoiceForge never claims
/// ownership of (and therefore never stops) a server it did not start
/// itself — `shutdownIfOwned()` is a strict no-op unless `ensureRunning()`
/// actually spawned the process in this run.
public actor OllamaCoordinator {
    public typealias HTTPPerformer = @Sendable (URLRequest) async throws -> (Data, URLResponse)
    public typealias ProcessStarter = @Sendable (URL, [String]) throws -> Process

    public private(set) var status: OllamaStatus = .idle

    private var ownedProcess: Process?
    private let executableURL: URL?
    private let baseURL: URL
    private let fileManager: FileManager
    private let httpPerformer: HTTPPerformer
    private let processStarter: ProcessStarter

    public init(
        executableURL: URL? = nil,
        baseURL: URL = URL(string: "http://127.0.0.1:11434")!,
        fileManager: FileManager = .default,
        httpPerformer: HTTPPerformer? = nil,
        processStarter: ProcessStarter? = nil
    ) {
        self.executableURL = executableURL
        self.baseURL = baseURL
        self.fileManager = fileManager
        self.httpPerformer = httpPerformer ?? { request in
            try await URLSession.shared.data(for: request)
        }
        self.processStarter = processStarter ?? { url, arguments in
            let process = Process()
            process.executableURL = url
            process.arguments = arguments
            process.standardOutput = FileHandle.nullDevice
            process.standardError = FileHandle.nullDevice
            try process.run()
            return process
        }
    }

    // MARK: - Discovery

    /// Common install locations for the `ollama` CLI. GUI-launched apps get a
    /// minimal `PATH`, so this checks the well-known Homebrew/official
    /// installer/app-bundle locations directly rather than relying on shell
    /// profile sourcing, the same approach used for discovering `mlx-speech`.
    public static func discoverOllama(
        homeDirectory: String = NSHomeDirectory(),
        fileManager: FileManager = .default
    ) -> URL? {
        for path in discoverySearchPaths(homeDirectory: homeDirectory) {
            var isDir: ObjCBool = false
            if fileManager.fileExists(atPath: path, isDirectory: &isDir),
               !isDir.boolValue,
               fileManager.isExecutableFile(atPath: path) {
                return URL(fileURLWithPath: path)
            }
        }
        return nil
    }

    public static func discoverySearchPaths(homeDirectory: String = NSHomeDirectory()) -> [String] {
        [
            "/usr/local/bin/ollama",
            "/opt/homebrew/bin/ollama",
            "/Applications/Ollama.app/Contents/Resources/ollama",
            homeDirectory + "/.ollama/bin/ollama"
        ] + (ProcessInfo.processInfo.environment["PATH"] ?? "/usr/bin:/bin")
            .split(separator: ":")
            .map { $0 + "/ollama" }
    }

    // MARK: - Lifecycle

    /// Ensures a local Ollama server is reachable. Idempotent and safe to
    /// call repeatedly (e.g. from a Settings "Refresh" button):
    /// - If a server already answers, it's adopted as `.runningExternal` and
    ///   never started or stopped by VoiceForge.
    /// - Otherwise, resolves the `ollama` executable and starts `ollama serve`
    ///   itself, polling briefly until it answers, becoming `.runningOwned`.
    /// - If the executable can't be found or the server never comes up,
    ///   returns `.unavailable(reason)`.
    @discardableResult
    public func ensureRunning() async -> OllamaStatus {
        if status == .runningOwned || status == .runningExternal {
            return status
        }
        if await probeServer() {
            status = .runningExternal
            return status
        }
        status = .starting
        guard let exe = executableURL ?? Self.discoverOllama(fileManager: fileManager) else {
            status = .unavailable(OllamaError.missingExecutable(Self.discoverySearchPaths()).errorDescription ?? "not found")
            return status
        }
        do {
            ownedProcess = try processStarter(exe, ["serve"])
        } catch {
            status = .unavailable("Could not launch ollama serve: \(error.localizedDescription)")
            return status
        }
        for _ in 0..<20 {
            if await probeServer() {
                status = .runningOwned
                return status
            }
            try? await Task.sleep(nanoseconds: 150_000_000)
        }
        ownedProcess?.terminate()
        ownedProcess = nil
        status = .unavailable("ollama serve did not become ready")
        return status
    }

    /// Terminates the Ollama process only if this coordinator started it in
    /// `ensureRunning()`. A `.runningExternal` server, or no server at all,
    /// is left completely untouched.
    public func shutdownIfOwned() async {
        guard let proc = ownedProcess else { return }
        ownedProcess = nil
        status = .idle
        guard proc.isRunning else { return }
        proc.terminate()
        let pid = proc.processIdentifier
        DispatchQueue.global(qos: .userInitiated).asyncAfter(deadline: .now() + 1.0) {
            if proc.isRunning { kill(pid, SIGKILL) }
        }
    }

    private func probeServer() async -> Bool {
        var request = URLRequest(url: baseURL.appendingPathComponent("api/tags"))
        request.timeoutInterval = 2
        guard let (_, response) = try? await httpPerformer(request) else { return false }
        return (response as? HTTPURLResponse)?.statusCode == 200
    }

    // MARK: - API

    public func listModels() async throws -> [OllamaModel] {
        var request = URLRequest(url: baseURL.appendingPathComponent("api/tags"))
        request.timeoutInterval = 5
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await httpPerformer(request)
        } catch {
            throw OllamaError.serverUnavailable(error.localizedDescription)
        }
        guard (response as? HTTPURLResponse)?.statusCode == 200 else {
            throw OllamaError.serverUnavailable("unexpected response listing models")
        }
        struct TagsResponse: Decodable { let models: [OllamaModel] }
        guard let decoded = try? JSONDecoder().decode(TagsResponse.self, from: data) else {
            throw OllamaError.invalidResponse("could not parse model list")
        }
        return decoded.models
    }

    /// Asks `model` to rewrite `sourceText` into a more descriptive,
    /// Fish-compatible expressive prompt (inline `[tag]` delivery cues).
    /// Returns the suggestion text only — the caller decides whether/when to
    /// apply it; this never touches any source-of-truth text itself.
    public func suggestPrompt(model: String, sourceText: String, emotionText: String) async throws -> String {
        try Task.checkCancellation()

        let instruction = """
        You help write expressive text-to-speech prompts for the Fish Audio S2 Pro voice model. \
        Fish supports inline emotion/delivery tags in square brackets, like [whispering softly], \
        [laughs], [sighs], [excited]. Rewrite the line below to be more descriptive and expressive \
        for TTS, adding at most one or two well-placed inline tags. Keep the original meaning and \
        language. Reply with ONLY the rewritten line — no explanation, no quotes, no preamble.

        Tone: \(emotionText.isEmpty ? "neutral" : emotionText)
        Line: \(sourceText)
        """

        struct GenerateRequest: Encodable {
            let model: String
            let prompt: String
            let stream: Bool
        }
        struct GenerateResponse: Decodable { let response: String }

        var request = URLRequest(url: baseURL.appendingPathComponent("api/generate"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 60
        request.httpBody = try JSONEncoder().encode(
            GenerateRequest(model: model, prompt: instruction, stream: false)
        )

        try Task.checkCancellation()
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await httpPerformer(request)
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            if Task.isCancelled { throw CancellationError() }
            throw OllamaError.requestFailed(error.localizedDescription)
        }
        try Task.checkCancellation()

        guard (response as? HTTPURLResponse)?.statusCode == 200 else {
            throw OllamaError.requestFailed("unexpected response from ollama")
        }
        guard let decoded = try? JSONDecoder().decode(GenerateResponse.self, from: data) else {
            throw OllamaError.invalidResponse("could not parse suggestion")
        }
        let trimmed = decoded.response.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw OllamaError.invalidResponse("empty suggestion")
        }
        return trimmed
    }
}
