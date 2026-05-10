import AVFoundation
import Combine
import Foundation

public final class AudioPlayerController: NSObject, ObservableObject, AVAudioPlayerDelegate {
    @Published public private(set) var isPlaying = false
    /// URL of the clip currently loaded into the player, or `nil` after `stop()`.
    /// Lets callers (UI rows, dock) decide between resume-vs-replace without
    /// inspecting the underlying `AVAudioPlayer`.
    @Published public private(set) var currentURL: URL?
    /// Fires exactly when the underlying `AVAudioPlayer` reports it finished
    /// playing naturally. Subscribers (`AppViewModel`) use this to clear
    /// per-row "playing" state once a clip ends on its own.
    public let didFinish = PassthroughSubject<Void, Never>()
    private var player: AVAudioPlayer?

    public override init() {
        super.init()
    }

    public func load(url: URL) throws {
        stop()
        player = try AVAudioPlayer(contentsOf: url)
        player?.delegate = self
        player?.prepareToPlay()
        currentURL = url
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
            }
            return
        }
        try load(url: url)
        player?.play()
        isPlaying = player?.isPlaying ?? false
    }

    public func pause() {
        guard let player, player.isPlaying else { return }
        player.pause()
        isPlaying = false
    }

    public func togglePlayback() {
        guard let player else {
            return
        }

        if player.isPlaying {
            player.pause()
            isPlaying = false
        } else {
            player.play()
            isPlaying = true
        }
    }

    public func stop() {
        player?.stop()
        player = nil
        isPlaying = false
        currentURL = nil
    }

    /// True iff the given URL is the loaded clip *and* the player is currently running.
    public func isPlaying(url: URL) -> Bool {
        currentURL == url && isPlaying
    }

    public func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        isPlaying = false
        didFinish.send(())
    }
}
