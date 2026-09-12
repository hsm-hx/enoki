import AppKit
import Dispatch
import EnokiCore
import os

/// 内蔵リソース（SwiftPM のリソースバンドル）へのアクセス。
/// `.app` 内では `Contents/Resources/Enoki_Enoki.bundle`、
/// `swift run` では実行ファイルの隣にある。Bundle.module が使えない場合に備えて自前でも探す。
enum BundledResources {

    private static let logger = Logger(subsystem: "com.enoki.mascot", category: "resources")

    static let resourceBundle: Bundle? = {
        let name = "Enoki_Enoki.bundle"
        var candidates: [URL] = []
        if let resourceURL = Bundle.main.resourceURL { candidates.append(resourceURL) }
        candidates.append(Bundle.main.bundleURL)
        candidates.append(Bundle.main.bundleURL.deletingLastPathComponent())
        let ownBundle = Bundle(for: MascotController.self)
        candidates.append(ownBundle.bundleURL)
        if let resourceURL = ownBundle.resourceURL { candidates.append(resourceURL) }

        for base in candidates {
            let url = base.appendingPathComponent(name)
            if let bundle = Bundle(url: url) { return bundle }
        }
        logger.error("リソースバンドル \(name, privacy: .public) が見つかりません")
        return nil
    }()

    /// 内蔵 DefaultSkin のフォルダ
    static var defaultSkinURL: URL? {
        guard let bundle = resourceBundle else { return nil }
        let url = bundle.bundleURL.appendingPathComponent("DefaultSkin", isDirectory: true)
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }
}

/// ウィンドウ・プレイヤー・状態機械・設定を結線する中心クラス。
@MainActor
final class MascotController: NSObject, MascotViewDelegate {

    private static let logger = Logger(subsystem: "com.enoki.mascot", category: "controller")

    let settings = AppSettings()

    private var window: MascotWindow?
    private var view: MascotView?
    private let player = SpritePlayer()
    private let idleMonitor = IdleMonitor()
    private var machine: MascotStateMachine?

    private(set) var skin: Skin?
    private(set) var skinSource: SkinSource = .bundled

    private var idleSwitchTimer: DispatchSourceTimer?
    /// 省電力による一時停止（スクリーンスリープ・遮蔽など）
    private var isSuspended = false

    private var now: TimeInterval { ProcessInfo.processInfo.systemUptime }

    // MARK: - 起動 / 終了

    func start() {
        guard loadSkin(initial: true) else { return }
        guard let skin else { return }

        let machine = MascotStateMachine(mapping: skin.mapping,
                                         sleepAfterSeconds: settings.sleepAfterSeconds,
                                         isVisible: settings.isVisible)
        self.machine = machine

        buildWindow(for: skin)
        applyWindowSettings()

        player.onFrame = { [weak self] animation, index in
            self?.view?.apply(animation: animation, frameIndex: index)
        }
        idleMonitor.onSample = { [weak self] seconds in
            guard let self, let machine = self.machine else { return }
            self.apply(machine.handle(.idleSecondsSampled(seconds), now: self.now))
        }

        registerObservers()
        Self.logger.info("内蔵スキン: \(BundledResources.defaultSkinURL?.path ?? "見つかりません", privacy: .public)")
        apply(machine.handle(.start, now: now))
        updateWindowVisibility()
        Self.logger.info("スキン「\(skin.displayName, privacy: .public)」を \(self.skinSource.rawValue, privacy: .public) から読み込みました")
        Self.logger.info("アニメーション: \(Self.describeFrames(of: skin), privacy: .public)")
    }

    /// ログ用: "idle=6 running-right=6 ..." のようにコマ数を列挙する
    private static func describeFrames(of skin: Skin) -> String {
        skin.animations.keys.sorted().map { "\($0)=\(skin.animations[$0]?.frameCount ?? 0)" }.joined(separator: " ")
    }

    func shutdown() {
        cancelIdleSwitchTimer()
        idleMonitor.stop()
        player.stop()
        NotificationCenter.default.removeObserver(self)
        NSWorkspace.shared.notificationCenter.removeObserver(self)
        window?.orderOut(nil)
    }

