import SwiftUI
import AVFoundation

/// Hands-free, turn-by-turn interpreter — the way a human interpreter works:
/// 1. One OpenAI transcription stream hears everyone and notices when each person finishes a
///    sentence. It writes down exactly what was said, in the language it was said in.
/// 2. The language says who spoke: Chinese is Mom; anything else is the other person (any number
///    of other people, English or German).
/// 3. Claude translates the whole sentence, with the recent conversation as context.
/// 4. A natural OpenAI voice says it, one turn at a time. While the phone talks, the mic is muted
///    so it never translates itself.
@MainActor
final class InterpreterEngine: ObservableObject {
    enum Status: Equatable {
        case idle, connecting, listening, speaking
        case failed(String)
    }

    struct Line: Identifiable, Equatable {
        let id = UUID()
        let fromMom: Bool
        var original = ""
        var translated = ""
        var started = Date()
        /// Translation failed; nothing will be said for this line.
        var failed = false
    }

    @Published private(set) var status: Status = .idle
    @Published private(set) var lines: [Line] = []
    @Published var askKeepListening = false
    /// The language of the person Mom is talking to.
    @Published private(set) var partner: PartnerLanguage = .english
    /// What went wrong, in English, shown small on screen so Alex can see it.
    @Published private(set) var problem: String?
    /// Someone is talking right now (drives the moving waveform).
    @Published private(set) var hearing = false

    var visibleLines: [Line] { lines.filter { !($0.original.isEmpty && $0.translated.isEmpty) } }
    var latestFromMom: Line? { visibleLines.last(where: { $0.fromMom }) }
    var latestFromOther: Line? { visibleLines.last(where: { !$0.fromMom }) }
    var isRunning: Bool { status == .listening || status == .speaking || status == .connecting }
    /// Changes when the conversation on screen grows; the view scrolls to the bottom on it.
    var scrollKey: String {
        guard let last = visibleLines.last else { return "" }
        return "\(visibleLines.count)-\(last.original.count)-\(last.translated.count)"
    }

    private var openAIKey = ""
    private var transcriber: TranscribeSocket?
    private let feed = MicFeed()
    /// Tried in order if the server rejects one.
    private let transcriptionModels = ["gpt-4o-transcribe", "gpt-4o-mini-transcribe"]
    private var modelIndex = 0
    private var heardSentence = false
    private var audio: InterpreterAudio?
    private var connected = false

    // Per sentence, from the transcription stream (keyed by its item id).
    private var speechStartMs: [String: Int] = [:]
    private var speechEndMs: [String: Int] = [:]
    private var speechEndedAt: [String: Date] = [:]

    /// Lines waiting to be said, in order. Translations can finish out of order; speech can't.
    private var speakQueue = TurnQueue()
    private var speakingTurn = false
    /// The translated speech of recent lines, for "play again".
    private var spokenAudio: [UUID: [Data]] = [:]
    private var spokenOrder: [UUID] = []
    private var timing: [UUID: Timing] = [:]
    private var lastActivity = Date()
    private var ticker: Timer?
    private var demoTask: Task<Void, Never>?
    private var startedAt = Date()
    private var lastLevelLog = Date()

    private struct Timing {
        var speechEnded: Date?
        var transcribed = Date()
        var translated: Date?
        var firstSound: Date?
    }

