import Foundation

/// 見た目プロファイルの選択状態（`AppSettings` に保存される値と 1:1）
public struct AppearanceState: Equatable, Sendable {
    /// メニューで選んだプロファイル id（nil = 自動）
    public var manualOverride: String?
    /// 仕事中モードと連動して切り替えるか
    public var autoSwitch: Bool

    public init(manualOverride: String? = nil, autoSwitch: Bool = true) {
        self.manualOverride = manualOverride
        self.autoSwitch = autoSwitch
    }
}

/// 「いまどのプロファイルで立つか」を決める純関数。時計もファイルも触らない。
public enum AppearanceResolver {

    /// 起動時プロファイルの特別値。「前回の状態を復元」ではなく、起動のたびに自動へ戻す。
    public static let automaticStartupID = "auto"

    /// 優先順位:
    /// 1. `manualOverride`（profiles に無ければ無視）
    /// 2. `scheduled`（将来の時刻ベース切替フック。MVP では常に nil）
    /// 3. `autoSwitch` が true なら activityMode（work → `work` / それ以外 → `casual`）
    /// 4. `default`
    public static func resolve(state: AppearanceState,
                               activityMode: ActivityMode,
                               scheduled: String? = nil,
                               profiles: [AppearanceProfile]) -> String {
        if let manual = state.manualOverride, exists(manual, in: profiles) {
            return manual
        }
        if let scheduled, exists(scheduled, in: profiles) {
            return scheduled
        }
        if state.autoSwitch {
            let candidate = activityMode == .work ? AppearanceProfile.ID.work : AppearanceProfile.ID.casual
            if exists(candidate, in: profiles) { return candidate }
        }
        return AppearanceProfile.ID.default
    }

    /// 仕事中モードを切り替えたあとの手動選択。
    /// ユーザーが自分でモードを変えたのだから、通常のプロファイルなら自動ルールに従うのが自然。
    /// `special`（renofa など）は「その日はこの見た目でいたい」という意思表示なので保持する。
    public static func overrideAfterActivityModeChange(current: String?,
                                                       profiles: [AppearanceProfile]) -> String? {
        guard let current, let profile = profiles.first(where: { $0.id == current }) else { return nil }
        return profile.special ? current : nil
    }

    /// 起動時の手動選択を決める。
    /// - `startupProfileID == nil`: 前回の状態を復元する（保存済みの override をそのまま使う）
    /// - `startupProfileID == "auto"`: override を解除して自動に戻す
    /// - それ以外: そのプロファイルを手動選択にする（profiles に無ければ前回の状態のまま）
    public static func startupOverride(startupProfileID: String?,
                                       stored: String?,
                                       profiles: [AppearanceProfile]) -> String? {
        guard let startupProfileID, !startupProfileID.isEmpty else { return stored }
        if startupProfileID == automaticStartupID { return nil }
        return exists(startupProfileID, in: profiles) ? startupProfileID : stored
    }

    private static func exists(_ id: String, in profiles: [AppearanceProfile]) -> Bool {
        profiles.contains { $0.id == id }
    }
}
