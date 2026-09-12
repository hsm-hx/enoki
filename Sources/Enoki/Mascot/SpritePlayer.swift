import Foundation
import Dispatch
import EnokiCore

/// スプライトのコマ送り。
/// `DispatchSourceTimer`（main queue）を **コマごとに再スケジュール** する。
/// 固定 60fps ループや CADisplayLink は使わないので、静止コマでは CPU を使わない。
@MainActor
final class SpritePlayer {

    /// コマが変わるたびに呼ばれる
    var onFrame: ((SpriteAnimation, Int) -> Void)?

    private(set) var animation: SpriteAnimation?
    private(set) var frameIndex: Int = 0
    private(set) var isPaused = false

    private var timer: DispatchSourceTimer?
    private var loop: Bool = true
    private var completion: (() -> Void)?
    /// タイマーの遅延許容（省電力のため大きめ）
    private static let leeway = DispatchTimeInterval.milliseconds(15)

    deinit {
        timer?.cancel()
        timer = nil
    }

    /// 再生を開始する。`loop` を省略するとアニメーション自身の設定を使う。
    func play(_ animation: SpriteAnimation, loop: Bool? = nil, completion: (() -> Void)? = nil) {
        stopTimer()
        self.animation = animation
        self.loop = loop ?? animation.loop
        self.completion = completion
        self.frameIndex = 0
        onFrame?(animation, 0)

        // 1 コマだけのループは静止画 → タイマーを立てない
        if animation.frames.count <= 1 {
            if !self.loop {
                finish()
            }
            return
        }
        guard !isPaused else { return }
        scheduleNextFrame()
    }

    /// 再生を止めて内容もクリアする
    func stop() {
        stopTimer()
        completion = nil
    }

    func pause() {
        guard !isPaused else { return }
        isPaused = true
        stopTimer()
    }

    func resume() {
        guard isPaused else { return }
        isPaused = false
        guard let animation, animation.frames.count > 1 else { return }
        scheduleNextFrame()
    }

    // MARK: - private

    private func stopTimer() {
        timer?.cancel()
        timer = nil
    }

    private func scheduleNextFrame() {
        guard let animation else { return }
        let delay = animation.duration(at: frameIndex)
        let source = DispatchSource.makeTimerSource(queue: .main)
        source.schedule(deadline: .now() + delay, leeway: SpritePlayer.leeway)
        source.setEventHandler { [weak self] in
            MainActor.assumeIsolated { self?.advance() }
        }
        timer = source
        source.resume()
    }

    private func advance() {
        guard let animation, !isPaused else { return }
        stopTimer()

        let next = frameIndex + 1
        if next >= animation.frames.count {
            if loop {
                frameIndex = 0
                onFrame?(animation, 0)
                scheduleNextFrame()
            } else {
                finish()
            }
            return
        }

        frameIndex = next
        onFrame?(animation, next)
        scheduleNextFrame()
    }

    /// 非ループ再生の終了。completion 内で play() が呼ばれても壊れないよう、
    /// 先にタイマーと completion を手放してから呼ぶ。
    private func finish() {
        stopTimer()
        let block = completion
        completion = nil
        block?()
    }
}