    // MARK: - スキン

    @discardableResult
    private func loadSkin(initial: Bool) -> Bool {
        do {
            let resolution = try SkinLoader.resolve(userSelected: settings.skinDirectory,
                                                    bundled: BundledResources.defaultSkinURL)
            for failure in resolution.failures {
                Self.logger.error("スキン読み込み失敗 \(failure.url.path, privacy: .public): \(failure.error.localizedDescription, privacy: .public)")
            }
            skin = resolution.skin
            skinSource = resolution.source
            return true
        } catch {
            Self.logger.error("スキンを読み込めません: \(error.localizedDescription, privacy: .public)")
            let alert = NSAlert()
            alert.alertStyle = .critical
            alert.messageText = "スキンを読み込めませんでした"
            alert.informativeText = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            alert.addButton(withTitle: "OK")
            alert.runModal()
            if initial { NSApp.terminate(nil) }
            return false
        }
    }

    /// スキンを読み直して状態機械を作り直す
    func reloadSkin() {
        guard loadSkin(initial: false), let skin, let machine else { return }
        machine.updateMapping(skin.mapping)
        apply(machine.handle(.skinReloaded, now: now))
        Self.logger.info("スキンを再読み込みしました: \(skin.displayName, privacy: .public)")
    }

    /// ユーザーがフォルダを選んだ
    func selectSkin(directory: URL) {
        guard SkinLoader.isSkinDirectory(directory) else {
            showAlert(title: "このフォルダはスキンとして使えません",
                      message: "pet.json か manifest.json があるフォルダを選んでください。")
            return
        }
        settings.skinDirectory = directory.path
        reloadSkin()
    }

    /// 内蔵スキンに戻す
    func useBundledSkin() {
        if let url = BundledResources.defaultSkinURL {
            settings.skinDirectory = url.path
        } else {
            settings.skinDirectory = nil
        }
        reloadSkin()
    }

    var skinDisplayName: String { skin?.displayName ?? "(未読み込み)" }
    var skinDirectoryURL: URL? { skin?.sourceURL }

    // MARK: - ウィンドウ構築

    private func buildWindow(for skin: Skin) {
        let animation = skin.animation(named: skin.defaultIdleName) ?? skin.animations.values.first
        let size = pointSize(for: animation)
        let origin = WindowPlacement.resolve(saved: settings.savedWindowOrigin,
                                             size: size,
                                             screens: visibleFrames(),
                                             mainScreen: mainVisibleFrame())

        let window = MascotWindow(contentRect: NSRect(origin: origin, size: size))
        let view = MascotView(frame: NSRect(origin: .zero, size: size))
        view.delegate = self
        view.setInterpolation(settings.interpolation)
        window.contentView = view
        window.setFrameOrigin(origin)

        self.window = window
        self.view = view
        view.layer?.contentsScale = window.backingScaleFactor
    }

    private func pointSize(for animation: SpriteAnimation?) -> CGSize {
        guard let animation else { return CGSize(width: 192, height: 208) }
        let scale = CGFloat(settings.scale)
        let base = animation.pointSize
        return CGSize(width: (base.width * scale).rounded(), height: (base.height * scale).rounded())
    }

    private func visibleFrames() -> [CGRect] {
        NSScreen.screens.map { $0.visibleFrame }
    }

    private func mainVisibleFrame() -> CGRect {
        NSScreen.main?.visibleFrame ?? NSScreen.screens.first?.visibleFrame ?? CGRect(x: 0, y: 0, width: 1440, height: 900)
    }

    // MARK: - 効果の適用

    private func apply(_ effects: [MascotStateMachine.Effect]) {
        for effect in effects {
            switch effect {
            case .play(let name, let loop, let token):
                playAnimation(named: name, loop: loop, token: token)
            case .scheduleIdleSwitch(let after):
                scheduleIdleSwitchTimer(after: after)
            case .cancelIdleSwitch:
                cancelIdleSwitchTimer()
            case .pausePlayback:
                player.pause()
            case .resumePlayback:
                if !isSuspended { player.resume() }
            case .setIdlePolling(let interval):
                idleMonitor.setPolling(interval: interval)
            }
        }
    }

