import AppKit
import os

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {

    static let logger = Logger(subsystem: "com.enoki.mascot", category: "app")

    private var controller: MascotController?
    private var statusMenu: StatusMenuController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let controller = MascotController()
        self.controller = controller
        self.statusMenu = StatusMenuController(controller: controller)
        controller.start()
        AppDelegate.logger.info("朔と栞 を起動しました")
    }

    func applicationWillTerminate(_ notification: Notification) {
        controller?.shutdown()
        AppDelegate.logger.info("終了します")
    }

    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool { true }
}
