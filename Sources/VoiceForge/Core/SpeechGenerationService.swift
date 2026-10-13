import Foundation

public enum SpeechGenerationError: LocalizedError, Sendable {
    case missingText
    case missingReferenceAudio
    case missingReferenceText
    case missingExecutable([String])
    case shellFailure(String)
    case invalidWAV(String)
    case invalidDrama3Prompt(String)

    public var errorDescription: String? {
        switch self {
        case .missingText:
            return "Enter text to generate."
        case .missingReferenceAudio:
            return "Choose a reference audio file."
        case .missingReferenceText:
            return "Enter the reference transcript."
        case .missingExecutable(let searched):
            let list = searched.map { "  • \($0)" }.joined(separator: "\n")
            return "mlx-speech not found. Searched:\n\(list)"
        case .shellFailure(let message):
            return message
        case .invalidWAV(let detail):
            return detail
        case .invalidDrama3Prompt(let token):
            return "Drama 3 cannot accept the structural token \(token) in prompt text. Remove model control tokens and use bracketed directions such as [whispers]."
        }
    }
}

/// Direct process-engine for Fish Audio S2 Pro via `mlx-speech`.
/// Prefers a persistent Python helper that loads the model once and serves
/// sequential requests. Falls back to direct CLI if the helper cannot start.
///
/// Reference-typed so one instance can be injected and shared across all
/// generation paths without value-copy hazards.
public final class SpeechGenerationService: @unchecked Sendable {

    // MARK: - Configuration

    private let executableURL: URL?
    private let renderRoot: URL?
    private nonisolated(unsafe) let fileManager: FileManager

    /// Internal runner for tests only; production uses `Self.launchProcess`.
    let runner: @Sendable (URL, [String], ProcessBox) async throws -> (stdout: String, stderr: String, exitCode: Int32)

    /// Optional persistent coordinator. Lazily created on first `generate()`.
    /// Access is serialized through the actor.
    private let usePersistent: Bool
    private let coordinatorRegistry: CoordinatorRegistry

    /// Mock generation closure for UI tests. When set, `generate()` calls this
    /// instead of running any real process. Writes a synthetic WAV to the output
    /// path and returns a `GenerationResult`.
    private let mockGenerate: (@Sendable (GenerationRequest) async throws -> GenerationResult)?

    private let formatter = PromptFormatter()

    // MARK: - Init

    /// Production initializer. The persistent helper is resolved lazily — the
    /// mlx-speech path is discovered on first `prewarm()` or `generate()`.
    public init() {
        self.executableURL = nil
        self.renderRoot = nil
        self.fileManager = .default
        self.runner = Self.launchProcess
        self.usePersistent = true
        self.mockGenerate = nil
        self.coordinatorRegistry = Self.makeCoordinatorRegistry(
            executableURL: nil, fileManager: .default)
    }

    /// Full injection initializer for tests. Not public.
    init(
        executableURL: URL? = nil,
        renderRoot: URL? = nil,
        fileManager: FileManager = .default,
        runner: (@Sendable (URL, [String], ProcessBox) async throws -> (stdout: String, stderr: String, exitCode: Int32))? = nil,
        usePersistent: Bool = false,
        mockGenerate: (@Sendable (GenerationRequest) async throws -> GenerationResult)? = nil,
        coordinatorRegistry: CoordinatorRegistry? = nil
    ) {
        self.executableURL = executableURL
        self.renderRoot = renderRoot
        self.fileManager = fileManager
        self.runner = runner ?? Self.launchProcess
        self.usePersistent = usePersistent
        self.mockGenerate = mockGenerate
        self.coordinatorRegistry = coordinatorRegistry ?? Self.makeCoordinatorRegistry(
            executableURL: executableURL, fileManager: fileManager)
    }

