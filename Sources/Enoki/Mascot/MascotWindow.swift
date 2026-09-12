import AppKit

/// マスコット用の透明・非アクティブ化パネル。
/// クリックしてもアプリがアクティブにならないので、作業の邪魔をしない。
final class MascotWindow: NSPanel {

    init(contentRect: NSRect) {
        super.init(contentRect: contentRect,
                   styleMask: [.borderless, .nonactivatingPanel],
                   backing: .buffered,
                   defer: false)

        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        isMovable = false               // 移動は MascotView 側で自前実装
        isMovableByWindowBackground = false
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        animationBehavior = .none
        isExcludedFromWindowsMenu = true
        ignoresMouseEvents = false
        collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        level = .floating
        // 透明部分のクリックは非 opaque ウィンドウの標準挙動で下へ抜ける
    }

    // キーウィンドウ・メインウィンドウにはならない
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    /// 常に最前面の ON/OFF
    func setAlwaysOnTop(_ onTop: Bool) {
        level = onTop ? .floating : .normal
    }

    /// クリック透過モード
    func setClickThrough(_ enabled: Bool) {
        ignoresMouseEvents = enabled
    }
}
