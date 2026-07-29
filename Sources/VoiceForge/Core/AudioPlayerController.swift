import AVFoundation
import Combine
import Foundation

@MainActor
public final class AudioPlayerController: NSObject, ObservableObject, AVAudioPlayerDelegate {
    @Published public private(set) var isPlaying = false
    /// URL of the clip currently loaded into the player, or `nil` after `stop()`.
    /// Lets callers (UI rows, dock) decide between resume-vs-replace without
    /// inspecting the underlying `AVAudioPlayer`.
    @Published public private(set) var currentURL: URL?
    /// Playhead position in seconds. Updated ~30x/second while playing.
    @Published public private(set) var currentTime: TimeInterval = 0
    /// Total duration of the loaded clip in seconds, 0 when nothing is loaded.
    @Published public private(set) var duration: TimeInterval = 0
    /// Peak-amplitude envelope of the loaded clip, one value per bar in [0, 1].
    /// Empty until async extraction finishes (or if extraction fails).
    @Published public private(set) var waveform: [Float] = []

    /// Fires exactly when the underlying `AVAudioPlayer` reports it finished
    /// playing naturally. Subscribers (`AppViewModel`) use this to clear
    /// per-row "playing" state once a clip ends on its own.
    public let didFinish = PassthroughSubject<Void, Never>()

    private var player: AVAudioPlayer?
    private var tickTask: Task<Void, Never>?
    private var waveformTask: Task<Void, Never>?

    public override init() {
        super.init()
    }

    deinit {
        tickTask?.cancel()
        waveformTask?.cancel()
    }

    public func load(url: URL) throws {
        stop()
        let newPlayer = try AVAudioPlayer(contentsOf: url)
        newPlayer.delegate = self
        newPlayer.prepareToPlay()
        player = newPlayer
        currentURL = url
        duration = newPlayer.duration
        currentTime = 0
        loadWaveform(from: url)
    }

    /// Smart play: if `url` is already loaded, just resume (no reload, so the
    /// playhead stays put). Otherwise stop the current clip, load the new one,
    /// and start it from the beginning. This is the single entry point row-level
    /// and dock-level controls should call so that switching between history
    /// entries actually swaps the audio.
    public func play(url: URL) throws {
        if currentURL == url, let player {
            if !player.isPlaying {
                player.play()
                isPlaying = true
                startTicking()
            }
            return
        }
        try load(url: url)
        player?.play()
        isPlaying = player?.isPlaying ?? false
        if isPlaying { startTicking() }
    }

    public func pause() {
        guard let player, player.isPlaying else { return }
        player.pause()
        isPlaying = false
        stopTicking()
    }

    public func togglePlayback() {
        guard let player else {
            return
        }

        if player.isPlaying {
            player.pause()
            isPlaying = false
            stopTicking()
        } else {
            player.play()
            isPlaying = true
            startTicking()
        }
    }

    public func stop() {
        stopTicking()
        waveformTask?.cancel()
        waveformTask = nil
        player?.stop()
        player = nil
        isPlaying = false
        currentURL = nil
        currentTime = 0
        duration = 0
        waveform = []
    }

    /// Moves the playhead to `time`, clamped to `[0, duration]`. Safe to call
    /// whether or not playback is currently running.
    public func seek(to time: TimeInterval) {
        guard let player else { return }
        let clamped = max(0, min(time, player.duration))
        player.currentTime = clamped
        currentTime = clamped
    }

    /// True iff the given URL is the loaded clip *and* the player is currently running.
    public func isPlaying(url: URL) -> Bool {
        currentURL == url && isPlaying
    }

    /// AVFoundation may invoke delegate callbacks off the main actor, so this
    /// conformance method is `nonisolated` and hops back explicitly rather than
    /// forcing the whole delegate protocol onto the main actor.
    nonisolated public func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor in
            self.isPlaying = false
            self.currentTime = 0
            self.stopTicking()
            self.didFinish.send(())
        }
    }

    // MARK: - Playhead timer

    /// Drives `currentTime` updates while playing using a cancellable, structured
    /// `Task` loop instead of `Timer` — avoids retain cycles (no strong target
    /// reference to invalidate) and Sendable-closure friction under Swift 6
    /// strict concurrency, since the loop body stays isolated to this MainActor
    /// class throughout.
    private func startTicking() {
        stopTicking()
        tickTask = Task { [weak self] in
            while true {
                guard let self, let player = self.player, player.isPlaying else { return }
                self.currentTime = player.currentTime
                try? await Task.sleep(nanoseconds: 33_000_000) // ~30 Hz
                if Task.isCancelled { return }
            }
        }
    }

    private func stopTicking() {
        tickTask?.cancel()
        tickTask = nil
    }

    // MARK: - Waveform extraction

    /// Kicks off async envelope extraction for `url` and applies the result only
    /// if this controller is still showing `url` by the time it finishes (guards
    /// against a stale result from a superseded `load()` overwriting a newer one).
    private func loadWaveform(from url: URL) {
        waveformTask?.cancel()
        waveform = []
        waveformTask = Task { [weak self] in
            let bars = Self.extractWaveform(from: url)
            if Task.isCancelled { return }
            guard let self, self.currentURL == url else { return }
            self.waveform = bars
        }
    }

    /// Extracts a peak-amplitude envelope from an audio file using `AVAudioFile`/
    /// `AVAudioPCMBuffer`. Reads through `floatChannelData`, which AVFoundation
    /// guarantees is a properly aligned, per-channel `Float` buffer — no manual
    /// byte-offset parsing or unaligned raw-pointer loads, and every channel is
    /// accounted for (averaged per frame) rather than assuming mono.
    nonisolated private static func extractWaveform(from url: URL, barCount: Int = 100) -> [Float] {
        guard let file = try? AVAudioFile(forReading: url) else { return [] }
        let totalFrames = Int(file.length)
        guard totalFrames > 0 else { return [] }

        guard let buffer = AVAudioPCMBuffer(
            pcmFormat: file.processingFormat,
            frameCapacity: AVAudioFrameCount(totalFrames)
        ) else { return [] }

        do {
            try file.read(into: buffer)
        } catch {
            return []
        }

        guard let channelData = buffer.floatChannelData else { return [] }
        let channelCount = Int(buffer.format.channelCount)
        let frameLength = Int(buffer.frameLength)
        guard channelCount > 0, frameLength > 0 else { return [] }

        let effectiveBarCount = min(barCount, frameLength)
        guard effectiveBarCount > 0 else { return [] }
        let samplesPerBar = max(1, frameLength / effectiveBarCount)

        var bars: [Float] = []
        bars.reserveCapacity(effectiveBarCount)

        var frameIndex = 0
        while frameIndex < frameLength && bars.count < effectiveBarCount {
            let end = min(frameIndex + samplesPerBar, frameLength)
            var peak: Float = 0
            for f in frameIndex..<end {
                var sum: Float = 0
                for ch in 0..<channelCount {
                    sum += abs(channelData[ch][f])
                }
                let frameAverage = sum / Float(channelCount)
                if frameAverage > peak { peak = frameAverage }
            }
            bars.append(min(1, peak))
            frameIndex = end
        }

        return bars
    }
}
