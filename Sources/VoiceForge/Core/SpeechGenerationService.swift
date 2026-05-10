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

    public func defaultOutputURL(homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser) throws -> URL {
        homeDirectory
            .appendingPathComponent("voiceforge", isDirectory: true)
            .appendingPathComponent("voiceforge_output.wav")
    }

    public func command(
        formattedText: String,
        referenceAudioPath: String,
        referenceText: String,
        outputURL: URL
    ) -> String {
        [
            "mlx-speech",
            "tts",
            "--model",
            "fish-s2-pro",
            "--text",
            shellQuote(formattedText),
            "--reference-audio",
            shellQuote(referenceAudioPath),
            "--reference-text",
            shellQuote(referenceText),
            "-o",
            shellQuote(outputURL.path)
        ].joined(separator: " ")
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
        let outputURL = try defaultOutputURL()
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
            outputURL: outputURL
        )

        return try await run(command: shellCommand, formattedPrompt: formattedPrompt, outputURL: outputURL)
    }

    private func ensureOutputDirectoryExists(for outputURL: URL) throws {
        let directory = outputURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    private func run(command: String, formattedPrompt: String, outputURL: URL) async throws -> GenerationResult {
        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: "/bin/zsh")
                process.arguments = ["-lc", command]

                let standardOutput = Pipe()
                let standardError = Pipe()
                process.standardOutput = standardOutput
                process.standardError = standardError

                do {
                    try process.run()
                    process.waitUntilExit()

                    let stdoutData = standardOutput.fileHandleForReading.readDataToEndOfFile()
                    let stderrData = standardError.fileHandleForReading.readDataToEndOfFile()
                    let stdout = String(decoding: stdoutData, as: UTF8.self)
                    let stderr = String(decoding: stderrData, as: UTF8.self)

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
