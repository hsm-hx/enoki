import XCTest
@testable import EnokiCore

final class MascotStateMachineTests: XCTestCase {

    private func makeMachine(sleepAfterSeconds: Int = 300,
                             mapping: StateMapping = CodexPetDefaults.stateMapping) -> MascotStateMachine {
        let machine = MascotStateMachine(mapping: mapping, sleepAfterSeconds: sleepAfterSeconds, isVisible: true)
        machine.randomIndex = { _ in 0 }                     // 常に先頭を選ぶ
        machine.randomInterval = { $0.lowerBound }           // 常に下限
        return machine
    }

    private func playedAnimations(_ effects: [MascotStateMachine.Effect]) -> [String] {
        effects.compactMap { effect in
            if case .play(let name, _, _) = effect { return name }
            return nil
        }
    }

    // MARK: - 起動

    func testStartEntersIdle() {
        let machine = makeMachine()
        let effects = machine.handle(.start, now: 0)
        XCTAssertEqual(machine.state, .idle(animation: "idle"))
        XCTAssertEqual(playedAnimations(effects), ["idle"])
        XCTAssertTrue(effects.contains(.scheduleIdleSwitch(after: 30)))
        XCTAssertTrue(effects.contains(.setIdlePolling(interval: 5)))
    }

    func testIdleSwitchPicksAnotherAnimation() {
        let machine = makeMachine()
        machine.handle(.start, now: 0)
        // 先頭 "idle" 以外から選ばれる（randomIndex は 0 なので "review"）
        let effects = machine.handle(.idleSwitchFired, now: 10)
        XCTAssertEqual(machine.state, .idle(animation: "review"))
        XCTAssertEqual(playedAnimations(effects), ["review"])
        XCTAssertTrue(effects.contains(.scheduleIdleSwitch(after: 30)))
    }

    func testIdleSwitchOnlyReschedulesWhenSingleCandidate() {
        var mapping = CodexPetDefaults.stateMapping
        mapping.idle = ["idle"]
        let machine = makeMachine(mapping: mapping)
        machine.handle(.start, now: 0)
        let effects = machine.handle(.idleSwitchFired, now: 10)
        XCTAssertEqual(playedAnimations(effects), [])
        XCTAssertEqual(effects, [.scheduleIdleSwitch(after: 30)])
    }

    // MARK: - idle → sleep → idle

    func testIdleToSleepAndBack() {
        let machine = makeMachine(sleepAfterSeconds: 300)
        machine.handle(.start, now: 0)

        // 閾値未満ではスリープしない
        XCTAssertEqual(machine.handle(.idleSecondsSampled(299), now: 5), [])
        XCTAssertTrue(machine.state.isIdle)

        // 閾値到達 → intro
        let toSleep = machine.handle(.idleSecondsSampled(300), now: 10)
        XCTAssertEqual(machine.state, .sleeping(phase: .intro))
        XCTAssertEqual(playedAnimations(toSleep), ["waiting"])
        XCTAssertTrue(toSleep.contains(.cancelIdleSwitch))
        XCTAssertTrue(toSleep.contains(.setIdlePolling(interval: 1)))

        // intro 完了 → loop
        let toLoop = machine.handle(.animationFinished(token: machine.currentToken), now: 11)
        XCTAssertEqual(machine.state, .sleeping(phase: .loop))
        XCTAssertEqual(playedAnimations(toLoop), ["sleep"])

        // 入力が戻る（無操作秒数が減る）→ idle
        let wake = machine.handle(.idleSecondsSampled(0), now: 20)
        XCTAssertTrue(machine.state.isIdle)
        XCTAssertEqual(playedAnimations(wake), ["idle"])
        XCTAssertTrue(wake.contains(.setIdlePolling(interval: 5)))
    }

    func testSleepDisabledNeverSleeps() {
        let machine = makeMachine(sleepAfterSeconds: 0)
        let start = machine.handle(.start, now: 0)
        XCTAssertTrue(start.contains(.setIdlePolling(interval: nil)), "スリープ無効ならポーリングしない")
        XCTAssertEqual(machine.handle(.idleSecondsSampled(99999), now: 10), [])
        XCTAssertTrue(machine.state.isIdle)
    }

    func testSleepWithoutIntroGoesStraightToLoop() {
        var mapping = CodexPetDefaults.stateMapping
        mapping.sleepIntro = nil
        let machine = makeMachine(mapping: mapping)
        machine.handle(.start, now: 0)
        let effects = machine.handle(.idleSecondsSampled(400), now: 10)
        XCTAssertEqual(machine.state, .sleeping(phase: .loop))
        XCTAssertEqual(playedAnimations(effects), ["sleep"])
    }

    // MARK: - クリック / リアクション

    func testClickStartsReactionAndReturnsToIdle() {
        let machine = makeMachine()
        machine.handle(.start, now: 0)

        let react = machine.handle(.clicked, now: 1)
        XCTAssertEqual(machine.state, .reacting(animation: "waving"))
        XCTAssertEqual(playedAnimations(react), ["waving"])
        XCTAssertTrue(react.contains(.cancelIdleSwitch))

        // リアクション中のクリックは無視（デバウンス）
        XCTAssertEqual(machine.handle(.clicked, now: 1.1), [])
        XCTAssertTrue(machine.state.isReacting)

        // 完了 → idle
        let done = machine.handle(.animationFinished(token: machine.currentToken), now: 2)
        XCTAssertTrue(machine.state.isIdle)
        XCTAssertEqual(playedAnimations(done), ["idle"])
    }

