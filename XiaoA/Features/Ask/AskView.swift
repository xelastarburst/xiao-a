import SwiftUI
import PhotosUI

/// 问一问: ask anything in Mandarin, optionally about a photo. Answers come back in short Chinese.
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

    private let quickQuestions = ["这是什么意思？", "这个怎么用？", "我要注意什么？"]

    var body: some View {
        VStack(spacing: 0) {
            TopBar(title: "问一问").padding(.bottom, 8)

            ScrollViewReader { proxy in
                ScrollView {
                    VStack(spacing: 12) {
                        photoArea
                        if model.turns.isEmpty { starter }
                        ForEach(model.turns) { turn in
                            if turn.fromMom {
                                MomBubble(text: turn.text)
                            } else {
                                AnswerCard(text: turn.text,
                                           demo: turn.demo,
                                           streaming: model.streaming && turn.id == model.turns.last?.id,
                                           onRead: { speaker.speakChinese(turn.text) },
                                           onAskAlex: { forwardToAlex(turn) },
                                           alexName: store.config.alexName,
                                           canAskAlex: !store.config.alexPhone.isEmpty)
                            }
                        }
                        if listener.isListening {
                            MomBubble(text: listener.transcript.isEmpty ? "正在听…" : listener.transcript, faded: true)
                        }
                        if let error = model.error ?? listenError {
                            ErrorCard(title: "没问成功", detail: error,
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
                Text("你的照片")
                    .font(.xa(15, .bold)).foregroundStyle(.white)
                    .padding(.horizontal, 10).frame(height: 30)
                    .background(Capsule().fill(Color.black.opacity(0.75)))
                    .padding(10)
            }
            .overlay(alignment: .bottomTrailing) {
                Button { takePhoto() } label: {
                    Label("换一张", systemImage: "camera.fill")
                        .font(.xa(17, .heavy)).foregroundStyle(Palette.ink)
                        .padding(.horizontal, 14).frame(height: 44)
                        .background(Capsule().fill(.white))
                }
                .buttonStyle(Squish())
                .padding(10)
            }
        } else {
            HStack(spacing: 12) {
                SoftButton(title: "拍照", systemImage: "camera.fill", height: 64, fontSize: 22) { takePhoto() }
                PhotosPicker(selection: $libraryItem, matching: .images) {
                    Label("相册", systemImage: "photo.on.rectangle")
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
            MascotSays(text: model.image == nil ? "有什么不懂的，问我吧！" : "想问这张图的什么？",
                       detail: "按住下面的按钮说话", mascotSize: 60, textSize: 22)
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
                TextField("打字问", text: $typed, axis: .vertical)
                    .font(.xa(22, .medium))
                    .lineLimit(1...3)
                    .focused($fieldFocused)
                    .padding(.horizontal, 16).padding(.vertical, 12)
                    .background(RoundedRectangle(cornerRadius: 24).strokeBorder(Palette.line, lineWidth: 3))
                IconButton(systemImage: "paperplane.fill", label: "发送", fill: Palette.teal, foreground: .white, size: 64) {
                    ask(typed)
                    typed = ""
                }
                .disabled(typed.trimmingCharacters(in: .whitespaces).isEmpty || model.streaming)
                IconButton(systemImage: "mic.fill", label: "说话", fill: Palette.cream, size: 56) {
                    typing = false
                    fieldFocused = false
                }
            } else {
                IconButton(systemImage: "keyboard", label: "打字", fill: .white, size: 72) {
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
            do { try await listener.start(locale: "zh-CN") }
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
                listenError = "没听清，按住按钮，说完再松开。"
            }
        }
    }

    private func forwardToAlex(_ answer: AskModel.Turn) {
        let question = model.question(before: answer) ?? ""
        let body = "【小A】妈妈问：\(question)\n\n小A 的回答：\n\(answer.text)"
        let jpeg = model.image?.resizedForUpload(maxSide: 1600).jpegData(compressionQuality: 0.8)
        app.text(store.config.alexPhone, body: body, image: jpeg)
    }
}

private struct MomBubble: View {
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
    var onAskAlex: () -> Void
    var alexName: String
    var canAskAlex: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Mascot(mood: streaming ? .talking : .happy, size: 44, bobbing: streaming)
                Text(streaming && text.isEmpty ? "我看看……" : "小A 说：").font(.xa(20, .heavy))
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
                    SoftButton(title: "朗读", systemImage: "speaker.wave.2.fill", action: onRead)
                    if canAskAlex {
                        BigButton(title: "问问 \(alexName)", systemImage: "paperplane.fill", fill: Palette.teal,
                                  depth: Palette.tealDeep, height: 56, fontSize: 20, action: onAskAlex)
                    }
                }
            }
        }
        .card()
    }
}
