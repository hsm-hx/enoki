import AppKit
import EnokiCore
import os

@MainActor
protocol ConversationPresenterDelegate: AnyObject {
    /// 行を出す直前（reaction アニメーションのフック）
    func presenter(_ presenter: ConversationPresenter, willShow line: DialogueLine)
    func presenter(_ presenter: ConversationPresenter, didFinish conversation: Conversation, cancelled: Bool)
}

/// 会話を 1 行ずつ吹き出しに出す。
@MainActor
final class ConversationPresenter {

    private static let logger = Logger(subsystem: "com.enoki.mascot", category: "conversation")

    /// 行の表示時間: 2.5 秒 + 0.08 秒 × 文字数（3〜7 秒）
    static func displayDuration(for text: String) -> TimeInterval {
        min(max(2.5 + 0.08 * Double(text.count), 3.0), 7.0)
    }

    /// 行間の空白
    static let gapRange: ClosedRange<TimeInterval> = 1.5...3.0

    weak var delegate: ConversationPresenterDelegate?

    /// テスト・調整用の乱数
    var randomGap: (ClosedRange<TimeInterval>) -> TimeInterval = { range in
        range.lowerBound >= range.upperBound ? range.lowerBound : TimeInterval.random(in: range)
    }

    private let bubble = SpeechBubbleWindow()
    private var task: Task<Void, Never>?
    /// 再生ごとに増やす世代番号（古い再生の後始末が新しい再生を壊さないように）
    private var generation = 0

    private(set) var isPlaying = false

    /// 会話を再生する
    func play(_ conversation: Conversation, over parent: NSWindow) {
        cancel()
        generation += 1
        let generation = self.generation
        isPlaying = true
        Self.logger.info("会話を再生: \(conversation.id, privacy: .public) (\(conversation.lines.count)行)")

        task = Task { [weak self] in
            guard let self else { return }
            var cancelled = false
            for (index, line) in conversation.lines.enumerated() {
                if Task.isCancelled { cancelled = true; break }
                self.delegate?.presenter(self, willShow: line)
                self.bubble.show(line: line, over: parent)

                if await Self.sleep(Self.displayDuration(for: line.text)) == false {
                    cancelled = true
                    break
                }
                await self.hideBubble()
                if index < conversation.lines.count - 1 {
                    if await Self.sleep(self.randomGap(Self.gapRange)) == false {
                        cancelled = true
                        break
                    }
                }
            }
            // 古い世代（cancel() 済み）の後始末は、新しい再生の吹き出しを消さないよう何もしない
            guard generation == self.generation else { return }
            if cancelled {
                await self.hideBubble(animated: false)
            }
            self.isPlaying = false
            self.task = nil
            self.delegate?.presenter(self, didFinish: conversation, cancelled: cancelled)
        }
    }

    /// 再生を止めて吹き出しを消す
    func cancel() {
        guard let task else { return }
        self.task = nil
        task.cancel()
        isPlaying = false
        bubble.dismiss(animated: false)
    }

    // MARK: - private

    /// 眠る。キャンセルされたら false。
    private static func sleep(_ seconds: TimeInterval) async -> Bool {
        do {
            try await Task.sleep(nanoseconds: UInt64(max(0, seconds) * 1_000_000_000))
            return true
        } catch {
            return false
        }
    }

    private func hideBubble(animated: Bool = true) async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            bubble.dismiss(animated: animated) {
                continuation.resume()
            }
        }
    }
}
