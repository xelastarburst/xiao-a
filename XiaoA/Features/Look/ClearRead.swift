import UIKit
import Vision

/// One paragraph of English found in a still photo.
struct PhotoBlock: Identifiable, Equatable {
    let id: Int
    /// Where it is, in fractions of the photo (origin top-left).
    var rect: CGRect
    var english: String
    var lines: Int
    /// Claude's translation, made with the whole photo in view. Nil until it arrives.
    var chinese: String?
    /// Claude says it isn't real text (stray letters, a barcode): don't cover it.
    var hidden = false
}

/// 定住画面 → read the full-resolution photo carefully (small print included), then have
/// Claude translate it with the whole picture in view, so a menu reads like a menu and a
/// medicine label like a medicine label.
enum ClearRead {
    /// Every line of English in the photo, grouped into paragraphs.
    static func readText(in image: UIImage) async -> [PhotoBlock] {
        guard let cgImage = image.cgImage else { return [] }
        let orientation = CGImagePropertyOrientation(image.imageOrientation)
        return await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let request = VNRecognizeTextRequest()
                request.recognitionLevel = .accurate
                request.recognitionLanguages = ["en-US"]
                request.usesLanguageCorrection = true
                // Default ignores text under 1/32 of the photo's height; read fine print too.
                request.minimumTextHeight = 0.006
                let handler = VNImageRequestHandler(cgImage: cgImage, orientation: orientation)
                try? handler.perform([request])
                let lines: [(text: String, rect: CGRect)] = (request.results ?? []).compactMap { observation in
                    guard let best = observation.topCandidates(1).first, best.confidence >= 0.3 else { return nil }
                    let text = best.string.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard text.rangeOfCharacter(from: .letters) != nil else { return nil }
                    let b = observation.boundingBox
                    return (text, CGRect(x: b.minX, y: 1 - b.maxY, width: b.width, height: b.height))
                }
                continuation.resume(returning: paragraphs(from: lines))
            }
        }
    }

    /// Lines that sit right under each other, overlap sideways and are about the same size
    /// belong to one paragraph, so a sentence that wraps is translated as one sentence.
    static func paragraphs(from lines: [(text: String, rect: CGRect)]) -> [PhotoBlock] {
        var blocks: [PhotoBlock] = []
        var lastLine: [Int: CGRect] = [:]
        for line in lines.sorted(by: { $0.rect.minY < $1.rect.minY }) {
            let r = line.rect
            let match = blocks.indices.last { i in
                guard let prev = lastLine[i] else { return false }
                let gap = r.minY - prev.maxY
                let ratio = r.height / max(prev.height, 0.0001)
                let overlaps = r.minX < blocks[i].rect.maxX && r.maxX > blocks[i].rect.minX
                return gap > -0.5 * r.height && gap < 0.9 * max(r.height, prev.height)
                    && ratio > 0.6 && ratio < 1.6 && overlaps
            }
            if let i = match {
                let joiner = blocks[i].english.hasSuffix("-") ? "" : " "
                if joiner.isEmpty { blocks[i].english.removeLast() }
                blocks[i].english += joiner + line.text
                blocks[i].rect = blocks[i].rect.union(r)
                blocks[i].lines += 1
                lastLine[i] = r
            } else {
                blocks.append(PhotoBlock(id: blocks.count + 1, rect: r, english: line.text, lines: 1))
                lastLine[blocks.count - 1] = r
            }
        }
        return blocks
    }

    struct Result {
        /// What the photo shows, in a few Chinese words (e.g. "药瓶上的标签").
        var what: String?
        var chinese: [Int: String]
    }

    /// Claude translates every paragraph at once, seeing the photo.
    static func translate(_ blocks: [PhotoBlock], photo: UIImage) async throws -> Result {
        let client = try ClaudeClient()
        guard let image = ClaudeClient.imageBlock(photo) else { return Result(chinese: [:]) }
        let list = blocks.map { "\($0.id): \($0.english)" }.joined(separator: "\n")
        let messages: [[String: Any]] = [[
            "role": "user",
            "content": [image, ["type": "text", "text": "Text blocks found in this photo:\n\(list)"]]
        ]]
        let reply = try await client.complete(model: ClaudeClient.Model.vision, system: systemPrompt,
                                              messages: messages, maxTokens: 2500)
        let result = parse(reply)
        if result.chinese.isEmpty { print("[XA] Look: couldn't read Claude's reply: \(reply.prefix(300))") }
        return result
    }

    /// Live mode: everything the camera sees right now, translated together (text only, fast).
    /// Returns English → Chinese for each piece.
    static func translateInContext(_ texts: [String]) async throws -> [String: String] {
        guard !texts.isEmpty else { return [:] }
        let client = try ClaudeClient()
        let list = texts.enumerated().map { "\($0.offset + 1): \($0.element)" }.joined(separator: "\n")
        let messages: [[String: Any]] = [["role": "user", "content": "Text pieces seen together, top to bottom:\n\(list)"]]
        let reply = try await client.complete(model: ClaudeClient.Model.fast, system: liveSystemPrompt,
                                              messages: messages, maxTokens: 1500)
        let parsed = parse(reply)
        if parsed.chinese.isEmpty { print("[XA] Look live: couldn't read Claude's reply: \(reply.prefix(300))") }
        var out: [String: String] = [:]
        for (i, text) in texts.enumerated() {
            if let zh = parsed.chinese[i + 1] { out[text] = zh.trimmingCharacters(in: .whitespacesAndNewlines) }
        }
        return out
    }

    static let liveSystemPrompt = """
    You translate English into Simplified Chinese for an elderly woman from mainland China who reads \
    no English. The numbered pieces were read by her phone's camera from one thing she is looking at \
    right now (a sign, menu, label, screen, form or page), listed top to bottom. Pieces may be cut off \
    or contain small reading mistakes.

    Translate each piece into short, natural Simplified Chinese, using the other pieces to understand \
    what the thing is and what each piece means there. Keep numbers, prices, times, dates, doses and \
    phone numbers exactly; brand names stay in English. Translate only what is written. If a piece is \
    not meaningful text, give an empty string.

    Reply in plain text, nothing else: one line per piece, in order: the piece number, a colon, the \
    Chinese. Leave it empty after the colon for a piece that is not meaningful text. Example:
    1: 今日特价
    2: 拿铁咖啡 $4.50
    3:
    """

    static let systemPrompt = """
    You translate English in photos into Simplified Chinese for an elderly woman from mainland China \
    who reads no English. You get a photo and the text blocks a text reader found in it, numbered.

    Translate every block into natural, plain Simplified Chinese that fits what the thing is \
    (a menu, a medicine label, a sign, a form, a letter, a product). Use the photo to fix reading \
    mistakes and to understand context, abbreviations and units. Keep numbers, prices, times, dates, \
    doses and phone numbers exactly as written; you may add Chinese units (e.g. "每天 2 次"). Keep \
    brand and product names in English and add a short Chinese description in brackets when it helps. \
    Translate only what is written: no advice, no extra information. If a block is not meaningful \
    text (stray letters, part of a logo, a barcode), give an empty string for it.

    Reply in plain text, nothing else. First line: WHAT: <what the photo shows, at most 10 Chinese \
    characters>. Then one line per block, in order: the block number, a colon, the Chinese. Leave it \
    empty after the colon for a block that is not meaningful text. Example:
    WHAT: 药瓶标签
    1: 布洛芬
    2: 每次 1 片，每天 3 次
    3:
    """

    /// Reads "WHAT: …" and "1: …" lines. Plain lines can't break the way JSON does when a
    /// translation contains quotes.
    static func parse(_ reply: String) -> Result {
        var what: String?
        var chinese: [Int: String] = [:]
        for raw in reply.split(whereSeparator: \.isNewline) {
            let line = raw.trimmingCharacters(in: .whitespaces)
            let upper = line.uppercased()
            if upper.hasPrefix("WHAT:") || upper.hasPrefix("WHAT：") {
                let text = line.dropFirst(5).trimmingCharacters(in: .whitespaces)
                if !text.isEmpty { what = text }
                continue
            }
            let digits = line.prefix(while: { $0.isASCII && $0.isNumber })
            guard !digits.isEmpty, digits.count <= 3, let id = Int(digits) else { continue }
            let rest = line.dropFirst(digits.count).drop(while: { $0 == " " })
            guard let separator = rest.first, ":：.、)".contains(separator) else { continue }
            chinese[id] = rest.dropFirst().trimmingCharacters(in: .whitespaces)
        }
        return Result(what: what, chinese: chinese)
    }
}

extension CGImagePropertyOrientation {
    init(_ orientation: UIImage.Orientation) {
        switch orientation {
        case .up: self = .up
        case .down: self = .down
        case .left: self = .left
        case .right: self = .right
        case .upMirrored: self = .upMirrored
        case .downMirrored: self = .downMirrored
        case .leftMirrored: self = .leftMirrored
        case .rightMirrored: self = .rightMirrored
        @unknown default: self = .up
        }
    }
}
