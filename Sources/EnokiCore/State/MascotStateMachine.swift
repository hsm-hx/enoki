import Foundation

/// マスコットの状態遷移（純ロジック）。
/// `Date` やタイマーを直接触らず、`MascotController` から「イベント + 現在時刻」を渡してもらう。
public final class MascotStateMachine {

    // MARK: - イベント / 効果

    public enum Event: Equatable {
        case start                                 // 起動・スキン読み込み完了
        case idleSwitchFired                       // idle 切替タイマー発火
        case idleSecondsSampled(TimeInterval)      // 無操作秒数のサンプル
        case dragBegan
        case dragEnded
        case clicked
        /// 会話の行に紐づいた reaction アニメーションの再生要求（idle / sleeping のときだけ効く）
        case reactionRequested(name: String)
        case animationFinished(token: Int)         // 非ループ再生の完了
        case setVisible(Bool)
        case skinReloaded
    }

    public enum Effect: Equatable {
        /// アニメーション再生。`loop == false` のとき、完了時に `.animationFinished(token:)` を返してもらう。
        case play(animation: String, loop: Bool, token: Int)
        case scheduleIdleSwitch(after: TimeInterval)
        case cancelIdleSwitch
        case pausePlayback
        case resumePlayback
        /// 無操作監視のポーリング間隔。nil で停止。
        case setIdlePolling(interval: TimeInterval?)
    }

    // MARK: - 設定

    public var mapping: StateMapping
    /// 0 = スリープしない
    public var sleepAfterSeconds: Int
    public private(set) var isVisible: Bool

    /// テスト用に差し替え可能な乱数（0..<count の index を返す）
    public var randomIndex: (Int) -> Int = { count in count <= 1 ? 0 : Int.random(in: 0..<count) }
    /// テスト用に差し替え可能な乱数（idle 切替間隔）
    public var randomInterval: (ClosedRange<TimeInterval>) -> TimeInterval = { range in
        range.lowerBound >= range.upperBound ? range.lowerBound : TimeInterval.random(in: range)
    }

    // MARK: - 状態

    public private(set) var state: MascotState = .hidden
    public private(set) var currentToken: Int = 0

    /// リアクション終了直後のクリックを無視する時間（秒）
    public static let reactionCooldown: TimeInterval = 0.3

    private var lastIdleSample: TimeInterval = 0
    private var clickBlockedUntil: TimeInterval = -.greatestFiniteMagnitude
    private var lastPollingInterval: TimeInterval??  // 未送信 = nil、送信済み = .some(値)

    /// 通常時 / スリープ中のポーリング間隔
    public static let normalPollingInterval: TimeInterval = 5
    public static let sleepingPollingInterval: TimeInterval = 1

    public init(mapping: StateMapping, sleepAfterSeconds: Int, isVisible: Bool = true) {
        self.mapping = mapping
        self.sleepAfterSeconds = sleepAfterSeconds
        self.isVisible = isVisible
    }

    // MARK: - 入口

    @discardableResult
    public func handle(_ event: Event, now: TimeInterval) -> [Effect] {
        switch event {
        case .start, .skinReloaded:
            lastIdleSample = 0
            return isVisible ? enterIdle(now: now) : enterHidden()

        case .setVisible(let visible):
            guard visible != isVisible else { return [] }
            isVisible = visible
            if visible {
                return [.resumePlayback] + enterIdle(now: now)
            } else {
                return enterHidden()
            }

        case .idleSwitchFired:
            guard case .idle(let current) = state else { return [] }
            let next = pickIdleName(excluding: current)
            if next == current {
                // 候補が実質 1 種類しかない → 再スケジュールのみ
                return [scheduleIdleSwitchEffect()]
            }
            state = .idle(animation: next)
            currentToken += 1
            return [.play(animation: next, loop: true, token: currentToken), scheduleIdleSwitchEffect()]

        case .idleSecondsSampled(let seconds):
            defer { lastIdleSample = seconds }
            return handleIdleSample(seconds, now: now)

        case .dragBegan:
            switch state {
            case .hidden, .dragging:
                return []
            default:
                state = .dragging
                currentToken += 1
                var effects: [Effect] = [.cancelIdleSwitch,
                                         .play(animation: mapping.drag, loop: true, token: currentToken)]
                effects.append(contentsOf: pollingEffect())
                return effects
            }

        case .dragEnded:
            guard state.isDragging else { return [] }
            return enterIdle(now: now)

        case .clicked:
            return handleClick(now: now)

        case .reactionRequested(let name):
            guard isVisible, !name.isEmpty else { return [] }
            switch state {
            case .idle, .sleeping:
                return enterReacting(named: name)
            case .reacting, .dragging, .hidden:
                return []
            }

        case .animationFinished(let token):
            guard token == currentToken else { return [] }   // 古い再生の完了は無視
            switch state {
            case .sleeping(.intro):
                state = .sleeping(phase: .loop)
                currentToken += 1
                return [.play(animation: mapping.sleepLoop, loop: true, token: currentToken)]
            case .reacting:
                clickBlockedUntil = now + Self.reactionCooldown
                return enterIdle(now: now)
            default:
                return []
            }
        }
    }