    public static func __internalInit(
        executableURL: URL?,
        renderRoot: URL?,
        fileManager: FileManager,
        runner: @Sendable @escaping (URL, [String], ProcessBox) async throws -> (stdout: String, stderr: String, exitCode: Int32),
        usePersistent: Bool,
        mockGenerate: (@Sendable (GenerationRequest) async throws -> GenerationResult)? = nil,
        coordinatorRegistry: CoordinatorRegistry? = nil
    ) -> SpeechGenerationService {
        return SpeechGenerationService(
            executableURL: executableURL, renderRoot: renderRoot,
            fileManager: fileManager, runner: runner,
            usePersistent: usePersistent, mockGenerate: mockGenerate,
            coordinatorRegistry: coordinatorRegistry
        )
    }

    /// Convenience for mock output URL under a given root.
    public static func __tempOutputURL(forID id: UUID, under root: URL) throws -> URL {
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root.appendingPathComponent("\(id.uuidString).wav")
    }

    private static func makeCoordinatorRegistry(
        executableURL: URL?,
        fileManager: FileManager
    ) -> CoordinatorRegistry {
        let fallbackPath = defaultHelperPath(mlxExecutable: nil)
        let resolver: CoordinatorRegistry.Resolver = { fm in
            let exeURL = executableURL ?? Self.discoverMLXSpeech(fileManager: fm)
            guard let mlxURL = exeURL else { return nil }
            guard let pythonURL = ShebangParser.resolvePython(mlxPath: mlxURL.path, fileManager: fm) else { return nil }
            let path = defaultHelperPath(mlxExecutable: mlxURL)
            return (pythonURL, path)
        }
        return CoordinatorRegistry(resolver: resolver, fallbackHelperPath: fallbackPath, fileManager: fileManager)
    }

    private static func defaultHelperPath(mlxExecutable: URL?) -> String {
        #if SWIFT_PACKAGE
        return Bundle.module.path(forResource: "mlx_persistent_server", ofType: "py") ?? ""
        #else
        if let bundlePath = Bundle.main.path(forResource: "mlx_persistent_server", ofType: "py") {
            return bundlePath
        }
        let exeURL = mlxExecutable ?? URL(fileURLWithPath: "/usr/bin/env")
        return exeURL.deletingLastPathComponent()
            .appendingPathComponent("mlx_persistent_server.py").path
        #endif
    }

    // MARK: - Output URLs

    public func renderRootDirectory() throws -> URL {
        if let root = renderRoot {
            return root
        }
        let base = try fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        return base.appendingPathComponent("VoiceForge", isDirectory: true)
    }

    public func defaultOutputURL() throws -> URL {
        try renderRootDirectory().appendingPathComponent("voiceforge_output.wav")
    }

    public static func renderRootDirectory(
        applicationSupport: URL? = nil
    ) throws -> URL {
        let base = try applicationSupport ?? FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        return base.appendingPathComponent("VoiceForge", isDirectory: true)
    }

    public func defaultOutputURL(applicationSupport: URL? = nil) throws -> URL {
        try Self.renderRootDirectory(applicationSupport: applicationSupport)
            .appendingPathComponent("voiceforge_output.wav")
    }

    public func outputURL(forID id: UUID) throws -> URL {
        try renderRootDirectory()
            .appendingPathComponent("outputs", isDirectory: true)
            .appendingPathComponent("\(id.uuidString).wav")
    }

    public func outputURL(forID id: UUID, applicationSupport: URL?) throws -> URL {
        try Self.renderRootDirectory(applicationSupport: applicationSupport)
            .appendingPathComponent("outputs", isDirectory: true)
            .appendingPathComponent("\(id.uuidString).wav")
    }

    // MARK: - Argument builder

    /// Builds an argv array for `mlx-speech tts`. Every element is literal —
    /// no shell quoting or interpolation. Edit flags are only included for
    /// models that support them (not Fish S2 Pro).
    public func arguments(
        formattedText: String,
        referenceAudioPath: String,
        referenceText: String,
        outputURL: URL,
        model: String = TTSModel.default.rawValue,
        maxNewTokens: Int? = nil,
        editType: String? = nil,
        editInfo: String? = nil
    ) -> [String] {
        var args: [String] = [
            "--text", formattedText,
            "--reference-audio", referenceAudioPath,
            "--reference-text", referenceText,
            "-o", outputURL.path
        ]
        if model != TTSModel.drama3.rawValue { args.insert(contentsOf: ["--model", model], at: 0) }
        if let maxNewTokens {
            args.append(contentsOf: ["--max-new-tokens", String(maxNewTokens)])
        }
        // Fish S2 Pro does not accept Step-Audio edit flags.
        if model != TTSModel.fishS2Pro.rawValue {
            if let editType, !editType.isEmpty {
                args.append(contentsOf: ["--edit-type", editType])
            }
            if let editInfo, !editInfo.isEmpty {
                args.append(contentsOf: ["--edit-info", editInfo])
            }
        }
        return args
    }

