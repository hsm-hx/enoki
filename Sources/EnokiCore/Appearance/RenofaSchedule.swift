import Foundation

/// 試合日の「いまどの局面か」。
///
/// キックオフ時刻が分かっている試合だけ細かく分かれます（不明なら終日 `.matchDay`）。
/// **試合結果（勝ち負け・得点）は見ません。** アプリはネットワークに一切アクセスしないので、
/// 「どちらが勝ったか」を知る手段がなく、台詞も結果に踏み込まない書き方にしてあります。
public enum MatchPhase: String, Equatable, Sendable {
    /// 試合の日だが、まだキックオフまで間がある（またはキックオフ時刻が不明）
    case matchDay
    /// キックオフ直前
    case preMatch
    /// 試合中
    case inMatch
    /// 試合直後
    case postMatch
    /// 試合後の余韻も過ぎた（この日はもう試合の話をしない）
    case finished

    /// メニュー・About に出す日本語名（`profiles.json` の `spriteSetsByPhase` のキーは `rawValue`）
    public var localizedName: String {
        switch self {
        case .matchDay:  return "試合日"
        case .preMatch:  return "試合前"
        case .inMatch:   return "試合中"
        case .postMatch: return "試合後"
        case .finished:  return "終了後"
        }
    }

    /// この局面で話してよい renofa 系カテゴリ（`.finished` は nil = どれも話さない）
    public var dialogueCategory: DialogueCategory? {
        switch self {
        case .matchDay:  return .renofa
        case .preMatch:  return .renofaPreMatch
        case .inMatch:   return .renofaMatch
        case .postMatch: return .renofaPostMatch
        case .finished:  return nil
        }
    }
}

/// 局面の窓の長さ。キックオフ時刻を中心に前後の幅だけを決める（値を変えれば局面の切り替わりも変わる）。
public struct MatchPhaseWindows: Equatable, Sendable {
    /// キックオフの何秒前から `.preMatch` にするか（既定 120 分）
    public var preMatchLead: TimeInterval
    /// キックオフから何秒を `.inMatch` とみなすか（既定 120 分。前後半 + ハーフタイム + ロスタイムの目安）
    public var matchDuration: TimeInterval
    /// 試合終了の見込み時刻から何秒を `.postMatch` にするか（既定 120 分）
    public var postMatchLength: TimeInterval

    public init(preMatchLead: TimeInterval = 120 * 60,
                matchDuration: TimeInterval = 120 * 60,
                postMatchLength: TimeInterval = 120 * 60) {
        self.preMatchLead = preMatchLead
        self.matchDuration = matchDuration
        self.postMatchLength = postMatchLength
    }
}

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
    /// 「試合前／試合中／試合後」の判定（`phase(at:windows:calendar:)`）の基準になります。
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

    /// この試合の、その時刻での局面。
    ///
    /// - キックオフ不明: 終日 `.matchDay`
    /// - `[00:00, kickoff-120分)` → `.matchDay` / `[kickoff-120分, kickoff)` → `.preMatch`
    /// - `[kickoff, kickoff+120分)` → `.inMatch` / `[kickoff+120分, kickoff+240分)` → `.postMatch`
    /// - それ以降 → `.finished`
    ///
    /// 窓の長さは `MatchPhaseWindows` で変えられます。
    public func phase(at date: Date,
                      windows: MatchPhaseWindows = MatchPhaseWindows(),
                      calendar: Calendar = .current) -> MatchPhase {
        guard let kickoff = kickoffDate(calendar: calendar) else { return .matchDay }
        if date < kickoff.addingTimeInterval(-windows.preMatchLead) { return .matchDay }
        if date < kickoff { return .preMatch }
        let end = kickoff.addingTimeInterval(windows.matchDuration)
        if date < end { return .inMatch }
        if date < end.addingTimeInterval(windows.postMatchLength) { return .postMatch }
        return .finished
    }

    /// 局面が切り替わる時刻（早い順）。キックオフが分からない試合は空。
    ///
    /// `kickoff-preMatchLead`（→ `.preMatch`） / `kickoff`（→ `.inMatch`） /
    /// `kickoff+matchDuration`（→ `.postMatch`） / `kickoff+matchDuration+postMatchLength`（→ `.finished`）の 4 つ。
    /// 見た目を局面に合わせて切り替えるとき、この時刻にだけタイマーを張ればよい（ポーリング不要）。
    public func phaseBoundaries(windows: MatchPhaseWindows = MatchPhaseWindows(),
                                calendar: Calendar = .current) -> [Date] {
        guard let kickoff = kickoffDate(calendar: calendar) else { return [] }
        let end = kickoff.addingTimeInterval(windows.matchDuration)
        return [kickoff.addingTimeInterval(-windows.preMatchLead),
                kickoff,
                end,
                end.addingTimeInterval(windows.postMatchLength)]
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

    /// その時刻の局面（その日に試合が無ければ nil）
    public func phase(at date: Date,
                      windows: MatchPhaseWindows = MatchPhaseWindows(),
                      calendar: Calendar = .current) -> MatchPhase? {
        match(on: date, calendar: calendar)?.phase(at: date, windows: windows, calendar: calendar)
    }

    /// その時刻より後の、いちばん近い局面の切り替わり時刻（その日に試合が無い・キックオフ不明・
    /// もう全部過ぎた場合は nil）。局面タイマーを 1 本だけ張るために使う。
    public func nextPhaseBoundary(after date: Date,
                                  windows: MatchPhaseWindows = MatchPhaseWindows(),
                                  calendar: Calendar = .current) -> Date? {
        guard let match = match(on: date, calendar: calendar) else { return nil }
        return match.phaseBoundaries(windows: windows, calendar: calendar)
            .first { $0 > date }
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
