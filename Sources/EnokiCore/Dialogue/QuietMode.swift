import Foundation

/// 「静かにしていて」の状態。
///
/// `until` / `untilEndOfWorkDay` は **解除時刻を値として持つ**。
/// `untilEndOfWorkDay` は「設定した時点」を基準に解除時刻を決める必要があり
/// （当日の workEndHour まで。既に過ぎていれば当日 24 時まで）、
/// 値を持たないと後から基準日が分からなくなるため。生成は `QuietMode.endOfWorkDay(from:)` を使う。
public enum QuietMode: Equatable, Sendable {
    /// 通常（声かけあり）
    case normal
    /// 指定時刻まで静かにする
    case until(Date)
    /// 今日の仕事終了まで静かにする（値は解決済みの解除時刻）
    case untilEndOfWorkDay(until: Date)
    /// 会話 OFF（手動の「ちょっと話して」以外はしゃべらない）
    case off

    public static let defaultWorkEndHour = 18

    /// 「今日の仕事終了まで」を、基準時刻から解決して作る
    public static func endOfWorkDay(from reference: Date,
                                    workEndHour: Int = QuietMode.defaultWorkEndHour,
                                    calendar: Calendar = .current) -> QuietMode {
        .untilEndOfWorkDay(until: workDayEnd(from: reference, workEndHour: workEndHour, calendar: calendar))
    }

    /// 当日の workEndHour 時。既に過ぎていれば翌日の 0 時（= 当日 24 時）。
    public static func workDayEnd(from reference: Date,
                                  workEndHour: Int = QuietMode.defaultWorkEndHour,
                                  calendar: Calendar = .current) -> Date {
        let hour = min(max(workEndHour, 0), 23)
        let startOfDay = calendar.startOfDay(for: reference)
        let end = calendar.date(byAdding: .hour, value: hour, to: startOfDay) ?? reference
        if reference < end { return end }
        return calendar.date(byAdding: .day, value: 1, to: startOfDay) ?? end
    }

    /// 解除時刻（`normal` / `off` は nil）
    public var expiry: Date? {
        switch self {
        case .until(let date), .untilEndOfWorkDay(let date): return date
        case .normal, .off: return nil
        }
    }

    /// いま黙るべきか
    public func isQuiet(at now: Date,
                        workEndHour: Int = QuietMode.defaultWorkEndHour,
                        calendar: Calendar = .current) -> Bool {
        switch self {
        case .normal: return false
        case .off:    return true
        case .until(let date), .untilEndOfWorkDay(let date):
            _ = workEndHour
            _ = calendar
            return now < date
        }
    }

    /// 期限切れ（= `normal` に戻してよい）か
    public func isExpired(at now: Date) -> Bool {
        guard let expiry else { return false }
        return now >= expiry
    }

    // MARK: - UserDefaults 用の変換

    public var rawValue: String {
        switch self {
        case .normal:             return "normal"
        case .until:              return "until"
        case .untilEndOfWorkDay:  return "untilEndOfWorkDay"
        case .off:                return "off"
        }
    }

    /// `rawValue` と保存しておいた解除時刻から復元する。
    /// 解除時刻が必要なのに無い／既に過ぎている場合は `.normal` に落とす。
    public init(rawValue: String?, until: Date?, now: Date = Date()) {
        switch rawValue {
        case "off":
            self = .off
        case "until":
            if let until, now < until { self = .until(until) } else { self = .normal }
        case "untilEndOfWorkDay":
            if let until, now < until { self = .untilEndOfWorkDay(until: until) } else { self = .normal }
        default:
            self = .normal
        }
    }

    /// メニュー表示用（残り時間つき）
    public func localizedName(at now: Date = Date()) -> String {
        switch self {
        case .normal:
            return "通常"
        case .off:
            return "会話OFF"
        case .until(let date):
            return "静かにする（残り \(QuietMode.remainingText(from: now, to: date))）"
        case .untilEndOfWorkDay(let date):
            return "今日の仕事終了まで静かにする（残り \(QuietMode.remainingText(from: now, to: date))）"
        }
    }

    public static func remainingText(from now: Date, to date: Date) -> String {
        let seconds = max(0, date.timeIntervalSince(now))
        let minutes = Int((seconds / 60).rounded(.up))
        if minutes >= 60 {
            let hours = minutes / 60
            let rest = minutes % 60
            return rest == 0 ? "\(hours)時間" : "\(hours)時間\(rest)分"
        }
        return "\(minutes)分"
    }
}
