import XCTest
@testable import EnokiCore

final class JapaneseHolidaysTests: XCTestCase {

    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Tokyo")!
        return calendar
    }()

    /// 同梱の Sources/Enoki/Resources/Holidays/jp-holidays.json（内閣府の公式 CSV から作ったもの）
    private var bundledHolidaysURL: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()          // Tests/EnokiCoreTests
            .deletingLastPathComponent()          // Tests
            .deletingLastPathComponent()          // リポジトリのルート
            .appendingPathComponent("Sources/Enoki/Resources/Holidays/jp-holidays.json")
    }

    private func date(_ year: Int, _ month: Int, _ day: Int) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: 12))!
    }

    private func makeHolidays(overrides: JapaneseHolidayOverrides = .none) throws -> JapaneseHolidays {
        JapaneseHolidays(data: try JapaneseHolidayData.load(url: bundledHolidaysURL), overrides: overrides)
    }

    // MARK: - 同梱データ

    func testBundledDataLoads() throws {
        let data = try JapaneseHolidayData.load(url: bundledHolidaysURL)
        XCTAssertFalse(data.isEmpty, "同梱の祝日データが空です")
        XCTAssertEqual(data.source, "https://www8.cao.go.jp/chosei/shukujitsu/syukujitsu.csv")
        XCTAssertTrue(data.covers(year: 2026), "2026 年はデータに載っているはずです")
        XCTAssertNotNil(data.updatedAt)
    }

    func testKnownHolidays2026() throws {
        let holidays = try makeHolidays()
        XCTAssertTrue(holidays.usesOfficialData(year: 2026))

        let expected: [(Int, Int, String)] = [
            (1, 1, "元日"), (1, 12, "成人の日"), (2, 11, "建国記念の日"), (2, 23, "天皇誕生日"),
            (3, 20, "春分の日"), (4, 29, "昭和の日"), (5, 3, "憲法記念日"), (5, 4, "みどりの日"),
            (5, 5, "こどもの日"), (5, 6, "休日"),        // 5/3 が日曜なので振替
            (7, 20, "海の日"), (8, 11, "山の日"),
            (9, 21, "敬老の日"), (9, 22, "休日"),        // 敬老の日と秋分の日に挟まれた国民の休日
            (9, 23, "秋分の日"), (10, 12, "スポーツの日"),
            (11, 3, "文化の日"), (11, 23, "勤労感謝の日"),
        ]
        for (month, day, name) in expected {
            XCTAssertEqual(holidays.holidayName(on: date(2026, month, day), calendar: calendar), name,
                           "2026-\(month)-\(day) が \(name) になりません")
        }
        XCTAssertEqual(holidays.holidays(in: 2026).count, expected.count)
    }

    func testKnownHolidays2025And2027() throws {
        let holidays = try makeHolidays()
        XCTAssertEqual(holidays.holidayName(on: date(2025, 3, 20), calendar: calendar), "春分の日")
        XCTAssertEqual(holidays.holidayName(on: date(2025, 9, 23), calendar: calendar), "秋分の日")
        XCTAssertNotNil(holidays.holidayName(on: date(2025, 11, 24), calendar: calendar), "11/23 が日曜なので振替休日")

        XCTAssertEqual(holidays.holidayName(on: date(2027, 1, 11), calendar: calendar), "成人の日")
        XCTAssertEqual(holidays.holidayName(on: date(2027, 3, 21), calendar: calendar), "春分の日")
        XCTAssertEqual(holidays.holidayName(on: date(2027, 9, 20), calendar: calendar), "敬老の日")
        XCTAssertEqual(holidays.holidayName(on: date(2027, 9, 23), calendar: calendar), "秋分の日")
        XCTAssertEqual(holidays.holidayName(on: date(2027, 10, 11), calendar: calendar), "スポーツの日")
    }

    func testOrdinaryDaysAreNotHolidays() throws {
        let holidays = try makeHolidays()
        XCTAssertNil(holidays.holidayName(on: date(2026, 3, 19), calendar: calendar))
        XCTAssertNil(holidays.holidayName(on: date(2026, 9, 24), calendar: calendar))
        XCTAssertFalse(holidays.isHoliday(date(2026, 9, 13), calendar: calendar))
    }

    func testYearBoundary() throws {
        let holidays = try makeHolidays()
        XCTAssertNil(holidays.holidayName(on: date(2026, 12, 31), calendar: calendar))
        XCTAssertEqual(holidays.holidayName(on: date(2027, 1, 1), calendar: calendar), "元日")
        XCTAssertNil(holidays.holidayName(on: date(2025, 12, 31), calendar: calendar))
        XCTAssertEqual(holidays.holidayName(on: date(2026, 1, 1), calendar: calendar), "元日")
    }

    // MARK: - データに無い年（保険の計算）

    func testFallbackForYearsOutsideData() throws {
        let holidays = try makeHolidays()
        XCTAssertFalse(holidays.usesOfficialData(year: 2035), "2035 年はまだ公式データに載っていません")

        // 2035: 成人の日 = 1月第2月曜(8日), 春分 3/21, 海の日 = 7月第3月曜(16日), 秋分 9/23
        XCTAssertEqual(holidays.holidayName(on: date(2035, 1, 8), calendar: calendar), "成人の日")
        XCTAssertEqual(holidays.holidayName(on: date(2035, 3, 21), calendar: calendar), "春分の日")
        XCTAssertEqual(holidays.holidayName(on: date(2035, 7, 16), calendar: calendar), "海の日")
        XCTAssertEqual(holidays.holidayName(on: date(2035, 9, 23), calendar: calendar), "秋分の日")
        XCTAssertEqual(holidays.holidayName(on: date(2035, 9, 24), calendar: calendar), "振替休日",
                       "2035-09-23（秋分の日）は日曜")
        XCTAssertNil(holidays.holidayName(on: date(2035, 3, 19), calendar: calendar))
    }

    /// 計算だけのインスタンス（データを読み込んでいない）でも 2026 年が合うこと
    func testFallbackMatchesOfficialDataFor2026() {
        let calculated = JapaneseHolidays()
        XCTAssertFalse(calculated.usesOfficialData(year: 2026))
        for (month, day) in [(1, 1), (1, 12), (2, 11), (2, 23), (3, 20), (4, 29), (5, 3), (5, 4), (5, 5),
                             (5, 6), (7, 20), (8, 11), (9, 21), (9, 22), (9, 23), (10, 12), (11, 3), (11, 23)] {
            XCTAssertTrue(calculated.isHoliday(date(2026, month, day), calendar: calendar),
                          "計算で 2026-\(month)-\(day) が祝日になりません")
        }
        XCTAssertEqual(calculated.holidayName(on: date(2026, 9, 22), calendar: calendar), "国民の休日")
        XCTAssertEqual(calculated.holidayName(on: date(2026, 5, 6), calendar: calendar), "振替休日")
        XCTAssertEqual(calculated.holidays(in: 2026).count, 18)
    }

    // MARK: - 特例ファイル

    func testOverridesAddAndRemove() throws {
        let overrides = JapaneseHolidayOverrides.load(data: Data("""
        {"add": [{"date": "2026-09-13", "name": "テストの日"}], "remove": ["2026-11-03"]}
        """.utf8))
        XCTAssertEqual(overrides.add.count, 1)
        XCTAssertEqual(overrides.remove, ["2026-11-03"])

        let holidays = try makeHolidays(overrides: overrides)
        XCTAssertEqual(holidays.holidayName(on: date(2026, 9, 13), calendar: calendar), "テストの日")
        XCTAssertNil(holidays.holidayName(on: date(2026, 11, 3), calendar: calendar), "除外した祝日は消える")
        XCTAssertEqual(holidays.holidayName(on: date(2026, 11, 23), calendar: calendar), "勤労感謝の日")
    }

    func testBrokenOverridesAreIgnored() {
        let overrides = JapaneseHolidayOverrides.load(data: Data("""
        {"add": [{"date": "2026/09/13", "name": "書式違い"}, {"name": "日付なし"}], "remove": ["ぜんぶ"]}
        """.utf8))
        XCTAssertEqual(overrides, .none)
        XCTAssertEqual(JapaneseHolidayOverrides.load(data: Data("こわれている".utf8)), .none)
    }
}
