import Foundation
import CoreGraphics

/// 話し手。`id` は `dialogue.json` の `speaker` に書いた文字列そのもの。
///
/// **表示名と立ち位置はここには持たない。** それらは `SpeakerStyle`（`dialogue.json` の `speakers`、
/// または登場人数からの既定値）が決める。こうすることで、1 人用の台詞ファイルでも
/// 自分のキャラクター名の id をそのまま書ける。
public struct Speaker: Hashable, Codable, Sendable, CustomStringConvertible {

    public let id: String

    public init(_ id: String) {
        self.id = id
    }

    /// 同梱してきた台詞ファイルで使っている id（テスト・既定値用の定数）
    public static let saku = Speaker("saku")
    public static let shiori = Speaker("shiori")

    public var description: String { id }

    public init(from decoder: Decoder) throws {
        id = try decoder.singleValueContainer().decode(String.self)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(id)
    }
}

/// `dialogue.json` の `speakers` に書ける宣言。省略した項目は既定値で埋める。
public struct SpeakerDeclaration: Equatable, Sendable {
    public let id: String
    /// 吹き出しに出す名前（省略時は既定表示名）
    public let displayName: String?
    /// 立ち位置 0〜1（省略時は登場人数から決める）
    public let anchor: CGFloat?

    public init(id: String, displayName: String? = nil, anchor: CGFloat? = nil) {
        self.id = id
        self.displayName = displayName
        self.anchor = anchor.map { min(max($0, 0), 1) }
    }
}

/// 1 人ぶんの吹き出しの見せ方。
public struct SpeakerStyle: Equatable, Sendable {
    public let id: String
    public let displayName: String
    /// マスコット窓の横幅に対する立ち位置（0 = 左端, 0.5 = 中央, 1 = 右端）。吹き出しのしっぽ位置。
    public let anchor: CGFloat
    /// 名前ラベルの色を選ぶ添字（登場順）
    public let colorIndex: Int

    public init(id: String, displayName: String, anchor: CGFloat, colorIndex: Int = 0) {
        self.id = id
        self.displayName = displayName
        self.anchor = anchor
        self.colorIndex = colorIndex
    }
}

/// 話者 id → 見せ方の対応表。`DialogueSet` が「宣言」と「実際の登場順」から組み立てる。
///
/// 既定の立ち位置は登場人数で決まる:
/// - **1 人 → 0.5（中央）**。1 人用の台詞ファイルは何も書かなくても吹き出しが中央に出る。
/// - 2 人 → 0.25 / 0.75（これまでの朔・栞と同じ）
/// - 3 人以上 → 等間隔
public struct SpeakerStyleTable: Equatable, Sendable {

    /// 登場順の id
    public let order: [String]
    private let styles: [String: SpeakerStyle]

    public static let empty = SpeakerStyleTable(order: [], styles: [:])

    private init(order: [String], styles: [String: SpeakerStyle]) {
        self.order = order
        self.styles = styles
    }

