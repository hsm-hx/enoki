import Foundation

/// 見た目プロファイル（Appearance Profile）。
///
/// 「どのスプライトセットで立つか」と「どのカテゴリの台詞を話してよいか」を 1 つにまとめた設定で、
/// **Swift には id をハードコードせず** `Resources/Profiles/profiles.json` から読み込む。
/// 季節もの（winter / christmas …）を足すときは JSON に 1 項目足すだけでよい。
/// （`Identifiable` には準拠していない。準拠すると `associatedtype ID` と、既知 id をまとめた
/// 下の `enum ID` が衝突するため。id は `String` なので `Identifiable` が無くても困らない。）
public struct AppearanceProfile: Codable, Equatable, Sendable {

    /// 解決ロジックが参照する既知の id。これ以外の id は JSON 側の自由。
    public enum ID {
        public static let `default` = "default"
        public static let work = "work"
        public static let casual = "casual"
    }

    /// プロファイル id（`profiles.json` の `id`）
    public let id: String
    /// メニューに出す名前
    public let displayName: String
    /// スプライトセットのフォルダ名。nil ならベーススキン（スキンメニューで選んでいるスキン）を使う。
    public let spriteSet: String?
    /// 試合日の局面ごとのスプライトセット（キーは `MatchPhase` の `rawValue`）。
    /// nil / 該当なしなら `spriteSet` を使う（= 局面を無視する従来どおりの動き）。
    public let spriteSetsByPhase: [String: String]?
    /// 使ってよい台詞カテゴリ（nil = 制限しない）。未知のカテゴリ名は無視する。
    public let dialogueCategories: [String]?
    /// 使わない台詞カテゴリ。`dialogueCategories` より強い。
    public let disabledDialogueCategories: [String]
    /// 特別なプロファイル（仕事中モードの切り替えで手動選択を解除しない）
    public let special: Bool
    /// 着替え後に 1 回だけ再生するアニメーション名（スキンに無ければ無視）。将来の「着替え reaction」用。
    public let transitionAnimation: String?

    public init(id: String,
                displayName: String,
                spriteSet: String? = nil,
                spriteSetsByPhase: [String: String]? = nil,
                dialogueCategories: [String]? = nil,
                disabledDialogueCategories: [String] = [],
                special: Bool = false,
                transitionAnimation: String? = nil) {
        self.id = id
        self.displayName = displayName
        self.spriteSet = spriteSet
        self.spriteSetsByPhase = spriteSetsByPhase
        self.dialogueCategories = dialogueCategories
        self.disabledDialogueCategories = disabledDialogueCategories
        self.special = special
        self.transitionAnimation = transitionAnimation
    }

    private enum CodingKeys: String, CodingKey {
        case id, displayName, spriteSet, spriteSetsByPhase
        case dialogueCategories, disabledDialogueCategories, special, transitionAnimation
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        displayName = try container.decodeIfPresent(String.self, forKey: .displayName) ?? id
        spriteSet = try container.decodeIfPresent(String.self, forKey: .spriteSet)
        spriteSetsByPhase = try container.decodeIfPresent([String: String].self, forKey: .spriteSetsByPhase)
        dialogueCategories = try container.decodeIfPresent([String].self, forKey: .dialogueCategories)
        disabledDialogueCategories = try container.decodeIfPresent([String].self, forKey: .disabledDialogueCategories) ?? []
        special = try container.decodeIfPresent(Bool.self, forKey: .special) ?? false
        transitionAnimation = try container.decodeIfPresent(String.self, forKey: .transitionAnimation)
    }

    /// `profiles.json` が読めなかったときに使う最小構成（ベーススキン + 全カテゴリ）
    public static let fallbackDefault = AppearanceProfile(id: ID.default, displayName: "Default")

    /// この局面で使うスプライトセットのフォルダ名。
    ///
    /// - `phase` が nil（試合日ではない）→ `spriteSet`
    /// - `spriteSetsByPhase` にその局面の名前があればそれ
    /// - `.finished`（試合終了想定時刻以降）は `.postMatch` の名前にフォールバック（試合後のポーズのまま）
    /// - どれも無ければ `spriteSet`
    public func spriteSet(for phase: MatchPhase?) -> String? {
        guard let phase, let byPhase = spriteSetsByPhase else { return spriteSet }
        if let name = byPhase[phase.rawValue], !name.isEmpty { return name }
        if phase == .finished, let name = byPhase[MatchPhase.postMatch.rawValue], !name.isEmpty { return name }
        return spriteSet
    }

    /// このプロファイルで使ってよいカテゴリ。
    /// `base`（仕事中モードが許すカテゴリ）∩ `dialogueCategories`（あれば）− `disabledDialogueCategories`。
    /// 未知のカテゴリ名は無視する。
    public func allowedCategories(base: Set<DialogueCategory>) -> Set<DialogueCategory> {
        var result = base
        if let dialogueCategories {
            let named = Set(dialogueCategories.compactMap(DialogueCategory.init(rawValue:)))
            result.formIntersection(named)
        }
        result.subtract(disabledDialogueCategories.compactMap(DialogueCategory.init(rawValue:)))
        return result
    }
}
