import SwiftUI

/// 看一看: point the camera at English and see Chinese laid over it, live and offline.
struct LookView: View {
    @EnvironmentObject private var app: AppState
    @StateObject private var model = LookModel()
    @StateObject private var translator = TranslationEngine()
    @StateObject private var speaker = Speaker.shared
    @State private var cameraAllowed: Bool?
    /// A paragraph Mom tapped on the frozen photo, shown big.
    @State private var selected: PhotoBlock?

    var body: some View {
        ZStack(alignment: .top) {
            Color(hex: 0x1E1814).ignoresSafeArea()

            cameraLayer
                .ignoresSafeArea(edges: .top)

            VStack(spacing: 8) {
                TopBar(title: "看一看", onDark: true)
                HStack {
                    if model.readingClearly {
                        StatusChip(text: "小A 在看清楚…", symbol: "sparkle.magnifyingglass", fill: Palette.teal)
                    } else if model.frozen {
                        StatusChip(text: "画面已定住", symbol: "pause.fill", fill: Color.black.opacity(0.75))
                    } else if translator.allInContext {
                        StatusChip(text: "小A 看懂了整体", symbol: "sparkles", fill: Palette.teal)
                    } else if translator.refining {
                        StatusChip(text: "小A 在细看…", symbol: "sparkle.magnifyingglass", fill: Palette.teal)
                    } else {
                        StatusChip(text: "没网也能用", symbol: "checkmark", fill: Palette.teal)
                    }
                    Spacer()
                }
                .padding(.horizontal, 16)
                Spacer()
                if let tapped = selected {
                    // The latest version, in case Claude's translation arrived after the tap.
                    let block = model.photoBlocks.first(where: { $0.id == tapped.id }) ?? tapped
                    BigCaption(block: block, chinese: chinese(for: block)) { selected = nil }
                        .padding(.horizontal, 16)
                } else {
                    hintBubble
                }
                controls
            }
        }
        .translationTask(LookModel.usesDemo ? nil : translator.configuration) { session in
            await translator.run(session)
        }
        .task {
            if LookModel.usesDemo { return }      // no camera in the simulator demo
            let allowed = await model.requestCamera()
            cameraAllowed = allowed
            if allowed {
                try? await Task.sleep(nanoseconds: 300_000_000)
                model.start()
            }
        }
        .onChange(of: model.boxes) { _, boxes in
            translator.request(boxes.map(\.source))
            translator.noteVisible(boxes
                .sorted { ($0.rect.minY, $0.rect.minX) < ($1.rect.minY, $1.rect.minX) }
                .map(\.source))
        }
        .task {
            if !LookModel.usesDemo { await translator.refineWhileSteady() }
        }
        .onChange(of: model.photoBlocks) { _, blocks in
            // The phone's own translation shows at once; Claude's replaces it when it arrives.
            translator.request(blocks.filter { $0.chinese == nil }.map(\.english))
        }
        .onChange(of: model.frozen) { _, frozen in
            if !frozen { selected = nil }
        }
        .onDisappear {
            model.setTorch(false)
            speaker.stop()
        }
    }

    // MARK: Camera + overlay

    @ViewBuilder private var cameraLayer: some View {
        if LookModel.usesDemo {
            demoLayer
        } else if !LookModel.isSupported {
            unavailable("这台手机不支持实时翻译。可以用“问一问”拍照提问。")
        } else if cameraAllowed == false {
            unavailable("需要打开相机权限。请让 Alex 在 iPhone 设置 › 小A 里打开“相机”。")
        } else {
            ZStack {
                LiveTextScanner(model: model)
                if let image = model.frozenImage {
                    Image(uiImage: image).resizable().scaledToFill()
                        .frame(maxWidth: .infinity, maxHeight: .infinity).clipped()
                }
                if let image = model.frozenImage, !model.photoBlocks.isEmpty {
                    photoOverlay(image)
                } else {
                    overlay
                }
            }
        }
    }