    public static func describeCommand(executable: String, arguments: [String]) -> String {
        let quoted = arguments.map { arg in
            if arg.contains(" ") || arg.contains("\"") || arg.contains("$") || arg.contains("`") {
                let escaped = arg.replacingOccurrences(of: "\"", with: "\\\"")
                return "\"\(escaped)\""
            }
            return arg
        }
        return ([executable] + quoted).joined(separator: " ")
    }

    // MARK: - Discovery

    public static func discoverMLXSpeech(
        homeDirectory: String = NSHomeDirectory(),
        fileManager: FileManager = .default
    ) -> URL? {
        let candidates = [
            homeDirectory + "/.local/bin/mlx-speech",
            "/opt/homebrew/bin/mlx-speech",
            "/usr/local/bin/mlx-speech"
        ] + (ProcessInfo.processInfo.environment["PATH"] ?? "/usr/bin:/bin")
            .split(separator: ":")
            .map { $0 + "/mlx-speech" }

        for path in candidates {
            let url = URL(fileURLWithPath: path)
            var isDir: ObjCBool = false
            if fileManager.fileExists(atPath: path, isDirectory: &isDir),
               !isDir.boolValue,
               fileManager.isExecutableFile(atPath: path) {
                return url
            }
        }
        return nil
    }

    private static func discoverySearchPaths(
        homeDirectory: String = NSHomeDirectory()
    ) -> [String] {
        [
            homeDirectory + "/.local/bin/mlx-speech",
            "/opt/homebrew/bin/mlx-speech",
            "/usr/local/bin/mlx-speech"
        ] + (ProcessInfo.processInfo.environment["PATH"] ?? "/usr/bin:/bin")
            .split(separator: ":")
            .map { $0 + "/mlx-speech" }
    }

    // MARK: - Lifecycle

    /// Prewarms the persistent helper (loads model once). Call once at app start.
    /// Returns `true` if the helper is ready; `false` means CLI fallback will be used.
    public func prewarmPersistentHelper(model: String = TTSModel.default.rawValue) async -> Bool {
        guard usePersistent else { return false }
        let c = coordinatorRegistry.getOrCreate()
        return await c.prewarmOnce(model: model)
    }

    public func persistentCheckpoint(model: String = TTSModel.default.rawValue) async -> String? {
        guard usePersistent else { return nil }
        let coordinator = coordinatorRegistry.getOrCreate()
        _ = await coordinator.prewarmOnce(model: model)
        return await coordinator.checkpoint
    }

    public func transcribe(audio: String, language: String? = nil) async throws -> String {
        let id = UUID().uuidString
        let coordinator = coordinatorRegistry.getOrCreate()
        guard await coordinator.prewarmOnce(model: TTSModel.drama3.rawValue, loadModel: false) else { throw PersistentError.notReady }
        let event = try await coordinator.send(PersistentRequest(action: "transcribe", id: id, model: TTSModel.drama3.rawValue, language: language, audio: audio), id: id)
        return event.text ?? ""
    }

    public func inspectReference(audio: String, text: String? = nil) async throws -> ReferenceInspection {
        let id = UUID().uuidString
        let coordinator = coordinatorRegistry.getOrCreate()
        guard await coordinator.prewarmOnce(model: TTSModel.drama3.rawValue, loadModel: false) else { throw PersistentError.notReady }
        let event = try await coordinator.send(PersistentRequest(action: "inspect_reference", id: id, text: text, model: TTSModel.drama3.rawValue, audio: audio), id: id)
        return ReferenceInspection(duration: event.duration, sampleRate: event.sample_rate, channels: event.channels,
                                   peak: event.peak, clippingRatio: event.clipping_ratio,
                                   silenceRatio: event.silence_ratio, lufs: event.lufs, wordErrorRate: event.wer, warnings: event.warnings ?? [])
    }

