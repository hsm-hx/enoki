import Foundation

/// 内閣府の公式データ（`jp-holidays.json`）。`scripts/update_holidays.py` が作ります。
///
/// ```json
/// {"schema_version": 1, "source": "https://www8.cao.go.jp/…/syukujitsu.csv", "updated_at": "2026-09-13",
///  "first_year": 1955, "last_year": 2027, "holidays": {"2026-01-01": "元日", …}}
/// ```
public struct JapaneseHolidayData: Equatable, Sendable {

    /// 同梱ファイル名（ユーザー側の置き場も同じ名前）
    public static let fileName = "jp-holidays.json"

    public let source: String?
    public let updatedAt: String?
    /// データが載っている年の範囲（空なら nil）
    public let firstYear: Int?
    public let lastYear: Int?
    /// "yyyy-MM-dd" → 祝日名（振替休日・国民の休日は公式 CSV では「休日」）
    public let holidays: [String: String]

    public static let empty = JapaneseHolidayData(source: nil, updatedAt: nil, holidays: [:])

    public init(source: String?, updatedAt: String?, holidays: [String: String]) {
        self.source = source
        self.updatedAt = updatedAt
        self.holidays = holidays
        let years = holidays.keys.compactMap { JapaneseHolidays.parseDayKey($0)?.year }
        self.firstYear = years.min()
        self.lastYear = years.max()
    }

    public var isEmpty: Bool { holidays.isEmpty }

    /// その年がデータの範囲内か（範囲内ならアルゴリズム計算は使わない）
    public func covers(year: Int) -> Bool {
        guard let firstYear, let lastYear else { return false }
        return (firstYear...lastYear).contains(year)
    }

    /// 壊れた項目だけ捨てて読む（ファイル全体は失敗させない）
    public static func load(data: Data) -> JapaneseHolidayData {
        guard let root = (try? JSONSerialization.jsonObject(with: data, options: [])) as? [String: Any],
              let raw = root["holidays"] as? [String: Any] else { return .empty }
        var holidays: [String: String] = [:]
        for (key, value) in raw {
            guard JapaneseHolidays.isDayKey(key),
                  let name = (value as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !name.isEmpty else { continue }
            holidays[key] = name
        }
        return JapaneseHolidayData(source: root["source"] as? String,
                                   updatedAt: root["updated_at"] as? String,
                                   holidays: holidays)
    }

    public static func load(url: URL) throws -> JapaneseHolidayData {
        load(data: try Data(contentsOf: url))
    }
}

/// `holidays-overrides.json` の中身（一過性の特例を手で足し引きするためのファイル）
///
/// ```json
/// {"add": [{"date": "2021-07-22", "name": "海の日"}], "remove": ["2021-07-19"]}
/// ```
public struct JapaneseHolidayOverrides: Equatable, Sendable {

    public struct Entry: Equatable, Sendable {
        public let date: String     // yyyy-MM-dd
        public let name: String

        public init(date: String, name: String) {
            self.date = date
            self.name = name
        }
    }

    /// 追加する祝日
    public let add: [Entry]
    /// 取り消す祝日（yyyy-MM-dd）
    public let remove: Set<String>

    public static let none = JapaneseHolidayOverrides(add: [], remove: [])

    public init(add: [Entry], remove: Set<String>) {
        self.add = add
        self.remove = remove
    }

    /// 置き場のファイル名（`~/Library/Application Support/Enoki/holidays-overrides.json`）
    public static let fileName = "holidays-overrides.json"

