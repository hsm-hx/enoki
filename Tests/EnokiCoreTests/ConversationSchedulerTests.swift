import XCTest
@testable import EnokiCore

final class ConversationSchedulerTests: XCTestCase {

    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Tokyo")!
        return calendar
    }()

    /// 2026-03-02（月）
    private func date(_ hour: Int, _ minute: Int = 0, day: Int = 2) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 3, day: day, hour: hour, minute: minute))!
    }

    /// 乱数は常に下限（globalGap=20分, break=50分, water=105分, encouragement=70分,
    /// ambient=40分, workReturn=10分, lunch=12:00-20分=11:40）
    private func makeScheduler(start: Date? = nil,
                               mode: ActivityMode = .work,
                               quiet: QuietMode = .normal) -> ConversationScheduler {
        let scheduler = ConversationScheduler(sessionStart: start ?? date(9),
                                              activityMode: mode,
                                              quietMode: quiet,
                                              workEndHour: 18,
                                              calendar: calendar)
        scheduler.randomInterval = { $0.lowerBound }
        return scheduler
    }

    private func conversation(_ category: DialogueCategory) -> Conversation {
        Conversation(id: "\(category.rawValue)_1", category: category,
                     lines: [DialogueLine(speaker: .saku, text: "…")])
    }

    // MARK: - 基本

    func testSilentRightAfterLaunch() {
        let scheduler = makeScheduler()
        XCTAssertEqual(scheduler.evaluate(now: date(9, 1)), [])
        XCTAssertEqual(scheduler.evaluate(now: date(9, 19)), [])   // 最低間隔 20 分の手前
    }

    func testBreakAfterFiftyFiveMinutes() {
        let scheduler = makeScheduler()
        let categories = scheduler.evaluate(now: date(9, 55))
        XCTAssertEqual(categories.first, .break)
        XCTAssertFalse(categories.contains(.water))          // 水分は 105 分後
        XCTAssertFalse(categories.contains(.encouragement))  // 励ましは 13 時から
        XCTAssertEqual(categories, [.break, .ambient, .pair])
    }

    func testWaterAfterItsInterval() {
        let scheduler = makeScheduler()
        let categories = scheduler.evaluate(now: date(10, 45))   // 9:00 + 105 分
        XCTAssertEqual(categories.first, .water)
    }

    func testLunchOnlyInsideItsWindow() {
        let scheduler = makeScheduler()
        XCTAssertFalse(scheduler.evaluate(now: date(11, 0)).contains(.lunch))    // 窓の前
        XCTAssertFalse(scheduler.evaluate(now: date(11, 35)).contains(.lunch))   // 窓の中だが目標時刻（11:40）前
        XCTAssertEqual(scheduler.evaluate(now: date(11, 45)).first, .lunch)
        XCTAssertFalse(scheduler.evaluate(now: date(14, 30)).contains(.lunch))   // 窓の後
    }

    func testLunchOncePerDay() {
        let scheduler = makeScheduler()
        scheduler.record(conversation(.lunch), at: date(11, 45))
        XCTAssertFalse(scheduler.evaluate(now: date(13, 30)).contains(.lunch))
        // 翌日はまた出る
        let tomorrow = makeScheduler(start: date(9, 0, day: 3))
        tomorrow.record(conversation(.lunch), at: date(11, 45))
        tomorrow.record(conversation(.ambient), at: date(9, 10, day: 3))
        XCTAssertTrue(tomorrow.evaluate(now: date(11, 45, day: 3)).contains(.lunch))
    }

    func testWorkReturnAfterBreakAndSkipsSameCategory() {
        let scheduler = makeScheduler()
        scheduler.record(conversation(.break), at: date(9, 55))
        // 10 分後、休憩の直後なので「仕事に戻ろう」
        let categories = scheduler.evaluate(now: date(10, 20))
        XCTAssertFalse(categories.contains(.break), "直前と同じカテゴリは避ける")
        XCTAssertEqual(categories.first, .work)
        // 一度出したら、その休憩に対しては二度と出さない
        scheduler.record(conversation(.work), at: date(10, 20))
        XCTAssertFalse(scheduler.evaluate(now: date(10, 45)).contains(.work))
    }

    func testEncouragementOnlyInAfternoon() {
        let scheduler = makeScheduler(start: date(9))
        XCTAssertFalse(scheduler.evaluate(now: date(12, 50)).contains(.encouragement))
        XCTAssertTrue(scheduler.evaluate(now: date(13, 10)).contains(.encouragement))
        XCTAssertFalse(scheduler.evaluate(now: date(18, 30)).contains(.encouragement))
    }

    // MARK: - 黙る条件

    func testQuietReturnsNothing() {
        let scheduler = makeScheduler(quiet: .until(date(12)))
        XCTAssertEqual(scheduler.evaluate(now: date(9, 55)), [])
        XCTAssertEqual(scheduler.evaluate(now: date(11, 59)), [])

        // quiet 明けは「最終会話時刻」が解除時刻になり、すぐには話さない
        scheduler.quietMode = .normal
        XCTAssertEqual(scheduler.evaluate(now: date(12, 0)), [])
        XCTAssertEqual(scheduler.evaluate(now: date(12, 15)), [])
        XCTAssertFalse(scheduler.evaluate(now: date(12, 25)).isEmpty)
    }

    func testAwayOrHiddenReturnsNothing() {
        let scheduler = makeScheduler()
        scheduler.setUserAway(true, now: date(10))
        XCTAssertEqual(scheduler.evaluate(now: date(9, 55)), [])
        scheduler.setUserAway(false, now: date(10, 1))
        scheduler.isMascotHidden = true
        XCTAssertEqual(scheduler.evaluate(now: date(9, 55)), [])
        scheduler.isMascotHidden = false
        XCTAssertFalse(scheduler.evaluate(now: date(9, 55)).isEmpty)
    }

    func testRestModeOnlyAmbientAndPair() {
        let scheduler = makeScheduler(mode: .rest)
        XCTAssertEqual(scheduler.evaluate(now: date(11, 45)), [.ambient, .pair])
        XCTAssertEqual(scheduler.evaluate(now: date(13, 10)), [.ambient, .pair])
    }

    func testAmbientAndPairAlternate() {
        let scheduler = makeScheduler(mode: .rest)
        scheduler.record(conversation(.ambient), at: date(9, 40))
        XCTAssertEqual(scheduler.evaluate(now: date(10, 0)), [])          // 40 分の周期に届かない
        XCTAssertEqual(scheduler.evaluate(now: date(10, 20)), [.pair])    // 直前の ambient は避ける
    }

    // MARK: - 履歴

    func testHistoryRecordAndRoundTrip() {
        let scheduler = makeScheduler()
        scheduler.record(conversation(.water), at: date(10))
        XCTAssertEqual(scheduler.history.lastCategory, .water)
        XCTAssertEqual(scheduler.history.recentIDs, ["water_1"])
        XCTAssertEqual(scheduler.history.lastShown(of: .water), date(10))

        let data = scheduler.history.encoded()
        let restored = ConversationHistory.decoded(from: data)
        XCTAssertEqual(restored, scheduler.history)
        XCTAssertEqual(ConversationHistory.decoded(from: nil), ConversationHistory())
    }

    func testRecentIDsAreCapped() {
        var history = ConversationHistory()
        for index in 0..<(ConversationHistory.recentIDLimit + 5) {
            history.record(Conversation(id: "c\(index)", category: .ambient,
                                        lines: [DialogueLine(speaker: .shiori, text: "…")]),
                           at: date(9).addingTimeInterval(TimeInterval(index)))
        }
        XCTAssertEqual(history.recentIDs.count, ConversationHistory.recentIDLimit)
        XCTAssertEqual(history.recentIDs.first, "c24")
    }

    // MARK: - 離席からの復帰

    func testLongAwayRestartsSessionSoBreakIsNotDueRightAfterReturn() {
        let scheduler = makeScheduler(start: date(9))
        // 9:30 に離席、10:30 に戻る（60 分）→ 戻った時刻が新しいセッション開始
        scheduler.setUserAway(true, now: date(9, 30))
        XCTAssertEqual(scheduler.evaluate(now: date(10)), [], "離席中は黙る")
        scheduler.setUserAway(false, now: date(10, 30))
        XCTAssertEqual(scheduler.sessionStart, date(10, 30))
        XCTAssertFalse(scheduler.evaluate(now: date(10, 31)).contains(.break), "戻った直後に休憩は言わない")
        XCTAssertTrue(scheduler.evaluate(now: date(11, 21)).contains(.break), "戻ってから 50 分で休憩")
    }

    func testShortAwayKeepsSession() {
        let scheduler = makeScheduler(start: date(9))
        scheduler.setUserAway(true, now: date(9, 40))
        scheduler.setUserAway(false, now: date(9, 45))   // 5 分 < 10 分
        XCTAssertEqual(scheduler.sessionStart, date(9))
        XCTAssertTrue(scheduler.evaluate(now: date(9, 51)).contains(.break), "セッションは継続、9:00 から 50 分で休憩")
    }
}
