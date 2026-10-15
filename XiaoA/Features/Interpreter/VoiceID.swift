#if canImport(FluidAudio)
// Parked 2026-10-14: voiceprint interpreter. Builds only once the FluidAudio package is added back.
import Foundation
import Accelerate
import FluidAudio

/// On-device voice tools for 翻译官, from FluidAudio (Apple Neural Engine):
/// - when anyone is talking (Silero voice activity detection), and
/// - whose voice it is (a 256-number WeSpeaker voiceprint per stretch of speech).
/// Nothing here leaves the phone. The models (~35 MB) download once, the first time.
actor VoiceID {
    static let shared = VoiceID()

    /// All audio here is 16 kHz mono.
    static let sampleRate = 16_000
    /// The voice activity model looks at 256 ms at a time.
    static let vadChunk = VadManager.chunkSize

    private var vad: VadManager?
    private var diarizer: DiarizerManager?
    private var loadTask: Task<Void, Error>?

    /// Speech starts at a fairly confident 0.6 and ends after 0.7 s of quiet.
    let segmentation = VadSegmentationConfig(minSpeechDuration: 0.15, minSilenceDuration: 0.7, speechPadding: 0.1)

    var isReady: Bool { vad != nil && diarizer != nil }

    /// Downloads (first time only) and loads the models. Safe to call often.
    func prepare() async throws {
        if isReady { return }
        if loadTask == nil {
            loadTask = Task { try await self.load() }
        }
        do {
            try await loadTask?.value
        } catch {
            loadTask = nil
            throw error
        }
    }

    private func load() async throws {
        let started = Date()
        let vad = try await VadManager(config: VadConfig(defaultThreshold: 0.6))
        let models = try await DiarizerModels.downloadIfNeeded()
        let diarizer = DiarizerManager()
        diarizer.initialize(models: models)
        self.vad = vad
        self.diarizer = diarizer
        print(String(format: "[XA] voice models ready in %.1fs", Date().timeIntervalSince(started)))
    }

    func newStreamState() async -> VadStreamState {
        guard let vad else { return VadStreamState.initial() }
        return await vad.makeStreamState()
    }

    /// One 256 ms step of voice activity detection.
    func detectSpeech(_ chunk: [Float], state: VadStreamState) async throws -> VadStreamResult {
        guard let vad else { throw VadError.notInitialized }
        return try await vad.processStreamingChunk(chunk, state: state, config: segmentation)
    }

    /// The voiceprint of one person's speech (at least ~0.3 s; only the last 8 s are used).
    func voiceprint(of samples: [Float]) throws -> [Float] {
        guard let diarizer else { throw DiarizerError.notInitialized }
        let clip = samples.count > 8 * Self.sampleRate ? Array(samples.suffix(8 * Self.sampleRate)) : samples
        guard clip.count >= Self.sampleRate * 3 / 10 else { throw DiarizerError.invalidAudioData }
        return try diarizer.extractSpeakerEmbedding(from: clip)
    }

    /// 0 = the same voice, ~1 = unrelated voices.
    nonisolated static func distance(_ a: [Float], _ b: [Float]) -> Float {
        guard a.count == b.count, !a.isEmpty else { return 2 }
        var dot: Float = 0, aa: Float = 0, bb: Float = 0
        vDSP_dotpr(a, 1, b, 1, &dot, vDSP_Length(a.count))
        vDSP_svesq(a, 1, &aa, vDSP_Length(a.count))
        vDSP_svesq(b, 1, &bb, vDSP_Length(b.count))
        guard aa > 0, bb > 0 else { return 2 }
        return 1 - dot / (aa.squareRoot() * bb.squareRoot())
    }

    /// Average of several voiceprints, normalised.
    nonisolated static func mean(_ prints: [[Float]]) -> [Float] {
        guard let first = prints.first else { return [] }
        var sum = [Float](repeating: 0, count: first.count)
        for p in prints where p.count == sum.count {
            vDSP_vadd(sum, 1, p, 1, &sum, 1, vDSP_Length(sum.count))
        }
        var norm: Float = 0
        vDSP_svesq(sum, 1, &norm, vDSP_Length(sum.count))
        let scale = norm > 0 ? 1 / norm.squareRoot() : 0
        return sum.map { $0 * scale }
    }
}

/// Mom's voiceprint, recorded once (翻译官 asks for it the first time; Alex mode can redo it).
/// Kept on this iPhone only, as numbers, not as a recording.
enum MomVoiceprint {
    private static let key = "momVoiceprint.v1"
    private static let size = 256

    /// One voiceprint per recorded sentence.
    static var prints: [[Float]] {
        guard let data = UserDefaults.standard.data(forKey: key) else { return [] }
        let floats: [Float] = data.withUnsafeBytes { Array($0.bindMemory(to: Float.self)) }
        guard floats.count >= size, floats.count % size == 0 else { return [] }
        return stride(from: 0, to: floats.count, by: size).map { Array(floats[$0..<$0 + size]) }
    }

    static var isRecorded: Bool { !prints.isEmpty }

    static func save(_ prints: [[Float]]) {
        let floats = prints.filter { $0.count == size }.flatMap { $0 }
        let data = floats.withUnsafeBufferPointer { Data(buffer: $0) }
        UserDefaults.standard.set(data, forKey: key)
    }

    static func clear() {
        UserDefaults.standard.removeObject(forKey: key)
    }
}
#endif
