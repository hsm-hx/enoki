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
}
