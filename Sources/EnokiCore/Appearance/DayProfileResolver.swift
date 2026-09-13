import Foundation

/// 「今日はどんな日か」の判定結果。
/// `profileID == nil` は「特別な日ではない」＝ 既存ルール（手動選択・仕事中モード連動・default）に任せる、の意味。
public struct DayProfileDecision: Equatable, Sendable {
    public let profileID: String?
    /// メニューとログに出す理由（「土曜日」「祝日: 文化の日」「レノファ戦 vs ○○ (H) 14:00」「平日」）
    public let reason: String

    public init(profileID: String?, reason: String) {
        self.profileID = profileID
        self.reason = reason
    }

    /// 特別な日ではない（既存ルールに任せる）
    public static func ordinary(_ reason: String) -> DayProfileDecision {
        DayProfileDecision(profileID: nil, reason: reason)
    }
}

/// 「その日が当てはまるか」を 1 つだけ判定するルール。
/// 当てはまれば理由の文字列を返す。当てはまらなければ nil。
public struct DayRule {
    public let name: String
    public let matches: (Date, Calendar) -> String?
    public let profileID: String

    public init(name: String, profileID: String, matches: @escaping (Date, Calendar) -> String?) {
        self.name = name
        self.profileID = profileID
        self.matches = matches
    }
}

/// 「その日がどんな日か」から見た目プロファイルを選ぶ純関数。時計もファイルもネットワークも触りません
/// （`date` は引数で受け取り、祝日と試合日は読み込み済みのデータを渡してもらいます）。
///
/// ルールは**先頭から順に評価して、最初に一致したものを採用**します。
/// 季節もの・誕生日・他のスポーツを足したくなったら `rules` に `DayRule` を 1 つ足すだけです
/// （汎用ルールエンジンにはしません）。
public enum DayProfileResolver {

    /// 優先順位つきのルール一覧
    /// 1. レノファの試合日 → `renofa`
    /// 2. 土日 → `casual`
    /// 3. 祝日 → `casual`
    public static func rules(schedule: RenofaSchedule,
                             holidays: JapaneseHolidays = .shared) -> [DayRule] {
        [
            DayRule(name: "レノファ試合日", profileID: "renofa") { date, calendar in
                guard let match = schedule.match(on: date, calendar: calendar) else { return nil }
                var reason = "レノファ戦 vs \(match.opponent) (\(match.homeAwayLabel))"
                if let kickoff = match.kickoff { reason += " \(kickoff)" }
                return reason
            },
            DayRule(name: "土日", profileID: AppearanceProfile.ID.casual) { date, calendar in
                switch calendar.component(.weekday, from: date) {
                case 7:  return "土曜日"
                case 1:  return "日曜日"
                default: return nil
                }
            },
            DayRule(name: "祝日", profileID: AppearanceProfile.ID.casual) { date, calendar in
                guard let name = holidays.holidayName(on: date, calendar: calendar) else { return nil }
                return "祝日: \(name)"
            },
        ]
    }

    /// 今日の判定。どのルールにも当てはまらなければ `profileID: nil`（＝ 既存ルールに任せる）。
    public static func resolve(date: Date,
                               schedule: RenofaSchedule,
                               holidays: JapaneseHolidays = .shared,
                               calendar: Calendar = .current) -> DayProfileDecision {
        for rule in rules(schedule: schedule, holidays: holidays) {
            if let reason = rule.matches(date, calendar) {
                return DayProfileDecision(profileID: rule.profileID, reason: reason)
            }
        }
        return .ordinary("平日")
    }

    /// 日付のキー（yyyy-MM-dd）。手動選択の「その日限り」判定と試合日の突き合わせに使う。
    /// `DateFormatter` を使わないので、ロケール（和暦など）の設定に左右されません。
    public static func dayKey(for date: Date, calendar: Calendar = .current) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }
}
