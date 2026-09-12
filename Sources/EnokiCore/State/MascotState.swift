import Foundation

/// スリープ中の段階
public enum SleepPhase: Equatable, Sendable {
    case intro   // 導入アニメーション（1 度だけ）
    case loop    // 寝息ループ
}

/// マスコットの状態
public enum MascotState: Equatable {
    case idle(animation: String)
    case sleeping(phase: SleepPhase)
    case dragging
    case reacting(animation: String)
    case hidden

    public var isIdle: Bool { if case .idle = self { return true }; return false }
    public var isSleeping: Bool { if case .sleeping = self { return true }; return false }
    public var isReacting: Bool { if case .reacting = self { return true }; return false }
    public var isDragging: Bool { if case .dragging = self { return true }; return false }
    public var isHidden: Bool { self == .hidden }

    /// 現在再生しているアニメーション名（sleeping は mapping が必要なので nil）
    public var animationName: String? {
        switch self {
        case .idle(let name), .reacting(let name): return name
        default: return nil
        }
    }
}
