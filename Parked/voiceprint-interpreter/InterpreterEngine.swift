import SwiftUI
import AVFoundation

/// Hands-free two-way interpreter for Mom and one or more other people.
///
/// The phone knows Mom's voice (a voiceprint she records once). Each stretch of speech is
/// checked on the phone, then sent to exactly one OpenAI translation session:
/// - Mom's speech → the session that speaks the other person's language (English or German),
/// - everyone else's → the session that speaks Chinese.
/// So no session ever hears its own output language, nobody hears their own words repeated, and
/// any number of other people can join. Translations play once nobody is talking, so no one is
/// cut off mid-sentence; while the phone talks, the mic is muted so it never translates itself.
@MainActor
final class InterpreterEngine: ObservableObject {
    enum Status: Equatable {
        case idle, connecting, listening, speaking
        case failed(String)
    }

    enum Direction: Hashable { case toPartner, toChinese }

    struct Line: Identifiable, Equatable {
        let id = UUID()
        let fromMom: Bool
        /// For other people: 1, 2, 3… in the order they first spoke.
        var person = 0
        var original = ""
        var translated = ""
        var started = Date()
        var lastUpdate = Date()
        // For the debug log (Xcode console).
        var firstSound: Date?
        var soundSeconds: Double = 0
    }

    @Published private(set) var status: Status = .idle
    @Published private(set) var lines: [Line] = []
    @Published var askKeepListening = false
    /// The language of the person Mom is talking to.
    @Published private(set) var partner: PartnerLanguage = .english
    /// What went wrong on OpenAI's side, in English, shown small on screen so Alex can see it.
    @Published private(set) var problem: String?
    /// Someone is talking right now (drives the moving waveform).
    @Published private(set) var hearing = false
    /// How many different other people have spoken.
    @Published private(set) var otherPeople = 0

    var visibleLines: [Line] { lines.filter { !($0.original.isEmpty && $0.translated.isEmpty) } }
    var latestFromMom: Line? { visibleLines.last(where: { $0.fromMom }) }
    var latestFromOther: Line? { visibleLines.last(where: { !$0.fromMom }) }
    var isRunning: Bool { status == .listening || status == .speaking || status == .connecting }
    /// Changes when the conversation on screen grows; the view scrolls to the bottom on it.
    var scrollKey: String {
        guard let last = visibleLines.last else { return "" }
        return "\(visibleLines.count)-\(last.original.count)-\(last.translated.count)"
    }

    /// "对方说", or "对方1说 / 对方2说" once more than one other person has spoken.
    func label(for line: Line) -> String {
        otherPeople > 1 && line.person > 0 ? "对方\(line.person)说" : "对方说"
    }

    private var sockets: [Direction: TranslateSocket] = [:]
    private var audio: InterpreterAudio?
    private var router: SpeakerRouter?
    private var micFeed: AsyncStream<(Data, [Float])>.Continuation?
    private var routerTask: Task<Void, Never>?
    /// The line each session's output belongs to.
    private var current: [Direction: UUID] = [:]
    private var lastPerson = 0
    /// Someone is talking: translations wait (in `waiting`) so nobody is cut off.
    private var someoneSpeaking = false
    private var waiting: [(line: UUID, audio: Data, since: Date)] = []
    /// The translated speech of recent lines, for "play again".
    private var spokenAudio: [UUID: [Data]] = [:]
    private var spokenOrder: [UUID] = []
    private var lastActivity = Date()
    /// The translation service streams audio all the time, silence included. Only speech counts:
    /// this is when each session last sent audible speech.
    private var lastSpeechOut: [Direction: Date] = [:]
    private var outputDeltas = 0
    private var reported: Set<UUID> = []
    private var ticker: Timer?
    private var demoTask: Task<Void, Never>?
    private var startedAt = Date()
    private var connected: Set<Direction> = []

    /// A pause this long in one person's speech still continues the same line.
    private let lineGap: TimeInterval = 3
    /// Translations never wait longer than this for a pause (e.g. a TV talking in the room).
    private let maxWait: TimeInterval = 6
    /// Ask "keep listening?" after this much silence. Never stops on its own.
    private let silencePrompt: TimeInterval = 10 * 60
    /// Output audio quieter than this (out of 32768) is treated as silence.
    private static let speechPeak = 500

