import SwiftUI
import PhotosUI

/// Fragen: ask anything in German, optionally about a photo. Answers come back in short, plain German.
struct AskView: View {
    @EnvironmentObject private var app: AppState
    @EnvironmentObject private var store: ConfigStore
    @StateObject private var model = AskModel()
    @StateObject private var listener = SpeechListener()
    @StateObject private var speaker = Speaker.shared

    @State private var typing = false
    @State private var typed = ""
    @State private var showCamera = false
    @State private var libraryItem: PhotosPickerItem?
    @State private var listenError: String?
    @FocusState private var fieldFocused: Bool

    private let quickQuestions = ["Was bedeutet das?", "Wie benutze ich das?", "Worauf muss ich achten?"]

    var body: some View {
        VStack(spacing: 0) {
            TopBar(title: "Fragen").padding(.bottom, 8)

            ScrollViewReader { proxy in
                ScrollView {
                    VStack(spacing: 12) {
                        photoArea
                        if model.turns.isEmpty { starter }
                        ForEach(model.turns) { turn in
                            if turn.fromHer {
                                HerBubble(text: turn.text)
                            } else {
                                AnswerCard(text: turn.text,
                                           demo: turn.demo,
                                           streaming: model.streaming && turn.id == model.turns.last?.id,
                                           onRead: { speaker.speakGerman(turn.text) },
                                           onAskContact: { forwardToContact(turn) },
                                           contactName: store.config.contactLabel,
                                           canAskContact: !store.config.contactPhone.isEmpty)
                            }
                        }
                        if listener.isListening {
                            HerBubble(text: listener.transcript.isEmpty ? "Ich höre zu…" : listener.transcript, faded: true)
                        }
                        if let error = model.error ?? listenError {
                            ErrorCard(title: "Das hat nicht geklappt", detail: error,
                                      retry: model.lastFailedQuestion.map { q in { ask(q) } })
                        }
                        Color.clear.frame(height: 1).id("bottom")
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 16)
                }
                .onChange(of: model.turns) { _, _ in
                    withAnimation { proxy.scrollTo("bottom", anchor: .bottom) }
                }
                .onChange(of: model.streaming) { _, _ in
                    withAnimation { proxy.scrollTo("bottom", anchor: .bottom) }
                }
                .onChange(of: listener.transcript) { _, _ in
                    proxy.scrollTo("bottom", anchor: .bottom)
                }
            }

            inputBar
        }
        .background(ScreenBackground())
        .onAppear {
            if let image = app.pendingAskImage {
                model.startOver(with: image)
                app.pendingAskImage = nil
            }
        }
        .onDisappear {
            listener.cancel()
            speaker.stop()
        }
        // Ask for the microphone up front, so the system prompt never interrupts a press.
        .task { _ = await SpeechListener.requestPermissions() }
        .fullScreenCover(isPresented: $showCamera) {
            CameraPicker { image in
                showCamera = false
                if let image { model.startOver(with: image) }
            }
            .ignoresSafeArea()
        }
        .onChange(of: libraryItem) { _, item in
            guard let item else { return }
            Task {
                if let data = try? await item.loadTransferable(type: Data.self), let image = UIImage(data: data) {
                    model.startOver(with: image)
                }
                libraryItem = nil
            }
        }
    }

    // MARK: Pieces

    @ViewBuilder private var photoArea: some View {
        if let image = model.image {
            ZStack(alignment: .topLeading) {
                Image(uiImage: image).resizable().scaledToFill()
                    .frame(height: 160).frame(maxWidth: .infinity).clipped()
                    .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                Text("Ihr Foto")
                    .font(.xa(15, .bold)).foregroundStyle(.white)
                    .padding(.horizontal, 10).frame(height: 30)
                    .background(Capsule().fill(Color.black.opacity(0.75)))
                    .padding(10)
            }
            .overlay(alignment: .bottomTrailing) {
                Button { takePhoto() } label: {
                    Label("Neues Foto", systemImage: "camera.fill")
                        .font(.xa(17, .heavy)).foregroundStyle(Palette.ink)
                        .padding(.horizontal, 14).frame(height: 44)
                        .background(Capsule().fill(.white))
                }
                .buttonStyle(Squish())
                .padding(10)
            }
        } else {
            HStack(spacing: 12) {
                SoftButton(title: "Foto", systemImage: "camera.fill", height: 64, fontSize: 22) { takePhoto() }
                PhotosPicker(selection: $libraryItem, matching: .images) {
                    Label("Fotos", systemImage: "photo.on.rectangle")
                        .font(.xa(22, .heavy)).foregroundStyle(Palette.ink)
                        .frame(maxWidth: .infinity).frame(height: 64)
                        .chunky(.white, radius: 32, border: Palette.line)
                }
                .buttonStyle(Squish())
            }
        }
    }

    private var starter: some View {
        VStack(alignment: .leading, spacing: 12) {
            MascotSays(text: model.image == nil ? "Fragen Sie mich, was Sie wissen möchten!" : "Was möchten Sie zu diesem Bild wissen?",
                       detail: "Halten Sie den Knopf unten gedrückt und sprechen Sie", mascotSize: 60, textSize: 22)
            if model.image != nil {
                ForEach(quickQuestions, id: \.self) { q in
                    Button { ask(q) } label: {
                        Text(q).font(.xa(21, .heavy)).foregroundStyle(Palette.ink)
                            .padding(.horizontal, 18).frame(minHeight: 56)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .chunky(Palette.sky, radius: 20)
                    }
                    .buttonStyle(Squish())
                }
            }
        }
    }