    /// 宣言と登場順から組み立てる（宣言にある id が先、続いて台詞に出てきた順）
    public init(declared: [SpeakerDeclaration], appearing: [String]) {
        var order: [String] = []
        for declaration in declared where !order.contains(declaration.id) {
            order.append(declaration.id)
        }
        for id in appearing where !order.contains(id) {
            order.append(id)
        }
        let declarationsByID = Dictionary(declared.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        var styles: [String: SpeakerStyle] = [:]
        for (index, id) in order.enumerated() {
            let declaration = declarationsByID[id]
            styles[id] = SpeakerStyle(
                id: id,
                displayName: declaration?.displayName ?? Self.defaultDisplayName(for: id),
                anchor: declaration?.anchor ?? Self.defaultAnchor(index: index, count: order.count),
                colorIndex: index)
        }
        self.init(order: order, styles: styles)
    }

    /// その話者の見せ方（表に無ければ中央・id をそのまま名前にする）
    public func style(for speaker: Speaker) -> SpeakerStyle {
        styles[speaker.id] ?? SpeakerStyle(id: speaker.id,
                                           displayName: Self.defaultDisplayName(for: speaker.id),
                                           anchor: 0.5)
    }

    public var count: Int { order.count }
    /// 1 人用の台詞ファイルか
    public var isSolo: Bool { order.count <= 1 }

    /// 人数から決まる既定の立ち位置
    public static func defaultAnchor(index: Int, count: Int) -> CGFloat {
        switch count {
        case ...1: return 0.5
        case 2:    return index == 0 ? 0.25 : 0.75
        default:   return CGFloat(index + 1) / CGFloat(count + 1)
        }
    }

    /// 既定の表示名。同梱してきた id だけ日本語名を持つ（互換用）。それ以外は id をそのまま出す。
    public static func defaultDisplayName(for id: String) -> String {
        switch id {
        case Speaker.saku.id:   return "朔"
        case Speaker.shiori.id: return "栞"
        default:                return id
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
    // 見た目プロファイル専用のカテゴリ（§12）。プロファイルが許可したときだけ候補に入る。
    case renofa                                      // レノファの日の雑談
    case renofaPreMatch = "renofa_pre_match"         // 試合前（将来の時刻ベース切替フック用）
    case renofaMatch = "renofa_match"                // 試合中
    case renofaPostMatch = "renofa_post_match"       // 試合後

    public var localizedName: String {
        switch self {
        case .work:          return "仕事"
        case .water:         return "水分"
        case .break:         return "休憩"
        case .lunch:         return "昼食"
        case .encouragement: return "励まし"
        case .ambient:       return "雰囲気"
        case .pair:          return "2人の会話"
        case .renofa:          return "レノファ"
        case .renofaPreMatch:  return "レノファ（試合前）"
        case .renofaMatch:     return "レノファ（試合中）"
        case .renofaPostMatch: return "レノファ（試合後）"
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
    /// この会話を使ってよい見た目プロファイル id（nil = 全プロファイル共通）
    public let profiles: [String]?

    public init(id: String,
                category: DialogueCategory,
                cooldown: TimeInterval = Conversation.defaultCooldown,
                lines: [DialogueLine],
                profiles: [String]? = nil) {
        self.id = id
        self.category = category
        self.cooldown = cooldown
        self.lines = lines
        self.profiles = profiles
    }

    private enum CodingKeys: String, CodingKey {
        case id, category, cooldown, lines, profiles
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        category = try container.decode(DialogueCategory.self, forKey: .category)
        cooldown = try container.decodeIfPresent(TimeInterval.self, forKey: .cooldown) ?? Conversation.defaultCooldown
        lines = try container.decode([DialogueLine].self, forKey: .lines)
        profiles = try container.decodeIfPresent([String].self, forKey: .profiles)
    }

    /// このプロファイルで使ってよい会話か（`profiles` が無ければ共通）
    public func matches(profileID: String) -> Bool {
        guard let profiles, !profiles.isEmpty else { return true }
        return profiles.contains(profileID)
    }

    public var speakers: [Speaker] { lines.map(\.speaker) }
}

/// 読み込み済みの台詞集合
public struct DialogueSet: Equatable, Sendable {
    public let schemaVersion: Int
    public let conversations: [Conversation]
    /// `dialogue.json` の `speakers`（省略可）
    public let declaredSpeakers: [SpeakerDeclaration]
    /// 話者 id → 吹き出しの見せ方（宣言 + 登場順から組み立てたもの）
    public let speakerStyles: SpeakerStyleTable

    public init(schemaVersion: Int = 1,
                conversations: [Conversation],
                declaredSpeakers: [SpeakerDeclaration] = []) {
        self.schemaVersion = schemaVersion
        self.conversations = conversations
        self.declaredSpeakers = declaredSpeakers
        var appearing: [String] = []
        for conversation in conversations {
            for line in conversation.lines where !appearing.contains(line.speaker.id) {
                appearing.append(line.speaker.id)
            }
        }
        self.speakerStyles = SpeakerStyleTable(declared: declaredSpeakers, appearing: appearing)
    }

    public static let empty = DialogueSet(schemaVersion: 1, conversations: [])

    /// 実際に登場する話者（登場順）
    public var speakers: [Speaker] { speakerStyles.order.map(Speaker.init) }
    /// 1 人用の台詞ファイルか（吹き出しは中央に出る）
    public var isSolo: Bool { speakerStyles.isSolo }

    public var isEmpty: Bool { conversations.isEmpty }

    public func conversations(in category: DialogueCategory) -> [Conversation] {
        conversations.filter { $0.category == category }
    }

    public func conversation(id: String) -> Conversation? {
        conversations.first { $0.id == id }
    }
}