    public func generateScene(
        speakers: [SceneSpeaker], lines: [SceneLine], direction: String,
        settings: Drama3Settings, onProgress: (@Sendable (Int, Int) -> Void)? = nil
    ) async throws -> SceneGenerationResult {
        guard usePersistent else { throw SpeechGenerationError.shellFailure("Scene generation requires the persistent Drama 3 helper.") }
        guard !speakers.isEmpty, !lines.isEmpty else { throw SpeechGenerationError.missingText }
        guard speakers.allSatisfy({ !$0.references.isEmpty && $0.id >= 0 && $0.id < 16 }) else { throw SpeechGenerationError.missingReferenceAudio }
        let id = UUID().uuidString
        let root = try renderRootDirectory().appendingPathComponent("outputs", isDirectory: true)
        let dir = root.appendingPathComponent("scene-\(id)", isDirectory: true)
        try fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
        let sceneURL = dir.appendingPathComponent("scene.wav")
        let lineURLs = lines.indices.map { dir.appendingPathComponent("line-\($0).wav") }
        let codesURL = dir.appendingPathComponent("scene.npy")
        let req = PersistentRequest(
            action: "generate_scene", id: id, output: sceneURL.path,
            max_new_tokens: settings.maxNewTokens, model: TTSModel.drama3.rawValue,
            temperature: settings.temperature, top_p: settings.topP, top_k: settings.topK,
            seed: settings.seed, normalize: settings.normalize,
            save_codes: codesURL.path,
            speakers: speakers.map { .init(id: $0.id, name: $0.name, description: $0.description, references: $0.references.map { .init(audio: $0.audioPath, text: $0.text) }) },
            lines: lines.map { .init(speaker: $0.speaker, text: $0.text) },
            direction: direction.isEmpty ? nil : direction,
            line_outputs: lineURLs.map(\.path))
        let coordinator = coordinatorRegistry.getOrCreate()
        guard await coordinator.prewarmOnce(model: TTSModel.drama3.rawValue) else { throw PersistentError.notReady }
        let event = try await coordinator.send(req, id: id) { event in
            if event.event == "progress", let done = event.done, let total = event.total { onProgress?(done, total) }
        }
        try validateWAVOutput(at: sceneURL)
        return SceneGenerationResult(outputURL: sceneURL, lineOutputURLs: event.line_outputs?.map(URL.init(fileURLWithPath:)) ?? lineURLs,
                                    lineTimes: event.line_times, codesURL: event.codes.map(URL.init(fileURLWithPath:)) ?? codesURL)
    }

    /// Shuts down the persistent helper.
    public func shutdownPersistentHelper() async {
        await coordinatorRegistry.shutdownCurrent()
    }

    // MARK: - Generate

