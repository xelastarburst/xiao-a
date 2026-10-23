import SwiftUI

/// Dolmetscher. She is in charge of the conversation:
/// 1. Before: she picks the other person's language and presses the big "Gespräch beginnen" button.
///    Nothing listens until she does.
/// 2. During: the top half faces the other person (English or Chinese, upside down), the
///    bottom half faces her. One big "Gespräch beenden" button stops it. No Notfall here, so
///    nothing sits next to it to be pressed by mistake; it's in the top bar before and after.
/// 3. After: what was said stays on screen to read again, with "Neu starten" and "Startseite".
struct InterpreterView: View {
    private enum Phase { case ready, live, ended }

    @EnvironmentObject private var app: AppState
    @StateObject private var engine = InterpreterEngine()
    /// The other person's language. Remembered for next time.
    @AppStorage("interpreterPartner") private var partnerCode = PartnerLanguage.english.rawValue
    @State private var phase: Phase = .ready
    /// The simulator plays a scripted conversation when there's no OpenAI key.
    private let demo = Demo.isOn && APIKeys.get(.openAI) == nil

    private var partner: PartnerLanguage { PartnerLanguage(rawValue: partnerCode) ?? .english }

    var body: some View {
        Group {
            switch phase {
            case .ready: readyScreen
            case .live: liveScreen
            case .ended: endedScreen
            }
        }
        .animation(.snappy(duration: 0.25), value: phase)
        .onDisappear { engine.stop() }
        .onChange(of: engine.status) { _, status in
            // If the connection breaks mid-conversation, go back to the start screen,
            // which explains what happened; the big button tries again.
            if case .failed = status, phase == .live { phase = .ready }
        }
        .alert("Weiter dolmetschen?", isPresented: $engine.askKeepListening) {
            Button("Weiter") { engine.keepListening() }
            Button("Beenden", role: .cancel) { endConversation() }
        } message: {
            Text("Seit 10 Minuten hat niemand gesprochen.")
        }
    }

    private func startConversation() {
        Haptics.success()
        engine.start(partner: partner)
        if case .failed = engine.status { return }
        phase = .live
    }

    private func endConversation() {
        engine.stop()
        phase = engine.visibleLines.isEmpty ? .ready : .ended
    }

    // MARK: - 1. Before: she starts it

