import AppKit
import EnokiCore
import os

/// メニューバー（NSStatusItem）。メニューを開くたびに中身を作り直してチェック状態を最新化する。
@MainActor
final class StatusMenuController: NSObject, NSMenuDelegate {

    private static let logger = Logger(subsystem: "com.enoki.mascot", category: "menu")

    private let controller: MascotController
    private var settings: AppSettings { controller.settings }
    private let statusItem: NSStatusItem
    private let menu = NSMenu()

    init(controller: MascotController) {
        self.controller = controller
        self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        super.init()

        if let button = statusItem.button {
            let image = NSImage(systemSymbolName: "person.2.fill", accessibilityDescription: "朔と栞")
            image?.isTemplate = true
            button.image = image
            button.toolTip = "朔と栞"
        }
        menu.delegate = self
        statusItem.menu = menu
        rebuild()
    }

    // MARK: - NSMenuDelegate

    func menuNeedsUpdate(_ menu: NSMenu) {
        rebuild()
    }

    // MARK: - メニュー構築

    private func rebuild() {
        menu.removeAllItems()

        add(title: "朔と栞を表示", action: #selector(toggleVisible), state: settings.isVisible)
        add(title: "ちょっと話して", action: #selector(speakNow), state: false)
        menu.addItem(conversationMenuItem())
        add(title: "仕事中モード", action: #selector(toggleActivityMode), state: settings.activityMode == .work)
        menu.addItem(.separator())

        add(title: "常に最前面", action: #selector(toggleAlwaysOnTop), state: settings.alwaysOnTop)
        add(title: "クリック透過（ドラッグ・クリック不可）", action: #selector(toggleClickThrough), state: settings.clickThrough)

        menu.addItem(scaleMenuItem())
        menu.addItem(interpolationMenuItem())
        menu.addItem(sleepMenuItem())

        menu.addItem(.separator())
        menu.addItem(skinMenuItem())

        menu.addItem(.separator())
        add(title: "ログイン時に自動起動", action: #selector(toggleLoginItem), state: LoginItemManager.isEnabled)
        add(title: "位置をリセット", action: #selector(resetPosition), state: false)

        menu.addItem(.separator())
        add(title: "Enoki について", action: #selector(showAbout), state: false)
        let quit = NSMenuItem(title: "終了", action: #selector(quit), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)
    }

    @discardableResult
    private func add(title: String, action: Selector, state: Bool, representedObject: Any? = nil) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        item.state = state ? .on : .off
        item.representedObject = representedObject
        menu.addItem(item)
        return item
    }

    private func scaleMenuItem() -> NSMenuItem {
        let item = NSMenuItem(title: "表示倍率", action: nil, keyEquivalent: "")
        let submenu = NSMenu()
        let current = settings.scale
        for preset in AppSettings.scalePresets {
            let sub = NSMenuItem(title: "\(Int(preset * 100))%", action: #selector(setScale(_:)), keyEquivalent: "")
            sub.target = self
            sub.representedObject = preset
            sub.state = abs(current - preset) < 0.001 ? .on : .off
            submenu.addItem(sub)
        }
        item.submenu = submenu
        return item
    }

    private func interpolationMenuItem() -> NSMenuItem {
        let item = NSMenuItem(title: "描画補間", action: nil, keyEquivalent: "")
        let submenu = NSMenu()
        for mode in InterpolationMode.allCases {
            let sub = NSMenuItem(title: mode.localizedName, action: #selector(setInterpolation(_:)), keyEquivalent: "")
            sub.target = self
            sub.representedObject = mode.rawValue
            sub.state = settings.interpolation == mode ? .on : .off
            submenu.addItem(sub)
        }
        item.submenu = submenu
        return item
    }

    private func sleepMenuItem() -> NSMenuItem {
        let item = NSMenuItem(title: "スリープまでの時間", action: nil, keyEquivalent: "")
        let submenu = NSMenu()
        let current = settings.sleepAfterSeconds
        for preset in AppSettings.sleepPresets {
            if preset == 0 { submenu.addItem(.separator()) }
            let title = preset == 0 ? "スリープしない" : "\(preset / 60)分"
            let sub = NSMenuItem(title: title, action: #selector(setSleepAfter(_:)), keyEquivalent: "")
            sub.target = self
            sub.representedObject = preset
            sub.state = current == preset ? .on : .off
            submenu.addItem(sub)
        }
        item.submenu = submenu
        return item
    }

    /// 会話（静かにする）サブメニュー。現在の状態をラジオで示す。
    private func conversationMenuItem() -> NSMenuItem {
        let item = NSMenuItem(title: "会話", action: nil, keyEquivalent: "")
        let submenu = NSMenu()
        let now = Date()
        let current = settings.quietMode

        let header = NSMenuItem(title: "現在: \(current.localizedName(at: now))", action: nil, keyEquivalent: "")
        header.isEnabled = false
        submenu.addItem(header)
        submenu.addItem(.separator())

        let choices: [(title: String, tag: String)] = [
            ("通常", "normal"),
            ("1時間静かにする", "hour"),
            ("今日の仕事終了まで静かにする", "workday"),
            ("会話OFF", "off"),
        ]
        for choice in choices {
            let sub = NSMenuItem(title: choice.title, action: #selector(setQuietMode(_:)), keyEquivalent: "")
            sub.target = self
            sub.representedObject = choice.tag
            sub.state = (Self.quietTag(for: current) == choice.tag) ? .on : .off
            submenu.addItem(sub)
        }

        item.submenu = submenu
        return item
    }

    private static func quietTag(for mode: QuietMode) -> String {
        switch mode {
        case .normal:            return "normal"
        case .until:             return "hour"
        case .untilEndOfWorkDay: return "workday"
        case .off:               return "off"
        }
    }

    private func skinMenuItem() -> NSMenuItem {
        let item = NSMenuItem(title: "スキン", action: nil, keyEquivalent: "")
        let submenu = NSMenu()

        let currentPath = controller.skinDirectoryURL?.path ?? ""
        let header = NSMenuItem(title: "現在: \(controller.skinDisplayName)（\(abbreviate(currentPath))）",
                                action: nil, keyEquivalent: "")
        header.isEnabled = false
        submenu.addItem(header)
        submenu.addItem(.separator())

        let pets = SkinLoader.discoverCodexPets()
        if pets.isEmpty {
            let empty = NSMenuItem(title: "~/.codex/pets にスキンがありません", action: nil, keyEquivalent: "")
            empty.isEnabled = false
            submenu.addItem(empty)
        } else {
            for pet in pets {
                let sub = NSMenuItem(title: "\(pet.displayName)（\(pet.url.lastPathComponent)）",
                                     action: #selector(selectSkin(_:)), keyEquivalent: "")
                sub.target = self
                sub.representedObject = pet.url
                sub.state = (pet.url.path == currentPath) ? .on : .off
                submenu.addItem(sub)
            }
        }
        submenu.addItem(.separator())

        let choose = NSMenuItem(title: "フォルダを選択…", action: #selector(chooseSkinFolder), keyEquivalent: "")
        choose.target = self
        submenu.addItem(choose)

        let bundled = NSMenuItem(title: "内蔵スキンを使用", action: #selector(useBundledSkin), keyEquivalent: "")
        bundled.target = self
        submenu.addItem(bundled)

        let reload = NSMenuItem(title: "再読み込み", action: #selector(reloadSkin), keyEquivalent: "")
        reload.target = self
        submenu.addItem(reload)

        item.submenu = submenu
        return item
    }

    private func abbreviate(_ path: String) -> String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return path.hasPrefix(home) ? "~" + path.dropFirst(home.count) : path
    }

    // MARK: - アクション

    @objc private func toggleVisible() { settings.isVisible.toggle() }
    @objc private func toggleAlwaysOnTop() { settings.alwaysOnTop.toggle() }
    @objc private func toggleClickThrough() { settings.clickThrough.toggle() }

    @objc private func speakNow() { controller.speakNow() }

    @objc private func toggleActivityMode() {
        settings.activityMode = (settings.activityMode == .work) ? .rest : .work
    }

    @objc private func setQuietMode(_ sender: NSMenuItem) {
        guard let tag = sender.representedObject as? String else { return }
        let now = Date()
        switch tag {
        case "hour":
            settings.quietMode = .until(now.addingTimeInterval(60 * 60))
        case "workday":
            settings.quietMode = QuietMode.endOfWorkDay(from: now, workEndHour: settings.workEndHour)
        case "off":
            settings.quietMode = .off
        default:
            settings.quietMode = .normal
        }
        Self.logger.info("会話モード: \(self.settings.quietMode.rawValue, privacy: .public)")
    }

    @objc private func setScale(_ sender: NSMenuItem) {
        guard let value = sender.representedObject as? Double else { return }
        settings.scale = value
    }

    @objc private func setInterpolation(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String,
              let mode = InterpolationMode(rawValue: raw) else { return }
        settings.interpolation = mode
    }

    @objc private func setSleepAfter(_ sender: NSMenuItem) {
        guard let value = sender.representedObject as? Int else { return }
        settings.sleepAfterSeconds = value
    }

    @objc private func selectSkin(_ sender: NSMenuItem) {
        guard let url = sender.representedObject as? URL else { return }
        controller.selectSkin(directory: url)
    }

    @objc private func chooseSkinFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = "選択"
        panel.message = "pet.json か manifest.json があるフォルダを選んでください。"
        NSApp.activate(ignoringOtherApps: true)
        guard panel.runModal() == .OK, let url = panel.url else { return }
        controller.selectSkin(directory: url)
    }

    @objc private func useBundledSkin() { controller.useBundledSkin() }
    @objc private func reloadSkin() { controller.reloadSkin() }
    @objc private func resetPosition() { controller.resetPosition() }

    @objc private func toggleLoginItem() {
        let enable = !LoginItemManager.isEnabled
        do {
            try LoginItemManager.setEnabled(enable)
        } catch {
            let alert = NSAlert()
            alert.alertStyle = .warning
            alert.messageText = "ログイン項目を変更できませんでした"
            alert.informativeText = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            alert.addButton(withTitle: "OK")
            if LoginItemManager.requiresApproval {
                alert.addButton(withTitle: "システム設定を開く")
            }
            NSApp.activate(ignoringOtherApps: true)
            if alert.runModal() == .alertSecondButtonReturn {
                LoginItemManager.openSystemSettings()
            }
            Self.logger.error("ログイン項目の変更に失敗しました")
        }
    }

    @objc private func showAbout() {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.1.0"
        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.messageText = "朔と栞 (Enoki) \(version)"
        alert.informativeText = """
        デスクトップに常駐するマスコットです。

        スキン: \(controller.skinDisplayName)
        読み込み元: \(abbreviate(controller.skinDirectoryURL?.path ?? "-"))
        台詞: \(abbreviate(controller.dialogueSourceURL?.path ?? "(読み込みなし)"))

        ネットワーク通信・テレメトリは一切行いません。
        アクセシビリティ／画面収録／入力監視の権限も不要です。
        """
        alert.addButton(withTitle: "OK")
        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}
