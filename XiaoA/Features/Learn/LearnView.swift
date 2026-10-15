import SwiftUI

/// 学英语: today's 30-minute spoken lesson.
struct LearnView: View {
    @EnvironmentObject private var app: AppState
    var body: some View { CoachScreen(coach: app.coach) }
}

private struct CoachScreen: View {
    @ObservedObject var coach: CoachModel
    @EnvironmentObject private var app: AppState
    @EnvironmentObject private var store: ConfigStore
    @EnvironmentObject private var learning: LearningStore
    @StateObject private var listener = SpeechListener()
    @State private var listenError: String?

    var body: some View {
        VStack(spacing: 0) {
            TopBar(title: coach.sessionTitle ?? "学英语",
                   onBack: backToScenes)
                .padding(.bottom, 8)
            switch coach.stage {
            case .overview: overview
            case .finished: finished
            default: lesson
            }
        }
        .background(ScreenBackground())
        .onAppear { coach.prepareIfNeeded(store: learning, config: store.config) }
        // Ask for the microphone up front, so the system prompt never interrupts a press.
        .task { _ = await SpeechListener.requestPermissions() }
        .onDisappear {
            listener.cancel()
            Speaker.shared.stop()
        }
        .overlay {
            if coach.paused { pausedOverlay }
        }
    }

    /// In a lesson, ← goes back to the 学英语 start screen instead of home.
    private var backToScenes: (() -> Void)? {
        guard coach.stage != .overview else { return nil }
        return {
            listener.cancel()
            coach.showOverview()
        }
    }

    // MARK: Overview

    private var overview: some View {
        VStack(spacing: 14) {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    if learning.doneToday {
                        MascotSays(text: "今天的课已经学完啦！", detail: "还想学？点下面的场景，或者再学几句新的", mascotSize: 76)
                    } else {
                        MascotSays(text: "今天学 \(coach.newCount) 句新话", detail: overviewDetail, mascotSize: 76)
                    }
                    if learning.streak > 0 {
                        Label("已经连续学了 \(learning.streak) 天", systemImage: "star.fill")
                            .font(.xa(20, .heavy)).foregroundStyle(Palette.warnInk)
                            .padding(14).frame(maxWidth: .infinity, alignment: .leading)
                            .background(RoundedRectangle(cornerRadius: 18).fill(Palette.butter))
                    }
                    if !learning.doneToday {
                        ForEach(coach.todayItems) { item in
                            HStack(spacing: 12) {
                                Text(item.isReview ? "复习" : "新")
                                    .font(.xa(16, .heavy)).foregroundStyle(item.isReview ? Palette.tealInk : Palette.persimmon)
                                    .frame(width: 48, height: 32)
                                    .background(Capsule().fill(item.isReview ? Palette.mint : Palette.peach))
                                VStack(alignment: .leading, spacing: 0) {
                                    Text(item.phrase.zh).font(.xa(21, .heavy))
                                    Text(item.phrase.en).font(.xa(17, .semibold)).foregroundStyle(Palette.ink2)
                                }
                                Spacer(minLength: 0)
                            }
                            .padding(14)
                            .background(RoundedRectangle(cornerRadius: 18).fill(.white))
                        }
                    }
                    Text("按场景练习").font(.xa(24, .heavy)).padding(.top, 6)
                    Text("出门要用的话，挑一个场景，一句一句学").font(.xa(18, .semibold)).foregroundStyle(Palette.ink2)
                    LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
                        ForEach(units) { unit in
                            sceneCard(unit)
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 8)
            }
            Group {
                if coach.todayItems.isEmpty || learning.doneToday {
                    BigButton(title: "再学几句新的", systemImage: "plus", fill: Palette.teal, depth: Palette.tealDeep) {
                        coach.startMore(store: learning, config: store.config)
                    }
                } else {
                    BigButton(title: coach.todayStarted ? "接着学今天的课" : "开始今天的课", systemImage: "play.fill") {
                        coach.startToday()
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 12)
        }
    }

    private var units: [LessonUnit] { Curriculum.units(for: store.config) }

    private func sceneCard(_ unit: LessonUnit) -> some View {
        let learned = unit.phrases.filter { learning.stat($0.id).mastered }.count
        return Button {
            coach.startScene(unit, store: learning)
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                Image(systemName: Self.icon(for: unit.id))
                    .font(.system(size: 28, weight: .bold))
                    .foregroundStyle(Palette.teal)
                Text(unit.title).font(.xa(20, .heavy)).foregroundStyle(Palette.ink)
                    .lineLimit(2).minimumScaleFactor(0.8)
                    .fixedSize(horizontal: false, vertical: true)
                Text(learned == 0 ? "\(unit.phrases.count) 句" : "学会 \(learned)/\(unit.phrases.count)")
                    .font(.xa(16, .bold))
                    .foregroundStyle(learned == unit.phrases.count ? Palette.tealInk : Palette.ink2)
            }
            .frame(maxWidth: .infinity, minHeight: 118, alignment: .topLeading)
            .padding(14)
            .background(RoundedRectangle(cornerRadius: 20).fill(.white))
            .overlay(RoundedRectangle(cornerRadius: 20)
                .strokeBorder(learned == unit.phrases.count ? Palette.teal : Palette.line, lineWidth: 2))
        }
        .buttonStyle(.plain)
    }

