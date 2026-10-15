import SwiftUI
import AVFoundation

/// Always-on two-way interpreter.
///
/// The same microphone audio goes to two translation sessions: one into the other person's
/// language (English or German, for Mom's Chinese) and one into Chinese (for the other person).
/// Each session also reports what it heard in the source language; we only play a session's
/// output when the speaker was in the language that session is meant to translate, so nobody
/// hears their own words repeated. Speech we can't place is never played, and anything that
/// sounds like the phone's own last sentence coming back through the mic is dropped.
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
        var original = ""
        var translated = ""
        var valid: Bool?
        var started = Date()
        var lastUpdate = Date()
        /// When source speech text last arrived for this line.
        var lastInput = Date.distantPast
        /// The language the speaker used, once the transcript shows it: true = Chinese.
        var sourceChinese: Bool?
        // For the debug log (Xcode console): one summary per line.
        var firstInput: Date?
        var decidedAt: Date?
        var firstSound: Date?
        var soundSeconds: Double = 0
        var skipReason = ""
        var placedWithoutTranscript = false
        /// The phone was talking (so the mic was off) when this line began.
        var startedWhilePhoneTalked = false
    }

    @Published private(set) var status: Status = .idle
    @Published private(set) var lines: [Line] = []
    @Published var askKeepListening = false
    /// The language of the person Mom is talking to.
    @Published private(set) var partner: PartnerLanguage = .english
    /// What went wrong on OpenAI's side, in English, shown small on screen so Alex can see it.
    @Published private(set) var problem: String?
    /// The microphone hears someone talking right now (drives the moving waveform).
    @Published private(set) var hearing = false
    private var connected: Set<Direction> = []
    private var startedAt = Date()

    var visibleLines: [Line] { lines.filter { $0.valid == true && !($0.original.isEmpty && $0.translated.isEmpty) } }
    var latestFromMom: Line? { visibleLines.last(where: { $0.fromMom }) }
    var latestFromOther: Line? { visibleLines.last(where: { !$0.fromMom }) }
    var isRunning: Bool { status == .listening || status == .speaking || status == .connecting }
    /// Changes when the conversation on screen grows; the view scrolls to the bottom on it.
    var scrollKey: String {
        guard let last = visibleLines.last else { return "" }
        return "\(visibleLines.count)-\(last.original.count)-\(last.translated.count)"
    }

    private var sockets: [Direction: TranslateSocket] = [:]
    private var audio: InterpreterAudio?
    private var current: [Direction: UUID] = [:]
    private var heldAudio: [UUID: [Data]] = [:]
    /// The translated speech of recent lines, for "play again".
    private var spokenAudio: [UUID: [Data]] = [:]
    private var spokenOrder: [UUID] = []
    private var lastActivity = Date()
    /// The translation service streams audio all the time, silence included. Only speech counts:
    /// this is when each session last sent audible speech.
    private var lastSpeechOut: [Direction: Date] = [:]
    private var outputDeltas = 0
    /// Lines already summarised in the debug log.
    private var reported: Set<UUID> = []
    /// When either session last transcribed Chinese, i.e. when Mom was last heard speaking.
    private var lastChineseInput = Date.distantPast
    private var ticker: Timer?
    private var demoTask: Task<Void, Never>?

    /// Translated text and speech keep joining the current line for this long. Short, so the
    /// other person's reply doesn't get attached to the line before it.
    private let lineGap: TimeInterval = 1.5
    /// A pause this long in the source speech starts a new line (a new sentence or a new speaker).
    private let inputGap: TimeInterval = 1.8
    /// Short replies ("OK", "好") are placed once the speaker has paused this long.
    private let decidePause: TimeInterval = 0.6
    /// Speech that still can't be placed after this long is dropped, never played blind.
    private let undecidedTimeout: TimeInterval = 8
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
        status = .connecting
        lines.removeAll()
        problem = nil
        connected.removeAll()
        outputDeltas = 0
        reported.removeAll()
        startedAt = Date()
        print("[XA] ===== conversation started: Chinese <-> \(partner.rawValue) =====")
        Task {
            guard await AVAudioApplication.requestRecordPermission() else {
                status = .failed("需要打开麦克风权限。请让 Alex 在 iPhone 设置 › 小A 里打开。")
                return
            }
            let toPartner = TranslateSocket(apiKey: key, targetLanguage: partner.translationCode)
            let toChinese = TranslateSocket(apiKey: key, targetLanguage: "zh")
            toPartner.onEvent = { [weak self] event in self?.handle(event, from: .toPartner) }
            toChinese.onEvent = { [weak self] event in self?.handle(event, from: .toChinese) }
            sockets = [.toPartner: toPartner, .toChinese: toChinese]
            toPartner.connect()
            toChinese.connect()

            let audio = InterpreterAudio()
            audio.onMicChunk = { chunk in
                toPartner.append(pcm16: chunk)
                toChinese.append(pcm16: chunk)
            }
            do {
                AudioCoordinator.interpreterActive = true
                try audio.start()
            } catch {
                AudioCoordinator.interpreterActive = false
                stopSockets()
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
        stopSockets()
        Speaker.shared.onSpeakingChange = nil
        AudioCoordinator.interpreterActive = false
        UIApplication.shared.isIdleTimerDisabled = false
        heldAudio.removeAll()
        spokenAudio.removeAll()
        spokenOrder.removeAll()
        current.removeAll()
        lastSpeechOut.removeAll()
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
        var line = Line(fromMom: true, original: chinese, translated: phrase)
        line.valid = true
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
                var line = Line(fromMom: exchange.fromMom)
                line.valid = true
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

    // MARK: - Events

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
            let i = inputLineIndex(for: direction)
            lines[i].original += text
            lines[i].lastUpdate = Date()
            lines[i].lastInput = Date()
            if lines[i].firstInput == nil { lines[i].firstInput = Date() }
            if !Self.cjk(text).isEmpty { lastChineseInput = Date() }
            evaluate(i, direction, paused: false)
        case .outputText(let text):
            let i = lineIndex(for: direction)
            lines[i].translated += text
            lines[i].lastUpdate = Date()
        case .outputAudio(let data):
            let peak = InterpreterAudio.peak(of: data)
            outputDeltas += 1
            if outputDeltas == 1 { print("[XA] translated audio arrives in \(data.count)-byte pieces") }
            // Silence isn't a line and isn't played (playing it would keep the mic muted).
            // Short quiet gaps inside speech still play, so words don't run together.
            if peak >= Self.speechPeak {
                lastSpeechOut[direction] = Date()
            } else if Date().timeIntervalSince(lastSpeechOut[direction] ?? .distantPast) > 0.8 {
                return
            }
            let i = lineIndex(for: direction)
            lines[i].lastUpdate = Date()
            keep(data, for: lines[i].id)
            switch lines[i].valid {
            case .some(true): play(data, for: i)
            case .some(false): break
            case .none: heldAudio[lines[i].id, default: []].append(data)
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

    /// The line that translated text or speech belongs to.
    private func lineIndex(for direction: Direction) -> Int {
        if let id = current[direction],
           let i = lines.firstIndex(where: { $0.id == id }),
           Date().timeIntervalSince(lines[i].lastUpdate) < lineGap {
            return i
        }
        return newLine(for: direction)
    }

    /// The line that new source speech belongs to: the current one, unless the speech paused.
    /// (Output keeps a line "fresh" for a while, so it can't decide this: the other person often
    /// answers right after the phone finishes talking.)
    private func inputLineIndex(for direction: Direction) -> Int {
        let now = Date()
        if let id = current[direction], let i = lines.firstIndex(where: { $0.id == id }) {
            let line = lines[i]
            let continuing = line.lastInput == .distantPast
                ? now.timeIntervalSince(line.lastUpdate) < lineGap   // its translation came first
                : now.timeIntervalSince(line.lastInput) < inputGap
            if continuing { return i }
        }
        return newLine(for: direction)
    }

    private func newLine(for direction: Direction) -> Int {
        var line = Line(fromMom: direction == .toPartner)
        line.startedWhilePhoneTalked = (audio?.isPlaying ?? false) || Speaker.shared.isSpeaking
        lines.append(line)
        if lines.count > 80 { lines.removeFirst(lines.count - 80) }
        current[direction] = lines[lines.count - 1].id
        return lines.count - 1
    }

    private static func other(_ direction: Direction) -> Direction {
        direction == .toPartner ? .toChinese : .toPartner
    }

    /// Decide, once, whether this line's speaker is the one this session should translate.
    private func evaluate(_ i: Int, _ direction: Direction, paused: Bool) {
        let text = lines[i].original
        if lines[i].sourceChinese == nil {
            let cjk = Self.cjk(text).count
            let words = Self.words(text).count
            if cjk >= 2 || (paused && cjk >= 1) {
                lines[i].sourceChinese = true
            } else if cjk == 0 && (words >= 2 || (paused && text.filter(\.isLetter).count >= 2)) {
                lines[i].sourceChinese = false
            }
        }
        guard let chinese = lines[i].sourceChinese else { return }

        // The phone's own voice coming back through the mic: drop it on both sessions.
        if isEcho(lines[i], chinese: chinese) {
            if lines[i].valid != false {
                print("[XA] \(stamp(Date())) ECHO dropped (\(direction)): \(text.prefix(60))")
                lines[i].skipReason = "echo of the phone"
                setValid(false, at: i)
            }
            if let j = concurrentLine(to: i, in: Self.other(direction)), lines[j].valid != false {
                lines[j].skipReason = "echo of the phone"
                setValid(false, at: j)
            }
            return
        }

        guard lines[i].valid == nil else { return }
        let valid = (direction == .toPartner) == chinese
        if !valid { lines[i].skipReason = "speaker's own language" }
        setValid(valid, at: i)

        // The other session heard the same speech. If its version would be in the speaker's own
        // language (e.g. Mom's Chinese "translated" into Chinese), it must never play.
        let other = Self.other(direction)
        if (other == .toPartner) != chinese, let j = concurrentLine(to: i, in: other), lines[j].valid == nil {
            lines[j].skipReason = "speaker's own language (other session)"
            setValid(false, at: j)
        }
    }

    /// The other session's line for (roughly) the same moment.
    private func concurrentLine(to i: Int, in direction: Direction) -> Int? {
        guard let id = current[direction], let j = lines.firstIndex(where: { $0.id == id }) else { return nil }
        return abs(lines[j].started.timeIntervalSince(lines[i].started)) < 4 ? j : nil
    }

    /// True if this "speech" is really the phone's own recent sentence picked up by the mic.
    /// The mic is muted while the phone talks, so this is a second line of defence.
    private func isEcho(_ line: Line, chinese: Bool) -> Bool {
        guard let audio, line.started <= audio.speechEnd.addingTimeInterval(2) else { return false }
        let recent = Date().addingTimeInterval(-20)
        // The phone says Mom's lines in the other person's language and theirs in Chinese.
        let said = lines.filter {
            $0.id != line.id && $0.valid == true && $0.fromMom != chinese && $0.lastUpdate > recent
        }.map(\.translated)
        guard !said.isEmpty else { return false }
        if chinese {
            let heard = Self.cjk(line.original)
            guard heard.count >= 3 else { return false }
            let ref = Set(said.flatMap { Self.cjk($0) })
            return Double(heard.filter(ref.contains).count) / Double(heard.count) >= 0.7
        } else {
            let heard = Self.words(line.original)
            guard heard.count >= 2 else { return false }
            let ref = Set(said.flatMap { Self.words($0) })
            return Double(heard.filter(ref.contains).count) / Double(heard.count) >= 0.7
        }
    }

    private static func cjk(_ text: String) -> [Character] {
        text.filter { ch in
            ch.unicodeScalars.contains { (0x4E00...0x9FFF).contains($0.value) || (0x3400...0x4DBF).contains($0.value) }
        }.map { $0 }
    }

    /// Lower-case words in Latin letters (English, German), for comparing sentences.
    private static func words(_ text: String) -> [String] {
        text.lowercased()
            .split { !($0.isLetter || $0.isNumber) || cjk(String($0)).count > 0 }
            .map(String.init)
    }

    private func setValid(_ valid: Bool, at i: Int) {
        let was = lines[i].valid
        guard was != valid else { return }
        lines[i].valid = valid
        if lines[i].decidedAt == nil { lines[i].decidedAt = Date() }
        let id = lines[i].id
        if valid, let held = heldAudio.removeValue(forKey: id) {
            held.forEach { play($0, for: i) }
        } else if !valid {
            heldAudio[id] = nil
            // It was already playing: stop it now.
            if was == true {
                print("[XA] \(stamp(Date())) stopped playback mid-sentence")
                audio?.flush()
            }
        }
    }

    private func play(_ data: Data, for i: Int) {
        audio?.play(pcm16: data)
        if lines[i].firstSound == nil { lines[i].firstSound = Date() }
        lines[i].soundSeconds += Double(data.count / 2) / 24_000
    }

    /// A line with translated speech but no transcript of what was said. OpenAI often sends no
    /// transcript for the other person's English or German, while Mom's Chinese is transcribed
    /// within a fraction of a second. So when no Chinese was heard around that moment, the
    /// speech was the other person's. Copies of Mom's own words are still never played.
    private func placeWithoutTranscript(_ i: Int, _ direction: Direction) {
        let line = lines[i]
        let age = Date().timeIntervalSince(line.started)
        guard age >= 1.2, line.valid == nil else { return }
        let momSpeaking = lastChineseInput >= line.started.addingTimeInterval(-1.5)
        switch direction {
        case .toPartner:
            // Mom's speech whose own transcript went missing, or the other person's own words.
            if !momSpeaking { lines[i].skipReason = "other person's own language (no transcript)" }
            lines[i].placedWithoutTranscript = true
            setValid(momSpeaking, at: i)
        case .toChinese:
            // A copy of Mom's own words comes while she's talking or while the phone is
            // translating her. A real reply can only come after the phone stops (the mic is off
            // while it talks).
            if momSpeaking {
                lines[i].skipReason = "Mom was speaking (no transcript)"
                setValid(false, at: i)
                return
            }
            if line.startedWhilePhoneTalked {
                lines[i].skipReason = "came while the phone was talking (no transcript)"
                setValid(false, at: i)
                return
            }
            // The other session heard the same speech; follow its verdict once it has one.
            if let j = concurrentLine(to: i, in: .toPartner) {
                switch lines[j].valid {
                case .none: return
                case .some(true):
                    lines[i].skipReason = "Mom's speech (other session)"
                    setValid(false, at: i)
                    return
                case .some(false): break
                }
            }
            lines[i].placedWithoutTranscript = true
            setValid(true, at: i)
        }
    }

    // MARK: - Debug log

    /// Seconds since the conversation started, so log lines can be lined up.
    private func stamp(_ date: Date) -> String {
        String(format: "%6.1fs", date.timeIntervalSince(startedAt))
    }

    /// One summary per finished line: who spoke, what was played or skipped and why, and timing.
    private func reportFinishedLines(force: Bool = false) {
        let now = Date()
        for line in lines where !reported.contains(line.id) {
            guard force || now.timeIntervalSince(line.lastUpdate) > 3 else { continue }
            reported.insert(line.id)
            if line.original.isEmpty && line.translated.isEmpty && line.soundSeconds == 0 { continue }
            let dir = line.fromMom ? "Mom->\(partner.rawValue)" : "other->zh"
            let lang = line.sourceChinese.map { $0 ? "Chinese" : "not Chinese" } ?? "unknown language"
            let verdict: String
            switch line.valid {
            case .some(true):
                var timing = ""
                if let sound = line.firstSound {
                    if let first = line.firstInput {
                        timing += String(format: " | sound %.1fs after speech began", sound.timeIntervalSince(first))
                    }
                    timing += String(format: ", %.1fs of speech", line.soundSeconds)
                } else {
                    timing = " | NO SOUND played"
                }
                if let first = line.firstInput, let decided = line.decidedAt {
                    timing += String(format: ", placed after %.1fs", decided.timeIntervalSince(first))
                }
                verdict = "PLAYED" + timing + (line.placedWithoutTranscript ? " (no transcript)" : "")
            case .some(false): verdict = "skipped: \(line.skipReason.isEmpty ? "?" : line.skipReason)"
            case .none: verdict = "never placed"
            }
            print("[XA] \(stamp(line.started)) \(dir) heard \(lang): \"\(line.original.prefix(80))\"")
            print("[XA]          -> \"\(line.translated.prefix(80))\"  [\(verdict)]")
        }
    }

    private func tick() {
        guard let audio else { return }
        let speaking = audio.isPlaying || Speaker.shared.isSpeaking
        let hears = audio.hearsSomeone
        if hearing != hears { hearing = hears }
        if status == .listening && speaking { status = .speaking }
        else if status == .speaking && !speaking { status = .listening }

        let now = Date()
        for i in lines.indices where lines[i].valid == nil {
            let direction: Direction = lines[i].fromMom ? .toPartner : .toChinese
            if !lines[i].original.isEmpty && now.timeIntervalSince(lines[i].lastInput) > decidePause {
                evaluate(i, direction, paused: true)
            } else if lines[i].original.isEmpty {
                placeWithoutTranscript(i, direction)
            }
            // Never play speech we can't place: that is how the phone ends up repeating people.
            if lines[i].valid == nil
                && now.timeIntervalSince(lines[i].started) > undecidedTimeout
                && now.timeIntervalSince(lines[i].lastUpdate) > 1.5 {
                lines[i].skipReason = "couldn't tell who spoke"
                setValid(false, at: i)
            }
        }

        reportFinishedLines()

        if connected.isEmpty && problem == nil && Date().timeIntervalSince(startedAt) > 10 {
            problem = "No reply from OpenAI after 10 seconds. Check the key, billing and internet."
        }

        if !askKeepListening && Date().timeIntervalSince(lastActivity) > silencePrompt {
            askKeepListening = true
        }
    }

    private func stopSockets() {
        sockets.values.forEach { $0.close() }
        sockets.removeAll()
    }
}
