import Foundation

public enum SpeechGenerationError: LocalizedError, Sendable {
    case missingText
    case missingReferenceAudio
    case missingReferenceText
    case shellFailure(String)

    public var errorDescription: String? {
        switch self {
        case .missingText:
            return "Enter text to generate."
        case .missingReferenceAudio:
            return "Choose a reference audio file."
        case .missingReferenceText:
            return "Enter the reference transcript."
        case .shellFailure(let message):
            return message
        }
    }
}

public struct SpeechGenerationService: Sendable {
    private let formatter = PromptFormatter()

    public init() {}

    /// Root directory used for all VoiceForge renders. Lives under the user's
    /// Application Support folder so the files are user-visible (Finder shows it
    /// under `Library/Application Support`) and don't litter `$HOME`.
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

    /// Legacy "single file" output. Kept for back-compat with the Settings copy
    /// but no longer used by the per-id render path.
    public func defaultOutputURL(applicationSupport: URL? = nil) throws -> URL {
        try Self.renderRootDirectory(applicationSupport: applicationSupport)
            .appendingPathComponent("voiceforge_output.wav")
    }

    /// Per-generation unique output URL: `<App Support>/VoiceForge/outputs/<uuid>.wav`.
    /// Keeps every render addressable by its history entry so they never collide.
    public func outputURL(forID id: UUID, applicationSupport: URL? = nil) throws -> URL {
        try Self.renderRootDirectory(applicationSupport: applicationSupport)
            .appendingPathComponent("outputs", isDirectory: true)
            .appendingPathComponent("\(id.uuidString).wav")
    }

    public func command(
        formattedText: String,
        referenceAudioPath: String,
        referenceText: String,
        outputURL: URL,
        model: String = "fish-s2-pro",
        maxNewTokens: Int? = nil,
        editType: String? = nil,
        editInfo: String? = nil
    ) -> String {
        var parts: [String] = [
            "mlx-speech",
            "tts",
            "--model",
            model,
            "--text",
            shellQuote(formattedText),
            "--reference-audio",
            shellQuote(referenceAudioPath),
            "--reference-text",
            shellQuote(referenceText),
            "-o",
            shellQuote(outputURL.path)
        ]
        if let maxNewTokens {
            parts.append(contentsOf: ["--max-new-tokens", String(maxNewTokens)])
        }
        if let editType, !editType.isEmpty {
            parts.append(contentsOf: ["--edit-type", editType])
        }
        if let editInfo, !editInfo.isEmpty {
            parts.append(contentsOf: ["--edit-info", shellQuote(editInfo)])
        }
        return parts.joined(separator: " ")
    }

    public func generate(request: GenerationRequest) async throws -> GenerationResult {
        let sourceText = request.sourceText.trimmingCharacters(in: .whitespacesAndNewlines)
        let referenceAudioPath = request.referenceAudioPath.trimmingCharacters(in: .whitespacesAndNewlines)
        let referenceText = request.referenceText.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !sourceText.isEmpty else {
            throw SpeechGenerationError.missingText
        }
        guard !referenceAudioPath.isEmpty else {
            throw SpeechGenerationError.missingReferenceAudio
        }
        guard !referenceText.isEmpty else {
            throw SpeechGenerationError.missingReferenceText
        }

        let formattedPrompt = formatter.format(text: sourceText, emotion: request.emotionText)
        let outputURL = try outputURL(forID: request.id)
        try ensureOutputDirectoryExists(for: outputURL)

        if ProcessInfo.processInfo.arguments.contains("--uitest-mock-generation") {
            try writeMockWAV(to: outputURL)
            return GenerationResult(
                formattedPrompt: formattedPrompt,
                outputURL: outputURL,
                standardOutput: "Mock UI test generation completed.",
                standardError: ""
            )
        }

        let shellCommand = command(
            formattedText: formattedPrompt,
            referenceAudioPath: referenceAudioPath,
            referenceText: referenceText,
            outputURL: outputURL,
            model: request.model,
            maxNewTokens: request.maxNewTokens,
            editType: request.editType,
            editInfo: request.editInfo
        )

        let result = try await run(
            command: shellCommand,
            formattedPrompt: formattedPrompt,
            outputURL: outputURL
        )
        // Sanity check: the CLI claimed success but if `-o` was ignored or it
        // crashed mid-write we'd silently add an unplayable history entry. Surface
        // a clear, actionable error instead.
        guard FileManager.default.fileExists(atPath: outputURL.path) else {
            throw SpeechGenerationError.shellFailure(
                "mlx-speech reported success but no audio file was found at \(outputURL.path)."
            )
        }
        return result
    }

