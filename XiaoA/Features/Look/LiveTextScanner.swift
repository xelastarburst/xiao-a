import SwiftUI
import VisionKit
import AVFoundation

/// One block of English text the camera currently sees, in the scanner view's coordinates.
struct TextBox: Identifiable, Equatable {
    let id: UUID
    var rect: CGRect
    var source: String
}

@MainActor
final class LookModel: ObservableObject {
    @Published var boxes: [TextBox] = []
    @Published var frozen = false
    @Published var frozenImage: UIImage?
    @Published var showEnglish = false
    @Published var torchOn = false
    @Published var zoomed = false
    @Published var problem: String?
    /// After 定住画面: paragraphs read from the full-resolution photo, translated in context.
    @Published var photoBlocks: [PhotoBlock] = []
    @Published var readingClearly = false
    /// What Claude says the photo shows, e.g. "药瓶上的标签".
    @Published var photoWhat: String?
    @Published var claudeFailed = false
    private var freezeID = UUID()

    weak var scanner: DataScannerViewController?

    static var isSupported: Bool {
        DataScannerViewController.isSupported
    }

    /// Simulator demo: no live-text scanner, so 看一看 shows a photo of a sign instead.
    static var usesDemo: Bool { Demo.isOn && !isSupported }

    func requestCamera() async -> Bool {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized: return true
        case .notDetermined: return await AVCaptureDevice.requestAccess(for: .video)
        default: return false
        }
    }

    func update(from items: [RecognizedItem]) {
        guard !frozen else { return }
        boxes = items.compactMap { item in
            guard case .text(let text) = item else { return nil }
            let t = text.transcript.trimmingCharacters(in: .whitespacesAndNewlines)
            guard t.rangeOfCharacter(from: .letters) != nil else { return nil }
            let b = text.bounds
            let xs = [b.topLeft.x, b.topRight.x, b.bottomLeft.x, b.bottomRight.x]
            let ys = [b.topLeft.y, b.topRight.y, b.bottomLeft.y, b.bottomRight.y]
            let rect = CGRect(x: xs.min()!, y: ys.min()!, width: xs.max()! - xs.min()!, height: ys.max()! - ys.min()!)
            return TextBox(id: item.id, rect: rect, source: t)
        }
    }

    func start() {
        guard let scanner, !scanner.isScanning, !frozen else { return }
        do {
            try scanner.startScanning()
        } catch {
            problem = "相机暂时打不开，请再试一次。"
        }
    }

    func freeze() async {
        if Self.usesDemo {
            frozenImage = Demo.signImage
            frozen = true
            return
        }
        guard let scanner else { return }
        let id = UUID()
        freezeID = id
        let photo = try? await scanner.capturePhoto()
        frozenImage = photo
        frozen = true
        scanner.stopScanning()
        if torchOn { setTorch(false) }
        guard let photo else { return }

        // Read the full-resolution photo carefully, then translate it in context.
        readingClearly = true
        claudeFailed = false
        let blocks = await ClearRead.readText(in: photo)
        guard freezeID == id else { return }
        photoBlocks = blocks
        print("[XA] Look: \(blocks.count) paragraphs read from a \(Int(photo.size.width))x\(Int(photo.size.height)) photo")
        if !blocks.isEmpty, APIKeys.get(.anthropic) != nil {
            do {
                let started = Date()
                let result = try await ClearRead.translate(Array(blocks.prefix(40)), photo: photo)
                guard freezeID == id else { return }
                photoWhat = result.what
                for i in photoBlocks.indices {
                    guard let zh = result.chinese[photoBlocks[i].id] else { continue }
                    let clean = zh.trimmingCharacters(in: .whitespacesAndNewlines)
                    if clean.isEmpty { photoBlocks[i].hidden = true } else { photoBlocks[i].chinese = clean }
                }
                print(String(format: "[XA] Look: Claude translated %ld of %ld paragraphs in %.1fs (%@)",
                             result.chinese.count, blocks.count, Date().timeIntervalSince(started), result.what ?? "-"))
            } catch {
                guard freezeID == id else { return }
                print("[XA] Look: Claude failed: \(error)")
                claudeFailed = true
            }
        }
        readingClearly = false
    }

    func resume() {
        freezeID = UUID()
        frozen = false
        frozenImage = nil
        photoBlocks = []
        photoWhat = nil
        readingClearly = false
        claudeFailed = false
        start()
        if zoomed { setZoom(true) }
    }

    /// 放大: 2x zoom for small print.
    func setZoom(_ on: Bool) {
        zoomed = on
        guard let scanner else { return }
        scanner.zoomFactor = on ? min(2.0, scanner.maxZoomFactor) : max(1.0, scanner.minZoomFactor)
    }

    func setTorch(_ on: Bool) {
        guard let device = AVCaptureDevice.default(for: .video), device.hasTorch else { return }
        do {
            try device.lockForConfiguration()
            device.torchMode = on ? .on : .off
            device.unlockForConfiguration()
            torchOn = on
        } catch {
            torchOn = false
        }
    }
}

/// VisionKit's live text scanner: finds and tracks English text in the camera feed on-device.
struct LiveTextScanner: UIViewControllerRepresentable {
    @ObservedObject var model: LookModel

    func makeCoordinator() -> Coordinator { Coordinator(model: model) }

    func makeUIViewController(context: Context) -> DataScannerViewController {
        let vc = DataScannerViewController(
            recognizedDataTypes: [.text(languages: ["en-US"])],
            // .accurate reads small print better; it is a little slower to settle.
            qualityLevel: .accurate,
            recognizesMultipleItems: true,
            isHighFrameRateTrackingEnabled: true,
            isPinchToZoomEnabled: true,
            isGuidanceEnabled: false,
            isHighlightingEnabled: false
        )
        vc.delegate = context.coordinator
        model.scanner = vc
        return vc
    }

    func updateUIViewController(_ vc: DataScannerViewController, context: Context) {}

    static func dismantleUIViewController(_ vc: DataScannerViewController, coordinator: Coordinator) {
        vc.stopScanning()
    }

    final class Coordinator: NSObject, DataScannerViewControllerDelegate {
        let model: LookModel
        init(model: LookModel) { self.model = model }

        func dataScanner(_ dataScanner: DataScannerViewController, didAdd addedItems: [RecognizedItem], allItems: [RecognizedItem]) {
            MainActor.assumeIsolated { model.update(from: allItems) }
        }
        func dataScanner(_ dataScanner: DataScannerViewController, didUpdate updatedItems: [RecognizedItem], allItems: [RecognizedItem]) {
            MainActor.assumeIsolated { model.update(from: allItems) }
        }
        func dataScanner(_ dataScanner: DataScannerViewController, didRemove removedItems: [RecognizedItem], allItems: [RecognizedItem]) {
            MainActor.assumeIsolated { model.update(from: allItems) }
        }
        func dataScanner(_ dataScanner: DataScannerViewController, becameUnavailableWithError error: DataScannerViewController.ScanningUnavailable) {
            MainActor.assumeIsolated { model.problem = "相机暂时用不了。" }
        }
    }
}
