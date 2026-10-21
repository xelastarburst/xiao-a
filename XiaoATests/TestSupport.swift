import AVFoundation
import Foundation
@testable import XiaoA

/// A speech synthesizer that records what it was asked to say. With `autoFinish`, each sentence
/// "starts" and "finishes" a moment after it is queued, like a fast voice.
@MainActor
final class FakeSpeechEngine: SpeechEngine {
    var isSpeaking = false
    weak var delegate: AVSpeechSynthesizerDelegate?
    private(set) var utterances: [AVSpeechUtterance] = []
    private(set) var stopCount = 0
    var onSpeak: ((AVSpeechUtterance) -> Void)?

    var spoken: [String] { utterances.map(\.speechString) }

    func speak(_ utterance: AVSpeechUtterance) {
        utterances.append(utterance)
        onSpeak?(utterance)
    }

    func stopSpeaking(at boundary: AVSpeechBoundary) -> Bool {
        stopCount += 1
        return true
    }
}

/// Builds a Speaker on fake engines and drives their start/finish signals.
@MainActor
final class FakeVoice {
    private(set) var engines: [FakeSpeechEngine] = []
    /// When true, every sentence finishes ~10 ms after it is queued.
    var autoFinish = true
    private(set) var speaker: Speaker!

    init(autoFinish: Bool = true) {
        self.autoFinish = autoFinish
        speaker = Speaker(makeEngine: { [weak self] in
            let engine = FakeSpeechEngine()
            engine.onSpeak = { [weak self, weak engine] utterance in
                guard let self, self.autoFinish else { return }
                Task { @MainActor [weak self, weak engine] in
                    try? await Task.sleep(nanoseconds: 10_000_000)
                    guard let self, let engine, let speaker = self.speaker else { return }
                    speaker.started(from: ObjectIdentifier(engine))
                    speaker.finished(ObjectIdentifier(utterance), from: ObjectIdentifier(engine))
                }
            }
            self?.engines.append(engine)
            return engine
        })
        speaker.preparePlayback = {}          // a fake voice needs no audio hardware
    }

    var current: FakeSpeechEngine { engines.last! }
    /// Everything said, on every engine, in order.
    var allSpoken: [String] { engines.flatMap(\.spoken) }

    func start(_ engine: FakeSpeechEngine? = nil) {
        let e = engine ?? current
        speaker.started(from: ObjectIdentifier(e))
    }

    /// The engine finishes everything it was given.
    func finishAll(_ engine: FakeSpeechEngine? = nil) {
        let e = engine ?? current
        speaker.started(from: ObjectIdentifier(e))
        for u in e.utterances { speaker.finished(ObjectIdentifier(u), from: ObjectIdentifier(e)) }
    }
}

/// Scripted microphone tries for the Learn coach. Once the script runs out it waits (until cancelled).
@MainActor
final class ScriptedMic {
    var answers: [String]
    private(set) var calls = 0

    init(_ answers: [String]) { self.answers = answers }

    func listen() async throws -> String? {
        calls += 1
        if answers.isEmpty {
            try? await Task.sleep(nanoseconds: 30_000_000_000)
            return nil
        }
        return answers.removeFirst()
    }
}

enum TestFiles {
    static func temporaryURL(_ name: String = UUID().uuidString) -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("xiaoa-test-\(name).json")
    }
}

/// Polls until the condition holds (true) or the time runs out (false).
@MainActor
func waitUntil(_ seconds: Double = 5, _ condition: () -> Bool) async -> Bool {
    let deadline = Date().addingTimeInterval(seconds)
    while Date() < deadline {
        if condition() { return true }
        try? await Task.sleep(nanoseconds: 20_000_000)
    }
    return condition()
}

/// Little-endian 16-bit PCM of `count` samples at a constant level (0…1).
func pcm16(level: Double, count: Int = 2400) -> Data {
    let sample = Int16(max(-1, min(1, level)) * 32767)
    var data = Data(capacity: count * 2)
    for _ in 0..<count {
        withUnsafeBytes(of: sample.littleEndian) { data.append(contentsOf: $0) }
    }
    return data
}

func peak(of buffer: AVAudioPCMBuffer) -> Float {
    guard let channel = buffer.floatChannelData?[0] else { return 0 }
    var p: Float = 0
    for i in 0..<Int(buffer.frameLength) { p = max(p, abs(channel[i])) }
    return p
}
