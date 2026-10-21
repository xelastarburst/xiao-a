import AVFoundation

/// Microphone in (24 kHz PCM16 chunks) and translated speech out.
/// - Echo: while the phone is talking, the microphone sends silence so it never translates itself.
/// - Room noise: the phone learns how loud the room is and only lets through sound clearly
///   louder than that (someone talking to the phone). Background chatter, music and clatter are
///   sent as silence, so the transcriber never hears them.
/// - Loudness: translated speech is lifted and evened out (SpeechBooster) and played through
///   the loudspeaker at media volume.
final class InterpreterAudio {
    /// Called on an audio thread with ~100 ms of 24 kHz mono PCM16.
    var onMicChunk: ((Data) -> Void)?

    private let engine = AVAudioEngine()
    private let player = AVAudioPlayerNode()
    private let playFormat = SpeechBooster.format
    private let sendFormat = AVAudioFormat(commonFormat: .pcmFormatInt16, sampleRate: 24_000, channels: 1, interleaved: true)!
    private var converter: AVAudioConverter?
    private var booster = SpeechBooster()
    /// Rough loudness of what the mic heard, for "is the microphone working?" checks.
    private(set) var chunksSent = 0
    private(set) var loudChunks = 0

    /// The audio session mode. Default, never voice chat: voice processing handed the app empty
    /// microphone audio on some iPhones, and voice-chat mode plays quietly.
    static let sessionMode: AVAudioSession.Mode = .default

    private let lock = NSLock()
    /// When the phone is talking, so the mic sends silence (guarded by lock).
    private var playback = PlaybackClock()
    private var lastLoudInput = Date.distantPast
    /// Room-noise gate (audio thread only).
    private var gate = MicGate()

    // For the debug log (guarded by lock).
    private var statChunks = 0
    private var statOpen = 0
    private var statLoudest: Float = 0
    private var statRoom: Float = 0

    /// True while translated speech is playing (plus a short tail).
    var isPlaying: Bool {
        lock.lock(); defer { lock.unlock() }
        return playback.isMuted(at: Date())
    }

    /// When the phone last finished talking (now, if it still is).
    var speechEnd: Date {
        lock.lock(); defer { lock.unlock() }
        return playback.speechEnd(at: Date())
    }

    /// Stops translated speech that is playing or queued, e.g. when it turns out to be an echo.
    func flush() {
        player.stop()
        lock.lock(); playback.flush(at: Date()); lock.unlock()
        player.play()
    }

    /// True if the microphone heard someone talking in the last half second.
    var hearsSomeone: Bool {
        lock.lock(); defer { lock.unlock() }
        return Date().timeIntervalSince(lastLoudInput) < 0.5
    }

    /// Room level, loudest sound and how often the gate was open since the last call.
    func levelReport() -> String {
        lock.lock()
        let room = Int(statRoom), loudest = Int(statLoudest)
        let open = statChunks > 0 ? 100 * statOpen / statChunks : 0
        statChunks = 0; statOpen = 0; statLoudest = 0
        lock.unlock()
        let threshold = Int(max(MicGate.minSpeechLevel, Float(room) * MicGate.overRoom))
        return "room \(room), lets through > \(threshold), loudest \(loudest), open \(open)% of the time"
    }

    /// Loudest sample in 16-bit PCM, 0...32768.
    static func peak(of pcm16: Data) -> Int {
        pcm16.withUnsafeBytes { raw in
            var peak = 0
            var i = 0
            while i + 1 < raw.count {
                peak = max(peak, abs(Int(raw.loadUnaligned(fromByteOffset: i, as: Int16.self))))
                i += 2
            }
            return peak
        }
    }

    func setExternalMute(_ muted: Bool) {
        lock.lock()
        playback.setExternalMute(muted, at: Date())
        lock.unlock()
    }

    func start() throws {
        let session = AVAudioSession.sharedInstance()
        // Always the iPhone's own loudspeaker and microphone, even with AirPods connected:
        // the person across the table has to hear the translation and be heard.
        // Default mode (not voice chat) plays at full media loudness and never routes to
        // Bluetooth headsets.
        try session.setCategory(.playAndRecord, mode: Self.sessionMode, options: [.defaultToSpeaker])
        try session.setActive(true)
        try? session.overrideOutputAudioPort(.speaker)

        let input = engine.inputNode
        // No Apple voice processing: on some iPhones it hands the tap empty buffers.
        // Echo is handled by muting the mic while the phone talks (see process).

        engine.attach(player)
        engine.connect(player, to: engine.mainMixerNode, format: playFormat)

        let inFormat = input.outputFormat(forBus: 0)
        guard inFormat.sampleRate > 0, inFormat.channelCount > 0 else {
            throw NSError(domain: "XiaoA.Interpreter", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "No microphone input available"])
        }
        print("[InterpreterAudio] mic format: \(inFormat)")
        let tapSize = AVAudioFrameCount(max(1024, inFormat.sampleRate / 10))
        // format nil = whatever the mic actually delivers; the converter follows it.
        input.installTap(onBus: 0, bufferSize: tapSize, format: nil) { [weak self] buffer, _ in
            self?.process(buffer)
        }

