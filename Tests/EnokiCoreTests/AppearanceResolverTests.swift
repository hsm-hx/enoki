import XCTest
@testable import EnokiCore

final class AppearanceResolverTests: XCTestCase {

    private let profiles: [AppearanceProfile] = [
        AppearanceProfile(id: "default", displayName: "Default"),
        AppearanceProfile(id: "work", displayName: "Work", spriteSet: "saku_shiori_work"),
        AppearanceProfile(id: "casual", displayName: "Casual", spriteSet: "saku_shiori_casual",
                          dialogueCategories: ["ambient", "pair", "encouragement"],
                          disabledDialogueCategories: ["work"]),
        AppearanceProfile(id: "renofa", displayName: "Renofa", spriteSet: "saku_shiori_renofa",
                          dialogueCategories: ["renofa", "ambient", "pair", "encouragement"],
                          disabledDialogueCategories: ["work"],
                          special: true),
    ]

    private func resolve(_ state: AppearanceState,
                         _ mode: ActivityMode,
                         scheduled: String? = nil) -> String {
        AppearanceResolver.resolve(state: state, activityMode: mode, scheduled: scheduled, profiles: profiles)
    }

    // MARK: - 優先順位

    func testManualOverrideWinsOverEverything() {
        let state = AppearanceState(manualOverride: "renofa", autoSwitch: true)
        XCTAssertEqual(resolve(state, .work), "renofa")
        XCTAssertEqual(resolve(state, .rest), "renofa")
        XCTAssertEqual(resolve(state, .work, scheduled: "casual"), "renofa")
    }

    func testScheduledWinsWhenNoManualOverride() {
        let state = AppearanceState(manualOverride: nil, autoSwitch: true)
        XCTAssertEqual(resolve(state, .work, scheduled: "casual"), "casual")
        // profiles に無い scheduled は無視して自動ルールへ
        XCTAssertEqual(resolve(state, .work, scheduled: "halloween"), "work")
    }

    func testAutoSwitchFollowsActivityMode() {
        let state = AppearanceState(manualOverride: nil, autoSwitch: true)
        XCTAssertEqual(resolve(state, .work), "work")
        XCTAssertEqual(resolve(state, .rest), "casual")
    }

    func testFallsBackToDefault() {
        let state = AppearanceState(manualOverride: nil, autoSwitch: false)
        XCTAssertEqual(resolve(state, .work), "default")
        XCTAssertEqual(resolve(state, .rest), "default")

        // autoSwitch が true でも work / casual が無ければ default
        let onlyDefault = [AppearanceProfile(id: "default", displayName: "Default")]
        XCTAssertEqual(AppearanceResolver.resolve(state: AppearanceState(autoSwitch: true),
                                                  activityMode: .work,
                                                  profiles: onlyDefault), "default")
    }

    func testUnknownManualOverrideIsIgnored() {
        let state = AppearanceState(manualOverride: "halloween", autoSwitch: true)
        XCTAssertEqual(resolve(state, .work), "work")
        XCTAssertEqual(resolve(state, .rest), "casual")
    }

    // MARK: - 仕事中モードの切り替え

    func testSpecialOverrideSurvivesActivityModeChange() {
        XCTAssertEqual(AppearanceResolver.overrideAfterActivityModeChange(current: "renofa", profiles: profiles),
                       "renofa")
        // renofa 手動中は Work Mode を切り替えても上書きされない
        let state = AppearanceState(manualOverride: "renofa", autoSwitch: true)
        XCTAssertEqual(resolve(state, .rest), "renofa")
    }

    func testNonSpecialOverrideIsClearedByActivityModeChange() {
        XCTAssertNil(AppearanceResolver.overrideAfterActivityModeChange(current: "casual", profiles: profiles))
        XCTAssertNil(AppearanceResolver.overrideAfterActivityModeChange(current: "work", profiles: profiles))
        XCTAssertNil(AppearanceResolver.overrideAfterActivityModeChange(current: nil, profiles: profiles))
        // profiles に無い id も解除する
        XCTAssertNil(AppearanceResolver.overrideAfterActivityModeChange(current: "halloween", profiles: profiles))
    }

    // MARK: - 起動時プロファイル

    func testStartupProfileRestoresPreviousStateByDefault() {
        XCTAssertEqual(AppearanceResolver.startupOverride(startupProfileID: nil,
                                                          stored: "renofa",
                                                          profiles: profiles), "renofa")
        XCTAssertNil(AppearanceResolver.startupOverride(startupProfileID: nil, stored: nil, profiles: profiles))
    }

