import AppKit
import EnokiCore
import os

/// 見た目プロファイルがマスコット本体に頼むこと
@MainActor
protocol AppearanceHost: AnyObject {
    /// スキンメニューで選んでいるスキン（プロファイルのスプライトセットが無いときの行き先）
    var baseSkin: Skin? { get }
    /// いま表示しているスキン
    var currentSkin: Skin? { get }
    /// フェードに使うマスコット窓
    var appearanceWindow: NSWindow? { get }
    /// スキンを差し替える（状態はできるだけ引き継ぐ）
    func swapSkin(to skin: Skin)
    /// 着替えの前に吹き出しを消す
    func cancelConversationBubble()
    /// 着替え後の 1 回だけの reaction（スキンに無ければ何もしない）
    func playAppearanceTransition(named name: String)
    /// プロファイルが変わった（会話側へ伝える）
    func appearanceProfileDidChange(_ profile: AppearanceProfile)
}

/// 見た目プロファイル（§12）の司令塔。
///
/// 「どのプロファイルか」は `AppearanceResolver`（純関数）が決め、ここは
/// スプライトセットのフォルダ解決・スキンの読み込み・フェード付きの差し替えだけを担当する。
/// **ネットワークも外部プロセスも使わない**（試合日などを取りに行くことはしない）。
@MainActor
final class AppearanceCoordinator {

    private static let logger = Logger(subsystem: "com.enoki.mascot", category: "appearance")

    static let fadeOutDuration: TimeInterval = 0.15
    static let fadeInDuration: TimeInterval = 0.2

