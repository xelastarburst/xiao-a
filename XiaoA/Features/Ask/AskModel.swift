import SwiftUI

@MainActor
final class AskModel: ObservableObject {
    struct Turn: Identifiable, Equatable {
        let id = UUID()
        var fromHer: Bool
        var text: String
        /// Written by the simulator demo, not by Claude.
        var demo = false
    }

    @Published var image: UIImage? {
        didSet { imageBlock = image.flatMap { ClaudeClient.imageBlock($0) } }
    }
    @Published private(set) var turns: [Turn] = []
    @Published private(set) var streaming = false
    @Published var error: String?

    private var imageBlock: [String: Any]?
    private var task: Task<Void, Never>?
    private(set) var lastFailedQuestion: String?

    var latestAnswer: Turn? { turns.last(where: { !$0.fromHer && !$0.text.isEmpty }) }

    func question(before answer: Turn) -> String? {
        guard let i = turns.firstIndex(of: answer) else { return nil }
        return turns[..<i].last(where: { $0.fromHer })?.text
    }

    func startOver(with newImage: UIImage?) {
        task?.cancel()
        turns.removeAll()
        error = nil
        streaming = false
        image = newImage
    }

    func ask(_ question: String, config: AppConfig) {
        let q = question.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty, !streaming else { return }
        error = nil
        lastFailedQuestion = nil
        turns.append(Turn(fromHer: true, text: q))
        let messages = buildMessages()
        turns.append(Turn(fromHer: false, text: ""))
        let answerID = turns[turns.count - 1].id
        streaming = true
        let system = Self.systemPrompt(config)

        if Demo.isOn && APIKeys.get(.anthropic) == nil {
            playDemoAnswer(to: q, answerID: answerID, config: config)
            return
        }

        task = Task {
            do {
                let client = try ClaudeClient()
                for try await chunk in client.stream(model: ClaudeClient.Model.vision, system: system,
                                                     messages: messages, maxTokens: 700) {
                    if let i = turns.firstIndex(where: { $0.id == answerID }) { turns[i].text += chunk }
                }
            } catch is CancellationError {
            } catch {
                self.error = error.localizedDescription
                lastFailedQuestion = q
                // Drop the unanswered pair so the conversation stays valid for the next try.
                if let i = turns.firstIndex(where: { $0.id == answerID }), turns[i].text.isEmpty {
                    turns.remove(at: i)
                    if i > 0, turns[i - 1].fromHer { turns.remove(at: i - 1) }
                }
            }
            streaming = false
        }
    }

    /// Simulator demo: streams a ready-made answer in the same style the real prompt asks for.
    private func playDemoAnswer(to question: String, answerID: UUID, config: AppConfig) {
        let answer = Demo.askAnswer(question: question,
                                    aboutSign: image != nil && image === Demo.signImage,
                                    hasPhoto: image != nil,
                                    contactName: config.contactName)
        if let i = turns.firstIndex(where: { $0.id == answerID }) { turns[i].demo = true }
        task = Task {
            try? await Task.sleep(nanoseconds: 700_000_000)
            for chunk in Demo.chunks(answer) {
                if Task.isCancelled { break }
                if let i = turns.firstIndex(where: { $0.id == answerID }) { turns[i].text += chunk }
                try? await Task.sleep(nanoseconds: 35_000_000)
            }
            streaming = false
        }
    }

    private func buildMessages() -> [[String: Any]] {
        Self.messages(turns: turns, imageBlock: imageBlock)
    }

    /// The conversation for Claude: the photo goes with her first question only; empty turns are dropped.
    static func messages(turns: [Turn], imageBlock: [String: Any]?) -> [[String: Any]] {
        var messages: [[String: Any]] = []
        var attachedImage = false
        for turn in turns where !turn.text.isEmpty {
            if turn.fromHer {
                var content: [[String: Any]] = []
                if !attachedImage, let imageBlock {
                    content.append(imageBlock)
                    attachedImage = true
                }
                content.append(["type": "text", "text": turn.text])
                messages.append(["role": "user", "content": content])
            } else {
                messages.append(["role": "assistant", "content": turn.text])
            }
        }
        return messages
    }

    static func systemPrompt(_ config: AppConfig) -> String {
        let contact = config.contactLabel
        let name = config.herName.trimmingCharacters(in: .whitespaces)
        let who = name.isEmpty ? "" : " (\(name))"
        let family = config.contactName.isEmpty ? "" : " Ihre Ansprechperson in der Familie ist \(config.contactName)."
        var prompt = """
        Du bist „Helferlein“, ein kleiner Helfer auf dem iPhone einer älteren deutschen Dame\(who), \
        die in den USA lebt. Sie spricht Deutsch und kaum Englisch.\(family)

        Regeln für deine Antworten:
        - Antworte immer auf Deutsch und sprich sie mit „Sie“ an. Freundlich, einfach und kurz: meist höchstens 5 Zeilen, kurze Sätze, ein Punkt pro Zeile, jede Zeile beginnt mit „·“.
        - Kein Markdown (kein **, kein #, keine Tabellen).
        - Bei einem Foto: sag zuerst in einem Satz, was der englische Text bedeutet, dann beantworte ihre Frage.
        - Amerikanische Maßeinheiten (°F, oz, lb, Meilen, Zoll) zusätzlich in metrische umrechnen.
        - Medikamente und Arztsachen: sag nur, was auf dem Etikett oder Papier steht. Erfinde niemals Dosierung, Häufigkeit oder Anwendung; was nicht draufsteht: „Das steht nicht auf dem Etikett.“ Erinnere sie am Ende: vor der Einnahme zuerst \(contact), die Apotheke oder den Arzt fragen.
        - Geld, Rechnungen, Bank, Verträge, Briefe von Behörden: erkläre die Bedeutung, aber erinnere sie: noch nichts bezahlen, nichts unterschreiben, nicht zurückrufen, keine persönlichen Daten weitergeben, zuerst \(contact) fragen. Es könnte Betrug sein.
        - Wenn du unsicher bist, sag das ehrlich. Nicht raten.
        - Wenn sie verletzt ist, sich verlaufen hat, sich nicht wohlfühlt oder in Gefahr ist: sag ihr, sie soll sofort den roten „Notfall“-Knopf auf dem Bildschirm drücken.
        """
        if !config.askContext.isEmpty {
            prompt += "\n\nHintergrund von \(contact): \(config.askContext)"
        }
        if !config.homeAddressEN.isEmpty {
            prompt += "\nAdresse zu Hause: \(config.homeAddressEN)"
        }
        return prompt
    }
}
