import SwiftUI

@MainActor
final class AskModel: ObservableObject {
    struct Turn: Identifiable, Equatable {
        let id = UUID()
        var fromMom: Bool
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

    var latestAnswer: Turn? { turns.last(where: { !$0.fromMom && !$0.text.isEmpty }) }

    func question(before answer: Turn) -> String? {
        guard let i = turns.firstIndex(of: answer) else { return nil }
        return turns[..<i].last(where: { $0.fromMom })?.text
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
        turns.append(Turn(fromMom: true, text: q))
        let messages = buildMessages()
        turns.append(Turn(fromMom: false, text: ""))
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
                    if i > 0, turns[i - 1].fromMom { turns.remove(at: i - 1) }
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
                                    alexName: config.alexName)
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
            if turn.fromMom {
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
        let alex = config.alexName
        var prompt = """
        你是“小A”，是\(alex)做的小助手，正在帮他的妈妈。她只会说普通话、只读简体中文，不懂英语，正在美国探亲。

        回答规则：
        - 永远用简体中文回答。口语、亲切、简短：一般不超过5行，用短句，每个要点一行，行首用“·”。
        - 不要用 Markdown 格式（不要用 **、#、表格）。
        - 有照片时，先用一句话说清楚照片上的英文是什么意思，再回答她的问题。
        - 药品和看病：只说标签或纸上写了什么。绝对不要编造剂量、次数或用法；标签上没写的就说“标签上没写”。最后提醒她：吃药前先问\(alex)或药剂师、医生。
        - 钱、账单、银行、合同、政府或官方信件：解释意思，但提醒她先别付钱、别签字、别回电话、别给别人个人信息，先问\(alex)。注意可能是诈骗。
        - 不确定就直说不确定，不要猜。
        - 如果她受伤、迷路、身体不舒服或有危险：告诉她马上按屏幕上红色的“紧急”按钮。
        """
        if !config.askContext.isEmpty {
            prompt += "\n\n\(alex)告诉你的背景：\(config.askContext)"
        }
        if !config.homeAddressEN.isEmpty {
            prompt += "\n家的地址：\(config.homeAddressEN)"
        }
        return prompt
    }
}
