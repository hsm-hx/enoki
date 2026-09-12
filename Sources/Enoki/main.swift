import AppKit

// トップレベルコードはメインスレッドで実行される。
// Swift の並行性チェックに対して明示的に MainActor 上であることを伝える。
MainActor.assumeIsolated {
    let app = NSApplication.shared
    // Dock に出さない（Info.plist の LSUIElement と二重に保証する）
    app.setActivationPolicy(.accessory)

    // AppDelegate はこのスコープが app.run() を抱えている間ずっと生きる
    let delegate = AppDelegate()
    app.delegate = delegate
    app.run()
}
