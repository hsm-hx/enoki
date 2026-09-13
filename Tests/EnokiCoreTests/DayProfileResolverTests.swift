import XCTest
@testable import EnokiCore

final class DayProfileResolverTests: XCTestCase {

    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Tokyo")!
        return calendar
    }()

    /// 公式データを読まない（＝現行ルールの計算）インスタンス。2026 年の祝日は計算でも公式データと一致する。
    private let holidays = JapaneseHolidays()

    /// テスト用の日程（同梱データの更新に左右されないように、その場で作る）
    private let schedule = RenofaSchedule(season: "2026", source: "test", matches: [
        RenofaMatch(date: "2026-09-26", kickoff: "14:00", opponent: "SC相模原", home: true, competition: "J3"),      // 土曜
        RenofaMatch(date: "2026-11-03", kickoff: "14:00", opponent: "鹿児島ユナイテッドFC", home: true, competition: "J3"), // 文化の日（火曜）
        RenofaMatch(date: "2026-11-25", kickoff: "19:00", opponent: "福島ユナイテッドFC", home: true, competition: "J3"),   // 平日（水曜）
        RenofaMatch(date: "2026-12-13", opponent: "高知ユナイテッドSC", home: false, competition: "J3"),               // 日曜・キックオフ未定
    ])

    private func date(_ year: Int, _ month: Int, _ day: Int, hour: Int = 12) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour))!
    }

    private func resolve(_ year: Int, _ month: Int, _ day: Int) -> DayProfileDecision {
        DayProfileResolver.resolve(date: date(year, month, day),
                                   schedule: schedule,
                                   holidays: holidays,
                                   calendar: calendar)
    }

    // MARK: - 平日

    func testOrdinaryWeekdayIsLeftToExistingRules() {
        let decision = resolve(2026, 9, 24)   // 木曜・祝日でも試合日でもない
        XCTAssertNil(decision.profileID, "平日は既存ルール（手動選択・仕事中モード連動・default）に任せる")
        XCTAssertEqual(decision.reason, "平日")
    }

    // MARK: - 土日

    func testSaturdayAndSundayAreCasual() {
        let saturday = resolve(2026, 9, 19)
        XCTAssertEqual(saturday.profileID, "casual")
        XCTAssertEqual(saturday.reason, "土曜日")

        let sunday = resolve(2026, 9, 13)
        XCTAssertEqual(sunday.profileID, "casual")
        XCTAssertEqual(sunday.reason, "日曜日")
    }

    // MARK: - 祝日

    func testWeekdayHolidayIsCasual() {
        let decision = resolve(2026, 9, 21)   // 敬老の日（月曜）
        XCTAssertEqual(decision.profileID, "casual")
        XCTAssertEqual(decision.reason, "祝日: 敬老の日")

        // 祝日に挟まれた平日（国民の休日）も休み扱い
        XCTAssertEqual(resolve(2026, 9, 22).profileID, "casual")
        XCTAssertEqual(resolve(2026, 9, 22).reason, "祝日: 国民の休日")
    }

    // MARK: - 試合日（いちばん強い）

    func testWeekdayMatchIsRenofa() {
        let decision = resolve(2026, 11, 25)
        XCTAssertEqual(decision.profileID, "renofa")
        XCTAssertEqual(decision.reason, "レノファ戦 vs 福島ユナイテッドFC (H) 19:00")
    }

    func testMatchWinsOverWeekend() {
        let decision = resolve(2026, 9, 26)   // 土曜の試合日
        XCTAssertEqual(decision.profileID, "renofa", "試合日は土日より強い")
        XCTAssertEqual(decision.reason, "レノファ戦 vs SC相模原 (H) 14:00")
    }

    func testMatchWinsOverHoliday() {
        let decision = resolve(2026, 11, 3)   // 文化の日の試合日
        XCTAssertEqual(decision.profileID, "renofa")
        XCTAssertEqual(decision.reason, "レノファ戦 vs 鹿児島ユナイテッドFC (H) 14:00")
    }

    func testMatchWithoutKickoffTime() {
        let decision = resolve(2026, 12, 13)  // 日曜・キックオフ未定
        XCTAssertEqual(decision.profileID, "renofa")
        XCTAssertEqual(decision.reason, "レノファ戦 vs 高知ユナイテッドSC (A)")
    }

    // MARK: - ルールの並び

    func testRuleOrderIsMatchThenWeekendThenHoliday() {
        let rules = DayProfileResolver.rules(schedule: schedule, holidays: holidays)
        XCTAssertEqual(rules.map(\.name), ["レノファ試合日", "土日", "祝日"])
        XCTAssertEqual(rules.map(\.profileID), ["renofa", "casual", "casual"])
    }

    // MARK: - 日付キー

    func testDayKey() {
        XCTAssertEqual(DayProfileResolver.dayKey(for: date(2026, 9, 13), calendar: calendar), "2026-09-13")
        XCTAssertEqual(DayProfileResolver.dayKey(for: date(2026, 9, 13, hour: 23), calendar: calendar), "2026-09-13")
        XCTAssertEqual(DayProfileResolver.dayKey(for: date(2026, 12, 31), calendar: calendar), "2026-12-31")
    }

    /// 試合日程が空でも曜日・祝日の判定は動く
    func testWorksWithoutSchedule() {
        let decision = DayProfileResolver.resolve(date: date(2026, 11, 3),
                                                  schedule: .empty,
                                                  holidays: holidays,
                                                  calendar: calendar)
        XCTAssertEqual(decision.profileID, "casual")
        XCTAssertEqual(decision.reason, "祝日: 文化の日")
    }
}
