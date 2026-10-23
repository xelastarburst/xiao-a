import SwiftUI

/// Lesen: point the camera at English and see German laid over it, live and offline.
struct LookView: View {
    @EnvironmentObject private var app: AppState
    @StateObject private var model = LookModel()
    @StateObject private var translator = TranslationEngine()
    @StateObject private var speaker = Speaker.shared
    @State private var cameraAllowed: Bool?
    /// A paragraph she tapped on the frozen photo, shown big.
    @State private var selected: PhotoBlock?

    var body: some View {
        ZStack(alignment: .top) {
            Color(hex: 0x1E1814).ignoresSafeArea()

            cameraLayer
                .ignoresSafeArea(edges: .top)

            VStack(spacing: 8) {
                TopBar(title: "Lesen", onDark: true)
                HStack {
                    if model.readingClearly {
                        StatusChip(text: "Ich lese genau…", symbol: "sparkle.magnifyingglass", fill: Palette.teal)
                    } else if model.frozen {
                        StatusChip(text: "Bild angehalten", symbol: "pause.fill", fill: Color.black.opacity(0.75))
                    } else if translator.allInContext {
                        StatusChip(text: "Im Zusammenhang übersetzt", symbol: "sparkles", fill: Palette.teal)
                    } else if translator.refining {
                        StatusChip(text: "Ich schaue genauer…", symbol: "sparkle.magnifyingglass", fill: Palette.teal)
                    } else {
                        StatusChip(text: "Geht auch ohne Internet", symbol: "checkmark", fill: Palette.teal)
                    }
                    Spacer()
                }
                .padding(.horizontal, 16)
                Spacer()
                if let tapped = selected {
                    // The latest version, in case Claude's translation arrived after the tap.
                    let block = model.photoBlocks.first(where: { $0.id == tapped.id }) ?? tapped
                    BigCaption(block: block, translated: translated(for: block)) { selected = nil }
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
            translator.request(blocks.filter { $0.translated == nil }.map(\.english))
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
            unavailable("Dieses iPhone kann nicht live übersetzen. Sie können mit „Fragen“ ein Foto schicken.")
        } else if cameraAllowed == false {
            unavailable("Die Kamera ist nicht erlaubt. Bitte lassen Sie Ihre Familie in den iPhone-Einstellungen › Helferlein die „Kamera“ einschalten.")
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
                        if let zh { speaker.speakGerman(zh) }
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
                    let zh = translated(for: block)
                    ParagraphLabel(text: model.showEnglish ? block.english : (zh ?? block.english),
                                   rect: rect, lines: block.lines,
                                   waiting: zh == nil && !model.showEnglish,
                                   isSelected: selected?.id == block.id) {
                        selected = block
                        if let zh { speaker.speakGerman(zh) }
                    }
                    .accessibilityLabel(zh ?? block.english)
                }
            }
            .frame(width: geo.size.width, height: geo.size.height, alignment: .topLeading)
        }
        .animation(.easeOut(duration: 0.2), value: model.photoBlocks)
    }

    /// Claude's translation if it has arrived, otherwise the phone's own.
    private func translated(for block: PhotoBlock) -> String? {
        block.translated ?? translator.translation(for: block.english)
    }

