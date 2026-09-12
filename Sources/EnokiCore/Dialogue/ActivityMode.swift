import Foundation

/// いま何をしている時間か。
/// 将来 `creation`（制作モード = 仕事の話をせず、制作を後押しする声かけをする）を足せるように
/// 文字列 raw value で保存している。追加するときは `scheduledCategories` に分岐を足すだけでよい。
public enum ActivityMode: String, CaseIterable, Codable, Sendable {
    /// 仕事中（声かけあり）
    case work
    /// 仕事中モード OFF。休憩・私用の時間なので、雰囲気の会話だけにする。
    case rest

    public var localizedName: String {
        switch self {
        case .work: return "仕事中"
        case .rest: return "仕事中じゃない"
        }
    }

    /// 自動の声かけで使ってよいカテゴリ
    public var scheduledCategories: Set<DialogueCategory> {
        switch self {
        case .work:
            // work / water / break / lunch / encouragement が主役。
            // ambient / pair も混ぜるが、ConversationScheduler の優先順位で最後に回るため頻度は低い。
            return Set(DialogueCategory.allCases)
        case .rest:
            // 仕事の声かけ（work / water / break / lunch）以外は許す。
            // 見た目プロファイル側でさらに絞り込む（例: casual は encouragement を許可、work を落とす）。
            return Set(DialogueCategory.allCases).subtracting([.work, .water, .break, .lunch])
        }
    }
}
