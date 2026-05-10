import AVFoundation
import Foundation

public final class AudioPlayerController: NSObject, ObservableObject, AVAudioPlayerDelegate {
    @Published public private(set) var isPlaying = false
    private var player: AVAudioPlayer?

    public override init() {
        super.init()
    }

    public func load(url: URL) throws {
        stop()
        player = try AVAudioPlayer(contentsOf: url)
        player?.delegate = self
        player?.prepareToPlay()
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
    }

    public func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        isPlaying = false
    }
}