    /// 壊れた項目だけ捨てて読む（`dialogue.json` と同じ流儀）
    public static func load(data: Data) -> JapaneseHolidayOverrides {
        guard let root = (try? JSONSerialization.jsonObject(with: data, options: [])) as? [String: Any] else {
            return .none
        }
        var add: [Entry] = []
        for element in (root["add"] as? [Any]) ?? [] {
            guard let entry = element as? [String: Any],
                  let date = (entry["date"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
                  JapaneseHolidays.isDayKey(date) else { continue }
            let name = (entry["name"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? "祝日"
            add.append(Entry(date: date, name: name))
        }
        let remove = Set(((root["remove"] as? [Any]) ?? [])
            .compactMap { $0 as? String }
            .filter(JapaneseHolidays.isDayKey))
        return JapaneseHolidayOverrides(add: add, remove: remove)
    }

    public static func load(url: URL) -> JapaneseHolidayOverrides {
        guard let data = try? Data(contentsOf: url) else { return .none }
        return load(data: data)
    }
}

/// 日本の祝日。**内閣府の公式データが第一ソース**で、データに無い年だけ現行ルールで計算します。
///
/// | 年 | どう決まるか |
/// |---|---|
/// | `data` の範囲内（既定の同梱データは 1955〜翌年） | **公式データをそのまま引く**（振替休日・国民の休日も入っている） |
/// | 範囲外（データを更新し忘れた年・先の年） | 現行ルールで計算する保険（`fallbackHolidays`） |
///
/// どちらの結果にも最後に `holidays-overrides.json` の add / remove を適用します（データより優先）。
/// 曜日と日付の加減算は自前のユリウス通日で行うので、暦やタイムゾーンの設定に左右されません
/// （`Date` → 年月日の取り出しだけ `Calendar` を使います）。
public final class JapaneseHolidays: @unchecked Sendable {

    /// 公式データを読み込んでいない既定のインスタンス（＝すべて計算で補う）。
    /// アプリ本体は `AppearanceCoordinator` が同梱 JSON を読んで `init(data:overrides:)` で作ります。
    public static let shared = JapaneseHolidays()

    public let data: JapaneseHolidayData
    public let overrides: JapaneseHolidayOverrides

    private let lock = NSLock()
    /// 年 → (月日 → 名前)
    private var cache: [Int: [MonthDay: String]] = [:]
    /// 公式データを年ごとに引けるようにしたもの
    private let dataByYear: [Int: [MonthDay: String]]

    public init(data: JapaneseHolidayData = .empty, overrides: JapaneseHolidayOverrides = .none) {
        self.data = data
        self.overrides = overrides
        var byYear: [Int: [MonthDay: String]] = [:]
        for (key, name) in data.holidays {
            guard let parsed = Self.parseDayKey(key) else { continue }
            byYear[parsed.year, default: [:]][MonthDay(month: parsed.month, day: parsed.day)] = name
        }
        self.dataByYear = byYear
    }

    // MARK: - 問い合わせ

    /// その日が祝日なら名前を返す（祝日でなければ nil）
    public func holidayName(on date: Date, calendar: Calendar = .current) -> String? {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        guard let year = parts.year, let month = parts.month, let day = parts.day else { return nil }
        return holidayMap(year: year)[MonthDay(month: month, day: day)]
    }

    public func isHoliday(_ date: Date, calendar: Calendar = .current) -> Bool {
        holidayName(on: date, calendar: calendar) != nil
    }

    /// その年を公式データで引けるか（false なら計算で補っている）
    public func usesOfficialData(year: Int) -> Bool { data.covers(year: year) }

    /// その年の祝日を日付順に返す（確認・テスト用）
    public func holidays(in year: Int) -> [(date: String, name: String)] {
        holidayMap(year: year)
            .map { (String(format: "%04d-%02d-%02d", year, $0.key.month, $0.key.day), $0.value) }
            .sorted { $0.0 < $1.0 }
            .map { (date: $0.0, name: $0.1) }
    }

    // MARK: - 解決

    private func holidayMap(year: Int) -> [MonthDay: String] {
        lock.lock()
        if let cached = cache[year] {
            lock.unlock()
            return cached
        }
        lock.unlock()

        var map = data.covers(year: year) ? (dataByYear[year] ?? [:]) : Self.fallbackHolidays(year: year)
        applyOverrides(to: &map, year: year)

        lock.lock()
        cache[year] = map
        lock.unlock()
        return map
    }

    private func applyOverrides(to map: inout [MonthDay: String], year: Int) {
        for key in overrides.remove {
            guard let parsed = Self.parseDayKey(key), parsed.year == year else { continue }
            map.removeValue(forKey: MonthDay(month: parsed.month, day: parsed.day))
        }
        for entry in overrides.add {
            guard let parsed = Self.parseDayKey(entry.date), parsed.year == year else { continue }
            map[MonthDay(month: parsed.month, day: parsed.day)] = entry.name
        }
    }

    // MARK: - 保険（データに無い年の計算）

    /// 「国民の祝日に関する法律」の**現行ルール**で 1 年分を計算する。
    /// 前後の年もまとめて計算してから対象年だけ切り出す（12/31 → 1/1 をまたぐ振替・国民の休日のため）。
    ///
    /// - 注意: 現行ルールで過去も計算するので、制度が変わる前の年（山の日の前など）や
    ///   五輪年の移動といった一過性の特例は合いません。公式データの範囲内ならこの計算は使いません。
    static func fallbackHolidays(year: Int) -> [MonthDay: String] {
        var base: [Int: String] = [:]   // ユリウス通日 → 祝日名
        for y in (year - 1)...(year + 1) {
            for holiday in statutoryHolidays(year: y) {
                base[julianDay(year: y, month: holiday.month, day: holiday.day)] = holiday.name
            }
        }

        var resolved = base

        // 振替休日: 祝日が日曜なら、その後の最初の「祝日でない日」
        for day in base.keys.sorted() where weekdayIndex(julianDay: day) == 6 {
            var next = day + 1
            while base[next] != nil { next += 1 }
            if resolved[next] == nil { resolved[next] = "振替休日" }
        }

        // 国民の休日: 祝日に挟まれた平日（日曜・祝日・振替休日は対象外。例: 2026-09-22）
        for day in base.keys.sorted() {
            let middle = day + 1
            guard base[middle] == nil, resolved[middle] == nil,
                  weekdayIndex(julianDay: middle) != 6,
                  base[middle + 1] != nil else { continue }
            resolved[middle] = "国民の休日"
        }

        var map: [MonthDay: String] = [:]
        for (day, name) in resolved {
            let date = gregorian(julianDay: day)
            guard date.year == year else { continue }
            map[MonthDay(month: date.month, day: date.day)] = name
        }
        return map
    }

    /// 法律で決まっている 16 日（振替休日・国民の休日を除く）
    static func statutoryHolidays(year: Int) -> [(month: Int, day: Int, name: String)] {
        [
            (1, 1, "元日"),
            (1, nthMonday(year: year, month: 1, nth: 2), "成人の日"),
            (2, 11, "建国記念の日"),
            (2, 23, "天皇誕生日"),
            (3, vernalEquinoxDay(year: year), "春分の日"),
            (4, 29, "昭和の日"),
            (5, 3, "憲法記念日"),
            (5, 4, "みどりの日"),
            (5, 5, "こどもの日"),
            (7, nthMonday(year: year, month: 7, nth: 3), "海の日"),
            (8, 11, "山の日"),
            (9, nthMonday(year: year, month: 9, nth: 3), "敬老の日"),
            (9, autumnalEquinoxDay(year: year), "秋分の日"),
            (10, nthMonday(year: year, month: 10, nth: 2), "スポーツの日"),
            (11, 3, "文化の日"),
            (11, 23, "勤労感謝の日"),
        ]
    }

    /// 春分の日（1980〜2099 で有効な近似式）
    static func vernalEquinoxDay(year: Int) -> Int {
        equinoxDay(year: year, constant: 20.8431)
    }

    /// 秋分の日（1980〜2099 で有効な近似式）
    static func autumnalEquinoxDay(year: Int) -> Int {
        equinoxDay(year: year, constant: 23.2488)
    }

    private static func equinoxDay(year: Int, constant: Double) -> Int {
        let elapsed = year - 1980
        let leaps = Int(floor(Double(elapsed) / 4.0))
        return Int(floor(constant + 0.242194 * Double(elapsed))) - leaps
    }

    /// その月の第 n 月曜（ハッピーマンデー）
    static func nthMonday(year: Int, month: Int, nth: Int) -> Int {
        let first = weekdayIndex(julianDay: julianDay(year: year, month: month, day: 1))
        let offsetToMonday = (7 - first) % 7
        return 1 + offsetToMonday + 7 * (nth - 1)
    }

    // MARK: - 暦の計算（ユリウス通日）

    /// 0 = 月曜 … 6 = 日曜
    static func weekdayIndex(julianDay: Int) -> Int {
        let remainder = julianDay % 7
        return remainder < 0 ? remainder + 7 : remainder
    }

    static func julianDay(year: Int, month: Int, day: Int) -> Int {
        let a = (14 - month) / 12
        let y = year + 4800 - a
        let m = month + 12 * a - 3
        return day + (153 * m + 2) / 5 + 365 * y + y / 4 - y / 100 + y / 400 - 32045
    }

    static func gregorian(julianDay: Int) -> (year: Int, month: Int, day: Int) {
        let a = julianDay + 32044
        let b = (4 * a + 3) / 146097
        let c = a - 146097 * b / 4
        let d = (4 * c + 3) / 1461
        let e = c - 1461 * d / 4
        let m = (5 * e + 2) / 153
        return (year: 100 * b + d - 4800 + m / 10,
                month: m + 3 - 12 * (m / 10),
                day: e - (153 * m + 2) / 5 + 1)
    }

    // MARK: - yyyy-MM-dd

    static func isDayKey(_ value: String) -> Bool { parseDayKey(value) != nil }

    static func parseDayKey(_ value: String) -> (year: Int, month: Int, day: Int)? {
        let parts = value.split(separator: "-", omittingEmptySubsequences: false)
        guard parts.count == 3,
              parts[0].count == 4, parts[1].count == 2, parts[2].count == 2,
              let year = Int(parts[0]), let month = Int(parts[1]), let day = Int(parts[2]),
              (1...12).contains(month), (1...31).contains(day) else { return nil }
        return (year, month, day)
    }

    struct MonthDay: Hashable {
        let month: Int
        let day: Int
    }
}