    func start(partner: PartnerLanguage) {
        guard !isRunning else { return }
        self.partner = partner
        if Demo.isOn && APIKeys.get(.openAI) == nil {
            playDemoConversation()
            return
        }
        guard let key = APIKeys.get(.openAI) else {
            status = .failed("还没有设置 OpenAI 密钥。请让 Alex 在设置里填写。")
            return
        }
        let momPrints = MomVoiceprint.prints
        guard !momPrints.isEmpty else {
            status = .failed("小A 还不认识你的声音。请先录一下你的声音。")
            return
        }
        status = .connecting
        lines.removeAll()
        problem = nil
        connected.removeAll()
        outputDeltas = 0
        reported.removeAll()
        otherPeople = 0
        lastPerson = 0
        startedAt = Date()
        print("[XA] ===== conversation started: Chinese <-> \(partner.rawValue) =====")
        Task {
            guard await AVAudioApplication.requestRecordPermission() else {
                status = .failed("需要打开麦克风权限。请让 Alex 在 iPhone 设置 › 小A 里打开。")
                return
            }
            do {
                try await VoiceID.shared.prepare()
            } catch {
                print("[XA] voice models failed: \(error)")
                status = .failed("第一次用要下载声音识别（约 35MB）。请连上网络，再试一次。")
                return
            }
            guard status == .connecting else { return }   // ended while preparing

            let toPartner = TranslateSocket(apiKey: key, targetLanguage: partner.translationCode)
            let toChinese = TranslateSocket(apiKey: key, targetLanguage: "zh")
            toPartner.onEvent = { [weak self] event in self?.handle(event, from: .toPartner) }
            toChinese.onEvent = { [weak self] event in self?.handle(event, from: .toChinese) }
            sockets = [.toPartner: toPartner, .toChinese: toChinese]
            toPartner.connect()
            toChinese.connect()

            let router = SpeakerRouter(
                voice: VoiceID.shared,
                momPrints: momPrints,
                send: { forPartner, forChinese in
                    toPartner.append(pcm16: forPartner)
                    toChinese.append(pcm16: forChinese)
                },
                onEvent: { [weak self] event in
                    Task { @MainActor in self?.handle(event) }
                }
            )
            self.router = router
            let (feed, continuation) = AsyncStream<(Data, [Float])>.makeStream()
            micFeed = continuation
            routerTask = Task.detached {
                for await (pcm24, pcm16) in feed {
                    await router.ingest(pcm24: pcm24, pcm16: pcm16)
                }
            }

            let audio = InterpreterAudio()
            audio.onMicChunk = { pcm24, pcm16 in continuation.yield((pcm24, pcm16)) }
            do {
                AudioCoordinator.interpreterActive = true
                try audio.start()
            } catch {
                AudioCoordinator.interpreterActive = false
                stop()
                status = .failed("麦克风打不开，请再试一次。")
                return
            }
            self.audio = audio
            Speaker.shared.onSpeakingChange = { [weak audio] speaking in audio?.setExternalMute(speaking) }
            lastActivity = Date()
            status = .listening
            UIApplication.shared.isIdleTimerDisabled = true
            ticker = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
                Task { @MainActor in self?.tick() }
            }
        }
    }

    func stop() {
        if audio != nil {
            reportFinishedLines(force: true)
            print("[XA] ===== conversation ended at \(stamp(Date())) =====")
        }
        demoTask?.cancel()
        demoTask = nil
        ticker?.invalidate()
        ticker = nil
        audio?.stop()
        audio = nil
        micFeed?.finish()
        micFeed = nil
        routerTask?.cancel()
        routerTask = nil
        router = nil
        sockets.values.forEach { $0.close() }
        sockets.removeAll()
        Speaker.shared.onSpeakingChange = nil
        AudioCoordinator.interpreterActive = false
        UIApplication.shared.isIdleTimerDisabled = false
        waiting.removeAll()
        spokenAudio.removeAll()
        spokenOrder.removeAll()
        current.removeAll()
        lastSpeechOut.removeAll()
        someoneSpeaking = false
        hearing = false
        if isRunning { status = .idle }
    }

    func keepListening() {
        lastActivity = Date()
        askKeepListening = false
    }

    /// Says a line's translation again: the translated voice itself when we have it,
    /// otherwise the phone's own voice in the right language.
    func replay(_ line: Line) {
        guard !line.translated.isEmpty else { return }
        print("[XA] \(stamp(Date())) replay tapped: \(line.translated.prefix(50))")
        if let chunks = spokenAudio[line.id], !chunks.isEmpty, let audio {
            chunks.forEach { audio.play(pcm16: $0) }
        } else {
            Speaker.shared.speak(line.translated, language: line.fromMom ? partner.voice : "zh-CN")
        }
        lastActivity = Date()
    }

    /// Plays a ready-made phrase in the other person's language, and logs it as Mom's line.
    func say(_ phrase: String, chinese: String) {
        print("[XA] \(stamp(Date())) phrase button: \(phrase)")
        Speaker.shared.speak(phrase, language: partner.voice)
        let line = Line(fromMom: true, original: chinese, translated: phrase)
        lines.append(line)
        reported.insert(line.id)
        lastActivity = Date()
    }

    /// Simulator demo: a short scripted conversation, typed out the way live captions arrive.
    private func playDemoConversation() {
        status = .connecting
        lines.removeAll()
        demoTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 900_000_000)
            guard let self, !Task.isCancelled else { return }
            self.status = .listening
            for exchange in Demo.conversation(with: self.partner) {
                try? await Task.sleep(nanoseconds: UInt64(exchange.pause * 1_000_000_000))
                if Task.isCancelled { return }
                let line = Line(fromMom: exchange.fromMom, person: exchange.fromMom ? 0 : 1)
                self.lines.append(line)
                let id = line.id
                for word in exchange.original.split(separator: " ", omittingEmptySubsequences: false) {
                    try? await Task.sleep(nanoseconds: 140_000_000)
                    if Task.isCancelled { return }
                    if let i = self.lines.firstIndex(where: { $0.id == id }) {
                        self.lines[i].original += (self.lines[i].original.isEmpty ? "" : " ") + word
                    }
                }
                self.status = .speaking
                try? await Task.sleep(nanoseconds: 500_000_000)
                if let i = self.lines.firstIndex(where: { $0.id == id }) {
                    self.lines[i].translated = exchange.translated
                }
                // Spoken out loud like the real thing (quiet unless "Sound in the simulator" is on).
                Speaker.shared.speak(exchange.translated, language: exchange.fromMom ? self.partner.voice : "zh-CN")
                try? await Task.sleep(nanoseconds: 400_000_000)
                var waited = 0
                while Speaker.shared.isSpeaking && waited < 40 && !Task.isCancelled {
                    try? await Task.sleep(nanoseconds: 200_000_000)
                    waited += 1
                }
                try? await Task.sleep(nanoseconds: 500_000_000)
                if Task.isCancelled { return }
                self.status = .listening
                self.lastActivity = Date()
            }
        }
    }

    // MARK: - Who is talking (from the router)

    private func handle(_ event: SpeakerRouter.Event) {
        guard isRunning else { return }
        switch event {
        case .speaking(let on):
            someoneSpeaking = on
            hearing = on
            if on { lastActivity = Date() } else { playWaiting() }
        case .utterance(_, let speaker):
            startLine(for: speaker)
        case .decided(let id, let speaker, let distance, let seconds, let note):
            let who: String
            switch speaker {
            case .mom: who = "Mom"
            case .other(let n): who = "other \(n)"
            case nil: who = "dropped"
            }
            print(String(format: "[XA] %@ speech #%d: %.1fs -> %@ (voice distance %.2f) %@",
                         stamp(Date()), id, seconds, who, distance, note))
        }
    }

    /// A new stretch of speech is on its way to a session: continue that person's line if they
    /// were just talking, otherwise start a new one.
    private func startLine(for speaker: SpeakerRouter.Speaker) {
        let direction: Direction = speaker == .mom ? .toPartner : .toChinese
        var person = 0
        if case .other(let n) = speaker {
            person = n
            lastPerson = n
            otherPeople = max(otherPeople, n)
        }
        if let id = current[direction], let i = lines.firstIndex(where: { $0.id == id }),
           lines[i].person == person, Date().timeIntervalSince(lines[i].lastUpdate) < lineGap {
            lines[i].lastUpdate = Date()
            return
        }
        lines.append(Line(fromMom: speaker == .mom, person: person))
        if lines.count > 80 { lines.removeFirst(lines.count - 80) }
        current[direction] = lines[lines.count - 1].id
    }

    /// The line a session's text or speech belongs to.
    private func lineIndex(for direction: Direction) -> Int {
        if let id = current[direction], let i = lines.firstIndex(where: { $0.id == id }) {
            return i
        }
        lines.append(Line(fromMom: direction == .toPartner, person: direction == .toChinese ? lastPerson : 0))
        current[direction] = lines[lines.count - 1].id
        return lines.count - 1
    }

    // MARK: - Translation sessions

    private func handle(_ event: TranslateSocket.Event, from direction: Direction) {
        guard isRunning else { return }
        switch event {
        case .ready:
            if !connected.contains(direction) {
                print("[XA] \(stamp(Date())) \(direction) session ready")
            }
            connected.insert(direction)
        case .closed:
            print("[XA] \(stamp(Date())) \(direction) session closed")
        case .inputText(let text):
            lastActivity = Date()
            let i = lineIndex(for: direction)
            lines[i].original += text
            lines[i].lastUpdate = Date()
        case .outputText(let text):
            let i = lineIndex(for: direction)
            lines[i].translated += text
            lines[i].lastUpdate = Date()
        case .outputAudio(let data):
            outputDeltas += 1
            if outputDeltas == 1 { print("[XA] translated audio arrives in \(data.count)-byte pieces") }
            // Silence isn't played (playing it would keep the mic muted). Short quiet gaps inside
            // speech still play, so words don't run together.
            if InterpreterAudio.peak(of: data) >= Self.speechPeak {
                lastSpeechOut[direction] = Date()
            } else if Date().timeIntervalSince(lastSpeechOut[direction] ?? .distantPast) > 0.8 {
                return
            }
            let i = lineIndex(for: direction)
            lines[i].lastUpdate = Date()
            keep(data, for: lines[i].id)
            if someoneSpeaking || !waiting.isEmpty {
                waiting.append((lines[i].id, data, Date()))
            } else {
                play(data, line: i)
            }
        case .failed(let message):
            stop()
            status = .failed("网络不好，翻译官停下来了。请再试一次。\n(\(message))")
        case .serverError(let message):
            // Logged for Alex; a rejected setting shouldn't end the conversation.
            print("[XA] \(stamp(Date())) SERVER ERROR from \(direction): \(message)")
            problem = message
            if message.localizedCaseInsensitiveContains("api key") || message.localizedCaseInsensitiveContains("auth") {
                stop()
                status = .failed("OpenAI 密钥不对。请让 Alex 在设置里检查。")
            }
        }
    }

    private func keep(_ data: Data, for id: UUID) {
        if spokenAudio[id] == nil {
            spokenOrder.append(id)
            if spokenOrder.count > 12 { spokenAudio[spokenOrder.removeFirst()] = nil }
        }
        spokenAudio[id, default: []].append(data)
    }

    private func play(_ data: Data, line i: Int) {
        audio?.play(pcm16: data)
        if lines[i].firstSound == nil { lines[i].firstSound = Date() }
        lines[i].soundSeconds += Double(data.count / 2) / 24_000
    }

    /// Nobody is talking any more: say what was waiting, in order.
    private func playWaiting() {
        let queued = waiting
        waiting.removeAll()
        for item in queued {
            if let i = lines.firstIndex(where: { $0.id == item.line }) {
                play(item.audio, line: i)
            } else {
                audio?.play(pcm16: item.audio)
            }
        }
    }

    // MARK: - Debug log

    /// Seconds since the conversation started, so log lines can be lined up.
    private func stamp(_ date: Date) -> String {
        String(format: "%6.1fs", date.timeIntervalSince(startedAt))
    }

    /// One summary per finished line: who spoke, what they said, what was said for them.
    private func reportFinishedLines(force: Bool = false) {
        let now = Date()
        for line in lines where !reported.contains(line.id) {
            guard force || now.timeIntervalSince(line.lastUpdate) > 4 else { continue }
            reported.insert(line.id)
            if line.original.isEmpty && line.translated.isEmpty && line.soundSeconds == 0 { continue }
            let who = line.fromMom ? "Mom -> \(partner.rawValue)" : "other \(line.person) -> zh"
            let sound = line.firstSound.map {
                String(format: "sound %.1fs after the line began, %.1fs long", $0.timeIntervalSince(line.started), line.soundSeconds)
            } ?? "NO SOUND"
            print("[XA] \(stamp(line.started)) \(who): \"\(line.original.prefix(80))\"")
            print("[XA]          -> \"\(line.translated.prefix(80))\"  [\(sound)]")
        }
    }

    // MARK: - Every quarter second

    private func tick() {
        guard let audio else { return }
        let speaking = audio.isPlaying || Speaker.shared.isSpeaking
        if status == .listening && speaking { status = .speaking }
        else if status == .speaking && !speaking { status = .listening }

        if let oldest = waiting.first, Date().timeIntervalSince(oldest.since) > maxWait {
            print("[XA] \(stamp(Date())) played without waiting for a pause (someone kept talking)")
            playWaiting()
        }

        reportFinishedLines()

        if connected.isEmpty && problem == nil && Date().timeIntervalSince(startedAt) > 15 {
            problem = "No reply from OpenAI after 15 seconds. Check the key, billing and internet."
        }

        if !askKeepListening && Date().timeIntervalSince(lastActivity) > silencePrompt {
            askKeepListening = true
        }
    }
}
