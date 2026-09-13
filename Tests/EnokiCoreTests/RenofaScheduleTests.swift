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

    // MARK: - 局面（試合前・試合中・試合後）

    private func dateTime(_ hour: Int, _ minute: Int, day: Int = 20) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 9, day: day, hour: hour, minute: minute))!
    }

    /// 2026-09-20 13:00 キックオフ
    private var kickoffMatch: RenofaMatch {
        RenofaMatch(date: "2026-09-20", kickoff: "13:00", opponent: "ツエーゲン金沢", home: false, competition: "J3")
    }

    func testPhaseBoundaries() {
        let match = kickoffMatch
        func phase(_ hour: Int, _ minute: Int) -> MatchPhase {
            match.phase(at: dateTime(hour, minute), calendar: calendar)
        }
        XCTAssertEqual(phase(0, 0), .matchDay)
        XCTAssertEqual(phase(11, 29), .matchDay)
        XCTAssertEqual(phase(11, 30), .preMatch)    // キックオフ 90 分前ちょうど
        XCTAssertEqual(phase(12, 59), .preMatch)
        XCTAssertEqual(phase(13, 0), .inMatch)      // キックオフちょうど
        XCTAssertEqual(phase(14, 59), .inMatch)
        XCTAssertEqual(phase(15, 0), .postMatch)    // +120 分ちょうど
        XCTAssertEqual(phase(16, 59), .postMatch)
        XCTAssertEqual(phase(17, 0), .finished)     // +240 分ちょうど
        XCTAssertEqual(phase(23, 59), .finished)
    }

    func testPhaseWithoutKickoffIsMatchDayAllDay() {
        let match = RenofaMatch(date: "2026-09-20", opponent: "ツエーゲン金沢", home: false)
        for hour in 0..<24 {
            XCTAssertEqual(match.phase(at: dateTime(hour, 30), calendar: calendar), .matchDay, "\(hour) 時")
        }
    }

    func testPhaseWindowsAreConfigurable() {
        let match = kickoffMatch
        let windows = MatchPhaseWindows(preMatchLead: 30 * 60, matchDuration: 60 * 60, postMatchLength: 30 * 60)
        XCTAssertEqual(match.phase(at: dateTime(12, 0), windows: windows, calendar: calendar), .matchDay)
        XCTAssertEqual(match.phase(at: dateTime(12, 30), windows: windows, calendar: calendar), .preMatch)
        XCTAssertEqual(match.phase(at: dateTime(13, 30), windows: windows, calendar: calendar), .inMatch)
        XCTAssertEqual(match.phase(at: dateTime(14, 0), windows: windows, calendar: calendar), .postMatch)
        XCTAssertEqual(match.phase(at: dateTime(14, 30), windows: windows, calendar: calendar), .finished)
    }

    func testSchedulePhaseIsNilOnNonMatchDay() {
        let schedule = RenofaSchedule(matches: [kickoffMatch])
        XCTAssertEqual(schedule.phase(at: dateTime(13, 30), calendar: calendar), .inMatch)
        XCTAssertNil(schedule.phase(at: dateTime(13, 30, day: 21), calendar: calendar), "試合日でない日は nil")
        XCTAssertNil(RenofaSchedule.empty.phase(at: dateTime(13, 30), calendar: calendar))
    }

    func testPhaseDialogueCategory() {
        XCTAssertEqual(MatchPhase.matchDay.dialogueCategory, .renofa)
        XCTAssertEqual(MatchPhase.preMatch.dialogueCategory, .renofaPreMatch)
        XCTAssertEqual(MatchPhase.inMatch.dialogueCategory, .renofaMatch)
        XCTAssertEqual(MatchPhase.postMatch.dialogueCategory, .renofaPostMatch)
        XCTAssertNil(MatchPhase.finished.dialogueCategory)
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