    func testStartupProfileAutoClearsOverride() {
        XCTAssertNil(AppearanceResolver.startupOverride(startupProfileID: AppearanceResolver.automaticStartupID,
                                                        stored: "renofa",
                                                        profiles: profiles))
        // "auto" のあとは自動ルールが効く
        let state = AppearanceState(manualOverride: nil, autoSwitch: true)
        XCTAssertEqual(resolve(state, .work), "work")
    }

    func testStartupProfilePinsGivenProfile() {
        XCTAssertEqual(AppearanceResolver.startupOverride(startupProfileID: "casual",
                                                          stored: nil,
                                                          profiles: profiles), "casual")
        // 知らない id は前回の状態のまま
        XCTAssertEqual(AppearanceResolver.startupOverride(startupProfileID: "halloween",
                                                          stored: "renofa",
                                                          profiles: profiles), "renofa")
    }

    // MARK: - その日の自動判定（§12.9）を `scheduled` に流し込む

    func testDayDecisionIsWeakerThanManualButStrongerThanActivityMode() {
        let holidays = JapaneseHolidays()
        let schedule = RenofaSchedule(matches: [
            RenofaMatch(date: "2026-11-25", kickoff: "19:00", opponent: "福島ユナイテッドFC", home: true),
        ])
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Tokyo")!
        let matchDay = calendar.date(from: DateComponents(year: 2026, month: 11, day: 25, hour: 12))!
        let decision = DayProfileResolver.resolve(date: matchDay, schedule: schedule,
                                                  holidays: holidays, calendar: calendar)
        XCTAssertEqual(decision.profileID, "renofa")

        // 仕事中モードより強い（試合日は仕事中でも renofa）
        XCTAssertEqual(resolve(AppearanceState(manualOverride: nil, autoSwitch: true), .work,
                               scheduled: decision.profileID), "renofa")
        // 手動選択より弱い
        XCTAssertEqual(resolve(AppearanceState(manualOverride: "work", autoSwitch: true), .rest,
                               scheduled: decision.profileID), "work")
    }

    // MARK: - 手動選択は「その日限り」

    func testOverrideSurvivesWithinTheSameDay() {
        XCTAssertEqual(AppearanceResolver.expiredOverride(current: "work",
                                                          setOn: "2026-09-13",
                                                          today: "2026-09-13"), "work")
    }

    func testOverrideExpiresOnAnotherDay() {
        XCTAssertNil(AppearanceResolver.expiredOverride(current: "work",
                                                        setOn: "2026-09-12",
                                                        today: "2026-09-13"))
        // 日付を控えていない古い設定も解除する
        XCTAssertNil(AppearanceResolver.expiredOverride(current: "work", setOn: nil, today: "2026-09-13"))
        // そもそも手動選択が無ければ nil のまま
        XCTAssertNil(AppearanceResolver.expiredOverride(current: nil, setOn: "2026-09-13", today: "2026-09-13"))
    }

    /// 日付が変わったあとの再評価（`AppearanceCoordinator.reevaluateDay` の中身を純関数の組み合わせで再現）
    func testManualOverrideIsReplacedByNextDayDecision() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Tokyo")!
        let holidays = JapaneseHolidays()
        let schedule = RenofaSchedule(matches: [
            RenofaMatch(date: "2026-11-25", kickoff: "19:00", opponent: "福島ユナイテッドFC", home: true),
        ])

        // 前日（11/24 火・平日）に work を手動選択した
        let yesterday = calendar.date(from: DateComponents(year: 2026, month: 11, day: 24, hour: 22))!
        let setOn = DayProfileResolver.dayKey(for: yesterday, calendar: calendar)
        XCTAssertEqual(AppearanceResolver.resolve(state: AppearanceState(manualOverride: "work", autoSwitch: true),
                                                   activityMode: .rest,
                                                   scheduled: DayProfileResolver.resolve(date: yesterday, schedule: schedule,
                                                                                         holidays: holidays, calendar: calendar).profileID,
                                                   profiles: profiles), "work")

        // 翌日（11/25 水・試合日）になると手動選択は解除され、その日の判定が採用される
        let today = calendar.date(from: DateComponents(year: 2026, month: 11, day: 25, hour: 9))!
        let todayKey = DayProfileResolver.dayKey(for: today, calendar: calendar)
        let override = AppearanceResolver.expiredOverride(current: "work", setOn: setOn, today: todayKey)
        XCTAssertNil(override)

        let decision = DayProfileResolver.resolve(date: today, schedule: schedule,
                                                  holidays: holidays, calendar: calendar)
        XCTAssertEqual(AppearanceResolver.resolve(state: AppearanceState(manualOverride: override, autoSwitch: true),
                                                   activityMode: .work,
                                                   scheduled: decision.profileID,
                                                   profiles: profiles), "renofa")
    }
}