    private static func icon(for unit: Int) -> String {
        switch unit {
        case 1: return "hand.wave.fill"
        case 2: return "star.fill"
        case 3: return "questionmark.bubble.fill"
        case 4: return "person.fill"
        case 5: return "cross.case.fill"
        case 6: return "dollarsign.circle.fill"
        case 7: return "cart.fill"
        case 8: return "cup.and.saucer.fill"
        case 9: return "car.fill"
        case 10: return "pills.fill"
        case 11: return "house.fill"
        case 12: return "clock.fill"
        case 13: return "shield.fill"
        case 14: return "carrot.fill"
        case 15: return "tshirt.fill"
        case 16: return "fork.knife"
        case 17: return "map.fill"
        case 18: return "bus.fill"
        case 19: return "door.left.hand.open"
        case 20: return "heart.fill"
        case 21: return "stethoscope"
        case 22: return "cloud.sun.fill"
        case 23: return "figure.2.and.child.holdinghands"
        case 24: return "leaf.fill"
        case 25: return "phone.fill"
        case 26: return "building.columns.fill"
        case 27: return "number"
        case 28: return "calendar"
        default: return "face.smiling.fill"
        }
    }

    /// e.g. "主题：打招呼和礼貌。我说一遍，你跟着说"
    private var overviewDetail: String {
        let topic = coach.todayItems.first(where: { !$0.isReview })
            .flatMap { Curriculum.unitTitle(of: $0.phrase.id, config: store.config) }
        let lead = coach.reviewCount > 0 ? "先复习 \(coach.reviewCount) 句学过的" : "我说一遍，你跟着说"
        return topic.map { "主题：\($0)。\(lead)" } ?? lead
    }

    // MARK: Lesson

    @ViewBuilder private var lesson: some View {
        if let item = coach.current {
            VStack(spacing: 12) {
                progressCard(item)
                ScrollView {
                    VStack(spacing: 12) {
                        phraseCard(item)
                        if listener.isListening {
                            Text(listener.transcript.isEmpty ? "正在听……" : listener.transcript)
                                .font(.xa(22, .bold)).foregroundStyle(Palette.ink2)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .card(Palette.peach.opacity(0.6))
                        }
                        feedback
                        if let listenError {
                            ErrorCard(title: "没听成", detail: listenError)
                        }
                    }
                    .padding(.horizontal, 16)
                }
                bottomAction
                    .padding(.horizontal, 16)
                    .padding(.bottom, 12)
            }
        }
    }