    func testClickWithin300msAfterReactionIsIgnored() {
        let machine = makeMachine()
        machine.handle(.start, now: 0)
        machine.handle(.clicked, now: 1)
        machine.handle(.animationFinished(token: machine.currentToken), now: 2)

        // 300ms 以内は無視
        XCTAssertEqual(machine.handle(.clicked, now: 2.2), [])
        XCTAssertTrue(machine.state.isIdle)

        // 300ms 経過後は受け付ける
        let react = machine.handle(.clicked, now: 2.31)
        XCTAssertTrue(machine.state.isReacting)
        XCTAssertEqual(playedAnimations(react), ["waving"])
    }

    func testStaleAnimationFinishedIsIgnored() {
        let machine = makeMachine()
        machine.handle(.start, now: 0)
        let staleToken = machine.currentToken
        machine.handle(.clicked, now: 1)
        XCTAssertEqual(machine.handle(.animationFinished(token: staleToken), now: 1.5), [])
        XCTAssertTrue(machine.state.isReacting, "古い再生の完了通知では状態が変わらない")
    }

    func testClickWhileSleepingWakesAndReacts() {
        let machine = makeMachine()
        machine.handle(.start, now: 0)
        machine.handle(.idleSecondsSampled(300), now: 10)
        machine.handle(.animationFinished(token: machine.currentToken), now: 11)
        XCTAssertEqual(machine.state, .sleeping(phase: .loop))

        let effects = machine.handle(.clicked, now: 12)
        XCTAssertEqual(machine.state, .reacting(animation: "waving"), "起こされた扱いで idle を経てリアクションへ")
        XCTAssertEqual(playedAnimations(effects), ["waving"])
        XCTAssertTrue(effects.contains(.setIdlePolling(interval: 5)), "スリープ用の 1 秒ポーリングから戻る")

        let done = machine.handle(.animationFinished(token: machine.currentToken), now: 13)
        XCTAssertTrue(machine.state.isIdle)
        XCTAssertEqual(playedAnimations(done), ["idle"])
    }

    // MARK: - ドラッグ

    func testDragBlocksSleepAndReturnsToIdle() {
        let machine = makeMachine()
        machine.handle(.start, now: 0)

        let drag = machine.handle(.dragBegan, now: 1)
        XCTAssertEqual(machine.state, .dragging)
        XCTAssertEqual(playedAnimations(drag), ["running-right"])
        XCTAssertTrue(drag.contains(.cancelIdleSwitch))

        // ドラッグ中はスリープ判定しない
        XCTAssertEqual(machine.handle(.idleSecondsSampled(99999), now: 2), [])
        XCTAssertEqual(machine.state, .dragging)

        // ドラッグ中のクリックも無視
        XCTAssertEqual(machine.handle(.clicked, now: 3), [])

        let end = machine.handle(.dragEnded, now: 4)
        XCTAssertTrue(machine.state.isIdle)
        XCTAssertEqual(playedAnimations(end), ["idle"])
    }

    func testDragFromSleepingWorks() {
        let machine = makeMachine()
        machine.handle(.start, now: 0)
        machine.handle(.idleSecondsSampled(300), now: 10)
        let drag = machine.handle(.dragBegan, now: 11)
        XCTAssertEqual(machine.state, .dragging)
        XCTAssertEqual(playedAnimations(drag), ["running-right"])
    }

    // MARK: - 表示 / 非表示

    func testHideAndShow() {
        let machine = makeMachine()
        machine.handle(.start, now: 0)

        let hide = machine.handle(.setVisible(false), now: 1)
        XCTAssertEqual(machine.state, .hidden)
        XCTAssertTrue(hide.contains(.pausePlayback))
        XCTAssertTrue(hide.contains(.cancelIdleSwitch))
        XCTAssertTrue(hide.contains(.setIdlePolling(interval: nil)))

        // 非表示中はイベントを無視
        XCTAssertEqual(machine.handle(.clicked, now: 2), [])
        XCTAssertEqual(machine.handle(.idleSecondsSampled(9999), now: 3), [])

        let show = machine.handle(.setVisible(true), now: 4)
        XCTAssertTrue(show.contains(.resumePlayback))
        XCTAssertTrue(machine.state.isIdle)
        XCTAssertEqual(playedAnimations(show), ["idle"])
    }

    // MARK: - 設定変更

    func testDisablingSleepWhileSleepingReturnsToIdle() {
        let machine = makeMachine()
        machine.handle(.start, now: 0)
        machine.handle(.idleSecondsSampled(300), now: 10)
        XCTAssertTrue(machine.state.isSleeping)

        let effects = machine.updateSleepAfterSeconds(0, now: 11)
        XCTAssertTrue(machine.state.isIdle)
        XCTAssertTrue(effects.contains(.setIdlePolling(interval: nil)))
    }
}