    private func ensureOutputDirectoryExists(for outputURL: URL) throws {
        let directory = outputURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    /// Internal so tests can drive cancellation against an arbitrary shell command.
    /// `formattedPrompt` and `outputURL` are returned in the result for the success path.
    func run(command: String, formattedPrompt: String, outputURL: URL) async throws -> GenerationResult {
        let processBox = ProcessBox()

        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<GenerationResult, Error>) in
                DispatchQueue.global(qos: .userInitiated).async {
                    let process = Process()
                    process.executableURL = URL(fileURLWithPath: "/bin/zsh")
                    process.arguments = ["-lc", command]

                    let standardOutput = Pipe()
                    let standardError = Pipe()
                    process.standardOutput = standardOutput
                    process.standardError = standardError
                    processBox.store(process)

                    do {
                        try process.run()
                        process.waitUntilExit()

                        let stdoutData = standardOutput.fileHandleForReading.readDataToEndOfFile()
                        let stderrData = standardError.fileHandleForReading.readDataToEndOfFile()
                        let stdout = String(decoding: stdoutData, as: UTF8.self)
                        let stderr = String(decoding: stderrData, as: UTF8.self)

                        // If the surrounding Task was cancelled, surface CancellationError
                        // rather than a shellFailure (the process likely exited via SIGTERM/SIGKILL).
                        if processBox.wasCancelled {
                            continuation.resume(throwing: CancellationError())
                            return
                        }

                        if process.terminationStatus == 0 {
                            continuation.resume(
                                returning: GenerationResult(
                                    formattedPrompt: formattedPrompt,
                                    outputURL: outputURL,
                                    standardOutput: stdout,
                                    standardError: stderr
                                )
                            )
                        } else {
                            let message = stderr.isEmpty ? stdout : stderr
                            continuation.resume(throwing: SpeechGenerationError.shellFailure(message.trimmingCharacters(in: .whitespacesAndNewlines)))
                        }
                    } catch {
                        continuation.resume(throwing: error)
                    }
                }
            }
        } onCancel: {
            processBox.cancel()
        }
    }

    private func writeMockWAV(to outputURL: URL) throws {
        let sampleRate: UInt32 = 44_100
        let channelCount: UInt16 = 1
        let bitsPerSample: UInt16 = 16
        let durationFrames: UInt32 = sampleRate * 3
        let bytesPerSample = UInt32(bitsPerSample / 8)
        let dataChunkSize = durationFrames * UInt32(channelCount) * bytesPerSample
        let riffChunkSize = 36 + dataChunkSize
        let byteRate = sampleRate * UInt32(channelCount) * bytesPerSample
        let blockAlign = channelCount * (bitsPerSample / 8)

        var data = Data()
        data.append(contentsOf: Array("RIFF".utf8))
        data.append(contentsOf: withUnsafeBytes(of: riffChunkSize.littleEndian, Array.init))
        data.append(contentsOf: Array("WAVE".utf8))
        data.append(contentsOf: Array("fmt ".utf8))
        data.append(contentsOf: withUnsafeBytes(of: UInt32(16).littleEndian, Array.init))
        data.append(contentsOf: withUnsafeBytes(of: UInt16(1).littleEndian, Array.init))
        data.append(contentsOf: withUnsafeBytes(of: channelCount.littleEndian, Array.init))
        data.append(contentsOf: withUnsafeBytes(of: sampleRate.littleEndian, Array.init))
        data.append(contentsOf: withUnsafeBytes(of: byteRate.littleEndian, Array.init))
        data.append(contentsOf: withUnsafeBytes(of: blockAlign.littleEndian, Array.init))
        data.append(contentsOf: withUnsafeBytes(of: bitsPerSample.littleEndian, Array.init))
        data.append(contentsOf: Array("data".utf8))
        data.append(contentsOf: withUnsafeBytes(of: dataChunkSize.littleEndian, Array.init))

        let amplitude = Double(Int16.max) * 0.22
        let fadeSampleCount = Int(sampleRate / 20)

        for frame in 0..<Int(durationFrames) {
            let time = Double(frame) / Double(sampleRate)
            let envelope: Double
            if frame < fadeSampleCount {
                envelope = Double(frame) / Double(fadeSampleCount)
            } else if frame > Int(durationFrames) - fadeSampleCount {
                envelope = Double(Int(durationFrames) - frame) / Double(fadeSampleCount)
            } else {
                envelope = 1
            }

            let section = frame / Int(sampleRate)
            let frequency: Double
            switch section {
            case 0:
                frequency = 523.25
            case 1:
                frequency = 659.25
            default:
                frequency = 783.99
            }
            let sampleValue = sin(2 * Double.pi * frequency * time) * amplitude * max(0, envelope)
            let sample = Int16(sampleValue.rounded()).littleEndian
            data.append(contentsOf: withUnsafeBytes(of: sample, Array.init))
        }

        try data.write(to: outputURL, options: .atomic)
    }

    private func shellQuote(_ value: String) -> String {
        let escaped = value.replacingOccurrences(of: "\"", with: "\\\"")
        return "\"\(escaped)\""
    }
}

/// Thread-safe holder so an `onCancel` block running on an arbitrary executor can reach the
/// in-flight `Process` and signal it. Uses POSIX `kill` because `Process.terminate()` only
/// delivers SIGTERM; we follow up with SIGKILL after a short grace period.
final class ProcessBox: @unchecked Sendable {
    private let lock = NSLock()
    private var process: Process?
    private(set) var wasCancelled = false

    func store(_ process: Process) {
        lock.lock(); defer { lock.unlock() }
        self.process = process
    }

    func cancel() {
        lock.lock()
        wasCancelled = true
        let target = process
        lock.unlock()

        guard let target, target.isRunning else { return }
        let pid = target.processIdentifier
        target.terminate() // SIGTERM
        DispatchQueue.global(qos: .userInitiated).asyncAfter(deadline: .now() + 1.0) {
            if target.isRunning {
                kill(pid, SIGKILL)
            }
        }
    }
}
