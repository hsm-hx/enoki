import Foundation
import CoreGraphics

/// 話し手。スプライト上では朔が左、栞が右に立っている。
public enum Speaker: String, Codable, CaseIterable, Sendable {
    case saku
    case shiori

    public var displayName: String {
        switch self {
        case .saku:   return "朔"
        case .shiori: return "栞"
        }
    }

    /// マスコット窓の横幅に対する立ち位置（0 = 左端, 1 = 右端）。吹き出しのしっぽ位置に使う。
    public var horizontalAnchor: CGFloat {
        switch self {
        case .saku:   return 0.25
        case .shiori: return 0.75
        }
    }
}

/// 会話のカテゴリ
public enum DialogueCategory: String, Codable, CaseIterable, Sendable {
    case work            // 仕事へ戻る
    case water           // 水分
    case `break`         // 休憩
    case lunch           // 昼食
    case encouragement   // 励まし
    case ambient         // 独り言・雰囲気
    case pair            // 2 人の会話

    public var localizedName: String {
        switch self {
        case .work:          return "仕事"
        case .water:         return "水分"
        case .break:         return "休憩"
        case .lunch:         return "昼食"
        case .encouragement: return "励まし"
        case .ambient:       return "雰囲気"
        case .pair:          return "2人の会話"
        }
    }
}

/// 1 発言
public struct DialogueLine: Codable, Equatable, Sendable {
    public let speaker: Speaker
    public let text: String
    /// 将来の reaction スプライト名（JSON に無ければ nil）
    public let reaction: String?

    public init(speaker: Speaker, text: String, reaction: String? = nil) {
        self.speaker = speaker
        self.text = text
        self.reaction = reaction
    }
}

/// 1 会話（最大 4 発言程度）
public struct Conversation: Codable, Equatable, Identifiable, Sendable {
    public static let defaultCooldown: TimeInterval = 3600

    public let id: String
    public let category: DialogueCategory
    /// 同じ会話を再び選んでよくなるまでの秒数
    public let cooldown: TimeInterval
    public let lines: [DialogueLine]

    public init(id: String,
                category: DialogueCategory,
                cooldown: TimeInterval = Conversation.defaultCooldown,
                lines: [DialogueLine]) {
        self.id = id
        self.category = category
        self.cooldown = cooldown
        self.lines = lines
    }

    private enum CodingKeys: String, CodingKey {
        case id, category, cooldown, lines
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        category = try container.decode(DialogueCategory.self, forKey: .category)
        cooldown = try container.decodeIfPresent(TimeInterval.self, forKey: .cooldown) ?? Conversation.defaultCooldown
        lines = try container.decode([DialogueLine].self, forKey: .lines)
    }

    public var speakers: [Speaker] { lines.map(\.speaker) }
}

/// 読み込み済みの台詞集合
public struct DialogueSet: Codable, Equatable, Sendable {
    public let schemaVersion: Int
    public let conversations: [Conversation]

    private enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version"
        case conversations = "dialogues"
    }

    public init(schemaVersion: Int = 1, conversations: [Conversation]) {
        self.schemaVersion = schemaVersion
        self.conversations = conversations
    }

    public static let empty = DialogueSet(schemaVersion: 1, conversations: [])

    public var isEmpty: Bool { conversations.isEmpty }

    public func conversations(in category: DialogueCategory) -> [Conversation] {
        conversations.filter { $0.category == category }
    }

    public func conversation(id: String) -> Conversation? {
        conversations.first { $0.id == id }
    }
}