    /// Simulator demo: a photo of a pharmacy sign with the same German labels the camera would show.
    private var demoLayer: some View {
        GeometryReader { geo in
            let image = Demo.signImage
            ZStack(alignment: .topLeading) {
                if let image {
                    Image(uiImage: image).resizable().scaledToFill()
                        .frame(width: geo.size.width, height: geo.size.height).clipped()
                }
                ForEach(Demo.signLines) { line in
                    OverlayLabel(text: model.showEnglish ? line.en : line.de,
                                 rect: Demo.viewRect(for: line.rect, imageSize: image?.size ?? .zero, in: geo.size),
                                 containerWidth: geo.size.width,
                                 waiting: false) {
                        speaker.speakGerman(line.de)
                    }
                    .accessibilityLabel(line.de)
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
        if LookModel.usesDemo { return model.frozen ? "Angehalten. Tippen Sie auf Deutsch zum Vorlesen" : "Tippen Sie auf Deutsch zum Vorlesen" }
        if translator.needsDownload { return "Beim ersten Mal wird die Übersetzung geladen. Bitte mit WLAN verbinden" }
        if let problem = model.problem { return problem }
        if model.readingClearly { return "Ich lese genau, gleich fertig" }
        if model.frozen, let what = model.photoWhat { return "Das ist \(what). Tippen zum Vergrößern und Vorlesen" }
        if model.frozen && model.claudeFailed { return "Kein Internet: das iPhone übersetzt selbst" }
        if model.frozen { return "Angehalten. Tippen zum Vergrößern und Vorlesen" }
        if model.boxes.isEmpty { return model.zoomed ? "Vergrößert: auf die kleine Schrift halten" : "Einfach auf Englisch halten" }
        if !translator.allInContext && APIKeys.get(.anthropic) != nil { return "Ruhig halten, dann wird es genauer" }
        return "Tippen Sie auf Deutsch zum Vorlesen"
    }

    private var controls: some View {
        VStack(spacing: 14) {
            if model.frozen {
                HStack(spacing: 12) {
                    SoftButton(title: "Weiter", systemImage: "play.fill", height: 72, fontSize: 24) {
                        model.resume()
                    }
                    BigButton(title: "Dazu fragen", systemImage: "questionmark.bubble",
                              fill: Palette.teal, depth: Palette.tealDeep, fontSize: 24) {
                        app.ask(about: model.frozenImage)
                    }
                }
            } else {
                BigButton(title: "Bild anhalten", systemImage: "pause.fill") {
                    Task { await model.freeze() }
                }
            }
            HStack(spacing: 10) {
                ControlTile(title: "Vorlesen", symbol: "speaker.wave.2.fill") { readAll() }
                ControlTile(title: model.showEnglish ? "Deutsch" : "Englisch", symbol: "eye") {
                    model.showEnglish.toggle()
                }
                ControlTile(title: model.zoomed ? "Normal" : "Vergrößern",
                            symbol: model.zoomed ? "minus.magnifyingglass" : "plus.magnifyingglass") {
                    model.setZoom(!model.zoomed)
                }
                .disabled(model.frozen)
                ControlTile(title: model.torchOn ? "Licht aus" : "Licht",
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
            speaker.speakGerman(Demo.signLines.map(\.de).joined(separator: ". "))
            return
        }
        if model.frozen && !model.photoBlocks.isEmpty {
            let parts = model.photoBlocks
                .filter { !$0.hidden }
                .sorted { ($0.rect.minY, $0.rect.minX) < ($1.rect.minY, $1.rect.minX) }
                .compactMap { translated(for: $0) }
            let intro = model.photoWhat.map { "Das ist \($0). " } ?? ""
            speaker.speakGerman(intro + parts.joined(separator: ". "))
            return
        }
        let lines = model.boxes
            .sorted { ($0.rect.minY, $0.rect.minX) < ($1.rect.minY, $1.rect.minX) }
            .compactMap { translator.translation(for: $0.source) }
        if lines.isEmpty {
            speaker.speakGerman("Ich sehe noch kein Englisch. Bitte halten Sie die Kamera darauf.")
        } else {
            speaker.speakGerman(lines.joined(separator: ". "))
        }
    }
}

/// White label laid over the English it translates. Tap to hear it.
/// It starts where the English starts and may grow wider to fit the German at a size she can
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
                .lineLimit(3)
                .minimumScaleFactor(0.65)
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
                Text(title).font(.xa(18, .heavy))
                    .lineLimit(1).minimumScaleFactor(0.6)
            }
            .foregroundStyle(Palette.ink)
            .frame(maxWidth: .infinity, minHeight: 84)
            .background(RoundedRectangle(cornerRadius: 22, style: .continuous).fill(Palette.cream))
            .opacity(isEnabled ? 1 : 0.45)
        }
        .buttonStyle(Squish())
    }
}

/// One paragraph on the frozen photo: a white card over the English, German inside.
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

/// The tapped paragraph, big enough to read: German on top, the English underneath.
private struct BigCaption: View {
    var block: PhotoBlock
    var translated: String?
    var onClose: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top) {
                Text(translated ?? "…")
                    .font(.xa(26, .heavy)).foregroundStyle(Palette.ink)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Button(action: onClose) {
                    Image(systemName: "xmark").font(.system(size: 18, weight: .heavy))
                        .foregroundStyle(Palette.ink2)
                        .frame(width: 44, height: 44)
                        .background(Circle().fill(Palette.cream))
                }
                .accessibilityLabel("Schließen")
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