    private var overlay: some View {
        GeometryReader { geo in
            ZStack(alignment: .topLeading) {
                ForEach(model.boxes) { box in
                    let zh = translator.translation(for: box.source)
                    OverlayLabel(text: model.showEnglish ? box.source : (zh ?? box.source),
                                 rect: box.rect,
                                 containerWidth: geo.size.width,
                                 waiting: zh == nil && !model.showEnglish) {
                        if let zh { speaker.speakChinese(zh) }
                    }
                    .accessibilityLabel(zh ?? box.source)
                }
            }
            .frame(width: geo.size.width, height: geo.size.height, alignment: .topLeading)
        }
        .animation(.easeOut(duration: 0.12), value: model.boxes)
    }

    /// The frozen photo, read carefully: one label per paragraph, translated in context.
    private func photoOverlay(_ image: UIImage) -> some View {
        GeometryReader { geo in
            ZStack(alignment: .topLeading) {
                ForEach(model.photoBlocks.filter { !$0.hidden }) { block in
                    let rect = Demo.viewRect(for: block.rect, imageSize: image.size, in: geo.size)
                    let zh = chinese(for: block)
                    ParagraphLabel(text: model.showEnglish ? block.english : (zh ?? block.english),
                                   rect: rect, lines: block.lines,
                                   waiting: zh == nil && !model.showEnglish,
                                   isSelected: selected?.id == block.id) {
                        selected = block
                        if let zh { speaker.speakChinese(zh) }
                    }
                    .accessibilityLabel(zh ?? block.english)
                }
            }
            .frame(width: geo.size.width, height: geo.size.height, alignment: .topLeading)
        }
        .animation(.easeOut(duration: 0.2), value: model.photoBlocks)
    }

    /// Claude's translation if it has arrived, otherwise the phone's own.
    private func chinese(for block: PhotoBlock) -> String? {
        block.chinese ?? translator.translation(for: block.english)
    }

    /// Simulator demo: a photo of a pharmacy sign with the same Chinese labels the camera would show.
    private var demoLayer: some View {
        GeometryReader { geo in
            let image = Demo.signImage
            ZStack(alignment: .topLeading) {
                if let image {
                    Image(uiImage: image).resizable().scaledToFill()
                        .frame(width: geo.size.width, height: geo.size.height).clipped()
                }
                ForEach(Demo.signLines) { line in
                    OverlayLabel(text: model.showEnglish ? line.en : line.zh,
                                 rect: Demo.viewRect(for: line.rect, imageSize: image?.size ?? .zero, in: geo.size),
                                 containerWidth: geo.size.width,
                                 waiting: false) {
                        speaker.speakChinese(line.zh)
                    }
                    .accessibilityLabel(line.zh)
                }
            }
        }
    }

