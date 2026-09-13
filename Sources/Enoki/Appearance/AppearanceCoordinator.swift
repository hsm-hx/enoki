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
/// 「どのプロファイルか」は `AppearanceResolver` / `DayProfileResolver`（純関数）が決め、ここは
/// データの読み込み（祝日・試合日程）・スプライトセットのフォルダ解決・スキンの読み込み・
/// フェード付きの差し替え・日付が変わったときの再評価だけを担当する。
/// **ネットワークも外部プロセスも使わない**（試合日は同梱・ユーザー配置の JSON を読むだけ）。
@MainActor
final class AppearanceCoordinator {

    private static let logger = Logger(subsystem: "com.enoki.mascot", category: "appearance")

    static let fadeOutDuration: TimeInterval = 0.15
    static let fadeInDuration: TimeInterval = 0.2

    /// ユーザーが自分でデータを置ける場所（`~/Library/Application Support/Enoki/`）
    static var userSupportRoot: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Enoki", isDirectory: true)
    }

    /// ユーザーが自分で置けるスプライトセット置き場
    static var userCharactersRoot: URL {
        userSupportRoot.appendingPathComponent("Characters", isDirectory: true)
    }

    private let settings: AppSettings
    private weak var host: AppearanceHost?

    /// 祝日（内閣府の公式データ + 特例ファイル）
    private let holidays: JapaneseHolidays
    /// レノファの試合日程
    private(set) var schedule: RenofaSchedule = .empty
    /// 日付が変わった／スリープから復帰したときの再評価用
    private var dayObservers: [NSObjectProtocol] = []

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
        self.holidays = Self.loadHolidays()
        loadProfiles()
        loadSchedule()
    }

    deinit {
        for observer in dayObservers { NotificationCenter.default.removeObserver(observer) }
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

    // MARK: - その日の判定に使うデータ

    /// 祝日データ。ユーザー配置（`~/Library/Application Support/Enoki/jp-holidays.json`）があればそちらを優先し、
    /// 無ければ内蔵データを読む。特例ファイル（`holidays-overrides.json`）があれば重ねる。
    private static func loadHolidays() -> JapaneseHolidays {
        var data = JapaneseHolidayData.empty
        let candidates = [userSupportRoot.appendingPathComponent(JapaneseHolidayData.fileName),
                          BundledResources.holidaysURL].compactMap { $0 }
        for url in candidates {
            guard FileManager.default.fileExists(atPath: url.path) else { continue }
            guard let loaded = try? JapaneseHolidayData.load(url: url), !loaded.isEmpty else {
                logger.error("祝日データを読み込めません: \(url.path, privacy: .public)")
                continue
            }
            data = loaded
            logger.info("祝日データ: \(url.path, privacy: .public)（\(loaded.firstYear ?? 0)〜\(loaded.lastYear ?? 0) 年 \(loaded.holidays.count) 件）")
            break
        }
        if data.isEmpty {
            logger.info("祝日データが無いので、現行ルールの計算で判定します")
        }

        let overridesURL = userSupportRoot.appendingPathComponent(JapaneseHolidayOverrides.fileName)
        var overrides = JapaneseHolidayOverrides.none
        if FileManager.default.fileExists(atPath: overridesURL.path) {
            overrides = JapaneseHolidayOverrides.load(url: overridesURL)
            logger.info("祝日の特例: 追加 \(overrides.add.count) 件 / 除外 \(overrides.remove.count) 件（\(overridesURL.path, privacy: .public)）")
        }
        return JapaneseHolidays(data: data, overrides: overrides)
    }

    /// 試合日程。ユーザー配置（アプリを作り直さずに差し替えられる）→ 内蔵 の順に探す。
    private func loadSchedule() {
        let candidates = [Self.userSupportRoot.appendingPathComponent(RenofaScheduleLoader.fileName),
                          BundledResources.scheduleURL].compactMap { $0 }
        for url in candidates {
            guard FileManager.default.fileExists(atPath: url.path) else { continue }
            do {
                let result = try RenofaScheduleLoader.load(url: url)
                for issue in result.issues {
                    Self.logger.error("試合を 1 件読み飛ばしました: \(issue.localizedDescription, privacy: .public)")
                }
                schedule = result.schedule
                Self.logger.info("試合日程: \(url.path, privacy: .public)（\(result.schedule.matches.count) 試合 / 取得元 \(result.schedule.source ?? "-", privacy: .public)）")
                return
            } catch {
                Self.logger.error("試合日程を読み込めません（\(url.path, privacy: .public)）: \(error.localizedDescription, privacy: .public)")
            }
        }
        schedule = .empty
        Self.logger.info("試合日程がありません。曜日と祝日だけで判定します")
    }

    // MARK: - 今日の判定（§12.9）

    /// 今日がどんな日か（`profileID == nil` なら特別な日ではない = 既存ルールに任せる）
    var todayDecision: DayProfileDecision {
        DayProfileResolver.resolve(date: Date(), schedule: schedule, holidays: holidays)
    }

    /// メニュー・About の 1 行（「今日: 日曜日 → Casual」「今日: 平日」）
    var todayDescription: String {
        let decision = todayDecision
        guard let id = decision.profileID, let profile = profile(id: id) else {
            return "今日: \(decision.reason)"
        }
        return "今日: \(decision.reason) → \(profile.displayName)"
    }

    /// 日付が変わった／スリープから復帰した: 手動選択の期限切れを処理してから解決し直す
    func reevaluateDay(reason: String) {
        let today = DayProfileResolver.dayKey(for: Date())
        expireManualOverrideIfNeeded(today: today)
        let decision = todayDecision
        Self.logger.info("\(reason, privacy: .public) → 今日: \(decision.reason, privacy: .public) → \(decision.profileID ?? "default（既存ルール）", privacy: .public)")
        apply()
    }

    /// 手動選択は**その日限り**。選んだ日と今日が違えば解除する。
    @discardableResult
    private func expireManualOverrideIfNeeded(today: String) -> Bool {
        let next = AppearanceResolver.expiredOverride(current: settings.appearanceManualOverride,
                                                      setOn: settings.appearanceManualOverrideDay,
                                                      today: today)
        guard next != settings.appearanceManualOverride else { return false }
        Self.logger.info("日付が変わったので手動選択を解除しました: \(self.settings.appearanceManualOverride ?? "(なし)", privacy: .public)")
        settings.appearanceManualOverride = next   // 通知経由で apply が走る
        settings.appearanceManualOverrideDay = nil
        return true
    }

    private func registerDayObservers() {
        let dayChanged = NotificationCenter.default.addObserver(forName: .NSCalendarDayChanged,
                                                               object: nil,
                                                               queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.reevaluateDay(reason: "日付が変わりました") }
        }
        let didWake = NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didWakeNotification,
                                                                        object: nil,
                                                                        queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.reevaluateDay(reason: "スリープから復帰しました") }
        }
        dayObservers = [dayChanged, didWake]
    }

    // MARK: - 起動

    /// 起動時: 「起動時のプロファイル」設定と「手動選択はその日限り」を反映してから解決・適用する
    func start() {
        let today = DayProfileResolver.dayKey(for: Date())
        let startup = AppearanceResolver.startupOverride(startupProfileID: settings.appearanceStartupProfileID,
                                                         stored: settings.appearanceManualOverride,
                                                         profiles: profiles)
        // 「起動時のプロファイル」で id を指定しているときは、毎回それで始める（その日の判定より優先）
        let next = startupPinsProfile(startup)
            ? startup
            : AppearanceResolver.expiredOverride(current: startup,
                                                 setOn: settings.appearanceManualOverrideDay,
                                                 today: today)
        if next != settings.appearanceManualOverride {
            settings.appearanceManualOverride = next   // 通知経由で再適用が走る
        }
        let day = next == nil ? nil : today
        if settings.appearanceManualOverrideDay != day {
            settings.appearanceManualOverrideDay = day
        }
        Self.logger.info("起動時プロファイル設定: \(self.settings.appearanceStartupProfileID ?? "(前回の状態)", privacy: .public) 手動選択: \(next ?? "(なし)", privacy: .public)")
        let decision = todayDecision
        Self.logger.info("今日: \(decision.reason, privacy: .public) → \(decision.profileID ?? "default（既存ルール）", privacy: .public)")
        registerDayObservers()
        apply(animated: false)
    }

    /// 「起動時のプロファイル」でプロファイル id を指定しているか（「前回の状態」「自動」なら false）
    private func startupPinsProfile(_ startup: String?) -> Bool {
        guard let configured = settings.appearanceStartupProfileID, !configured.isEmpty,
              configured != AppearanceResolver.automaticStartupID else { return false }
        return startup == configured
    }

    // MARK: - 解決

    /// いま解決されるプロファイル id
    var resolvedProfileID: String {
        AppearanceResolver.resolve(state: settings.appearanceState,
                                   activityMode: settings.activityMode,
                                   scheduled: todayDecision.profileID,   // その日の自動判定（§12.9）
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
            if next == nil { settings.appearanceManualOverrideDay = nil }
            settings.appearanceManualOverride = next   // 通知経由で apply が走る
        }
        apply()
    }

    // MARK: - メニューからの操作

    /// 手動選択は**その日限り**なので、選んだ日も一緒に控える（日付が変わるか次回起動で自動に戻る）
    func selectProfile(id: String) {
        guard profile(id: id) != nil else { return }
        settings.appearanceManualOverrideDay = DayProfileResolver.dayKey(for: Date())
        settings.appearanceManualOverride = id
    }

    func clearManualOverride() {
        settings.appearanceManualOverrideDay = nil
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