    private func playAnimation(named name: String, loop: Bool, token: Int) {
        guard let skin, let animation = skin.animation(named: name) ?? skin.animation(named: skin.defaultIdleName) else {
            Self.logger.error("アニメーション \(name, privacy: .public) がありません")
            return
        }
        resizeWindowIfNeeded(for: animation)
        Self.logger.info("再生: \(animation.name, privacy: .public) \(animation.frameCount)コマ loop=\(loop) token=\(token)")
        player.play(animation, loop: loop) { [weak self] in
            guard let self, let machine = self.machine else { return }
            self.apply(machine.handle(.animationFinished(token: token), now: self.now))
        }
        if isSuspended { player.pause() }
    }

    private func resizeWindowIfNeeded(for animation: SpriteAnimation) {
        guard let window else { return }
        let newSize = pointSize(for: animation)
        guard abs(window.frame.width - newSize.width) > 0.5 || abs(window.frame.height - newSize.height) > 0.5 else { return }
        let origin = WindowPlacement.originPreservingBottomCenter(origin: window.frame.origin,
                                                                  oldSize: window.frame.size,
                                                                  newSize: newSize)
        // マウス位置ではなく、いま表示されている画面を基準にクランプする
        let clamped = WindowPlacement.resolve(saved: origin,
                                              size: newSize,
                                              screens: visibleFrames(),
                                              mainScreen: mainVisibleFrame())
        window.setFrame(NSRect(origin: clamped, size: newSize), display: false)
        view?.frame = NSRect(origin: .zero, size: newSize)
    }

    // MARK: - idle 切替タイマー

    private func scheduleIdleSwitchTimer(after seconds: TimeInterval) {
        cancelIdleSwitchTimer()
        let source = DispatchSource.makeTimerSource(queue: .main)
        source.schedule(deadline: .now() + max(1, seconds), leeway: .seconds(1))
        source.setEventHandler { [weak self] in
            MainActor.assumeIsolated {
                guard let self, let machine = self.machine else { return }
                self.apply(machine.handle(.idleSwitchFired, now: self.now))
            }
        }
        idleSwitchTimer = source
        source.resume()
    }

    private func cancelIdleSwitchTimer() {
        idleSwitchTimer?.cancel()
        idleSwitchTimer = nil
    }

    // MARK: - MascotViewDelegate

    func mascotViewDragBegan(_ view: MascotView) {
        guard let machine else { return }
        apply(machine.handle(.dragBegan, now: now))
    }

    func mascotViewDragEnded(_ view: MascotView) {
        guard let machine, let window else { return }
        // マウスのある画面に収める
        let settled = WindowPlacement.settle(origin: window.frame.origin,
                                             size: window.frame.size,
                                             mouseLocation: NSEvent.mouseLocation,
                                             screens: visibleFrames(),
                                             mainScreen: mainVisibleFrame())
        window.setFrameOrigin(settled)
        settings.savedWindowOrigin = settled
        apply(machine.handle(.dragEnded, now: now))
    }

    func mascotViewClicked(_ view: MascotView) {
        guard let machine else { return }
        apply(machine.handle(.clicked, now: now))
    }

    // MARK: - 設定の反映

    private func applyWindowSettings() {
        guard let window else { return }
        window.setAlwaysOnTop(settings.alwaysOnTop)
        window.setClickThrough(settings.clickThrough)
        view?.setInterpolation(settings.interpolation)
    }

    private func updateWindowVisibility() {
        guard let window else { return }
        if settings.isVisible {
            window.orderFrontRegardless()
        } else {
            window.orderOut(nil)
        }
    }

