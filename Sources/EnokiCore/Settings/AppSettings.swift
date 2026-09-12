import Foundation
import CoreGraphics

/// 描画補間
public enum InterpolationMode: String, CaseIterable {
    case linear
    case nearest

    public var localizedName: String {
        switch self {
        case .linear:  return "なめらか (Linear)"
        case .nearest: return "くっきり (Nearest)"
        }
    }
}

/// UserDefaults ラッパ。値を変更すると `AppSettings.didChangeNotification` が飛ぶ。
public final class AppSettings {

    public enum Key: String, CaseIterable {
        case isVisible
        case alwaysOnTop
        case clickThrough
        case scale
        case interpolation
        case sleepAfterSeconds
        case skinDirectory
        case windowOriginX
        case windowOriginY
        case hasSavedWindowOrigin
        case activityMode
        case quietModeRaw
        case quietUntil
        case workEndHour
        case conversationHistoryData
    }

    /// userInfo["key"] に `Key.rawValue` が入る
    public static let didChangeNotification = Notification.Name("com.enoki.mascot.settingsDidChange")
    public static let changedKeyUserInfoKey = "key"

    public static let scalePresets: [Double] = [0.5, 0.75, 1.0, 1.25, 1.5]
    /// 0 = スリープしない
    public static let sleepPresets: [Int] = [60, 180, 300, 600, 900, 1800, 0]

    private let defaults: UserDefaults
    private let notificationCenter: NotificationCenter

    public init(defaults: UserDefaults = .standard, notificationCenter: NotificationCenter = .default) {
        self.defaults = defaults
        self.notificationCenter = notificationCenter
        defaults.register(defaults: [
            Key.isVisible.rawValue: true,
            Key.alwaysOnTop.rawValue: true,
            Key.clickThrough.rawValue: false,
            Key.scale.rawValue: 1.0,
            Key.interpolation.rawValue: InterpolationMode.linear.rawValue,
            Key.sleepAfterSeconds.rawValue: 300,
            Key.hasSavedWindowOrigin.rawValue: false,
            Key.activityMode.rawValue: ActivityMode.work.rawValue,
            Key.workEndHour.rawValue: QuietMode.defaultWorkEndHour,
        ])
    }

    // MARK: - 値

    public var isVisible: Bool {
        get { defaults.bool(forKey: Key.isVisible.rawValue) }
        set { set(newValue, for: .isVisible) }
    }

    public var alwaysOnTop: Bool {
        get { defaults.bool(forKey: Key.alwaysOnTop.rawValue) }
        set { set(newValue, for: .alwaysOnTop) }
    }

    public var clickThrough: Bool {
        get { defaults.bool(forKey: Key.clickThrough.rawValue) }
        set { set(newValue, for: .clickThrough) }
    }

    /// 0.25〜4.0 にクランプ
    public var scale: Double {
        get { AppSettings.clampScale(defaults.double(forKey: Key.scale.rawValue)) }
        set { set(AppSettings.clampScale(newValue), for: .scale) }
    }

    public var interpolation: InterpolationMode {
        get { InterpolationMode(rawValue: defaults.string(forKey: Key.interpolation.rawValue) ?? "") ?? .linear }
        set { set(newValue.rawValue, for: .interpolation) }
    }

    /// 0 = スリープしない
    public var sleepAfterSeconds: Int {
        get { max(0, defaults.integer(forKey: Key.sleepAfterSeconds.rawValue)) }
        set { set(max(0, newValue), for: .sleepAfterSeconds) }
    }

    public var skinDirectory: String? {
        get { defaults.string(forKey: Key.skinDirectory.rawValue) }
        set {
            if let newValue, !newValue.isEmpty {
                set(newValue, for: .skinDirectory)
            } else {
                defaults.removeObject(forKey: Key.skinDirectory.rawValue)
                post(.skinDirectory)
            }
        }
    }

    public var hasSavedWindowOrigin: Bool {
        defaults.bool(forKey: Key.hasSavedWindowOrigin.rawValue)
    }

    /// 保存済みウィンドウ位置（未保存なら nil）
    public var savedWindowOrigin: CGPoint? {
        get {
            guard hasSavedWindowOrigin else { return nil }
            return CGPoint(x: defaults.double(forKey: Key.windowOriginX.rawValue),
                           y: defaults.double(forKey: Key.windowOriginY.rawValue))
        }
        set {
            if let newValue {
                defaults.set(Double(newValue.x), forKey: Key.windowOriginX.rawValue)
                defaults.set(Double(newValue.y), forKey: Key.windowOriginY.rawValue)
                defaults.set(true, forKey: Key.hasSavedWindowOrigin.rawValue)
            } else {
                defaults.removeObject(forKey: Key.windowOriginX.rawValue)
                defaults.removeObject(forKey: Key.windowOriginY.rawValue)
                defaults.set(false, forKey: Key.hasSavedWindowOrigin.rawValue)
            }
            post(.hasSavedWindowOrigin)
        }
    }

    // MARK: - 会話・声かけ

    /// 仕事中モード（既定 work）
    public var activityMode: ActivityMode {
        get { ActivityMode(rawValue: defaults.string(forKey: Key.activityMode.rawValue) ?? "") ?? .work }
        set { set(newValue.rawValue, for: .activityMode) }
    }

    /// 「静かにして」の状態。解除時刻は `quietUntil` に保存する。
    public var quietMode: QuietMode {
        get {
            QuietMode(rawValue: defaults.string(forKey: Key.quietModeRaw.rawValue),
                      until: storedQuietUntil)
        }
        set {
            defaults.set(newValue.rawValue, forKey: Key.quietModeRaw.rawValue)
            if let expiry = newValue.expiry {
                defaults.set(expiry.timeIntervalSince1970, forKey: Key.quietUntil.rawValue)
            } else {
                defaults.removeObject(forKey: Key.quietUntil.rawValue)
            }
            post(.quietModeRaw)
        }
    }

    private var storedQuietUntil: Date? {
        let seconds = defaults.double(forKey: Key.quietUntil.rawValue)
        return seconds > 0 ? Date(timeIntervalSince1970: seconds) : nil
    }

    /// 仕事を終える時刻（時）。「今日の仕事終了まで静かにする」の基準。0〜23 にクランプ。
    public var workEndHour: Int {
        get { min(max(defaults.integer(forKey: Key.workEndHour.rawValue), 0), 23) }
        set { set(min(max(newValue, 0), 23), for: .workEndHour) }
    }

    /// 会話履歴（JSON）
    public var conversationHistoryData: Data? {
        get { defaults.data(forKey: Key.conversationHistoryData.rawValue) }
        set {
            if let newValue {
                defaults.set(newValue, forKey: Key.conversationHistoryData.rawValue)
            } else {
                defaults.removeObject(forKey: Key.conversationHistoryData.rawValue)
            }
            post(.conversationHistoryData)
        }
    }

    public static func clampScale(_ value: Double) -> Double {
        guard value.isFinite, value > 0 else { return 1.0 }
        return min(max(value, 0.25), 4.0)
    }

    // MARK: - private

    private func set(_ value: Any, for key: Key) {
        defaults.set(value, forKey: key.rawValue)
        post(key)
    }

    private func post(_ key: Key) {
        notificationCenter.post(name: AppSettings.didChangeNotification,
                                object: self,
                                userInfo: [AppSettings.changedKeyUserInfoKey: key.rawValue])
    }
}
