import Foundation

/// 会話を 1 つ選ぶための文脈
public struct ConversationContext: Equatable, Sendable {

    /// 何がきっかけか
    public enum Trigger: String, Equatable, Sendable {
        /// スケジューラが「そろそろ話してよい」と判断した
        case scheduled
        /// メニューの「ちょっと話して」
        case manual
    }

    public var now: Date
    /// 選んでよいカテゴリ
    public var allowedCategories: Set<DialogueCategory>
    /// 最近出した会話 id（新しい順）
    public var recentlyShownIDs: [String]
    /// 直前に出した会話のカテゴリ
    public var lastCategory: DialogueCategory?
    /// 会話 id → 最後に出した時刻（クールダウン判定に使う）
    public var lastShownAt: [String: Date]
    public var trigger: Trigger
    public var activityMode: ActivityMode
    /// セッション（起動 or 仕事中モード ON）からの経過分
    public var minutesSinceSessionStart: Int

    public init(now: Date,
                allowedCategories: Set<DialogueCategory>,
                recentlyShownIDs: [String] = [],
                lastCategory: DialogueCategory? = nil,
                lastShownAt: [String: Date] = [:],
                trigger: Trigger = .scheduled,
                activityMode: ActivityMode = .work,
                minutesSinceSessionStart: Int = 0) {
        self.now = now
        self.allowedCategories = allowedCategories
        self.recentlyShownIDs = recentlyShownIDs
        self.lastCategory = lastCategory
        self.lastShownAt = lastShownAt
        self.trigger = trigger
        self.activityMode = activityMode
        self.minutesSinceSessionStart = minutesSinceSessionStart
    }
}

/// 会話の供給元。
///
/// 戻り値を Optional にしているのは「条件に合う会話が 1 つも無い」を表せるようにするため。
/// （要件の擬似コードは非 Optional だが、クールダウン中で候補が尽きたときに
/// 無理やり何かを返すと同じ台詞が連続してしまう。黙るという選択肢を残す。）
///
/// `async` なのは、将来 LLM 実装（`LLMConversationProvider`）に差し替えられるようにするため。
public protocol ConversationProvider: AnyObject {
    func nextConversation(context: ConversationContext) async -> Conversation?
}

/// JSON から読んだ台詞集合を使うローカル実装
public final class LocalDialogueProvider: ConversationProvider {

    public private(set) var dialogueSet: DialogueSet

    /// テスト用に差し替え可能な乱数（0..<count の index を返す）
    public var randomIndex: (Int) -> Int = { count in count <= 1 ? 0 : Int.random(in: 0..<count) }

    public init(dialogueSet: DialogueSet) {
        self.dialogueSet = dialogueSet
    }

    public func update(dialogueSet: DialogueSet) {
        self.dialogueSet = dialogueSet
    }

    public func nextConversation(context: ConversationContext) async -> Conversation? {
        pick(context: context)
    }

    /// 同期版（テストと内部用）
    public func pick(context: ConversationContext) -> Conversation? {
        let allowed = dialogueSet.conversations.filter { context.allowedCategories.contains($0.category) }
        guard !allowed.isEmpty else { return nil }

        // 直前と同じカテゴリは避ける。ただし allowed がそのカテゴリしか無いなら許可する。
        let avoidCategory: DialogueCategory? = {
            guard let last = context.lastCategory else { return nil }
            let others = allowed.filter { $0.category != last }
            return others.isEmpty ? nil : last
        }()

        // 1) 全部のフィルタ
        var candidates = allowed.filter { conversation in
            !isOnCooldown(conversation, context: context)
                && conversation.category != avoidCategory
                && !context.recentlyShownIDs.contains(conversation.id)
        }
        if let picked = choose(candidates) { return picked }

        // 手動（「ちょっと話して」）のときは必ず反応する。段階的に条件をゆるめる。
        guard context.trigger == .manual else { return nil }

        // 2) クールダウンを無視
        candidates = allowed.filter { $0.category != avoidCategory && !context.recentlyShownIDs.contains($0.id) }
        if let picked = choose(candidates) { return picked }

        // 3) 最近出した id も無視
        candidates = allowed.filter { $0.category != avoidCategory }
        if let picked = choose(candidates) { return picked }

        // 4) 直前カテゴリの回避も諦める
        return choose(allowed)
    }

    private func isOnCooldown(_ conversation: Conversation, context: ConversationContext) -> Bool {
        guard let last = context.lastShownAt[conversation.id] else { return false }
        return last.addingTimeInterval(conversation.cooldown) > context.now
    }

    private func choose(_ candidates: [Conversation]) -> Conversation? {
        guard !candidates.isEmpty else { return nil }
        let index = min(max(0, randomIndex(candidates.count)), candidates.count - 1)
        return candidates[index]
    }
}
