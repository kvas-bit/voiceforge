import Combine
import Foundation
#if canImport(VoiceForgeCore)
import VoiceForgeCore
#endif

public enum ConversationPlaybackState: Equatable {
    case idle
    case playing(lineIndex: Int)
    case paused(lineIndex: Int)
    case finished
}

public final class ConversationPlayer: ObservableObject {
    @Published public private(set) var state: ConversationPlaybackState = .idle
    @Published public private(set) var currentLineIndex: Int?

    private let audioPlayer: AudioPlayerController
    private var cancellables = Set<AnyCancellable>()
    private var lines: [ConversationLine] = []

    public init(audioPlayer: AudioPlayerController) {
        self.audioPlayer = audioPlayer
        setupDidFinishSubscription()
    }

    private func setupDidFinishSubscription() {
        audioPlayer.didFinish
            .receive(on: RunLoop.main)
            .sink { [weak self] in
                self?.handlePlaybackFinished()
            }
            .store(in: &cancellables)
    }

    private func handlePlaybackFinished() {
        guard let idx = currentLineIndex, idx < lines.count - 1 else {
            state = .finished
            return
        }
        let nextIndex = idx + 1
        currentLineIndex = nextIndex
        state = .playing(lineIndex: nextIndex)
        loadAndPlayLine(at: nextIndex)
    }

    public func play(lines: [ConversationLine], fromIndex: Int = 0) {
        self.lines = lines
        guard !lines.isEmpty, fromIndex < lines.count else {
            state = .finished
            return
        }
        currentLineIndex = fromIndex
        state = .playing(lineIndex: fromIndex)
        loadAndPlayLine(at: fromIndex)
    }

    public func pause() {
        guard case .playing(let idx) = state else { return }
        audioPlayer.pause()
        state = .paused(lineIndex: idx)
    }

    public func resume() {
        guard case .paused(let idx) = state else { return }
        state = .playing(lineIndex: idx)
        audioPlayer.togglePlayback()
    }

    public func togglePlayback() {
        switch state {
        case .idle, .finished:
            if !lines.isEmpty {
                play(lines: lines, fromIndex: 0)
            }
        case .playing:
            pause()
        case .paused:
            resume()
        }
    }

    public func advance() {
        guard let idx = currentLineIndex, idx < lines.count - 1 else {
            state = .finished
            return
        }
        let nextIndex = idx + 1
        currentLineIndex = nextIndex
        state = .playing(lineIndex: nextIndex)
        loadAndPlayLine(at: nextIndex)
    }

    public func jump(to index: Int) {
        guard index >= 0, index < lines.count else { return }
        currentLineIndex = index
        state = .playing(lineIndex: index)
        loadAndPlayLine(at: index)
    }

    public func previous() {
        guard let idx = currentLineIndex, idx > 0 else { return }
        let prevIndex = idx - 1
        currentLineIndex = prevIndex
        state = .playing(lineIndex: prevIndex)
        loadAndPlayLine(at: prevIndex)
    }

    public func stop() {
        audioPlayer.stop()
        state = .idle
        currentLineIndex = nil
    }

    private func loadAndPlayLine(at index: Int) {
        guard index < lines.count, let path = lines[index].outputPath else { return }
        let url = URL(fileURLWithPath: path)
        try? audioPlayer.play(url: url)
    }
}