    /// ユーザーが自分で置けるスプライトセット置き場
    static var userCharactersRoot: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Enoki/Characters", isDirectory: true)
    }

    private let settings: AppSettings
    private weak var host: AppearanceHost?

    private(set) var profiles: [AppearanceProfile] = [.fallbackDefault]
    private(set) var currentProfile: AppearanceProfile = .fallbackDefault
    /// 現在のプロファイルのスプライトセットの解決先（nil = ベーススキンにフォールバック中）
    private(set) var currentSpriteSetURL: URL?
    /// 読み込んだスキンのキャッシュ（同じフォルダを何度も読まない）
    private var skinCache: [URL: Skin] = [:]
    /// フェード中に来た再適用要求
    private var isSwapping = false
    private var needsReapply = false

    init(settings: AppSettings, host: AppearanceHost) {
        self.settings = settings
        self.host = host
        loadProfiles()
    }

    // MARK: - プロファイル定義

    private func loadProfiles() {
        guard let url = BundledResources.profilesURL else {
            Self.logger.error("profiles.json が見つかりません。default のみで動作します")
            profiles = [.fallbackDefault]
            return
        }
        do {
            let result = try AppearanceProfileLoader.load(url: url)
            for issue in result.issues {
                Self.logger.error("プロファイルを 1 件読み飛ばしました: \(issue.localizedDescription, privacy: .public)")
            }
            profiles = result.profiles
            Self.logger.info("プロファイルを読み込みました: \(result.profiles.map(\.id).joined(separator: ", "), privacy: .public)")
        } catch {
            Self.logger.error("profiles.json を読み込めません: \(error.localizedDescription, privacy: .public)")
            profiles = [.fallbackDefault]
        }
    }

    // MARK: - 起動

    /// 起動時: 「起動時のプロファイル」設定を手動選択へ反映してから解決・適用する
    func start() {
        let startup = AppearanceResolver.startupOverride(startupProfileID: settings.appearanceStartupProfileID,
                                                         stored: settings.appearanceManualOverride,
                                                         profiles: profiles)
        if startup != settings.appearanceManualOverride {
            settings.appearanceManualOverride = startup   // 通知経由で再適用が走る
        }
        Self.logger.info("起動時プロファイル設定: \(self.settings.appearanceStartupProfileID ?? "(前回の状態)", privacy: .public) 手動選択: \(startup ?? "(なし)", privacy: .public)")
        apply(animated: false)
    }

    // MARK: - 解決

    /// いま解決されるプロファイル id
    var resolvedProfileID: String {
        AppearanceResolver.resolve(state: settings.appearanceState,
                                   activityMode: settings.activityMode,
                                   scheduled: nil,   // 将来の時刻ベース切替フック
                                   profiles: profiles)
    }

    func profile(id: String) -> AppearanceProfile? { profiles.first { $0.id == id } }

    /// 手動選択中か
    var isManuallyOverridden: Bool {
        guard let manual = settings.appearanceManualOverride else { return false }
        return profile(id: manual) != nil
    }

    /// そのスプライトセット名を探すフォルダ（優先順）
    static func spriteSetCandidates(named name: String) -> [URL] {
        var urls = [
            SkinLoader.codexPetsRoot.appendingPathComponent(name, isDirectory: true),
            userCharactersRoot.appendingPathComponent(name, isDirectory: true),
        ]
        if let bundled = BundledResources.charactersURL?.appendingPathComponent(name, isDirectory: true) {
            urls.append(bundled)
        }
        return urls
    }

    /// プロファイルのスプライトセットを読む。見つからない／読めないときは nil（= ベーススキンへフォールバック）。
    private func spriteSetSkin(for profile: AppearanceProfile) -> Skin? {
        guard let spriteSet = profile.spriteSet, !spriteSet.isEmpty else { return nil }
        for url in Self.spriteSetCandidates(named: spriteSet) {
            guard SkinLoader.isSkinDirectory(url) else { continue }
            if let cached = skinCache[url] { return cached }
            do {
                let skin = try SkinLoader.load(directory: url)
                skinCache[url] = skin
                Self.logger.info("スプライトセット \(spriteSet, privacy: .public) を \(url.path, privacy: .public) から読み込みました")
                return skin
            } catch {
                Self.logger.info("スプライトセット \(spriteSet, privacy: .public) を読めません（\(url.path, privacy: .public)）: \(error.localizedDescription, privacy: .public)")
            }
        }
        Self.logger.info("スプライトセット \(spriteSet, privacy: .public) が見つかりません。ベーススキンを使います")
        return nil
    }

    /// いまのプロファイルで表示すべきスキン（スプライトセットが無ければベーススキン）
    func resolvedSkinForCurrentProfile() -> Skin? {
        spriteSetSkin(for: currentProfile) ?? host?.baseSkin
    }

    // MARK: - 適用

    /// 解決 → 必要ならスキンを差し替える
    func apply(animated: Bool = true) {
        guard let host else { return }
        guard !isSwapping else { needsReapply = true; return }

        let id = resolvedProfileID
        let profile = self.profile(id: id) ?? .fallbackDefault
        let spriteSkin = spriteSetSkin(for: profile)
        let target = spriteSkin ?? host.baseSkin

        let profileChanged = profile != currentProfile
        currentProfile = profile
        currentSpriteSetURL = spriteSkin?.sourceURL
        if profileChanged {
            Self.logger.info("プロファイル: \(profile.id, privacy: .public)（\(profile.displayName, privacy: .public)） スプライト: \(spriteSkin?.sourceURL.path ?? "ベーススキンにフォールバック", privacy: .public)")
        }
        host.appearanceProfileDidChange(profile)

        guard let target else { return }
        guard target.sourceURL != host.currentSkin?.sourceURL else { return }   // 同じスキンなら読み直さない

        host.cancelConversationBubble()
        guard animated, let window = host.appearanceWindow, window.isVisible else {
            host.swapSkin(to: target)
            playTransition(of: profile)
            return
        }

        isSwapping = true
        fade(window: window, to: 0, duration: Self.fadeOutDuration) { [weak self] in
            guard let self, let host = self.host else { return }
            host.swapSkin(to: target)
            self.fade(window: window, to: 1, duration: Self.fadeInDuration) { [weak self] in
                guard let self else { return }
                self.isSwapping = false
                self.playTransition(of: profile)
                if self.needsReapply {
                    self.needsReapply = false
                    self.apply()
                }
            }
        }
    }

    /// メニューの「再読み込み」で、スプライトセットのキャッシュも捨てる
    func invalidateSkinCache() {
        skinCache.removeAll()
    }

    /// ベーススキンを読み直したあとなど、同じ URL でも作り直したいとき
    func reapplyAfterBaseSkinChange() {
        apply(animated: false)
    }

    private func playTransition(of profile: AppearanceProfile) {
        guard let name = profile.transitionAnimation, !name.isEmpty else { return }
        host?.playAppearanceTransition(named: name)
    }

    private func fade(window: NSWindow, to alpha: CGFloat, duration: TimeInterval, completion: @escaping () -> Void) {
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = duration
            window.animator().alphaValue = alpha
        }, completionHandler: {
            MainActor.assumeIsolated {
                window.alphaValue = alpha
                completion()
            }
        })
    }

    // MARK: - 設定の反映

    /// 設定が変わった（`MascotController.settingsDidChange` から呼ばれる）
    func settingsDidChange(key: AppSettings.Key) {
        switch key {
        case .appearanceManualOverride, .appearanceAutoSwitch, .appearanceStartupProfileID:
            apply()
        case .activityMode:
            activityModeChanged()
        default:
            break
        }
    }

    /// 仕事中モードの切り替え。
    /// 通常のプロファイルを手動選択していたら解除して自動ルールに戻す（special は保持）。
    func activityModeChanged() {
        let next = AppearanceResolver.overrideAfterActivityModeChange(current: settings.appearanceManualOverride,
                                                                      profiles: profiles)
        if next != settings.appearanceManualOverride {
            Self.logger.info("仕事中モードの切り替えで手動選択を解除しました: \(self.settings.appearanceManualOverride ?? "(なし)", privacy: .public)")
            settings.appearanceManualOverride = next   // 通知経由で apply が走る
        }
        apply()
    }

    // MARK: - メニューからの操作

    func selectProfile(id: String) {
        guard profile(id: id) != nil else { return }
        settings.appearanceManualOverride = id
    }

    func clearManualOverride() {
        settings.appearanceManualOverride = nil
    }

    func setAutoSwitch(_ enabled: Bool) {
        settings.appearanceAutoSwitch = enabled
    }

    /// nil = 前回の状態を復元 / `AppearanceResolver.automaticStartupID` = 自動 / プロファイル id
    func setStartupProfile(id: String?) {
        settings.appearanceStartupProfileID = id
    }

    /// About 用の 1 行（解決先か、フォールバック中かが分かるようにする）
    var spriteSetDescription: String {
        guard let spriteSet = currentProfile.spriteSet, !spriteSet.isEmpty else {
            return "ベーススキン"
        }
        if let url = currentSpriteSetURL {
            let home = FileManager.default.homeDirectoryForCurrentUser.path
            let path = url.path.hasPrefix(home) ? "~" + url.path.dropFirst(home.count) : url.path
            return "\(spriteSet)（\(path)）"
        }
        return "\(spriteSet)（未配置のためベーススキン）"
    }
}