    private var readyScreen: some View {
        VStack(spacing: 16) {
            TopBar(title: "Dolmetscher", onBack: { app.home() })

            if case .failed(let message) = engine.status {
                ErrorCard(title: "Der Dolmetscher hat angehalten", detail: message)
                    .padding(.horizontal, 16)
            } else {
                MascotSays(text: "Mit jemandem sprechen?", detail: "Wählen Sie die Sprache, dann den großen Knopf.")
                    .padding(.horizontal, 16)
            }

            VStack(alignment: .leading, spacing: 10) {
                Text("Die andere Person spricht:").font(.xa(22, .heavy)).foregroundStyle(Palette.ink)
                BigToggle(left: PartnerLanguage.english.nameDE,
                          right: PartnerLanguage.chinese.nameDE,
                          isRight: Binding(
                            get: { partner == .chinese },
                            set: { partnerCode = ($0 ? PartnerLanguage.chinese : PartnerLanguage.english).rawValue }
                          ))
                Text("Sie sprechen Deutsch – ich übersetze in beide Richtungen.")
                    .font(.xa(17, .semibold)).foregroundStyle(Palette.ink2)
            }
            .card()
            .padding(.horizontal, 16)

            Spacer(minLength: 8)

            StartButton(title: "Gespräch\nbeginnen", action: startConversation)

            Text("Einmal drücken genügt. Wer gerade spricht, ist egal.")
                .font(.xa(19, .semibold))
                .foregroundStyle(Palette.ink2)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)

            Spacer(minLength: 8)
        }
        .padding(.bottom, 12)
        .background(ScreenBackground())
    }

    // MARK: - 2. During: the conversation

    private var liveScreen: some View {
        VStack(spacing: 0) {
            theirHalf
                .frame(height: 250)
            statusStrip
            VStack(spacing: 12) {
                ConversationList(lines: engine.visibleLines, scrollKey: engine.scrollKey,
                                 showDemoTag: demo, onReplay: { engine.replay($0) }) {
                    Text("Tippen Sie zuerst auf „\(engine.partner.cantSpeakLabel)“, damit die andere Person weiß, wie es geht. Dann sprechen Sie einfach ganz normal.")
                        .font(.xa(20, .bold)).foregroundStyle(Palette.ink2)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.top, 8)
                }

                HStack(spacing: 10) {
                    SoftButton(title: "Bitte langsamer", systemImage: "tortoise.fill", height: 64, fontSize: 18, lines: 2) {
                        engine.say(engine.partner.slowDown, german: "Bitte sprechen Sie etwas langsamer.")
                    }
                    SoftButton(title: engine.partner.cantSpeakLabel, systemImage: "speaker.wave.2.fill", height: 64, fontSize: 18, lines: 2) {
                        engine.say(engine.partner.cantSpeakPhrase, german: engine.partner.cantSpeakGerman)
                    }
                }
                .padding(.horizontal, 16)
                .disabled(!engine.isRunning)

                BigButton(title: "Gespräch beenden", systemImage: "stop.circle.fill", fill: Palette.ink, depth: nil,
                          height: 76, fontSize: 28, action: endConversation)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 8)
            }
        }
        .background(ScreenBackground())
    }

    /// Top half — for the other person, rotated to face them across the table.
    private var theirHalf: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Text(engine.partner.badge)
                    .font(.system(size: 16, weight: .heavy, design: .rounded))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 12).frame(height: 32)
                    .background(Capsule().fill(Palette.teal))
                Text(engine.partner.invitation)
                    .font(.system(size: 17, weight: .bold, design: .rounded))
                    .foregroundStyle(Color(hex: 0x2D4A43))
            }
            if let mom = engine.latestFromHer {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(alignment: .center) {
                        Text(engine.partner.sheSaid).font(.system(size: 15, weight: .heavy, design: .rounded)).foregroundStyle(Color(hex: 0x3B5A52))
                        Spacer(minLength: 8)
                        if !mom.translated.isEmpty {
                            Button { engine.replay(mom) } label: {
                                Label(engine.partner.playAgain, systemImage: "speaker.wave.2.fill")
                                    .font(.system(size: 15, weight: .heavy, design: .rounded))
                                    .foregroundStyle(Palette.tealInk)
                                    .padding(.horizontal, 12).frame(height: 40)
                                    .background(Capsule().fill(Color.white.opacity(0.85)))
                            }
                            .buttonStyle(Squish())
                        }
                    }
                    Text(mom.translated.isEmpty ? "…" : mom.translated.cleanedCaption)
                        .font(.system(size: 26, weight: .heavy, design: .rounded))
                        .foregroundStyle(Palette.ink)
                        .lineLimit(4).minimumScaleFactor(0.6)
                }
            }
            if let other = engine.latestFromOther, !other.original.isEmpty {
                VStack(alignment: .leading, spacing: 2) {
                    Text(engine.partner.youSaid).font(.system(size: 15, weight: .heavy, design: .rounded)).foregroundStyle(Color(hex: 0x3B5A52))
                    Text(other.original.cleanedCaption)
                        .font(.system(size: 19, weight: .bold, design: .rounded))
                        .foregroundStyle(Color(hex: 0x2D4A43))
                        .lineLimit(3).minimumScaleFactor(0.7)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 20)
        .padding(.top, 18)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .rotationEffect(.degrees(180))
        .background(Palette.mint.ignoresSafeArea(edges: .top))
        .accessibilityElement(children: .contain)
    }

    private var statusStrip: some View {
        HStack(spacing: 10) {
            Mascot(mood: engine.status == .speaking ? .talking : .happy, size: 58)
            VStack(alignment: .leading, spacing: 0) {
                Text(statusTitle).font(.xa(22, .heavy))
                Text(statusDetail).font(.xa(17, .semibold)).foregroundStyle(Palette.ink2)
                    .lineLimit(1).minimumScaleFactor(0.8)
                if let problem = engine.problem {
                    // English on purpose: this is for her family to read and fix.
                    Text("OpenAI: \(problem)")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Palette.red)
                        .lineLimit(2).minimumScaleFactor(0.8)
                }
            }
            Spacer(minLength: 0)
            if engine.status == .listening || engine.status == .speaking {
                // Moves only when someone is actually heard, or the phone is talking.
                let active = engine.hearing || engine.status == .speaking
                Image(systemName: "waveform")
                    .font(.system(size: 34, weight: .bold))
                    .foregroundStyle(active ? Palette.teal : Palette.ink2.opacity(0.4))
                    .symbolEffect(.variableColor.iterative, isActive: active)
            } else if engine.status == .connecting {
                ProgressView().controlSize(.large)
            }
        }
        .padding(.horizontal, 16)
        .frame(height: 84)
        .background(Color.white)
    }

    private var statusTitle: String {
        switch engine.status {
        case .idle: return "Pause"
        case .connecting: return "Ich bereite mich vor …"
        case .listening: return "Ich höre zu …"
        case .speaking: return "Ich übersetze …"
        case .failed: return "Angehalten"
        }
    }

    private var statusDetail: String {
        switch engine.status {
        case .listening, .speaking: return "Die andere Person spricht \(engine.partner.nameDE). Jeder darf sprechen."
        case .connecting, .idle: return "Gleich geht es los"
        case .failed: return "Bitte noch einmal versuchen"
        }
    }

    // MARK: - 3. After: read it again

    private var endedScreen: some View {
        VStack(spacing: 12) {
            TopBar(title: "Dolmetscher", onBack: { phase = .ready })

            MascotSays(text: "Fertig!", detail: "Alles Gesagte steht unten. Sie können es noch einmal lesen.")
                .padding(.horizontal, 16)

            ConversationList(lines: engine.visibleLines, scrollKey: "", showDemoTag: demo,
                             onReplay: { engine.replay($0) }) { EmptyView() }

            HStack(spacing: 10) {
                BigButton(title: "Neu starten", systemImage: "mic.fill", fill: Palette.teal, depth: Palette.tealDeep,
                          height: 72, fontSize: 26, action: startConversation)
                BigButton(title: "Startseite", systemImage: "house.fill", fill: Palette.ink, depth: nil,
                          height: 72, fontSize: 26) { app.home() }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 8)
        }
        .background(ScreenBackground())
    }
}