        engine.prepare()
        try engine.start()
        player.play()
    }

    func stop() {
        player.stop()
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    /// Plays translated speech (24 kHz mono PCM16), louder and evened out. Main thread.
    func play(pcm16 data: Data) {
        guard let buffer = booster.boost(data) else { return }
        lock.lock()
        playback.scheduled(seconds: Double(buffer.frameLength) / playFormat.sampleRate, at: Date())
        lock.unlock()
        player.scheduleBuffer(buffer, completionHandler: nil)
        if !player.isPlaying { player.play() }
    }

    private func process(_ buffer: AVAudioPCMBuffer) {
        guard buffer.frameLength > 0, buffer.format.sampleRate > 0 else { return }
        if converter == nil || converter?.inputFormat != buffer.format {
            converter = AVAudioConverter(from: buffer.format, to: sendFormat)
            print("[InterpreterAudio] converting from \(buffer.format)")
        }
        guard let converter else { return }
        let ratio = sendFormat.sampleRate / buffer.format.sampleRate
        let capacity = AVAudioFrameCount(Double(buffer.frameLength) * ratio) + 32
        guard let out = AVAudioPCMBuffer(pcmFormat: sendFormat, frameCapacity: capacity) else { return }

        var consumed = false
        var error: NSError?
        converter.convert(to: out, error: &error) { _, status in
            if consumed {
                status.pointee = .noDataNow
                return nil
            }
            consumed = true
            status.pointee = .haveData
            return buffer
        }
        guard error == nil, out.frameLength > 0, let samples = out.int16ChannelData?[0] else { return }

        let count = Int(out.frameLength)
        let byteCount = count * 2
        var peak: Int32 = 0
        var sumSquares: Float = 0
        for i in 0..<count {
            let s = Int32(samples[i])
            peak = max(peak, abs(s))
            sumSquares += Float(s) * Float(s)
        }
        let level = (sumSquares / Float(count)).squareRoot()
        let now = Date()
        lock.lock()
        let mute = playback.isMuted(at: now)
        lock.unlock()

        let raw = Data(bytes: samples, count: byteCount)
        let result = gate.feed(raw, level: level, muted: mute, now: now)

        lock.lock()
        if result.open { lastLoudInput = now }
        if !mute {
            statChunks += 1
            if result.open { statOpen += 1 }
            statLoudest = max(statLoudest, level)
        }
        statRoom = gate.roomLevel
        lock.unlock()
        chunksSent += 1
        if peak > 1500 { loudChunks += 1 }
        result.send.forEach { onMicChunk?($0) }
    }
}

/// When the phone is talking and the microphone must send silence. Worked out from the length of
/// the audio queued, never from the player's callbacks, so the mic can't stay muted by mistake.
struct PlaybackClock {
    /// Silence after speech before the mic opens again, so it doesn't catch the speaker's tail.
    static let tail: TimeInterval = 0.6
    /// After the phone's own voice (Apple speech) stops.
    static let externalTail: TimeInterval = 0.5

    private(set) var playUntil = Date.distantPast
    private var muteUntil = Date.distantPast
    private var externalMute = false

    mutating func scheduled(seconds: TimeInterval, at now: Date) {
        playUntil = max(now, playUntil).addingTimeInterval(seconds)
    }

    mutating func setExternalMute(_ muted: Bool, at now: Date) {
        externalMute = muted
        if !muted { muteUntil = now.addingTimeInterval(Self.externalTail) }
    }

    mutating func flush(at now: Date) {
        playUntil = now
    }

    func isMuted(at now: Date) -> Bool {
        externalMute || now < playUntil.addingTimeInterval(Self.tail) || now < muteUntil
    }

    func speechEnd(at now: Date) -> Date {
        externalMute ? now : max(playUntil, muteUntil)
    }
}

/// The room-noise gate. It learns how loud the room is and lets through only sound clearly louder
/// than that (someone talking to the phone); everything else goes out as silence, with the last
/// 0.3 s sent just ahead of speech so first syllables aren't lost. While the phone talks: silence.
struct MicGate {
    /// Never let through sound quieter than this, however quiet the room (RMS, 16-bit, ≈ -44 dBFS).
    static let minSpeechLevel: Float = 200
    /// Someone talking to the phone is at least this much louder than the room (2.2× ≈ 7 dB).
    static let overRoom: Float = 2.2
    /// Keeps the gate open through short pauses between words.
    static let hold: TimeInterval = 0.8
    /// Chunks of lead-in (~0.3 s at 100 ms chunks).
    static let preRollChunks = 3

    /// How loud the room is when nobody is talking to the phone.
    private(set) var roomLevel: Float = 150
    private var openUntil = Date.distantPast
    private var wasOpen = false
    private var preRoll: [Data] = []

    /// One chunk in; what to send (silence, the chunk, or lead-in + the chunk) and whether the gate is open.
    mutating func feed(_ raw: Data, level: Float, muted: Bool, now: Date) -> (send: [Data], open: Bool) {
        if muted {
            preRoll.removeAll()
            wasOpen = false
            return ([Data(count: raw.count)], false)
        }
        // The room level follows quiet moments quickly and loud ones very slowly, so talking
        // doesn't raise it, but a room that gets noisier is learned within ~20 s.
        if level < roomLevel {
            roomLevel = 0.7 * roomLevel + 0.3 * level
        } else {
            roomLevel = min(level, roomLevel * 1.005)
        }
        roomLevel = max(roomLevel, 20)
        if level > max(Self.minSpeechLevel, roomLevel * Self.overRoom) {
            openUntil = now.addingTimeInterval(Self.hold)
        }
        let open = now < openUntil
        var send: [Data] = []
        if open {
            if !wasOpen {
                send.append(contentsOf: preRoll)
                preRoll.removeAll()
            }
            send.append(raw)
        } else {
            send.append(Data(count: raw.count))
        }
        wasOpen = open
        // Lead-in is only audio that went out as silence: nothing already sent is ever sent twice.
        if open {
            preRoll.removeAll()
        } else {
            preRoll.append(raw)
            if preRoll.count > Self.preRollChunks { preRoll.removeFirst() }
        }
        return (send, open)
    }
}
