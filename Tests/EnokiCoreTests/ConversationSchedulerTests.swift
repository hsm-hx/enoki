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

    /// renofa 系は見た目プロファイル（§12）で絞る前提のカテゴリなので、
    /// 既存ルールの検証では取り除いてから比べる。
    private func core(_ categories: [DialogueCategory]) -> [DialogueCategory] {
        categories.filter { ![.renofa, .renofaPreMatch, .renofaMatch, .renofaPostMatch].contains($0) }
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
        XCTAssertEqual(core(categories), [.break, .ambient, .pair])
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

    /// 仕事中モード OFF は「仕事の声かけ（work / water / break / lunch）以外」。
    /// 励ましは残る（見た目プロファイル側でさらに絞る）。
    func testRestModeDropsWorkCategories() {
        let scheduler = makeScheduler(mode: .rest)
        XCTAssertEqual(core(scheduler.evaluate(now: date(11, 45))), [.ambient, .pair])
        XCTAssertEqual(core(scheduler.evaluate(now: date(13, 10))), [.encouragement, .ambient, .pair])
        for category in [DialogueCategory.work, .water, .break, .lunch] {
            XCTAssertFalse(scheduler.allowedCategories.contains(category), "\(category.rawValue) は rest では使わない")
        }
    }

    // MARK: - 見た目プロファイル（§12）

    private var casualProfile: AppearanceProfile {
        AppearanceProfile(id: "casual", displayName: "Casual", spriteSet: "saku_shiori_casual",
                          dialogueCategories: ["ambient", "pair", "encouragement"],
                          disabledDialogueCategories: ["work"])
    }

    private var renofaProfile: AppearanceProfile {
        AppearanceProfile(id: "renofa", displayName: "Renofa", spriteSet: "saku_shiori_renofa",
                          dialogueCategories: ["renofa", "renofa_pre_match", "renofa_match", "renofa_post_match",
                                               "ambient", "pair", "encouragement"],
                          disabledDialogueCategories: ["work"],
                          special: true)
    }

    func testCasualProfileDropsWorkCategoriesEvenInWorkMode() {
        let scheduler = makeScheduler()          // 仕事中モードは ON のまま
        scheduler.profile = casualProfile
        XCTAssertEqual(scheduler.allowedCategories, [.ambient, .pair, .encouragement])
        // 9:55 は本来 break が出るタイミングだが、casual では出ない
        XCTAssertEqual(scheduler.evaluate(now: date(9, 55)), [.ambient, .pair])
        for category in [DialogueCategory.work, .water, .break, .lunch] {
            XCTAssertFalse(scheduler.evaluate(now: date(13, 10)).contains(category))
        }
        XCTAssertEqual(scheduler.evaluate(now: date(13, 10)), [.encouragement, .ambient, .pair])
    }

    func testRenofaProfileAllowsRenofaCategory() {
        let scheduler = makeScheduler()
        scheduler.profile = renofaProfile
        // 試合日（キックオフまで間がある）の局面
        scheduler.setMatchPhase(.matchDay, now: date(9))
        XCTAssertEqual(scheduler.allowedCategories, [.renofa, .ambient, .pair, .encouragement])
        // renofa は ambient と同じ周期・ambient の直前の優先順位
        XCTAssertEqual(scheduler.evaluate(now: date(9, 55)), [.renofa, .ambient, .pair])

        // 直前に renofa を出したら、次はほかのカテゴリへ回る
        scheduler.record(conversation(.renofa), at: date(9, 55))
        XCTAssertEqual(scheduler.evaluate(now: date(10, 40)), [.ambient, .pair])
    }

    /// 試合日でなければ renofa 系は 1 つも候補にならない
    func testRenofaProfileWithoutMatchDayDropsRenofaCategories() {
        let scheduler = makeScheduler()
        scheduler.profile = renofaProfile
        XCTAssertEqual(scheduler.allowedCategories, [.ambient, .pair, .encouragement])
        XCTAssertEqual(scheduler.evaluate(now: date(9, 55)), [.ambient, .pair])
    }

    func testProfileWithoutRestrictionKeepsActivityMode() {
        let scheduler = makeScheduler()
        scheduler.profile = AppearanceProfile(id: "default", displayName: "Default")
        // 試合日でないので renofa 系（4 つ）は落ちる
        XCTAssertEqual(scheduler.allowedCategories,
                       Set(DialogueCategory.allCases).subtracting(ConversationScheduler.renofaCategories))
    }

    func testAmbientAndPairAlternate() {
        let scheduler = makeScheduler(mode: .rest)
        scheduler.record(conversation(.ambient), at: date(9, 40))
        XCTAssertEqual(scheduler.evaluate(now: date(10, 0)), [])          // 40 分の周期に届かない
        XCTAssertEqual(core(scheduler.evaluate(now: date(10, 20))), [.pair])   // 直前の ambient は避ける
    }

    // MARK: - 試合日の局面（§12.9）

    /// 局面ごとに許可される renofa 系カテゴリはちょうど 1 つ
    func testMatchPhaseAllowsExactlyOneRenofaCategory() {
        let scheduler = makeScheduler()
        scheduler.profile = renofaProfile
        let expected: [(MatchPhase, DialogueCategory)] = [(.matchDay, .renofa), (.preMatch, .renofaPreMatch),
                                                          (.inMatch, .renofaMatch), (.postMatch, .renofaPostMatch)]
        for (phase, category) in expected {
            scheduler.setMatchPhase(phase, now: date(9))
            let renofaAllowed = scheduler.allowedCategories.intersection(ConversationScheduler.renofaCategories)
            XCTAssertEqual(renofaAllowed, [category], "\(category.rawValue) だけが残ること")
        }
    }

    func testFinishedAndNilPhaseDropAllRenofaCategories() {
        let scheduler = makeScheduler()
        scheduler.profile = renofaProfile
        scheduler.setMatchPhase(.finished, now: date(9))
        XCTAssertTrue(scheduler.allowedCategories.isDisjoint(with: ConversationScheduler.renofaCategories))
        XCTAssertEqual(scheduler.evaluate(now: date(17, 30)).filter { ConversationScheduler.renofaCategories.contains($0) }, [])

        scheduler.setMatchPhase(nil, now: date(18))
        XCTAssertTrue(scheduler.allowedCategories.isDisjoint(with: ConversationScheduler.renofaCategories))
    }

    /// 試合前は全体の最低間隔（20 分）を免除され、12 分周期で出る
    func testPreMatchIgnoresGlobalGapAndUsesItsOwnInterval() {
        let scheduler = makeScheduler()
        scheduler.profile = renofaProfile
        scheduler.setMatchPhase(.preMatch, now: date(11, 30))

        // 直前に別の会話を出した（= 全体の最低間隔の途中）
        scheduler.record(conversation(.ambient), at: date(11, 30))
        XCTAssertEqual(scheduler.evaluate(now: date(11, 40)), [], "局面に入って 12 分経っていない")
        XCTAssertEqual(scheduler.evaluate(now: date(11, 42)), [.renofaPreMatch], "最低間隔 20 分の途中でも出る")

        // 出した直後でも、局面カテゴリは「直前と同じカテゴリ」の回避を免除され、12 分周期で続けて出る
        scheduler.record(conversation(.renofaPreMatch), at: date(11, 42))
        XCTAssertEqual(scheduler.evaluate(now: date(11, 52)), [], "11:42 から 12 分経っていない")
        XCTAssertEqual(scheduler.evaluate(now: date(11, 54)), [.renofaPreMatch])
    }

    /// 試合前・試合中・試合後は最優先（lunch より前）
    func testMatchPhaseCategoriesComeFirst() {
        let scheduler = makeScheduler()
        scheduler.profile = AppearanceProfile(id: "default", displayName: "Default")
        scheduler.setMatchPhase(.inMatch, now: date(11, 30))
        let categories = scheduler.evaluate(now: date(11, 45))   // 昼食も出せる時刻
        XCTAssertEqual(categories.first, .renofaMatch)
        XCTAssertTrue(categories.contains(.lunch))
        XCTAssertEqual(ConversationScheduler.priority.prefix(3),
                       [.renofaPreMatch, .renofaMatch, .renofaPostMatch])
    }

    /// 局面が変わったら、その場でもう一度話してよい（基準は 3 カテゴリの最終再生時刻）
    func testPhaseChangeMakesNewCategoryDueImmediately() {
        let scheduler = makeScheduler()
        scheduler.profile = renofaProfile
        scheduler.setMatchPhase(.preMatch, now: date(11, 30))
        scheduler.record(conversation(.renofaPreMatch), at: date(12, 50))
        XCTAssertEqual(scheduler.evaluate(now: date(12, 55)), [])

        scheduler.setMatchPhase(.inMatch, now: date(13, 0))
        XCTAssertEqual(scheduler.evaluate(now: date(13, 2)), [.renofaMatch])
    }

    /// plain renofa は従来どおり ambient の周期（40 分）で、最低間隔も効く
    func testPlainRenofaKeepsAmbientPacing() {
        let scheduler = makeScheduler()
        scheduler.profile = renofaProfile
        scheduler.setMatchPhase(.matchDay, now: date(9))
        XCTAssertEqual(scheduler.evaluate(now: date(9, 30)), [], "ambient 周期の 40 分に届かない")
        XCTAssertEqual(scheduler.evaluate(now: date(9, 40)), [.renofa, .ambient, .pair])

        // ambient を出すと renofa の基準も一緒に動く（基準時刻を共有している）
        scheduler.record(conversation(.ambient), at: date(9, 40))
        XCTAssertEqual(scheduler.evaluate(now: date(10, 10)), [])
        XCTAssertEqual(scheduler.evaluate(now: date(10, 20)), [.renofa, .pair])
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

    // MARK: - 局面カテゴリは連続して出てよい

    func testMatchPhaseCategoryMayRepeatWithoutAnotherCategoryInBetween() {
        let scheduler = makeScheduler(start: date(9))
        scheduler.profile = renofaProfile
        scheduler.setMatchPhase(.preMatch, now: date(12))
        scheduler.record(conversation(.renofaPreMatch), at: date(12, 1))
        XCTAssertFalse(scheduler.evaluate(now: date(12, 5)).contains(.renofaPreMatch), "12 分の周期が来るまでは出ない")
        XCTAssertTrue(scheduler.evaluate(now: date(12, 14)).contains(.renofaPreMatch),
                      "直前も試合前の台詞だったが、局面カテゴリは同じカテゴリの回避を免除される")
        // 通常のカテゴリは従来どおり直前と同じなら避ける
        scheduler.setMatchPhase(nil, now: date(13))
        scheduler.record(conversation(.ambient), at: date(13))
        XCTAssertFalse(scheduler.evaluate(now: date(14, 30)).contains(.ambient))
    }
}
