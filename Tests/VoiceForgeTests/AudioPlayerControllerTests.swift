import Foundation
import Testing
#if canImport(VoiceForgeCore)
@testable import VoiceForgeCore
#else
@testable import VoiceForge
#endif

@MainActor
struct AudioPlayerControllerTests {
    @Test func playReplacesPlayerWhenURLDiffers() throws {
        let player = AudioPlayerController()
        let dir = makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }

        let urlA = dir.appendingPathComponent("a.wav")
        let urlB = dir.appendingPathComponent("b.wav")
        try writeSilentWAV(to: urlA)
        try writeSilentWAV(to: urlB)

        // First clip becomes the current URL.
        try player.play(url: urlA)
        #expect(player.currentURL == urlA)

        // Switching to a different clip swaps currentURL — i.e. AudioPlayerController
        // didn't just keep playing the first clip.
        try player.play(url: urlB)
        #expect(player.currentURL == urlB)

        // Calling play() again with the same URL keeps it loaded (no reload churn).
        try player.play(url: urlB)
        #expect(player.currentURL == urlB)

        // pause() doesn't unload — currentURL must survive.
        player.pause()
        #expect(player.currentURL == urlB)

        // stop() clears the slot so the next play starts fresh.
        player.stop()
        #expect(player.currentURL == nil)
        #expect(!player.isPlaying)
    }

    @Test func isPlayingURLOnlyReturnsTrueForCurrentClip() throws {
        let player = AudioPlayerController()
        let dir = makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let urlA = dir.appendingPathComponent("a.wav")
        let urlB = dir.appendingPathComponent("b.wav")
        try writeSilentWAV(to: urlA)
        try writeSilentWAV(to: urlB)

        try player.play(url: urlA)
        #expect(player.isPlaying(url: urlA) == player.isPlaying)
        // urlB has never been loaded — must always be false even if A is playing.
        #expect(!player.isPlaying(url: urlB))
    }
}

// MARK: - Helpers

func makeTempDirectory() -> URL {
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("VoiceForgeAudioTests-\(UUID().uuidString)", isDirectory: true)
    try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}

/// Writes a minimal, valid 8 kHz mono 16-bit silent WAV that AVAudioPlayer can open.
func writeSilentWAV(to url: URL, sampleCount: Int = 8) throws {
    let sampleRate: UInt32 = 8_000
    let channels: UInt16 = 1
    let bitsPerSample: UInt16 = 16
    let byteRate = sampleRate * UInt32(channels) * UInt32(bitsPerSample / 8)
    let blockAlign = channels * (bitsPerSample / 8)
    let dataSize = UInt32(sampleCount * 2)
    let riffSize = 36 + dataSize

    var data = Data()
    data.append(contentsOf: Array("RIFF".utf8))
    data.append(contentsOf: withUnsafeBytes(of: riffSize.littleEndian, Array.init))
    data.append(contentsOf: Array("WAVE".utf8))
    data.append(contentsOf: Array("fmt ".utf8))
    data.append(contentsOf: withUnsafeBytes(of: UInt32(16).littleEndian, Array.init))
    data.append(contentsOf: withUnsafeBytes(of: UInt16(1).littleEndian, Array.init))
    data.append(contentsOf: withUnsafeBytes(of: channels.littleEndian, Array.init))
    data.append(contentsOf: withUnsafeBytes(of: sampleRate.littleEndian, Array.init))
    data.append(contentsOf: withUnsafeBytes(of: byteRate.littleEndian, Array.init))
    data.append(contentsOf: withUnsafeBytes(of: blockAlign.littleEndian, Array.init))
    data.append(contentsOf: withUnsafeBytes(of: bitsPerSample.littleEndian, Array.init))
    data.append(contentsOf: Array("data".utf8))
    data.append(contentsOf: withUnsafeBytes(of: dataSize.littleEndian, Array.init))
    data.append(Data(repeating: 0, count: Int(dataSize)))
    try data.write(to: url)
}