    public func generate(request: GenerationRequest) async throws -> GenerationResult {
        let sourceText = request.model == TTSModel.drama3.rawValue ? request.sourceText : request.sourceText.trimmingCharacters(in: .whitespacesAndNewlines)
        let referenceAudioPath = request.referenceAudioPath.trimmingCharacters(in: .whitespacesAndNewlines)
        let referenceText = request.referenceText.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !sourceText.isEmpty else { throw SpeechGenerationError.missingText }
        let dramaReferences = request.references.isEmpty
            ? (referenceAudioPath.isEmpty || referenceText.isEmpty ? [] : [VoiceReference(audioPath: referenceAudioPath, text: referenceText)])
            : request.references
        guard request.model != TTSModel.drama3.rawValue || !dramaReferences.isEmpty else { throw SpeechGenerationError.missingReferenceAudio }
        guard request.model != TTSModel.drama3.rawValue || dramaReferences.allSatisfy({ !$0.audioPath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) else { throw SpeechGenerationError.missingReferenceAudio }
        guard request.model != TTSModel.drama3.rawValue || dramaReferences.allSatisfy({ !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) else { throw SpeechGenerationError.missingReferenceText }
        guard request.model == TTSModel.drama3.rawValue || !referenceAudioPath.isEmpty else { throw SpeechGenerationError.missingReferenceAudio }
        guard request.model == TTSModel.drama3.rawValue || !referenceText.isEmpty else { throw SpeechGenerationError.missingReferenceText }

        // Mock path — writes synthetic WAV immediately.
        if let mock = mockGenerate { return try await mock(request) }

        let formattedPrompt = formatter.format(text: sourceText, emotion: request.emotionText, model: request.model)
        if request.model == TTSModel.drama3.rawValue,
           let token = Self.invalidDrama3Token(in: formattedPrompt) {
            throw SpeechGenerationError.invalidDrama3Prompt(token)
        }
        let outputURL = try outputURL(forID: request.id)
        try ensureOutputDirectoryExists(for: outputURL)
        let codesURL = request.model == TTSModel.drama3.rawValue
            ? outputURL.deletingPathExtension().appendingPathExtension("npy") : nil

        // Only try persistent when enabled.
        if usePersistent {
            let coordinator = coordinatorRegistry.getOrCreate()
            let helperReady = await coordinator.prewarmOnce(model: request.model)
            if helperReady {
                do {
                    // Try persistent path. Only pre-accept failures reach CLI fallback.
                    return try await withTaskCancellationHandler {
                        let event = try await coordinator.generate(
                            id: request.id.uuidString,
                            text: formattedPrompt,
                            referenceAudio: referenceAudioPath,
                            referenceText: referenceText,
                            output: outputURL.path,
                            model: request.model,
                            maxNewTokens: request.maxNewTokens,
                            references: dramaReferences,
                            settings: request.drama3Settings,
                            previousTakes: request.previousTakes,
                            saveCodes: request.saveCodesPath ?? codesURL?.path
                        )
                        try validateWAVOutput(at: outputURL)
                        return GenerationResult(
                            formattedPrompt: formattedPrompt,
                            outputURL: URL(fileURLWithPath: event.output ?? outputURL.path),
                            standardOutput: "",
                            standardError: "",
                            codesURL: event.codes.map(URL.init(fileURLWithPath:)) ?? codesURL,
                            duration: event.duration, sampleRate: event.sample_rate
                        )
                    } onCancel: {
                        Task {
                            await coordinatorRegistry.shutdownCurrent()
                            try? fileManager.removeItem(at: outputURL)
                        }
                    }
                } catch PersistentError.preAcceptFailure, PersistentError.notReady {
                    // Helper failed before accepting, or a request queued behind
                    // a just-cancelled one found the helper torn down — fall
                    // through to CLI unless the task was already cancelled.
                    try Task.checkCancellation()
                    await coordinatorRegistry.shutdownCurrent()
                } catch is CancellationError {
                    try? fileManager.removeItem(at: outputURL)
                    throw CancellationError()
                } catch {
                    // Post-accept or other error — clean up and propagate.
                    // If the task was cancelled, surface CancellationError instead.
                    if Task.isCancelled {
                        try? fileManager.removeItem(at: outputURL)
                        throw CancellationError()
                    }
                    try? fileManager.removeItem(at: outputURL)
                    throw error
                }
            }
        }

        // Only pre-accept failures reach here — fall back to CLI.
        let (exeURL, prefixArgs) = try resolveExecutable(model: request.model)
        let argv = arguments(
            formattedText: formattedPrompt,
            referenceAudioPath: referenceAudioPath,
            referenceText: referenceText,
            outputURL: outputURL,
            model: request.model,
            maxNewTokens: request.maxNewTokens
        )
        let ttsArgs = request.model == TTSModel.drama3.rawValue
            ? prefixArgs + argv
            : ["tts"] + argv
        do {
            let result = try await run(
                executableURL: exeURL,
                arguments: ttsArgs,
                outputURL: outputURL,
                formattedPrompt: formattedPrompt
            )
            try validateWAVOutput(at: outputURL)
            return result
        } catch {
            try? fileManager.removeItem(at: outputURL)
            throw error
        }
    }

    private func resolveExecutable(model: String) throws -> (URL, [String]) {
        if let exe = executableURL {
            return (exe, [])
        }
        if model == TTSModel.drama3.rawValue {
            let paths = [NSHomeDirectory() + "/.local/bin/drama3-tts", "/opt/homebrew/bin/drama3-tts", "/usr/local/bin/drama3-tts"]
                + (ProcessInfo.processInfo.environment["PATH"] ?? "/usr/bin:/bin").split(separator: ":").map { $0 + "/drama3-tts" }
            if let cli = paths.first(where: { fileManager.isExecutableFile(atPath: $0) }) {
                return (URL(fileURLWithPath: cli), [])
            }
            if let mlx = Self.discoverMLXSpeech(), let python = ShebangParser.resolvePython(mlxPath: mlx.path, fileManager: fileManager) {
                return (python, ["-m", "drama3_mlx.cli"])
            }
            throw SpeechGenerationError.missingExecutable(paths + ["python -m drama3_mlx.cli"])
        }
        if let discovered = Self.discoverMLXSpeech() {
            return (discovered, [])
        }
        throw SpeechGenerationError.missingExecutable(Self.discoverySearchPaths())
    }

    private static func invalidDrama3Token(in text: String) -> String? {
        for token in ["<|im_start|>", "<|im_end|>", "<|voice|>", "<|text|>", "<|interleave|>", "<|semantic:"] where text.contains(token) {
            return token
        }
        let pattern = #"<\|speaker(?::[0-9]+)?\|>"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        for match in regex.matches(in: text, range: NSRange(text.startIndex..., in: text)) {
            guard let range = Range(match.range, in: text) else { continue }
            let token = String(text[range])
            let number = token.dropFirst("<|speaker:".count).dropLast(2)
            guard let id = Int(number), (0...15).contains(id), String(id) == number else { return token }
        }
        if text.contains("<|speaker") { return "<|speaker...|>" }
        return nil
    }

    private func ensureOutputDirectoryExists(for outputURL: URL) throws {
        let directory = outputURL.deletingLastPathComponent()
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    // MARK: - Process execution

    func run(
        executableURL: URL,
        arguments: [String],
        outputURL: URL,
        formattedPrompt: String = ""
    ) async throws -> GenerationResult {
        var isDir: ObjCBool = false
        guard fileManager.fileExists(atPath: executableURL.path, isDirectory: &isDir),
              !isDir.boolValue,
              fileManager.isExecutableFile(atPath: executableURL.path) else {
            throw SpeechGenerationError.missingExecutable([executableURL.path])
        }

        let processBox = ProcessBox()

        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<GenerationResult, Error>) in
                if Task.isCancelled {
                    continuation.resume(throwing: CancellationError())
                    return
                }

                let task = Task.detached(priority: .userInitiated) { [runner, formattedPrompt] in
                    do {
                        let (stdout, stderr, exitCode) = try await runner(executableURL, arguments, processBox)
                        // Check cancellation state under the lock after the runner returns.
                        if processBox.isCancelled {
                            continuation.resume(throwing: CancellationError())
                            return
                        }
                        if exitCode == 0 {
                            continuation.resume(returning: GenerationResult(
                                formattedPrompt: formattedPrompt,
                                outputURL: outputURL,
                                standardOutput: stdout,
                                standardError: stderr
                            ))
                        } else {
                            let message = stderr.isEmpty ? stdout : stderr
                            continuation.resume(throwing:
                                SpeechGenerationError.shellFailure(message.trimmingCharacters(in: .whitespacesAndNewlines)))
                        }
                    } catch {
                        continuation.resume(throwing: error)
                    }
                }
                processBox.storeTask(task)
            }
        } onCancel: {
            processBox.cancel()
        }
    }

    /// The real process launcher. Stores the process before running, checks
    /// cancellation state under the lock both before and after `process.run()`,
    /// and starts concurrent pipe readers only on successful launch.
    public static let launchProcess: @Sendable (URL, [String], ProcessBox) async throws -> (stdout: String, stderr: String, exitCode: Int32) = {
        executableURL, arguments, processBox in

        let process = Process()
        process.executableURL = executableURL
        process.arguments = arguments

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        processBox.storeProcess(process)

        // Snapshot cancellation under the lock before launch.
        if processBox.isCancelled {
            throw CancellationError()
        }

        try process.run()

        // Recheck immediately after a successful launch.  If cancellation
        // arrived between `storeProcess` and `process.run`, the child may
        // have started but we must terminate it before draining pipes.
        if processBox.isCancelled {
            processBox.cancel()
            throw CancellationError()
        }

        // Start concurrent readers AFTER successful launch + post-run check.
        async let stdoutStr = readPipe(stdoutPipe)
        async let stderrStr = readPipe(stderrPipe)

        let (stdout, stderr) = await (stdoutStr, stderrStr)
        process.waitUntilExit()

        if processBox.isCancelled {
            throw CancellationError()
        }
        return (stdout, stderr, process.terminationStatus)
    }

    private static func readPipe(_ pipe: Pipe) async -> String {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                continuation.resume(returning: String(decoding: data, as: UTF8.self))
            }
        }
    }

    // MARK: - WAV validation

    /// Validates that the file at `outputURL` is a real WAV with RIFF and WAVE
    /// markers. The error message includes the resolved path for diagnostics.
    func validateWAVOutput(at outputURL: URL) throws {
        let path = outputURL.path
        guard fileManager.fileExists(atPath: path) else {
            throw SpeechGenerationError.invalidWAV(
                "mlx-speech reported success but no audio file was found at \(path)."
            )
        }
        let fileSize = (try? fileManager.attributesOfItem(atPath: path)[.size] as? Int) ?? nil
        guard let size = fileSize, size >= 44 else {
            throw SpeechGenerationError.invalidWAV(
                "Output at \(path) is too small (\(fileSize.map(String.init) ?? "?") bytes) to be a valid WAV (minimum 44 bytes)."
            )
        }
        guard let handle = try? FileHandle(forReadingFrom: outputURL) else {
            throw SpeechGenerationError.invalidWAV(
                "Output at \(path) could not be opened for reading."
            )
        }
        defer { try? handle.close() }

        let riff = handle.readData(ofLength: 4)
        guard riff == Data([0x52, 0x49, 0x46, 0x46]) else {
            throw SpeechGenerationError.invalidWAV(
                "Output at \(path) is not a valid WAV file (missing RIFF header)."
            )
        }

        // Skip chunk size (4 bytes), then read WAVE marker at offset 8.
        _ = handle.readData(ofLength: 4)
        let wave = handle.readData(ofLength: 4)
        guard wave == Data([0x57, 0x41, 0x56, 0x45]) else {
            throw SpeechGenerationError.invalidWAV(
                "Output at \(path) has RIFF header but is not a WAVE file (missing WAVE marker at offset 8)."
            )
        }
    }
}

// MARK: - ProcessBox (cancellation helper)

/// Thread-safe holder so an `onCancel` block can reach the in-flight `Process`
/// (or its `Task`) and terminate it. All mutable state is guarded by `NSLock`.
public final class ProcessBox: @unchecked Sendable {
    private let lock = NSLock()
    private var process: Process?
    private var innerTask: Task<Void, Never>?
    private var _cancelled = false

    /// Thread-safe cancellation snapshot.
    var isCancelled: Bool {
        lock.lock(); defer { lock.unlock() }
        return _cancelled
    }

    func storeProcess(_ process: Process) {
        lock.lock(); defer { lock.unlock() }
        self.process = process
    }

    func storeTask(_ task: Task<Void, Never>) {
        lock.lock(); defer { lock.unlock() }
        innerTask = task
    }

    func cancel() {
        lock.lock()
        _cancelled = true
        let target = process
        let task = innerTask
        lock.unlock()

        task?.cancel()

        guard let target, target.isRunning else { return }
        target.terminate()
        let pid = target.processIdentifier
        DispatchQueue.global(qos: .userInitiated).asyncAfter(deadline: .now() + 1.0) {
            if target.isRunning {
                kill(pid, SIGKILL)
            }
        }
    }
}
