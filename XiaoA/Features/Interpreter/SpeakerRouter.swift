#if canImport(FluidAudio)
// Parked 2026-10-14: voiceprint interpreter. Builds only once the FluidAudio package is added back.
import Foundation
import FluidAudio

/// Splits the microphone by speaker, so each translation session only ever hears the person it
/// is meant to translate (OpenAI's advice: keep each speaker's audio separate):
/// - Mom's speech goes to the session that speaks the other person's language,
/// - everyone else's speech goes to the session that speaks Chinese,
/// - each session hears silence the rest of the time.
/// Who is talking comes from Mom's voiceprint, checked on the phone. Audio is held back for
/// about a second until that's known, then sent on.
actor SpeakerRouter {
    enum Speaker: Equatable, Sendable {
        case mom
        /// Someone else; numbered in the order they first spoke (1, 2, 3…).
        case other(Int)
    }

    enum Event: Sendable {
        /// Someone started or stopped talking (drives the waveform and "wait for a pause").
        case speaking(Bool)
        /// A new stretch of speech is about to reach a session.
        case utterance(id: Int, speaker: Speaker)
        /// For the debug log.
        case decided(id: Int, speaker: Speaker?, distance: Float, seconds: Double, note: String)
    }

    private struct Chunk {
        let pcm24: Data      // 24 kHz PCM16, for OpenAI
        let start: Int       // first 16 kHz sample
        let end: Int         // one past the last
    }

    private struct Utterance {
        let id: Int
        var start: Int
        var end: Int?
        var speaker: Speaker?
        /// Too short or unclear to translate: its audio is sent as silence.
        var dropped = false
        var announced = false
    }

    // Cosine distance to Mom's voiceprint. Below `momBelow`: Mom. Above `otherAbove`: someone
    // else. In between, wait for more speech (up to `forceAfter`), then go with the nearer side.
    private let momBelow: Float = 0.45
    private let otherAbove: Float = 0.62
    /// Other speakers whose voiceprints are this close are the same person.
    private let samePersonBelow: Float = 0.5

    private let rate = VoiceID.sampleRate
    private var decideAfter: Int { rate }              // 1.0 s of speech
    private var forceAfter: Int { rate * 5 / 2 }       // 2.5 s
    private var minSpeech: Int { rate * 3 / 10 }       // 0.3 s
    /// Quiet audio waits this long before going out as silence, in case speech is detected
    /// a little late (detection can reach back ~0.4 s).
    private var quietLag: Int { rate / 2 }

    private let voice: VoiceID
    private let momPrints: [[Float]]
    private var sessionMomPrints: [[Float]] = []
    private var others: [(print: [Float], count: Int)] = []
    private let send: @Sendable (_ toPartner: Data, _ toChinese: Data) -> Void
    private let onEvent: @Sendable (Event) -> Void

    private var audio: [Float] = []      // recent 16 kHz audio
    private var audioBase = 0            // sample index of audio[0]
    private var received = 0             // samples received
    private var vadQueue: [Float] = []   // not yet seen by voice activity detection
    private var vadState: VadStreamState?
    private var pending: [Chunk] = []
    private var utterances: [Utterance] = []
    private var nextID = 1
    private var speaking = false

    init(voice: VoiceID,
         momPrints: [[Float]],
         send: @escaping @Sendable (Data, Data) -> Void,
         onEvent: @escaping @Sendable (Event) -> Void) {
        self.voice = voice
        self.momPrints = momPrints
        self.send = send
        self.onEvent = onEvent
    }

    /// ~100 ms of microphone audio, in both formats. Call in order.
    func ingest(pcm24: Data, pcm16: [Float]) async {
        if vadState == nil { vadState = await voice.newStreamState() }
        pending.append(Chunk(pcm24: pcm24, start: received, end: received + pcm16.count))
        received += pcm16.count
        audio.append(contentsOf: pcm16)
        let keep = rate * 30
        if audio.count > keep + rate * 5 {
            let drop = audio.count - keep
            audio.removeFirst(drop)
            audioBase += drop
        }

        vadQueue.append(contentsOf: pcm16)
        while vadQueue.count >= VoiceID.vadChunk {
            let step = Array(vadQueue.prefix(VoiceID.vadChunk))
            vadQueue.removeFirst(VoiceID.vadChunk)
            guard let state = vadState,
                  let result = try? await voice.detectSpeech(step, state: state) else { continue }
            vadState = result.state
            if let event = result.event { handle(event) }
        }

        await decide()
        release()
    }

    // MARK: - Speech start/stop

    private func handle(_ event: VadStreamEvent) {
        if event.isStart {
            utterances.append(Utterance(id: nextID, start: max(event.sampleIndex, audioBase)))
            nextID += 1
            setSpeaking(true)
        } else if let i = utterances.lastIndex(where: { $0.end == nil }) {
            utterances[i].end = max(event.sampleIndex, utterances[i].start)
            setSpeaking(false)
        }
        if utterances.count > 60 { utterances.removeFirst(utterances.count - 60) }
    }

    private func setSpeaking(_ value: Bool) {
        guard speaking != value else { return }
        speaking = value
        onEvent(.speaking(value))
    }

    /// The point up to which voice activity detection has looked.
    private var seen: Int { received - vadQueue.count }

    // MARK: - Whose voice

    private func decide() async {
        for i in utterances.indices where utterances[i].speaker == nil && !utterances[i].dropped {
            let u = utterances[i]
            let end = u.end ?? seen
            let length = end - u.start
            let finished = u.end != nil
            guard length >= decideAfter || finished else { continue }
            guard length >= minSpeech else {
                utterances[i].dropped = true
                onEvent(.decided(id: u.id, speaker: nil, distance: 0, seconds: seconds(length), note: "too short"))
                continue
            }
            guard let clip = samples(from: u.start, to: end),
                  let print = try? await voice.voiceprint(of: clip) else {
                // Can't tell. Never guess: drop it rather than send it to the wrong side.
                if finished || length >= forceAfter * 2 {
                    utterances[i].dropped = true
                    onEvent(.decided(id: u.id, speaker: nil, distance: 0, seconds: seconds(length), note: "no voiceprint"))
                }
                continue
            }
            let d = momDistance(print)
            let speaker: Speaker
            var note = ""
            if d < momBelow {
                speaker = .mom
            } else if d > otherAbove {
                speaker = .other(otherNumber(for: print))
            } else if finished || length >= forceAfter {
                // Unclear: go with the nearer side.
                speaker = d < (momBelow + otherAbove) / 2 ? .mom : .other(otherNumber(for: print))
                note = "unclear, nearer side"
            } else {
                continue   // listen a bit longer
            }
            utterances[i].speaker = speaker
            // Learn how Mom sounds here (room, distance), from clear matches only.
            if speaker == .mom, d < 0.35, length >= rate * 2 {
                sessionMomPrints.append(print)
                if sessionMomPrints.count > 6 { sessionMomPrints.removeFirst() }
            }
            onEvent(.decided(id: u.id, speaker: speaker, distance: d, seconds: seconds(length), note: note))
        }
    }

    private func momDistance(_ print: [Float]) -> Float {
        (momPrints + sessionMomPrints).map { VoiceID.distance(print, $0) }.min() ?? 2
    }

    /// Which other person this is: an earlier one with a close voice, or someone new.
    private func otherNumber(for print: [Float]) -> Int {
        let distances = others.map { VoiceID.distance(print, $0.print) }
        if let best = distances.indices.min(by: { distances[$0] < distances[$1] }), distances[best] < samePersonBelow {
            // Running average of that person's voice.
            others[best].print = VoiceID.mean([others[best].print, print])
            others[best].count += 1
            return best + 1
        }
        others.append((print, 1))
        return others.count
    }

    private func samples(from start: Int, to end: Int) -> [Float]? {
        let a = max(start, audioBase) - audioBase
        let b = min(end, audioBase + audio.count) - audioBase
        guard b > a else { return nil }
        return Array(audio[a..<b])
    }

    private func seconds(_ samples: Int) -> Double { Double(samples) / Double(rate) }

    // MARK: - Sending audio on

    private func release() {
        while let chunk = pending.first {
            if let i = utterances.lastIndex(where: { $0.start < chunk.end && ($0.end ?? .max) > chunk.start }) {
                let u = utterances[i]
                if u.dropped {
                    sendSilence(chunk)
                } else if let speaker = u.speaker {
                    if !u.announced {
                        utterances[i].announced = true
                        onEvent(.utterance(id: u.id, speaker: speaker))
                    }
                    let quiet = Data(count: chunk.pcm24.count)
                    if speaker == .mom {
                        send(chunk.pcm24, quiet)
                    } else {
                        send(quiet, chunk.pcm24)
                    }
                } else {
                    break   // still working out who it is
                }
            } else if chunk.end + quietLag <= seen {
                sendSilence(chunk)
            } else {
                break
            }
            pending.removeFirst()
        }
    }

    private func sendSilence(_ chunk: Chunk) {
        let quiet = Data(count: chunk.pcm24.count)
        send(quiet, quiet)
    }
}
#endif
