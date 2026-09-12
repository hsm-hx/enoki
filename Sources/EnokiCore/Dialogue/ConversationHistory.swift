import Foundation

/// 会話の履歴。UserDefaults に JSON で保存する（`AppSettings.conversationHistoryData`）。
public struct ConversationHistory: Codable, Equatable, Sendable {

    /// 覚えておく「最近出した会話 id」の数
    public static let recentIDLimit = 20

    /// 会話 id → 最後に出した時刻
    public private(set) var lastShownAt: [String: Date]
    /// カテゴリ（rawValue）→ 最後に出した時刻
    public private(set) var categoryLastShownAt: [String: Date]
    /// 最近出した会話 id（新しい順、最大 `recentIDLimit` 件）
    public private(set) var recentIDs: [String]
    /// 最後に会話した時刻（カテゴリを問わない）
    public var lastConversationAt: Date?
    /// 最後に出した会話のカテゴリ
    public private(set) var lastCategoryRaw: String?

    public init(lastShownAt: [String: Date] = [:],
                categoryLastShownAt: [String: Date] = [:],
                recentIDs: [String] = [],
                lastConversationAt: Date? = nil,
                lastCategory: DialogueCategory? = nil) {
        self.lastShownAt = lastShownAt
        self.categoryLastShownAt = categoryLastShownAt
        self.recentIDs = recentIDs
        self.lastConversationAt = lastConversationAt
        self.lastCategoryRaw = lastCategory?.rawValue
    }

    public var lastCategory: DialogueCategory? {
        lastCategoryRaw.flatMap(DialogueCategory.init(rawValue:))
    }

    public func lastShown(of category: DialogueCategory) -> Date? {
        categoryLastShownAt[category.rawValue]
    }

    public func lastShown(id: String) -> Date? {
        lastShownAt[id]
    }

    /// 会話を出した記録をつける
    public mutating func record(_ conversation: Conversation, at date: Date) {
        lastShownAt[conversation.id] = date
        categoryLastShownAt[conversation.category.rawValue] = date
        lastConversationAt = date
        lastCategoryRaw = conversation.category.rawValue
        recentIDs.removeAll { $0 == conversation.id }
        recentIDs.insert(conversation.id, at: 0)
        if recentIDs.count > Self.recentIDLimit {
            recentIDs.removeLast(recentIDs.count - Self.recentIDLimit)
        }
    }

    /// 古すぎる記録（既定 3 日）を捨てる。保存データが際限なく増えないように。
    public mutating func prune(before cutoff: Date) {
        lastShownAt = lastShownAt.filter { $0.value >= cutoff }
        categoryLastShownAt = categoryLastShownAt.filter { $0.value >= cutoff }
        recentIDs = recentIDs.filter { lastShownAt[$0] != nil }
    }

    // MARK: - 永続化

    public func encoded() -> Data? {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .secondsSince1970
        return try? encoder.encode(self)
    }

    public static func decoded(from data: Data?) -> ConversationHistory {
        guard let data else { return ConversationHistory() }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        return (try? decoder.decode(ConversationHistory.self, from: data)) ?? ConversationHistory()
    }
}
