import Foundation

/// 「いつ・どのカテゴリの声をかけてよいか」だけを決める純ロジック。
///
/// `Date` は引数で受け取り、乱数は `randomInterval` で差し替えられる。
/// 実際のタイマー（60 秒ごとの tick）は `ConversationCoordinator` が持つ。
public final class ConversationScheduler {

    /// 各ルールの間隔（秒）。数値をひとまとめにして、テストとドキュメントから参照できるようにする。
    public struct Intervals: Equatable, Sendable {
        /// 会話どうしの最低間隔（20 分 + 0〜15 分）
        public var globalGap: ClosedRange<TimeInterval> = (20 * 60)...(35 * 60)
        /// 休憩の周期（50〜60 分）
        public var breakEvery: ClosedRange<TimeInterval> = (50 * 60)...(60 * 60)
        /// 水分の周期（120 分 ±15 分）
        public var waterEvery: ClosedRange<TimeInterval> = (105 * 60)...(135 * 60)
        /// 励ましの周期（90 分 ±20 分）
        public var encouragementEvery: ClosedRange<TimeInterval> = (70 * 60)...(110 * 60)
        /// 雰囲気・2 人の会話の周期（40〜90 分）
        public var ambientEvery: ClosedRange<TimeInterval> = (40 * 60)...(90 * 60)
        /// 休憩・昼食のあと「仕事に戻ろう」と言うまで（10〜15 分）
        public var workReturnDelay: ClosedRange<TimeInterval> = (10 * 60)...(15 * 60)
        /// 昼食の目標時刻のぶれ（12:00 ±20 分）
        public var lunchJitter: ClosedRange<TimeInterval> = (-20 * 60)...(20 * 60)
        /// これ以上離席していたら、戻った時刻を新しいセッション開始にする（10 分）
        public var awayResetsSession: TimeInterval = 10 * 60

        public init() {}
    }

    /// 昼食の窓（11:30〜14:00）と目標時刻（12:00）
    public static let lunchWindow = (startHour: 11, startMinute: 30, endHour: 14, endMinute: 0)
    public static let lunchTargetHour = 12
    /// 励ましの窓（13:00〜18:00）
    public static let encouragementWindow = (startHour: 13, endHour: 18)

    /// 優先順位（先頭ほど優先）
    public static let priority: [DialogueCategory] = [.lunch, .water, .break, .work, .encouragement, .ambient, .pair]

    // MARK: - 設定

    public var intervals = Intervals()
    public var activityMode: ActivityMode
    public var quietMode: QuietMode
    public var workEndHour: Int
    public var calendar: Calendar
    /// ユーザーが離席中（マスコットがスリープ状態）。`setUserAway(_:now:)` で更新する。
    public private(set) var isUserAway = false
    /// 離席が始まった時刻
    private var awaySince: Date?
    /// マスコットが非表示
    public var isMascotHidden = false

    /// テスト用に差し替え可能な乱数
    public var randomInterval: (ClosedRange<TimeInterval>) -> TimeInterval = { range in
        range.lowerBound >= range.upperBound ? range.lowerBound : TimeInterval.random(in: range)
    }

    /// アプリ起動 or 仕事中モード ON の時刻
    public private(set) var sessionStart: Date
    public private(set) var history: ConversationHistory

    /// 直前の tick が quiet で黙っていたか（quiet 明けの一斉発話を防ぐ）
    private var wasQuiet = false
    /// 「基準時刻 → その周期に使う乱数」のキャッシュ。基準が動いたら引き直す。
    private var targets: [String: (basis: Date, value: TimeInterval)] = [:]

    public init(sessionStart: Date,
                history: ConversationHistory = ConversationHistory(),
                activityMode: ActivityMode = .work,
                quietMode: QuietMode = .normal,
                workEndHour: Int = QuietMode.defaultWorkEndHour,
                calendar: Calendar = .current) {
        self.sessionStart = sessionStart
        self.history = history
        self.activityMode = activityMode
        self.quietMode = quietMode
        self.workEndHour = workEndHour
        self.calendar = calendar
    }

    // MARK: - 履歴の更新

    /// セッション（起動 / 仕事中モード ON）の開始時刻を入れ替える
    public func restartSession(at date: Date) {
        sessionStart = date
        targets.removeAll()
    }

    /// 会話を出した記録をつける
    public func record(_ conversation: Conversation, at date: Date) {
        history.record(conversation, at: date)
        history.prune(before: date.addingTimeInterval(-3 * 24 * 60 * 60))
    }