    @objc private func settingsDidChange(_ note: Notification) {
        guard let raw = note.userInfo?[AppSettings.changedKeyUserInfoKey] as? String,
              let key = AppSettings.Key(rawValue: raw) else { return }

        switch key {
        case .isVisible:
            updateWindowVisibility()
            if let machine {
                apply(machine.handle(.setVisible(settings.isVisible), now: now))
            }
        case .alwaysOnTop:
            window?.setAlwaysOnTop(settings.alwaysOnTop)
        case .clickThrough:
            window?.setClickThrough(settings.clickThrough)
        case .interpolation:
            view?.setInterpolation(settings.interpolation)
        case .scale:
            applyScaleChange()
        case .sleepAfterSeconds:
            if let machine {
                apply(machine.updateSleepAfterSeconds(settings.sleepAfterSeconds, now: now))
            }
        case .skinDirectory, .windowOriginX, .windowOriginY, .hasSavedWindowOrigin:
            break
        }
    }

    /// 表示倍率の変更: 下端中央を固定してリサイズ → クランプ → 保存
    private func applyScaleChange() {
        guard let window, let animation = player.animation else { return }
        let newSize = pointSize(for: animation)
        let origin = WindowPlacement.originPreservingBottomCenter(origin: window.frame.origin,
                                                                  oldSize: window.frame.size,
                                                                  newSize: newSize)
        // メニュー操作中のマウスは別画面にあり得るので、マスコットが乗っている画面を基準にする
        let clamped = WindowPlacement.resolve(saved: origin,
                                              size: newSize,
                                              screens: visibleFrames(),
                                              mainScreen: mainVisibleFrame())
        window.setFrame(NSRect(origin: clamped, size: newSize), display: true)
        view?.frame = NSRect(origin: .zero, size: newSize)
        settings.savedWindowOrigin = clamped
    }

    /// 位置を既定（メイン画面右下）に戻す
    func resetPosition() {
        guard let window else { return }
        settings.savedWindowOrigin = nil
        let origin = WindowPlacement.defaultOrigin(size: window.frame.size, within: mainVisibleFrame())
        window.setFrameOrigin(origin)
        settings.savedWindowOrigin = origin
    }

    // MARK: - 通知

    private func registerObservers() {
        let center = NotificationCenter.default
        center.addObserver(self, selector: #selector(settingsDidChange(_:)),
                           name: AppSettings.didChangeNotification, object: nil)
        center.addObserver(self, selector: #selector(screenParametersChanged(_:)),
                           name: NSApplication.didChangeScreenParametersNotification, object: nil)
        center.addObserver(self, selector: #selector(occlusionChanged(_:)),
                           name: NSWindow.didChangeOcclusionStateNotification, object: window)

        let workspace = NSWorkspace.shared.notificationCenter
        workspace.addObserver(self, selector: #selector(suspendPlayback),
                              name: NSWorkspace.willSleepNotification, object: nil)
        workspace.addObserver(self, selector: #selector(resumePlayback),
                              name: NSWorkspace.didWakeNotification, object: nil)
        workspace.addObserver(self, selector: #selector(suspendPlayback),
                              name: NSWorkspace.sessionDidResignActiveNotification, object: nil)
        workspace.addObserver(self, selector: #selector(resumePlayback),
                              name: NSWorkspace.sessionDidBecomeActiveNotification, object: nil)
    }

    @objc private func screenParametersChanged(_ note: Notification) {
        guard let window else { return }
        Self.logger.info("画面構成が変わりました: origin=\(window.frame.origin.x),\(window.frame.origin.y)")
        let origin = WindowPlacement.resolve(saved: window.frame.origin,
                                             size: window.frame.size,
                                             screens: visibleFrames(),
                                             mainScreen: mainVisibleFrame())
        window.setFrameOrigin(origin)
        if settings.hasSavedWindowOrigin { settings.savedWindowOrigin = origin }
    }

    @objc private func occlusionChanged(_ note: Notification) {
        guard let window else { return }
        Self.logger.info("遮蔽状態: visible=\(window.occlusionState.contains(.visible))")
        if window.occlusionState.contains(.visible) {
            resumePlayback()
        } else {
            suspendPlayback()
        }
    }

    @objc private func suspendPlayback() {
        isSuspended = true
        player.pause()
    }

    @objc private func resumePlayback() {
        isSuspended = false
        guard settings.isVisible else { return }
        player.resume()
    }

    // MARK: - ヘルパ

    private func showAlert(title: String, message: String) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = title
        alert.informativeText = message
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }
}
