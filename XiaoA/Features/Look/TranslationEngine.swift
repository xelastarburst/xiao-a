import SwiftUI
import Translation

/// English → Simplified Chinese for 看一看, in two layers:
/// 1. On-device (Apple), instant and offline, one line at a time.
/// 2. In context (Claude): when the camera rests on something for a moment, everything in view
///    is translated together, so a menu reads like a menu and a label like a label. These replace
///    the on-device lines as they arrive.
/// Lives inside a `.translationTask` so the on-device session stays open while the camera is on.
@MainActor
final class TranslationEngine: ObservableObject {
    @Published private(set) var cache: [String: String] = [:]
    /// Claude's translations, made with everything else in view as context.
    @Published private(set) var contextual: [String: String] = [:]
    @Published var needsDownload = false
    /// Claude is translating what's in view right now.
    @Published private(set) var refining = false

    /// What the camera sees, top to bottom, and when something new last appeared.
    private var visible: [String] = []
    private var lastNewText = Date()
    private var lastRefine = Date.distantPast

    let configuration = TranslationSession.Configuration(
        source: Locale.Language(identifier: "en"),
        target: Locale.Language(identifier: "zh-Hans")
    )

    private var pending = Set<String>()
    private var continuation: AsyncStream<[String]>.Continuation?

    func translation(for text: String) -> String? {
        if let inContext = contextual[text], !inContext.isEmpty { return inContext }
        return cache[text]
    }

    /// True when everything in view has its in-context translation.
    var allInContext: Bool { !visible.isEmpty && visible.allSatisfy { contextual[$0] != nil } }

    /// What the camera sees now, top to bottom.
    func noteVisible(_ texts: [String]) {
        if !Set(texts).isSubset(of: Set(visible)) { lastNewText = Date() }
        visible = texts
    }

    /// Runs while the camera is on: once it has rested on the same text for a moment, Claude
    /// translates everything in view together. Text already done is reused, so holding still
    /// costs one quick request, not a stream of them.
    func refineWhileSteady() async {
        while !Task.isCancelled {
            try? await Task.sleep(nanoseconds: 300_000_000)
            guard !refining, APIKeys.get(.anthropic) != nil else { continue }
            let missing = visible.filter { contextual[$0] == nil }
            guard !missing.isEmpty,
                  Date().timeIntervalSince(lastNewText) > 0.7,
                  Date().timeIntervalSince(lastRefine) > 1.5 else { continue }
            refining = true
            lastRefine = Date()
            let texts = Array(visible.prefix(40))
            let started = Date()
            do {
                let result = try await ClearRead.translateInContext(texts)
                // Empty = Claude skipped it as not real text; keep the on-device line, don't ask again.
                for english in texts { contextual[english] = result[english] ?? "" }
                print(String(format: "[XA] Look live: %ld lines in context in %.1fs", result.count, Date().timeIntervalSince(started)))
            } catch {
                print("[XA] Look live: Claude failed: \(error)")
                lastRefine = Date().addingTimeInterval(8)   // offline or no key: back off
            }
            refining = false
        }
    }

    /// Ask for translations of any lines we haven't seen yet.
    func request(_ texts: [String]) {
        let fresh = texts.filter { cache[$0] == nil && !pending.contains($0) }
        guard !fresh.isEmpty, let continuation else { return }
        fresh.forEach { pending.insert($0) }
        continuation.yield(Array(Set(fresh)))
    }

    /// Runs for as long as the screen is open.
    func run(_ session: TranslationSession) async {
        let (stream, cont) = AsyncStream<[String]>.makeStream()
        continuation = cont
        defer {
            continuation = nil
            pending.removeAll()
        }
        do {
            try await session.prepareTranslation()
        } catch {
            needsDownload = true
        }
        for await batch in stream {
            let requests = batch.map { TranslationSession.Request(sourceText: $0, clientIdentifier: $0) }
            do {
                let responses = try await session.translations(from: requests)
                for response in responses {
                    if let key = response.clientIdentifier { cache[key] = response.targetText }
                }
            } catch {
                needsDownload = true
            }
            batch.forEach { pending.remove($0) }
        }
    }
}
