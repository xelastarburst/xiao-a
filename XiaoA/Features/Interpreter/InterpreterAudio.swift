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

    private let lock = NSLock()
    /// When the speech queued on the player should be finished. Worked out from the audio's
    /// length rather than the player's callbacks, so the mic can never stay muted by mistake.
    private var playUntil = Date.distantPast
    private var muteUntil = Date.distantPast
    private var externalMute = false
    private var lastLoudInput = Date.distantPast
    /// Silence after speech before the mic opens again, so it doesn't catch the speaker's tail.
    private let tail: TimeInterval = 0.6

    // MARK: Room-noise gate (audio thread)

    /// How loud the room is when nobody is talking to the phone (RMS, 16-bit units).
    private var roomLevel: Float = 150
    private var gateOpenUntil = Date.distantPast
    private var gateWasOpen = false
    /// The last ~0.3 s of mic audio, sent just ahead of speech so first syllables aren't lost.
    private var preRoll: [Data] = []
    /// Never let through sound quieter than this, however quiet the room (≈ -44 dBFS).
    static let minSpeechLevel: Float = 200
    /// Someone talking to the phone is at least this much louder than the room (2.2× ≈ 7 dB).
    static let overRoom: Float = 2.2
    /// Keeps the gate open through short pauses between words.
    static let hold: TimeInterval = 0.8

    // For the debug log (guarded by lock).
    private var statChunks = 0
    private var statOpen = 0
    private var statLoudest: Float = 0

    /// True while translated speech is playing (plus a short tail).
    var isPlaying: Bool {
        lock.lock(); defer { lock.unlock() }
        return Date() < playUntil.addingTimeInterval(tail) || Date() < muteUntil
    }

    /// When the phone last finished talking (now, if it still is).
    var speechEnd: Date {
        lock.lock(); defer { lock.unlock() }
        if externalMute { return Date() }
        return max(playUntil, muteUntil)
    }

    /// Stops translated speech that is playing or queued, e.g. when it turns out to be an echo.
    func flush() {
        player.stop()
        lock.lock(); playUntil = Date(); lock.unlock()
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
        let room = Int(roomLevel), loudest = Int(statLoudest)
        let open = statChunks > 0 ? 100 * statOpen / statChunks : 0
        statChunks = 0; statOpen = 0; statLoudest = 0
        lock.unlock()
        let threshold = Int(max(Self.minSpeechLevel, Float(room) * Self.overRoom))
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
        externalMute = muted
        if !muted { muteUntil = Date().addingTimeInterval(0.5) }
        lock.unlock()
    }

    func start() throws {
        let session = AVAudioSession.sharedInstance()
        // Always the iPhone's own loudspeaker and microphone, even with AirPods connected:
        // the person across the table has to hear the translation and be heard.
        // Default mode (not voice chat) plays at full media loudness and never routes to
        // Bluetooth headsets.
        try session.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker])
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
        playUntil = max(Date(), playUntil).addingTimeInterval(Double(buffer.frameLength) / playFormat.sampleRate)
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
        let mute = externalMute || now < playUntil.addingTimeInterval(tail) || now < muteUntil
        lock.unlock()

        var open = false
        if !mute {
            // The room level follows quiet moments quickly and loud ones very slowly, so
            // talking doesn't raise it, but a room that gets noisier is learned within ~20 s.
            if level < roomLevel {
                roomLevel = 0.7 * roomLevel + 0.3 * level
            } else {
                roomLevel = min(level, roomLevel * 1.005)
            }
            roomLevel = max(roomLevel, 20)
            if level > max(Self.minSpeechLevel, roomLevel * Self.overRoom) {
                gateOpenUntil = now.addingTimeInterval(Self.hold)
            }
            open = now < gateOpenUntil
        }

        lock.lock()
        if open { lastLoudInput = now }
        if !mute {
            statChunks += 1
            if open { statOpen += 1 }
            statLoudest = max(statLoudest, level)
        }
        lock.unlock()
        chunksSent += 1
        if peak > 1500 { loudChunks += 1 }

        let raw = Data(bytes: samples, count: byteCount)
        if mute {
            preRoll.removeAll()
            gateWasOpen = false
            onMicChunk?(Data(count: byteCount))
            return
        }
        if open {
            if !gateWasOpen {
                preRoll.forEach { onMicChunk?($0) }
                preRoll.removeAll()
            }
            gateWasOpen = true
            onMicChunk?(raw)
        } else {
            gateWasOpen = false
            onMicChunk?(Data(count: byteCount))
        }
        preRoll.append(raw)
        if preRoll.count > 3 { preRoll.removeFirst() }
    }
}
