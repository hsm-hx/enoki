import XCTest
@testable import EnokiCore

final class RenofaScheduleTests: XCTestCase {

    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Tokyo")!
        return calendar
    }()

    /// 同梱の Sources/Enoki/Resources/Schedule/renofa-schedule.json
    private var bundledScheduleURL: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()          // Tests/EnokiCoreTests
            .deletingLastPathComponent()          // Tests
            .deletingLastPathComponent()          // リポジトリのルート
            .appendingPathComponent("Sources/Enoki/Resources/Schedule/renofa-schedule.json")
    }

    private func date(_ year: Int, _ month: Int, _ day: Int, hour: Int = 12) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour))!
    }

    // MARK: - 同梱ファイル

    func testBundledScheduleLoads() throws {
        let result = try RenofaScheduleLoader.load(url: bundledScheduleURL)
        XCTAssertEqual(result.issues, [], "同梱の試合日程に壊れた項目があります")
        XCTAssertEqual(result.schedule.schemaVersion, 1)
        XCTAssertEqual(result.schedule.team, "renofa-yamaguchi")
        XCTAssertNotNil(result.schedule.source, "取得元を書いておくこと（URL か \"manual\"）")

        // 試合が 0 件でも壊れていないこと（日程を空にして配布することもある）
        for match in result.schedule.matches {
            XCTAssertNotNil(JapaneseHolidays.parseDayKey(match.date), "日付が yyyy-MM-dd でありません: \(match.date)")
            XCTAssertFalse(match.opponent.isEmpty)
        }
        // 日付順に並んでいる
        XCTAssertEqual(result.schedule.matches.map(\.date), result.schedule.matches.map(\.date).sorted())
    }

    // MARK: - 読み込み

    func testBrokenMatchesAreDroppedIndividually() throws {
        let json = """
        {
          "schema_version": 1,
          "team": "renofa-yamaguchi",
          "season": "2026",
          "source": "manual",
          "updated_at": "2026-09-13",
          "matches": [
            {"date": "2026-09-20", "kickoff": "13:00", "opponent": "ツエーゲン金沢", "home": false, "competition": "J3"},
            {"date": "2026/09/26", "opponent": "SC相模原", "home": true},
            {"date": "2026-10-03", "home": false},
            "文字列",
            {"date": "2026-10-18", "kickoff": "ごご2時", "opponent": "高知ユナイテッドSC", "home": true}
          ]
        }
        """
        let result = try RenofaScheduleLoader.load(data: Data(json.utf8))
        XCTAssertEqual(result.schedule.matches.count, 2)
        XCTAssertEqual(result.issues, [
            .invalidDate(index: 1, raw: "2026/09/26"),
            .missingOpponent(index: 2),
            .entryNotAnObject(index: 3),
        ])
        // 時刻の書式が違う試合は、キックオフだけ捨てて試合自体は残す
        XCTAssertEqual(result.schedule.matches.last?.date, "2026-10-18")
        XCTAssertNil(result.schedule.matches.last?.kickoff)
    }

    func testRootMustBeAnObject() {
        XCTAssertThrowsError(try RenofaScheduleLoader.load(data: Data("[]".utf8))) { error in
            XCTAssertEqual(error as? RenofaScheduleLoadIssue, .notAnObject)
        }
    }

    func testEmptyScheduleIsValid() throws {
        let result = try RenofaScheduleLoader.load(data: Data(#"{"schema_version": 1, "source": "manual", "matches": []}"#.utf8))
        XCTAssertEqual(result.issues, [])
        XCTAssertTrue(result.schedule.isEmpty)
        XCTAssertNil(result.schedule.match(on: date(2026, 9, 20), calendar: calendar))
    }

    // MARK: - 問い合わせ

    func testMatchOnDate() throws {
        let schedule = RenofaSchedule(matches: [
            RenofaMatch(date: "2026-09-20", kickoff: "13:00", opponent: "ツエーゲン金沢", home: false, competition: "J3"),
            RenofaMatch(date: "2026-09-26", kickoff: "14:00", opponent: "SC相模原", home: true, competition: "J3"),
        ])
        XCTAssertEqual(schedule.match(on: date(2026, 9, 20), calendar: calendar)?.opponent, "ツエーゲン金沢")
        // 同じ日なら時刻は問わない（深夜でも当日扱い）
        XCTAssertEqual(schedule.match(on: date(2026, 9, 20, hour: 23), calendar: calendar)?.opponent, "ツエーゲン金沢")
        XCTAssertNil(schedule.match(on: date(2026, 9, 21), calendar: calendar))
        XCTAssertEqual(schedule.match(on: date(2026, 9, 26), calendar: calendar)?.homeAwayLabel, "H")
        XCTAssertEqual(schedule.match(on: date(2026, 9, 20), calendar: calendar)?.homeAwayLabel, "A")
    }

    func testKickoffDate() {
        let match = RenofaMatch(date: "2026-09-20", kickoff: "13:00", opponent: "ツエーゲン金沢", home: false)
        XCTAssertEqual(match.kickoffDate(calendar: calendar),
                       calendar.date(from: DateComponents(year: 2026, month: 9, day: 20, hour: 13, minute: 0)))

        // キックオフ未定なら nil
        let undecided = RenofaMatch(date: "2026-09-20", opponent: "ツエーゲン金沢", home: false)
        XCTAssertNil(undecided.kickoffDate(calendar: calendar))
    }
}
