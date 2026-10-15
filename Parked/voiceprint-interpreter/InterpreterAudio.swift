import AVFoundation

/// Microphone in and translated speech out, with echo protection: while the phone is talking,
/// the microphone sends silence so it never translates itself.
final class InterpreterAudio {
    /// Called on an audio thread with the same ~100 ms of audio twice: 24 kHz mono PCM16 for
    /// OpenAI, and 16 kHz mono float for the on-phone voice checks.
    var onMicChunk: ((Data, [Float]) -> Void)?

    private let engine = AVAudioEngine()
    private let player = AVAudioPlayerNode()
    private let playFormat = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 24_000, channels: 1, interleaved: false)!
    private let sendFormat = AVAudioFormat(commonFormat: .pcmFormatInt16, sampleRate: 24_000, channels: 1, interleaved: true)!
    private var converter: AVAudioConverter?
    private let voiceFormat = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 16_000, channels: 1, interleaved: false)!
    private var voiceConverter: AVAudioConverter?
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
        try session.setCategory(.playAndRecord, mode: .voiceChat, options: [.defaultToSpeaker])
        try session.setActive(true)

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

    func play(pcm16 data: Data) {
        let frames = data.count / 2
        guard frames > 0,
              let buffer = AVAudioPCMBuffer(pcmFormat: playFormat, frameCapacity: AVAudioFrameCount(frames)),
              let channel = buffer.floatChannelData?[0] else { return }
        buffer.frameLength = AVAudioFrameCount(frames)
        data.withUnsafeBytes { raw in
            for i in 0..<frames {
                channel[i] = Float(raw.loadUnaligned(fromByteOffset: i * 2, as: Int16.self)) / 32768
            }
        }
        lock.lock()
        playUntil = max(Date(), playUntil).addingTimeInterval(Double(frames) / playFormat.sampleRate)
        lock.unlock()
        player.scheduleBuffer(buffer, completionHandler: nil)
        if !player.isPlaying { player.play() }
    }

    private func process(_ buffer: AVAudioPCMBuffer) {
        guard buffer.frameLength > 0, buffer.format.sampleRate > 0 else { return }
        if converter == nil || converter?.inputFormat != buffer.format {
            converter = AVAudioConverter(from: buffer.format, to: sendFormat)
            voiceConverter = AVAudioConverter(from: buffer.format, to: voiceFormat)
            print("[InterpreterAudio] converting from \(buffer.format)")
        }
        guard let converter, let voiceConverter,
              let out = Self.convert(buffer, with: converter, to: sendFormat),
              let samples = out.int16ChannelData?[0],
              let voiceOut = Self.convert(buffer, with: voiceConverter, to: voiceFormat),
              let voiceSamples = voiceOut.floatChannelData?[0] else { return }

        let byteCount = Int(out.frameLength) * 2
        var peak: Int32 = 0
        for i in 0..<Int(out.frameLength) { peak = max(peak, abs(Int32(samples[i]))) }
        let now = Date()
        lock.lock()
        let mute = externalMute || now < playUntil.addingTimeInterval(tail) || now < muteUntil
        if peak > 1500 && !mute { lastLoudInput = now }
        lock.unlock()
        chunksSent += 1
        if peak > 1500 { loudChunks += 1 }
        let data = mute ? Data(count: byteCount) : Data(bytes: samples, count: byteCount)
        let voice = mute
            ? [Float](repeating: 0, count: Int(voiceOut.frameLength))
            : Array(UnsafeBufferPointer(start: voiceSamples, count: Int(voiceOut.frameLength)))
        onMicChunk?(data, voice)
    }

    private static func convert(_ buffer: AVAudioPCMBuffer, with converter: AVAudioConverter,
                                to format: AVAudioFormat) -> AVAudioPCMBuffer? {
        let ratio = format.sampleRate / buffer.format.sampleRate
        let capacity = AVAudioFrameCount(Double(buffer.frameLength) * ratio) + 32
        guard let out = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: capacity) else { return nil }
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
        guard error == nil, out.frameLength > 0 else { return nil }
        return out
    }
}