    private var inputBar: some View {
        HStack(spacing: 12) {
            if typing {
                TextField("Frage tippen", text: $typed, axis: .vertical)
                    .font(.xa(22, .medium))
                    .lineLimit(1...3)
                    .focused($fieldFocused)
                    .padding(.horizontal, 16).padding(.vertical, 12)
                    .background(RoundedRectangle(cornerRadius: 24).strokeBorder(Palette.line, lineWidth: 3))
                IconButton(systemImage: "paperplane.fill", label: "Senden", fill: Palette.teal, foreground: .white, size: 64) {
                    ask(typed)
                    typed = ""
                }
                .disabled(typed.trimmingCharacters(in: .whitespaces).isEmpty || model.streaming)
                IconButton(systemImage: "mic.fill", label: "Sprechen", fill: Palette.cream, size: 56) {
                    typing = false
                    fieldFocused = false
                }
            } else {
                IconButton(systemImage: "keyboard", label: "Tippen", fill: .white, size: 72) {
                    typing = true
                    fieldFocused = true
                }
                .overlay(Circle().strokeBorder(Palette.line, lineWidth: 3))
                HoldToTalkButton(isActive: listener.isListening, onStart: startListening, onEnd: stopListening)
                    .disabled(model.streaming)
                    .opacity(model.streaming ? 0.6 : 1)
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 16)
        .padding(.bottom, 12)
        .background(
            UnevenRoundedRectangle(topLeadingRadius: 28, topTrailingRadius: 28).fill(.white)
                .ignoresSafeArea(edges: .bottom)
        )
    }

    // MARK: Actions

    private func ask(_ question: String) {
        speaker.stop()
        model.ask(question, config: store.config)
    }

    private func takePhoto() {
        if Demo.isOn, let sign = Demo.signImage {
            model.startOver(with: sign)      // the simulator has no camera
        } else {
            showCamera = true
        }
    }

    private func startListening() {
        listenError = nil
        if Demo.isOn {
            listener.startDemo()
            return
        }
        Task {
            do { try await listener.start(locale: "de-DE") }
            catch { listenError = error.localizedDescription }
        }
    }

    private func stopListening() {
        if Demo.isOn {
            _ = listener.stopDemo()
            ask(Demo.spokenQuestion)
            return
        }
        Task {
            let text = await listener.stop()
            if !text.trimmingCharacters(in: .whitespaces).isEmpty {
                ask(text)
            } else if listenError == nil {
                listenError = "Das habe ich nicht verstanden. Knopf gedrückt halten, sprechen, dann loslassen."
            }
        }
    }

    private func forwardToContact(_ answer: AskModel.Turn) {
        let question = model.question(before: answer) ?? ""
        let who = store.config.herName.isEmpty ? "Ihre Frage" : "\(store.config.herName) fragt"
        let body = "[Helferlein] \(who): \(question)\n\nAntwort von Helferlein:\n\(answer.text)"
        let jpeg = model.image?.resizedForUpload(maxSide: 1600).jpegData(compressionQuality: 0.8)
        app.text(store.config.contactPhone, body: body, image: jpeg)
    }
}

private struct HerBubble: View {
    var text: String
    var faded = false
    var body: some View {
        HStack {
            Spacer(minLength: 50)
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "waveform").font(.system(size: 18, weight: .bold)).foregroundStyle(Color(hex: 0x7A3A16))
                    .padding(.top, 4)
                Text(text).font(.xa(22, .heavy)).foregroundStyle(Palette.ink)
            }
            .padding(.horizontal, 16).padding(.vertical, 12)
            .background(UnevenRoundedRectangle(topLeadingRadius: 22, bottomLeadingRadius: 22,
                                               bottomTrailingRadius: 6, topTrailingRadius: 22).fill(Palette.peach))
            .opacity(faded ? 0.7 : 1)
        }
    }
}

private struct AnswerCard: View {
    var text: String
    var demo = false
    var streaming: Bool
    var onRead: () -> Void
    var onAskContact: () -> Void
    var contactName: String
    var canAskContact: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Mascot(mood: streaming ? .talking : .happy, size: 44, bobbing: streaming)
                Text(streaming && text.isEmpty ? "Ich schaue nach…" : "Helferlein sagt:").font(.xa(20, .heavy))
                Spacer(minLength: 0)
                if demo { DemoTag() }
            }
            if !text.isEmpty {
                Text(text)
                    .font(.xa(21, .medium))
                    .lineSpacing(5)
                    .foregroundStyle(Palette.ink)
                    .textSelection(.enabled)
            }
            if !streaming && !text.isEmpty {
                HStack(spacing: 10) {
                    SoftButton(title: "Vorlesen", systemImage: "speaker.wave.2.fill", action: onRead)
                    if canAskContact {
                        BigButton(title: "An \(contactName)", systemImage: "paperplane.fill", fill: Palette.teal,
                                  depth: Palette.tealDeep, height: 56, fontSize: 20, action: onAskContact)
                    }
                }
            }
        }
        .card()
    }
}