    /// Ask "keep listening?" after this much silence. Never stops on its own.
    private let silencePrompt: TimeInterval = 10 * 60

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
        guard APIKeys.get(.anthropic) != nil else {
            status = .failed("还没有设置 Claude 密钥。请让 Alex 在设置里填写。")
            return
        }
        openAIKey = key
        status = .connecting
        lines.removeAll()
        problem = nil
        connected = false
        heardSentence = false
        modelIndex = 0
        speakQueue.removeAll()
        speakingTurn = false
        timing.removeAll()
        startedAt = Date()
        lastLevelLog = Date()
        print("[XA] ===== conversation started (turn by turn): Chinese <-> \(partner.rawValue), "
              + "voices: Mom \(InterpreterVoice.forMom), others \(InterpreterVoice.forOthers) =====")
        Task {
            guard await AVAudioApplication.requestRecordPermission() else {
                status = .failed("需要打开麦克风权限。请让 Alex 在 iPhone 设置 › 小A 里打开。")
                return
            }
            guard status == .connecting else { return }
            connectTranscriber()

            let audio = InterpreterAudio()
            let feed = self.feed
            audio.onMicChunk = { chunk in feed.send(chunk) }
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

    private func connectTranscriber() {
        transcriber?.close()
        let model = transcriptionModels[modelIndex]
        let socket = TranscribeSocket(apiKey: openAIKey, model: model, prompt: transcriptionPrompt)
        socket.onEvent = { [weak self] event in self?.handle(event) }
        transcriber = socket
        feed.socket = socket
        socket.connect()
        print("[XA] \(stamp(Date())) transcribing with \(model)")
    }

    private var transcriptionPrompt: String {
        "A face-to-face conversation between an elderly woman who speaks Mandarin Chinese and people "
            + "who speak \(partnerName). Transcribe exactly what is said, in the language it is spoken. "
            + "Write Chinese in simplified characters."
    }

    private var partnerName: String { partner == .german ? "German" : "English" }

    func stop() {
        if audio != nil { print("[XA] ===== conversation ended at \(stamp(Date())) =====") }
        demoTask?.cancel()
        demoTask = nil
        ticker?.invalidate()
        ticker = nil
        audio?.stop()
        audio = nil
        feed.socket = nil
        transcriber?.close()
        transcriber = nil
        Speaker.shared.onSpeakingChange = nil
        AudioCoordinator.interpreterActive = false
        UIApplication.shared.isIdleTimerDisabled = false
        speakQueue.removeAll()
        speakingTurn = false
        spokenAudio.removeAll()
        spokenOrder.removeAll()
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
        lines.append(Line(fromMom: true, original: chinese, translated: phrase))
        lastActivity = Date()
    }

    // MARK: - Hearing

    private func handle(_ event: TranscribeSocket.Event) {
        guard isRunning else { return }
        switch event {
        case .ready:
            if !connected { print("[XA] \(stamp(Date())) transcription ready") }
            connected = true
        case .speechStarted(let item, let ms):
            speechStartMs[item] = ms
            hearing = true
            lastActivity = Date()
        case .speechStopped(let item, let ms):
            speechEndMs[item] = ms
            speechEndedAt[item] = Date()
            hearing = false
        case .partial:
            break
        case .sentence(let item, let text):
            heardSentence = true
            took(text, item: item)
        case .closed:
            print("[XA] \(stamp(Date())) transcription closed")
        case .failed(let message):
            stop()
            status = .failed("网络不好，翻译官停下来了。请再试一次。\n(\(message))")
        case .serverError(let message):
            print("[XA] \(stamp(Date())) SERVER ERROR (transcription): \(message)")
            problem = message
            switch Self.reaction(to: message, heardSentence: heardSentence,
                                 modelIndex: modelIndex, modelCount: transcriptionModels.count) {
            case .stopBadKey:
                stop()
                status = .failed("OpenAI 密钥不对。请让 Alex 在设置里检查。")
            case .switchModel:
                modelIndex += 1
                connectTranscriber()
            case .carryOn:
                break
            }
        }
    }

    /// A finished sentence: keep it, work out who said it, translate it.
    private func took(_ raw: String, item: String) {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let ms = (speechEndMs[item] ?? 0) - (speechStartMs[item] ?? 0)
        guard Self.isRealSpeech(text, milliseconds: ms) else {
            if !text.isEmpty { print("[XA] \(stamp(Date())) ignored (noise): \"\(text)\" \(ms)ms") }
            return
        }
        let line = Line(fromMom: Self.hasChinese(text), original: text)
        lines.append(line)
        if lines.count > 80 { lines.removeFirst(lines.count - 80) }
        timing[line.id] = Timing(speechEnded: speechEndedAt[item])
        speakQueue.add(line.id)
        lastActivity = Date()
        Task { await translate(line.id) }
    }

    enum ServerErrorReaction: Equatable { case stopBadKey, switchModel, carryOn }

    /// A wrong key stops; a model the account can't use is swapped for the backup, but only before
    /// the first sentence (after that the model clearly works); anything else is shown and ignored.
    static func reaction(to message: String, heardSentence: Bool, modelIndex: Int, modelCount: Int) -> ServerErrorReaction {
        let lower = message.lowercased()
        if lower.contains("api key") || lower.contains("auth") { return .stopBadKey }
        if !heardSentence, lower.contains("model"), modelIndex + 1 < modelCount { return .switchModel }
        return .carryOn
    }

    static func hasChinese(_ text: String) -> Bool {
        text.unicodeScalars.contains { (0x4E00...0x9FFF).contains($0.value) || (0x3400...0x4DBF).contains($0.value) }
    }

    /// Speech recognisers invent words in noise ("Thank you for watching"). Drop the usual ones
    /// and anything too short to be a real sentence.
    static func isRealSpeech(_ text: String, milliseconds: Int) -> Bool {
        guard text.contains(where: { $0.isLetter }) else { return false }
        if milliseconds > 0 && milliseconds < 300 { return false }
        let junk = ["thanks for watching", "thank you for watching", "字幕", "订阅", "点赞", "amara.org",
                    "请不吝", "谢谢观看", "明镜"]
        let lower = text.lowercased()
        return !junk.contains(where: { lower.contains($0) })
    }

    // MARK: - Translating

    private func translate(_ id: UUID) async {
        guard let i = lines.firstIndex(where: { $0.id == id }) else { return }
        let message = Self.translationMessage(for: lines[i], earlier: Array(lines[..<i]), partnerName: partnerName)
        do {
            let client = try ClaudeClient()
            let reply = try await client.complete(model: ClaudeClient.Model.vision, system: translatorPrompt,
                                                  messages: [["role": "user", "content": message]], maxTokens: 500)
            let clean = Self.cleanTranslation(reply)
            guard let j = lines.firstIndex(where: { $0.id == id }) else { return }
            if clean.isEmpty { lines[j].failed = true } else { lines[j].translated = clean }
            timing[id]?.translated = Date()
        } catch {
            print("[XA] \(stamp(Date())) translation failed: \(error)")
            problem = "Claude: \(error.localizedDescription)"
            if let j = lines.firstIndex(where: { $0.id == id }) { lines[j].failed = true }
        }
        speakNext()
    }

    /// What Claude is asked: the last 8 translated lines as context, then the new line and which
    /// way to translate it. Mom's lines go into the other person's language, never back into hers.
    static func translationMessage(for line: Line, earlier: [Line], partnerName: String) -> String {
        let history = earlier.filter { !$0.translated.isEmpty }.suffix(8)
            .map { "\($0.fromMom ? "Mom" : "Other") said: \($0.original) → \($0.translated)" }
            .joined(separator: "\n")
        let target = targetLanguage(fromMom: line.fromMom, partnerName: partnerName)
        let who = line.fromMom ? "Mom (in Chinese)" : "the other person"
        return (history.isEmpty ? "" : "Conversation so far:\n\(history)\n\n")
            + "New line from \(who):\n\(line.original)\n\nTranslate the new line into \(target)."
    }

    static func targetLanguage(fromMom: Bool, partnerName: String) -> String {
        fromMom ? partnerName : "Simplified Chinese (as used in mainland China)"
    }

    /// Claude's reply without surrounding spaces or quotes.
    static func cleanTranslation(_ reply: String) -> String {
        reply.trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "\"“”「」"))
    }

    private var translatorPrompt: String {
        """
        You are a professional live interpreter. You help an elderly woman from mainland China \
        ("Mom", she speaks Mandarin) talk with people who speak \(partnerName). Each message gives \
        the recent conversation and one new line, written down by speech recognition.

        Translate the new line faithfully and completely, as natural spoken language in the same \
        person and tone: what an excellent human interpreter would say out loud. Use the conversation \
        to get names, references and ambiguous words right. If speech recognition clearly misheard a \
        word, translate the most likely intended meaning. Keep names, numbers, prices, times and \
        addresses exactly. Output only the translation: no quotes, notes or explanations.
        """
    }

    // MARK: - Speaking, one turn at a time

    private func speakNext() {
        guard isRunning, !speakingTurn else { return }
        let lines = self.lines
        guard let id = speakQueue.next(state: { id in
            guard let line = lines.first(where: { $0.id == id }) else { return .gone }
            if line.failed { return .failed }
            return line.translated.isEmpty ? .translating : .ready
        }), let line = lines.first(where: { $0.id == id }) else { return }
        speakingTurn = true
        Task {
            await speakAloud(line)
            speakingTurn = false
            report(line.id)
            speakNext()
        }
    }

    private func speakAloud(_ line: Line) async {
        // Mom's words are said in the other person's language; theirs in Chinese.
        let chinese = !line.fromMom
        let voice = line.fromMom ? InterpreterVoice.forMom : InterpreterVoice.forOthers
        do {
            try await OpenAISpeech.speak(line.translated, apiKey: openAIKey, voice: voice, chinese: chinese) { [weak self] chunk in
                await self?.play(chunk, for: line.id)
            }
        } catch {
            print("[XA] \(stamp(Date())) voice failed, using the phone's own: \(error.localizedDescription)")
            guard isRunning else { return }
            Speaker.shared.speak(line.translated, language: chinese ? "zh-CN" : partner.voice)
            timing[line.id]?.firstSound = Date()
            // Let the phone's voice finish before the next turn, so two voices never overlap.
            try? await Task.sleep(nanoseconds: 300_000_000)
            var waited = 0
            while isRunning && Speaker.shared.isSpeaking && waited < 150 {
                try? await Task.sleep(nanoseconds: 200_000_000)
                waited += 1
            }
        }
    }

    private func play(_ chunk: Data, for id: UUID) {
        guard isRunning, let audio else { return }
        audio.play(pcm16: chunk)
        if timing[id]?.firstSound == nil { timing[id]?.firstSound = Date() }
        if spokenAudio[id] == nil {
            spokenOrder.append(id)
            if spokenOrder.count > 12 { spokenAudio[spokenOrder.removeFirst()] = nil }
        }
        spokenAudio[id, default: []].append(chunk)
    }

    // MARK: - Debug log (Xcode console)

    private func stamp(_ date: Date) -> String {
        String(format: "%6.1fs", date.timeIntervalSince(startedAt))
    }

    /// One summary per line: who spoke, what they said, the translation, and where the time went.
    private func report(_ id: UUID) {
        guard let line = lines.first(where: { $0.id == id }), let t = timing[id] else { return }
        func gap(_ a: Date?, _ b: Date?) -> String {
            guard let a, let b else { return "?" }
            return String(format: "%.1fs", b.timeIntervalSince(a))
        }
        print("[XA] \(stamp(line.started)) \(line.fromMom ? "Mom" : "Other"): \"\(line.original.prefix(80))\"")
        print("[XA]          -> \"\(line.translated.prefix(80))\"  [pause->text \(gap(t.speechEnded, t.transcribed)), "
              + "text->translation \(gap(t.transcribed, t.translated)), translation->voice \(gap(t.translated, t.firstSound))]")
    }

    // MARK: - Every quarter second

    private func tick() {
        guard let audio else { return }
        let speaking = audio.isPlaying || Speaker.shared.isSpeaking
        if status == .listening && speaking { status = .speaking }
        else if status == .speaking && !speaking { status = .listening }

        if !connected && problem == nil && Date().timeIntervalSince(startedAt) > 15 {
            problem = "No reply from OpenAI after 15 seconds. Check the key, billing and internet."
        }
        if !askKeepListening && Date().timeIntervalSince(lastActivity) > silencePrompt {
            askKeepListening = true
        }
        if Date().timeIntervalSince(lastLevelLog) >= 15 {
            lastLevelLog = Date()
            print("[XA] \(stamp(Date())) mic: \(audio.levelReport())")
        }
    }

    // MARK: - Simulator demo

    /// A short scripted conversation, typed out the way live captions arrive.
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
                let line = Line(fromMom: exchange.fromMom)
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
}

/// Hands microphone audio from the audio thread to whichever transcription socket is current.
final class MicFeed: @unchecked Sendable {
    private let lock = NSLock()
    private var _socket: TranscribeSocket?
    var socket: TranscribeSocket? {
        get { lock.lock(); defer { lock.unlock() }; return _socket }
        set { lock.lock(); _socket = newValue; lock.unlock() }
    }
    func send(_ chunk: Data) { socket?.append(pcm16: chunk) }
}

/// Lines waiting to be spoken, in the order they were said. Translations can finish out of order;
/// speech can't. A failed line, or one that scrolled away, is skipped; every other line is spoken once.
struct TurnQueue {
    enum LineState { case ready, translating, failed, gone }

    private(set) var waiting: [UUID] = []

    mutating func add(_ id: UUID) { waiting.append(id) }
    mutating func removeAll() { waiting.removeAll() }

    /// The next line to say, if the oldest one waiting is translated. Nil while it still translates.
    mutating func next(state: (UUID) -> LineState) -> UUID? {
        while let id = waiting.first {
            switch state(id) {
            case .failed, .gone:
                waiting.removeFirst()
            case .translating:
                return nil
            case .ready:
                waiting.removeFirst()
                return id
            }
        }
        return nil
    }
}