    private func unavailable(_ text: String) -> some View {
        VStack {
            Spacer()
            Text(text).font(.xa(22, .bold)).foregroundStyle(.white).multilineTextAlignment(.center).padding(32)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: Bottom

    private var hintBubble: some View {
        HStack(alignment: .bottom, spacing: 6) {
            Mascot(size: 58)
            Text(hint)
                .font(.xa(20, .bold))
                .foregroundStyle(Palette.ink)
                .padding(.horizontal, 14).padding(.vertical, 8)
                .background(UnevenRoundedRectangle(topLeadingRadius: 18, bottomLeadingRadius: 6,
                                                   bottomTrailingRadius: 18, topTrailingRadius: 18).fill(.white))
                .padding(.bottom, 8)
            Spacer()
            if LookModel.usesDemo { DemoTag().padding(.bottom, 14) }
        }
        .padding(.horizontal, 16)
    }

    private var hint: String {
        if LookModel.usesDemo { return model.frozen ? "定住了，点中文可以朗读" : "点中文可以朗读" }
        if translator.needsDownload { return "第一次用要下载翻译，请连上 Wi-Fi" }
        if let problem = model.problem { return problem }
        if model.readingClearly { return "小A 正在仔细看，马上就好" }
        if model.frozen, let what = model.photoWhat { return "这是\(what)。点中文可以放大、朗读" }
        if model.frozen && model.claudeFailed { return "没连上网，先用手机自己的翻译" }
        if model.frozen { return "定住了，点中文可以放大、朗读" }
        if model.boxes.isEmpty { return model.zoomed ? "放大了，对准小字" : "对准英文就行" }
        if !translator.allInContext && APIKeys.get(.anthropic) != nil { return "拿稳一点，小A 翻得更准" }
        return "点中文可以朗读"
    }

    private var controls: some View {
        VStack(spacing: 14) {
            if model.frozen {
                HStack(spacing: 12) {
                    SoftButton(title: "继续看", systemImage: "play.fill", height: 72, fontSize: 24) {
                        model.resume()
                    }
                    BigButton(title: "问问这张", systemImage: "questionmark.bubble",
                              fill: Palette.teal, depth: Palette.tealDeep, fontSize: 24) {
                        app.ask(about: model.frozenImage)
                    }
                }
            } else {
                BigButton(title: "定住画面", systemImage: "pause.fill") {
                    Task { await model.freeze() }
                }
            }
            HStack(spacing: 10) {
                ControlTile(title: "朗读", symbol: "speaker.wave.2.fill") { readAll() }
                ControlTile(title: model.showEnglish ? "看中文" : "看英文", symbol: "eye") {
                    model.showEnglish.toggle()
                }
                ControlTile(title: model.zoomed ? "还原" : "放大",
                            symbol: model.zoomed ? "minus.magnifyingglass" : "plus.magnifyingglass") {
                    model.setZoom(!model.zoomed)
                }
                .disabled(model.frozen)
                ControlTile(title: model.torchOn ? "关手电" : "手电筒",
                            symbol: model.torchOn ? "flashlight.on.fill" : "flashlight.off.fill") {
                    model.setTorch(!model.torchOn)
                }
                .disabled(model.frozen)
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 20)
        .padding(.bottom, 12)
        .background(
            UnevenRoundedRectangle(topLeadingRadius: 30, topTrailingRadius: 30).fill(.white)
                .ignoresSafeArea(edges: .bottom)
        )
    }

    /// Reads every translated line, top to bottom.
    private func readAll() {
        if LookModel.usesDemo {
            speaker.speakChinese(Demo.signLines.map(\.zh).joined(separator: "。"))
            return
        }
        if model.frozen && !model.photoBlocks.isEmpty {
            let parts = model.photoBlocks
                .filter { !$0.hidden }
                .sorted { ($0.rect.minY, $0.rect.minX) < ($1.rect.minY, $1.rect.minX) }
                .compactMap { chinese(for: $0) }
            let intro = model.photoWhat.map { "这是\($0)。" } ?? ""
            speaker.speakChinese(intro + parts.joined(separator: "。"))
            return
        }
        let lines = model.boxes
            .sorted { ($0.rect.minY, $0.rect.minX) < ($1.rect.minY, $1.rect.minX) }
            .compactMap { translator.translation(for: $0.source) }
        if lines.isEmpty {
            speaker.speakChinese("还没看到英文，请对准一点。")
        } else {
            speaker.speakChinese(lines.joined(separator: "。"))
        }
    }
}

/// White label laid over the English it translates. Tap to hear it.
/// It starts where the English starts and may grow wider to fit the Chinese at a size Mom can
/// read, wrapping to a second line rather than running off the screen.
private struct OverlayLabel: View {
    var text: String
    var rect: CGRect
    var containerWidth: CGFloat
    var waiting: Bool
    var onTap: () -> Void

    var body: some View {
        let x = min(max(rect.minX, 6), max(6, containerWidth - 62))
        let room = max(56, containerWidth - x - 6)
        Button(action: onTap) {
            Text(text)
                .font(.system(size: max(17, min(rect.height * 0.8, 32)), weight: .heavy, design: .rounded))
                .foregroundStyle(waiting ? Palette.ink2 : Palette.ink)
                .lineLimit(2)
                .minimumScaleFactor(0.8)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 6)
                .frame(minWidth: min(max(rect.width, 56), room), maxWidth: room, minHeight: max(rect.height, 30))
                .fixedSize(horizontal: true, vertical: false)
                .background(RoundedRectangle(cornerRadius: 8).fill(Color.white))
                .shadow(color: .black.opacity(0.18), radius: 3, y: 1)
        }
        .buttonStyle(.plain)
        .offset(x: x, y: rect.minY)
    }
}

private struct StatusChip: View {
    var text: String
    var symbol: String
    var fill: Color
    var body: some View {
        Label(text, systemImage: symbol)
            .font(.xa(17, .bold))
            .foregroundStyle(.white)
            .padding(.horizontal, 12)
            .frame(height: 36)
            .background(Capsule().fill(fill))
    }
}

private struct ControlTile: View {
    var title: String
    var symbol: String
    var action: () -> Void
    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: symbol).font(.system(size: 26, weight: .semibold))
                Text(title).font(.xa(19, .heavy))
            }
            .foregroundStyle(Palette.ink)
            .frame(maxWidth: .infinity, minHeight: 84)
            .background(RoundedRectangle(cornerRadius: 22, style: .continuous).fill(Palette.cream))
            .opacity(isEnabled ? 1 : 0.45)
        }
        .buttonStyle(Squish())
    }
}