    /// 離席状態の更新。`awayResetsSession` 以上の離席から戻ったら、戻った時刻を新しいセッション開始にする
    /// （戻った直後に「休憩しよっか」と言わないため。休憩・水分の周期は戻った時刻から数え直す）。
    public func setUserAway(_ away: Bool, now: Date) {
        guard away != isUserAway else { return }
        isUserAway = away
        if away {
            awaySince = now
        } else if let since = awaySince, now.timeIntervalSince(since) >= intervals.awayResetsSession {
            restartSession(at: now)
            awaySince = nil
        } else {
            awaySince = nil
        }
    }

    public func replaceHistory(_ history: ConversationHistory) {
        self.history = history
        targets.removeAll()
    }

    // MARK: - 判定

    /// いま話してよいカテゴリを優先順に返す。空なら黙る。
    public func evaluate(now: Date) -> [DialogueCategory] {
        if quietMode.isQuiet(at: now, workEndHour: workEndHour, calendar: calendar) {
            wasQuiet = true
            return []
        }
        if wasQuiet {
            // quiet 明けに溜まっていたぶんを一斉に話さないよう、最終会話時刻を解除時刻に更新する
            wasQuiet = false
            history.lastConversationAt = now
            targets.removeValue(forKey: "global")
        }
        guard !isMascotHidden, !isUserAway else { return [] }

        // 全体の最低間隔
        let globalBasis = history.lastConversationAt ?? sessionStart
        let gap = target("global", basis: globalBasis, range: intervals.globalGap)
        guard now >= globalBasis.addingTimeInterval(gap) else { return [] }

        let allowed = activityMode.scheduledCategories
        return Self.priority.filter { category in
            allowed.contains(category)
                && category != history.lastCategory
                && isDue(category, now: now)
        }
    }

    /// そのカテゴリの条件が満たされているか
    public func isDue(_ category: DialogueCategory, now: Date) -> Bool {
        switch category {
        case .lunch:
            return isLunchDue(now: now)
        case .water:
            let basis = history.lastShown(of: .water) ?? sessionStart
            return now >= basis.addingTimeInterval(target("water", basis: basis, range: intervals.waterEvery))
        case .break:
            let basis = history.lastShown(of: .break) ?? sessionStart
            return now >= basis.addingTimeInterval(target("break", basis: basis, range: intervals.breakEvery))
        case .work:
            return isWorkReturnDue(now: now)
        case .encouragement:
            let hour = calendar.component(.hour, from: now)
            guard hour >= Self.encouragementWindow.startHour, hour < Self.encouragementWindow.endHour else { return false }
            let basis = history.lastShown(of: .encouragement) ?? sessionStart
            return now >= basis.addingTimeInterval(target("encouragement", basis: basis, range: intervals.encouragementEvery))
        case .ambient, .pair:
            let basis = latest(history.lastShown(of: .ambient), history.lastShown(of: .pair)) ?? sessionStart
            return now >= basis.addingTimeInterval(target("ambient", basis: basis, range: intervals.ambientEvery))
        }
    }

    /// 昼食: 11:30〜14:00 の窓の中、1 日 1 回、目標時刻（12:00 ±20 分）以降
    private func isLunchDue(now: Date) -> Bool {
        let day = calendar.startOfDay(for: now)
        let windowStart = time(Self.lunchWindow.startHour, Self.lunchWindow.startMinute, on: day)
        let windowEnd = time(Self.lunchWindow.endHour, Self.lunchWindow.endMinute, on: day)
        guard now >= windowStart, now < windowEnd else { return false }
        if let last = history.lastShown(of: .lunch), calendar.isDate(last, inSameDayAs: now) { return false }
        let noon = time(Self.lunchTargetHour, 0, on: day)
        let jitter = target("lunch", basis: day, range: intervals.lunchJitter)
        return now >= noon.addingTimeInterval(jitter)
    }

    /// 仕事へ戻る: 休憩・昼食のあと 10〜15 分、その休憩につき 1 回だけ
    private func isWorkReturnDue(now: Date) -> Bool {
        guard let basis = latest(history.lastShown(of: .break), history.lastShown(of: .lunch)) else { return false }
        if let lastWork = history.lastShown(of: .work), lastWork >= basis { return false }
        return now >= basis.addingTimeInterval(target("work", basis: basis, range: intervals.workReturnDelay))
    }

    // MARK: - ヘルパ

    private func latest(_ dates: Date?...) -> Date? {
        dates.compactMap { $0 }.max()
    }

    private func time(_ hour: Int, _ minute: Int, on day: Date) -> Date {
        let start = calendar.startOfDay(for: day)
        return start.addingTimeInterval(TimeInterval(hour * 3600 + minute * 60))
    }

    /// 基準時刻ごとに一度だけ乱数を引き、基準が動くまで同じ値を使う
    private func target(_ key: String, basis: Date, range: ClosedRange<TimeInterval>) -> TimeInterval {
        if let cached = targets[key], cached.basis == basis { return cached.value }
        let value = randomInterval(range)
        targets[key] = (basis, value)
        return value
    }
}