    private func progressCard(_ item: CoachModel.Item) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .firstTextBaseline) {
                    Text("第 \(coach.index + 1) / \(coach.items.count) 句" + (item.isReview ? " · 复习" : ""))
                        .font(.xa(19, .heavy))
                    Spacer()
                    TimelineView(.periodic(from: .now, by: 30)) { context in
                        Text("还剩 \(coach.minutesLeft(at: context.date)) 分钟")
                            .font(.xa(17, .bold)).foregroundStyle(Palette.ink2)
                    }
                }
                if Demo.isOn {
                    HStack(spacing: 6) {
                        DemoTag()
                        Text("麦克风是模拟的").font(.xa(14, .bold)).foregroundStyle(Palette.ink2)
                    }
                }
                ProgressView(value: coach.progress)
                    .tint(Palette.leaf)
                    .scaleEffect(x: 1, y: 2.2, anchor: .center)
            }
            IconButton(systemImage: "pause.fill", label: "暂停", fill: .white, size: 60) {
                listener.cancel()
                Speaker.shared.stop()
                coach.paused = true
            }
            .overlay(Circle().strokeBorder(Palette.line, lineWidth: 3))
        }
        .padding(.leading, 16).padding(.trailing, 12).padding(.vertical, 12)
        .background(RoundedRectangle(cornerRadius: 22).fill(.white))
        .padding(.horizontal, 16)
    }

    private func phraseCard(_ item: CoachModel.Item) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center, spacing: 10) {
                Mascot(size: 56)
                Text("\(item.phrase.scene)，你想说：\(item.phrase.zh)")
                    .font(.xa(20, .bold)).lineSpacing(3)
            }
            Divider()
            Text("跟我说").font(.xa(18, .bold)).foregroundStyle(Palette.ink2)
            Text(sentence(item.phrase.en))
                .font(.system(size: 32, weight: .heavy, design: .rounded))
                .fixedSize(horizontal: false, vertical: true)
            Text(beats(item.phrase.beats))
                .font(.system(size: 20, weight: .bold, design: .rounded))
                .foregroundStyle(Palette.ink2)
            HStack(spacing: 10) {
                SoftButton(title: "听一遍", systemImage: "speaker.wave.2.fill", fill: Palette.sky, border: nil) {
                    coach.playModel()
                }
                SoftButton(title: "慢慢听", systemImage: "tortoise.fill", fill: Palette.sky, border: nil) {
                    coach.playModel(slow: true)
                }
            }
        }
        .card()
    }

    @ViewBuilder private var feedback: some View {
        switch coach.stage {
        case .checking:
            HStack(spacing: 12) {
                ProgressView().controlSize(.large)
                Text("我听听……").font(.xa(22, .heavy))
            }
            .card(Palette.mint)
        case .retry(let tip, let close):
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(close ? "很接近了！" : "再试一次！").font(.xa(26, .heavy)).foregroundStyle(Palette.tealInk)
                    Spacer()
                    TriesDots(used: coach.tries, total: CoachModel.maxTries)
                }
                if !coach.heard.isEmpty {
                    Text("我听到的是：\(coach.heard)")
                        .font(.xa(19, .bold)).foregroundStyle(Palette.ink2)
                }
                Text(tip).font(.xa(20, .semibold)).foregroundStyle(Color(hex: 0x23403A)).lineSpacing(3)
            }
            .card(Palette.mint)
        case .passed(let stars):
            HStack(spacing: 12) {
                HStack(spacing: 2) {
                    ForEach(0..<3, id: \.self) { i in
                        Image(systemName: i < stars ? "star.fill" : "star")
                            .font(.system(size: 30, weight: .bold))
                            .foregroundStyle(Palette.gold)
                    }
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text("太棒了！").font(.xa(26, .heavy))
                    Text("说得很清楚，这句学会了").font(.xa(19, .semibold))
                }
            }
            .foregroundStyle(Palette.warnInk)
            .card(Palette.butter)
        case .gaveUp:
            VStack(alignment: .leading, spacing: 4) {
                Text("你很努力了！").font(.xa(26, .heavy))
                Text("这句明天再练，我们先学下一句。").font(.xa(20, .semibold))
            }
            .foregroundStyle(Color(hex: 0x33455C))
            .card(Palette.sky)
        default:
            EmptyView()
        }
    }

    @ViewBuilder private var bottomAction: some View {
        switch coach.stage {
        case .passed, .gaveUp:
            BigButton(title: "下一句", systemImage: "chevron.right", fill: Palette.teal, depth: Palette.tealDeep, height: 80, fontSize: 28) {
                coach.next(store: learning)
            }
        case .checking:
            BigButton(title: "我听听……", fill: Palette.line, depth: nil, foreground: Palette.ink2, height: 80) {}
                .disabled(true)
        default:
            VStack(spacing: 8) {
                HoldToTalkButton(title: "按住，说英语", activeTitle: "说完松开", isActive: listener.isListening,
                                 height: 80, onStart: startListening, onEnd: stopListening)
                Button {
                    listener.cancel()
                    coach.skip(store: learning)
                } label: {
                    Label("跳过这句", systemImage: "forward.fill")
                        .font(.xa(19, .bold)).foregroundStyle(Palette.ink2)
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(.plain)
                .disabled(listener.isListening)
            }
        }
    }

    // MARK: Finished

    private var finished: some View {
        VStack(spacing: 16) {
            Spacer()
            Mascot(size: 140)
            Text(coach.session == .today ? "今天的课学完啦！" : "这一组练完啦！").font(.xa(32, .heavy))
            HStack(spacing: 6) {
                Image(systemName: "star.fill").foregroundStyle(Palette.gold)
                Text("今天得了 \(coach.starsToday) 颗星").font(.xa(24, .heavy))
            }
            if learning.streak > 0 {
                Text("已经连续学了 \(learning.streak) 天").font(.xa(22, .bold)).foregroundStyle(Palette.ink2)
            }
            Spacer()
            if case .scene(let id) = coach.session, let next = units.first(where: { $0.id > id }) {
                BigButton(title: "下一个场景：\(next.title)", systemImage: "chevron.right", fill: Palette.teal, depth: Palette.tealDeep,
                          height: 72, fontSize: 22) {
                    coach.startScene(next, store: learning)
                }
            } else {
                BigButton(title: "再学几句新的", systemImage: "plus", fill: Palette.teal, depth: Palette.tealDeep) {
                    coach.startMore(store: learning, config: store.config)
                }
            }
            SoftButton(title: "选别的场景", systemImage: "square.grid.2x2.fill", height: 64, fontSize: 22) {
                coach.showOverview()
            }
            SoftButton(title: "回首页", systemImage: "house.fill", height: 56, fontSize: 20) {
                app.home()
            }
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 12)
    }

    private var pausedOverlay: some View {
        ZStack {
            Color.black.opacity(0.45).ignoresSafeArea()
            VStack(spacing: 14) {
                Mascot(mood: .calm, size: 96, bobbing: false)
                Text("休息一下").font(.xa(28, .heavy))
                Text("回来接着学，进度不会丢。").font(.xa(20, .semibold)).foregroundStyle(Palette.ink2)
                BigButton(title: "继续学", systemImage: "play.fill") {
                    coach.paused = false
                    coach.playModel()
                }
                SoftButton(title: "选别的场景", systemImage: "square.grid.2x2.fill", height: 64, fontSize: 22) {
                    coach.showOverview()
                }
                SoftButton(title: "回首页", systemImage: "house.fill", height: 56, fontSize: 20) {
                    coach.paused = false
                    app.home()
                }
            }
            .padding(24)
            .background(RoundedRectangle(cornerRadius: 30).fill(Palette.cream))
            .padding(24)
        }
    }

    // MARK: Actions

    private func startListening() {
        listenError = nil
        Speaker.shared.stop()
        if Demo.isOn {
            listener.startDemo()
            return
        }
        Task {
            do { try await listener.start(locale: "en-US", record: true) }
            catch { listenError = error.localizedDescription }
        }
    }

    private func stopListening() {
        Task {
            var heard = Demo.isOn ? listener.stopDemo() : await listener.stop()
            if heard.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, !Demo.isOn,
               let recording = listener.lastRecording, let key = APIKeys.get(.openAI) {
                coach.showChecking()
                do {
                    heard = try await OpenAITranscribe.transcribe(recording, apiKey: key, language: "en")
                    print("[XA] Learn: Apple heard nothing; OpenAI heard \"\(heard)\"")
                } catch {
                    print("[XA] Learn: OpenAI check failed: \(error.localizedDescription)")
                }
            }
            await coach.evaluate(heard: heard, store: learning, config: store.config)
        }
    }

    // MARK: Text styling

    /// The sentence, with words the recognizer didn't catch in orange and underlined.
    private func sentence(_ english: String) -> AttributedString {
        var result = AttributedString()
        let passed: Bool = { if case .passed = coach.stage { return true }; return false }()
        for (i, word) in english.split(separator: " ").enumerated() {
            var piece = AttributedString((i > 0 ? " " : "") + word)
            let tokens = PronunciationCheck.normalize(String(word), canonical: false)
            if passed {
                piece.foregroundColor = Palette.teal
            } else if !coach.missed.isEmpty && tokens.contains(where: { coach.missed.contains($0) }) {
                piece.foregroundColor = Palette.persimmon
                piece.underlineStyle = Text.LineStyle(pattern: .solid, color: Palette.persimmon)
            } else {
                piece.foregroundColor = Palette.ink
            }
            result += piece
        }
        return result
    }

    /// "where · is · the · REST·room" with the stressed beat highlighted.
    private func beats(_ beats: String) -> AttributedString {
        var result = AttributedString()
        let words = beats.components(separatedBy: " · ")
        for (w, word) in words.enumerated() {
            if w > 0 { result += AttributedString(" · ") }
            let syllables = word.components(separatedBy: "·")
            for (s, syllable) in syllables.enumerated() {
                if s > 0 { result += AttributedString("·") }
                var piece = AttributedString(syllable)
                let stressed = syllable.count > 1 && syllable == syllable.uppercased() && syllable.rangeOfCharacter(from: .letters) != nil
                if stressed {
                    piece.foregroundColor = Palette.persimmon
                    piece.font = .system(size: 22, weight: .heavy, design: .rounded)
                }
                result += piece
            }
        }
        return result
    }
}

private struct TriesDots: View {
    var used: Int
    var total: Int
    var body: some View {
        HStack(spacing: 6) {
            ForEach(0..<total, id: \.self) { i in
                Circle()
                    .fill(i < used ? Palette.teal : Color.clear)
                    .overlay(Circle().strokeBorder(Palette.teal, lineWidth: 2))
                    .frame(width: 14, height: 14)
            }
            Text("第 \(used) 次").font(.xa(16, .bold)).foregroundStyle(Color(hex: 0x33504A))
        }
    }
}