    /// 設定変更（スリープ時間）を反映する
    @discardableResult
    public func updateSleepAfterSeconds(_ seconds: Int, now: TimeInterval) -> [Effect] {
        guard seconds != sleepAfterSeconds else { return [] }
        sleepAfterSeconds = seconds
        var effects: [Effect] = []
        if seconds <= 0, state.isSleeping {
            effects.append(contentsOf: enterIdle(now: now))
        }
        effects.append(contentsOf: pollingEffect())
        return effects
    }

    /// スキン差し替え時など、mapping を入れ替える
    public func updateMapping(_ mapping: StateMapping) {
        self.mapping = mapping
    }

    // MARK: - 遷移の実装

    private func handleIdleSample(_ seconds: TimeInterval, now: TimeInterval) -> [Effect] {
        switch state {
        case .sleeping:
            // 入力が戻った = 無操作秒数が前回より小さくなった、または閾値未満
            let threshold = TimeInterval(sleepAfterSeconds)
            if sleepAfterSeconds <= 0 || seconds < lastIdleSample || seconds < threshold {
                return enterIdle(now: now)
            }
            return []

        case .idle:
            guard sleepAfterSeconds > 0, seconds >= TimeInterval(sleepAfterSeconds) else { return [] }
            return enterSleeping()

        case .dragging, .reacting, .hidden:
            // ドラッグ中・リアクション中・非表示中はスリープ判定しない
            return []
        }
    }

    private func handleClick(now: TimeInterval) -> [Effect] {
        guard now >= clickBlockedUntil else { return [] }   // リアクション直後のデバウンス
        switch state {
        case .idle:
            return enterReacting(now: now)
        case .sleeping:
            // 「起こされた」扱い: スリープを抜けて（idle 相当に戻して）リアクションへ
            lastIdleSample = 0
            return enterReacting(now: now)
        case .reacting, .dragging, .hidden:
            return []
        }
    }

    private func enterIdle(now: TimeInterval) -> [Effect] {
        let name = pickIdleName(excluding: nil)
        state = .idle(animation: name)
        currentToken += 1
        var effects: [Effect] = [.play(animation: name, loop: true, token: currentToken),
                                 scheduleIdleSwitchEffect()]
        effects.append(contentsOf: pollingEffect())
        return effects
    }

    private func enterSleeping() -> [Effect] {
        currentToken += 1
        var effects: [Effect] = [.cancelIdleSwitch]
        if let intro = mapping.sleepIntro {
            state = .sleeping(phase: .intro)
            effects.append(.play(animation: intro, loop: false, token: currentToken))
        } else {
            state = .sleeping(phase: .loop)
            effects.append(.play(animation: mapping.sleepLoop, loop: true, token: currentToken))
        }
        effects.append(contentsOf: pollingEffect())
        return effects
    }

    private func enterReacting(now: TimeInterval) -> [Effect] {
        guard !mapping.reaction.isEmpty else { return enterIdle(now: now) }
        return enterReacting(named: mapping.reaction[clampedIndex(mapping.reaction.count)])
    }

    /// アニメーション名を指定してリアクションへ入る
    private func enterReacting(named name: String) -> [Effect] {
        state = .reacting(animation: name)
        currentToken += 1
        var effects: [Effect] = [.cancelIdleSwitch,
                                 .play(animation: name, loop: false, token: currentToken)]
        effects.append(contentsOf: pollingEffect())
        return effects
    }

    private func enterHidden() -> [Effect] {
        state = .hidden
        currentToken += 1
        var effects: [Effect] = [.cancelIdleSwitch, .pausePlayback]
        effects.append(contentsOf: pollingEffect())
        return effects
    }

    // MARK: - ヘルパ

    private func pickIdleName(excluding current: String?) -> String {
        let pool = mapping.idle
        guard !pool.isEmpty else { return "idle" }
        if let current {
            let others = pool.filter { $0 != current }
            if others.isEmpty { return current }
            return others[clampedIndex(others.count)]
        }
        return pool[clampedIndex(pool.count)]
    }

    private func clampedIndex(_ count: Int) -> Int {
        guard count > 0 else { return 0 }
        return min(max(0, randomIndex(count)), count - 1)
    }

    private func scheduleIdleSwitchEffect() -> Effect {
        .scheduleIdleSwitch(after: randomInterval(mapping.idleSwitchInterval))
    }

    /// 現在の状態に応じた無操作ポーリング間隔（変化したときだけ Effect を出す）
    private var desiredPollingInterval: TimeInterval? {
        guard sleepAfterSeconds > 0, !state.isHidden else { return nil }
        return state.isSleeping ? Self.sleepingPollingInterval : Self.normalPollingInterval
    }

    private func pollingEffect() -> [Effect] {
        let desired = desiredPollingInterval
        if let last = lastPollingInterval, last == desired { return [] }
        lastPollingInterval = .some(desired)
        return [.setIdlePolling(interval: desired)]
    }
}
