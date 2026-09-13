import Foundation

/// 1 試合
public struct RenofaMatch: Codable, Equatable, Sendable {
    /// yyyy-MM-dd（ローカル暦の日付）
    public let date: String
    /// HH:mm（不明なら nil）
    public let kickoff: String?
    public let opponent: String
    /// ホームゲームか
    public let home: Bool
    /// 大会名（J3 / 天皇杯 …）
    public let competition: String?
    public let venue: String?
    public let note: String?

    public init(date: String,
                kickoff: String? = nil,
                opponent: String,
                home: Bool,
                competition: String? = nil,
                venue: String? = nil,
                note: String? = nil) {
        self.date = date
        self.kickoff = kickoff
        self.opponent = opponent
        self.home = home
        self.competition = competition
        self.venue = venue
        self.note = note
    }

    /// メニュー・ログ用の "(H)" / "(A)"
    public var homeAwayLabel: String { home ? "H" : "A" }

    /// キックオフの時刻（`kickoff` が無ければ nil）。
    /// **いまの判定では使っていません**。将来「試合前／試合中／試合後」で台詞や見た目を変えるための入口です。
    public func kickoffDate(calendar: Calendar = .current) -> Date? {
        guard let day = JapaneseHolidays.parseDayKey(date),
              let kickoff, let time = Self.parseTime(kickoff) else { return nil }
        var components = DateComponents()
        components.year = day.year
        components.month = day.month
        components.day = day.day
        components.hour = time.hour
        components.minute = time.minute
        return calendar.date(from: components)
    }

    static func parseTime(_ value: String) -> (hour: Int, minute: Int)? {
        let parts = value.split(separator: ":", omittingEmptySubsequences: false)
        guard parts.count == 2,
              let hour = Int(parts[0]), let minute = Int(parts[1]),
              (0...23).contains(hour), (0...59).contains(minute) else { return nil }
        return (hour, minute)
    }
}

/// レノファ山口FC の試合日程。
///
/// ```json
/// {"schema_version": 1, "team": "renofa-yamaguchi", "season": "2026",
///  "source": "https://www.renofa.com/…", "updated_at": "2026-09-13",
///  "matches": [{"date": "2026-09-20", "kickoff": "13:00", "opponent": "…", "home": false,
///               "competition": "J3", "venue": "…"}]}
/// ```
///
/// **アプリはネットワークに一切アクセスしません。** このデータは開発時に公式ページから写して同梱するだけです。
public struct RenofaSchedule: Codable, Equatable, Sendable {

    public let schemaVersion: Int
    public let team: String?
    public let season: String?
    /// 取得元（URL か "manual"）
    public let source: String?
    public let updatedAt: String?
    public let matches: [RenofaMatch]

    public static let empty = RenofaSchedule(schemaVersion: 1, team: nil, season: nil,
                                             source: nil, updatedAt: nil, matches: [])

    public init(schemaVersion: Int = 1,
                team: String? = nil,
                season: String? = nil,
                source: String? = nil,
                updatedAt: String? = nil,
                matches: [RenofaMatch]) {
        self.schemaVersion = schemaVersion
        self.team = team
        self.season = season
        self.source = source
        self.updatedAt = updatedAt
        self.matches = matches
    }

    private enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version"
        case team, season, source
        case updatedAt = "updated_at"
        case matches
    }

    public var isEmpty: Bool { matches.isEmpty }

    /// その日の試合（同じ日に複数あれば最初の 1 つ）
    public func match(on date: Date, calendar: Calendar = .current) -> RenofaMatch? {
        let key = DayProfileResolver.dayKey(for: date, calendar: calendar)
        return matches.first { $0.date == key }
    }
}

/// 日程ファイルの読み込みで「その試合だけ捨てた」理由
public enum RenofaScheduleLoadIssue: Error, Equatable, LocalizedError {
    case notAnObject                          // ルートが辞書でない
    case entryNotAnObject(index: Int)
    case invalidDate(index: Int, raw: String)
    case missingOpponent(index: Int)

    public var errorDescription: String? {
        switch self {
        case .notAnObject:
            return "試合日程ファイルのルートがオブジェクトではありません。"
        case .entryNotAnObject(let index):
            return "matches[\(index)] がオブジェクトではありません。"
        case .invalidDate(let index, let raw):
            return "matches[\(index)] の日付が yyyy-MM-dd ではありません: \(raw)"
        case .missingOpponent(let index):
            return "matches[\(index)] に opponent がありません。"
        }
    }
}

/// 読み込み結果。壊れた試合は `issues` に理由が入り、`schedule` からは取り除かれる。
public struct RenofaScheduleLoadResult: Equatable {
    public let schedule: RenofaSchedule
    public let issues: [RenofaScheduleLoadIssue]

    public init(schedule: RenofaSchedule, issues: [RenofaScheduleLoadIssue]) {
        self.schedule = schedule
        self.issues = issues
    }
}

/// `renofa-schedule.json` のローダ。
/// 未知のキーは無視し、「日付が不正 / opponent が無い」試合だけ捨てて残りを返す（`dialogue.json` と同じ流儀）。
public enum RenofaScheduleLoader {

    public static let fileName = "renofa-schedule.json"

    public static func load(data: Data) throws -> RenofaScheduleLoadResult {
        let json = try JSONSerialization.jsonObject(with: data, options: [])
        guard let root = json as? [String: Any] else {
            throw RenofaScheduleLoadIssue.notAnObject
        }

        var matches: [RenofaMatch] = []
        var issues: [RenofaScheduleLoadIssue] = []

        for (index, element) in ((root["matches"] as? [Any]) ?? []).enumerated() {
            guard let entry = element as? [String: Any] else {
                issues.append(.entryNotAnObject(index: index))
                continue
            }
            let rawDate = (entry["date"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            guard JapaneseHolidays.isDayKey(rawDate) else {
                issues.append(.invalidDate(index: index, raw: rawDate))
                continue
            }
            guard let opponent = (entry["opponent"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !opponent.isEmpty else {
                issues.append(.missingOpponent(index: index))
                continue
            }
            let kickoff = (entry["kickoff"] as? String).flatMap { RenofaMatch.parseTime($0) == nil ? nil : $0 }
            matches.append(RenofaMatch(
                date: rawDate,
                kickoff: kickoff,
                opponent: opponent,
                home: (entry["home"] as? NSNumber)?.boolValue ?? false,
                competition: (entry["competition"] as? String).flatMap { $0.isEmpty ? nil : $0 },
                venue: (entry["venue"] as? String).flatMap { $0.isEmpty ? nil : $0 },
                note: (entry["note"] as? String).flatMap { $0.isEmpty ? nil : $0 }))
        }

        let schedule = RenofaSchedule(
            schemaVersion: (root["schema_version"] as? NSNumber)?.intValue ?? 1,
            team: root["team"] as? String,
            season: root["season"] as? String,
            source: root["source"] as? String,
            updatedAt: root["updated_at"] as? String,
            matches: matches.sorted { $0.date < $1.date })
        return RenofaScheduleLoadResult(schedule: schedule, issues: issues)
    }

    public static func load(url: URL) throws -> RenofaScheduleLoadResult {
        try load(data: Data(contentsOf: url))
    }
}