/// One paragraph on the frozen photo: a white card over the English, Chinese inside.
/// Small print gets a small card; tap it to see it big.
private struct ParagraphLabel: View {
    var text: String
    var rect: CGRect
    var lines: Int
    var waiting: Bool
    var isSelected: Bool
    var onTap: () -> Void

    var body: some View {
        let width = max(rect.width, 64)
        let height = max(rect.height, 26)
        let lineHeight = height / CGFloat(max(lines, 1))
        Button(action: onTap) {
            Text(text)
                .font(.system(size: max(13, min(lineHeight * 0.8, 30)), weight: .heavy, design: .rounded))
                .foregroundStyle(waiting ? Palette.ink2 : Palette.ink)
                .minimumScaleFactor(0.45)
                .multilineTextAlignment(.leading)
                .padding(.horizontal, 4)
                .frame(width: width, height: height, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 6).fill(Color.white.opacity(0.96)))
                .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(isSelected ? Palette.teal : .clear, lineWidth: 3))
                .shadow(color: .black.opacity(0.18), radius: 2, y: 1)
        }
        .buttonStyle(.plain)
        .offset(x: rect.minX - (width - rect.width) / 2, y: rect.minY - (height - rect.height) / 2)
    }
}

/// The tapped paragraph, big enough to read: Chinese on top, the English underneath.
private struct BigCaption: View {
    var block: PhotoBlock
    var chinese: String?
    var onClose: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top) {
                Text(chinese ?? "…")
                    .font(.xa(26, .heavy)).foregroundStyle(Palette.ink)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Button(action: onClose) {
                    Image(systemName: "xmark").font(.system(size: 18, weight: .heavy))
                        .foregroundStyle(Palette.ink2)
                        .frame(width: 44, height: 44)
                        .background(Circle().fill(Palette.cream))
                }
                .accessibilityLabel("关上")
            }
            Text(block.english)
                .font(.system(size: 16, weight: .semibold, design: .rounded))
                .foregroundStyle(Palette.ink2)
                .lineLimit(4)
        }
        .padding(16)
        .frame(maxHeight: 260)
        .background(RoundedRectangle(cornerRadius: 22, style: .continuous).fill(.white))
        .padding(.bottom, 8)
    }
}
