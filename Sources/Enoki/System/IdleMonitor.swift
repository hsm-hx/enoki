import Foundation
import Dispatch
import CoreGraphics

/// 無操作時間の監視。
/// `CGEventSource.secondsSinceLastEventType` を使うだけなので、
/// **入力の内容は一切取得せず、アクセシビリティ／入力監視の権限も不要**。
@MainActor
final class IdleMonitor {

    /// ポーリングごとに無操作秒数を通知する
    var onSample: ((TimeInterval) -> Void)?

    private var timer: DispatchSourceTimer?
    private(set) var interval: TimeInterval?

    deinit {
        timer?.cancel()
        timer = nil
    }

    /// 直近の入力からの経過秒数（種類を問わない任意の入力）
    static func idleSeconds() -> TimeInterval {
        // ~0 は kCGAnyInputEventType 相当
        guard let anyEvent = CGEventType(rawValue: ~0) else { return 0 }
        return CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: anyEvent)
    }

    /// ポーリング間隔を設定する。nil で停止（スリープ無効時など）。
    func setPolling(interval newInterval: TimeInterval?) {
        guard newInterval != interval else { return }
        interval = newInterval
        timer?.cancel()
        timer = nil

        guard let newInterval, newInterval > 0 else { return }
        let source = DispatchSource.makeTimerSource(queue: .main)
        source.schedule(deadline: .now() + newInterval,
                        repeating: newInterval,
                        leeway: .milliseconds(500))
        source.setEventHandler { [weak self] in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.onSample?(IdleMonitor.idleSeconds())
            }
        }
        timer = source
        source.resume()
    }

    func stop() {
        setPolling(interval: nil)
    }
}