// MARK: - Pieces

/// The big round button that starts a conversation.
private struct StartButton: View {
    var title: String
    var action: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var pulse = false

    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                Image(systemName: "mic.fill").font(.system(size: 54, weight: .bold))
                Text(title).font(.xa(26, .heavy)).lineLimit(2).minimumScaleFactor(0.7)
                    .multilineTextAlignment(.center)
            }
            .foregroundStyle(.white)
            .frame(width: 196, height: 196)
            .background(
                ZStack {
                    Circle().fill(Palette.tealDeep).offset(y: 6)
                    Circle().fill(Palette.teal)
                }
            )
            .background(
                // A soft ring that keeps spreading out: "press me".
                Circle()
                    .stroke(Palette.leaf.opacity(0.45), lineWidth: 12)
                    .scaleEffect(pulse ? 1.18 : 1)
                    .opacity(pulse ? 0 : 1)
            )
        }
        .buttonStyle(Squish())
        .accessibilityLabel(title.replacingOccurrences(of: "\n", with: " "))
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.easeOut(duration: 1.8).repeatForever(autoreverses: false)) { pulse = true }
        }
    }
}

/// What was said, newest at the bottom. Used during and after the conversation.
private struct ConversationList<Empty: View>: View {
    var lines: [InterpreterEngine.Line]
    var scrollKey: String
    var showDemoTag: Bool
    var onReplay: (InterpreterEngine.Line) -> Void
    @ViewBuilder var empty: () -> Empty

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(spacing: 10) {
                    if showDemoTag {
                        HStack { Spacer(); DemoTag() }
                    }
                    if lines.isEmpty { empty() }
                    ForEach(lines) { line in
                        if line.fromHer {
                            HerLine(text: (line.original.isEmpty ? line.translated : line.original).cleanedCaption)
                        } else {
                            TheirLine(text: line.translated.isEmpty ? "…" : line.translated.cleanedCaption) { onReplay(line) }
                        }
                    }
                    Color.clear.frame(height: 1).id("end")
                }
                .padding(.horizontal, 16)
                .padding(.top, 12)
            }
            .onAppear { proxy.scrollTo("end", anchor: .bottom) }
            .onChange(of: scrollKey) { _, _ in
                withAnimation { proxy.scrollTo("end", anchor: .bottom) }
            }
        }
    }
}

private struct HerLine: View {
    var text: String
    var body: some View {
        HStack {
            Spacer(minLength: 50)
            Text(text)
                .font(.xa(20, .semibold))
                .foregroundStyle(Palette.ink)
                .padding(.horizontal, 14).padding(.vertical, 10)
                .background(UnevenRoundedRectangle(topLeadingRadius: 20, bottomLeadingRadius: 20,
                                                   bottomTrailingRadius: 6, topTrailingRadius: 20).fill(Palette.peach))
        }
    }
}

private struct TheirLine: View {
    var text: String
    var onReplay: () -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("Die andere Person sagt:").font(.xa(17, .heavy)).foregroundStyle(Palette.tealInk)
                Spacer()
                IconButton(systemImage: "speaker.wave.2.fill", label: "Nochmal hören", fill: Palette.mint,
                           foreground: Palette.tealInk, size: 44, action: onReplay)
            }
            Text(text).font(.xa(26, .heavy)).foregroundStyle(Palette.ink)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 16).padding(.top, 10).padding(.bottom, 14)
        .background(
            UnevenRoundedRectangle(topLeadingRadius: 22, bottomLeadingRadius: 6,
                                   bottomTrailingRadius: 22, topTrailingRadius: 22)
                .fill(.white)
                .overlay(UnevenRoundedRectangle(topLeadingRadius: 22, bottomLeadingRadius: 6,
                                                bottomTrailingRadius: 22, topTrailingRadius: 22)
                    .stroke(Palette.leaf, lineWidth: 3))
        )
    }
}

private extension String {
    /// Captions arrive as fragments that can start with a space or the previous sentence's ". " or "。".
    var cleanedCaption: String {
        String(drop(while: { $0.isWhitespace || $0.isPunctuation }))
    }
}
