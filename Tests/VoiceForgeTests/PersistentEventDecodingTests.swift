import Foundation
import Testing
@testable import VoiceForge

/// Regression: the real Drama 3 engine's `done` event (recorded from a live render) must decode.
/// A decode failure used to drop the event silently and leave the app stuck on "Generating…".
@Suite struct PersistentEventDecodingTests {
    static let realDoneLine = #"{"event": "done", "id": "single", "output": "/tmp/out.wav", "codes": "/tmp/out.npy", "duration": 5.38702947845805, "sample_rate": 44100, "attempts": {"attempts": [{"attempt": 1, "reason": null, "temperature": 0.7, "top_p": 0.7, "top_k": 30, "seed": 7, "duration": 5.38702947845805, "speech_seconds": 5.1439909297052155, "silence_seconds": 0.24303854875283445, "elapsed_seconds": 18.049915916999453, "prefix_cache_hit": false}], "final_settings": {"temperature": 0.7, "top_p": 0.7, "top_k": 30, "seed": 7}, "reference_cache_hits": 0, "reference_count": 1, "reference_encode_seconds": 0.8261974999986705, "normalization_changed": false, "model_cache_hit": true, "model_load_seconds": 2.5458999516558833e-05}, "request_seconds": 18.880471374999615}"#

    @Test func realEngineDoneEventDecodes() throws {
        let event = try PersistentGenerationCoordinator.decodeEvent(Data(Self.realDoneLine.utf8))
        #expect(event.event == "done")
        #expect(event.output == "/tmp/out.wav")
        #expect(event.attempts?.count == 1)
    }

    @Test func bareAttemptArrayStillDecodes() throws {
        let line = #"{"event":"done","id":"x","output":"/tmp/a.wav","attempts":[{"attempt":1,"reason":"stall"},{"attempt":2}]}"#
        let event = try PersistentGenerationCoordinator.decodeEvent(Data(line.utf8))
        #expect(event.attempts?.count == 2)
    }

    @Test func unexpectedFieldTypeDoesNotDropTerminalEvent() throws {
        let line = #"{"event":"done","id":"x","output":"/tmp/a.wav","duration":"not-a-number","wer":{"nested":true}}"#
        let event = try PersistentGenerationCoordinator.decodeEvent(Data(line.utf8))
        #expect(event.event == "done")
        #expect(event.output == "/tmp/a.wav")
        #expect(event.duration == nil)
    }
}
