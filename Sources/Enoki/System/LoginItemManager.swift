import Foundation
import ServiceManagement
import os

/// ログイン時の自動起動（`SMAppService.mainApp`）。
/// `.app` バンドルとして起動していない場合は登録できないので、呼び出し側でエラーを表示する。
enum LoginItemManager {

    private static let logger = Logger(subsystem: "com.enoki.mascot", category: "loginItem")

    enum LoginItemError: LocalizedError {
        case notBundled
        case requiresApproval
        case underlying(Error)

        var errorDescription: String? {
            switch self {
            case .notBundled:
                return "ログイン項目に登録できませんでした。\n`swift run` などで直接起動している場合は登録できません。`make app` で作った Enoki.app を /Applications か ~/Applications に置いて起動してください。"
            case .requiresApproval:
                return "ログイン項目の登録に承認が必要です。「システム設定 > 一般 > ログイン項目」で Enoki を有効にしてください。"
            case .underlying(let error):
                return "ログイン項目の設定に失敗しました: \(error.localizedDescription)"
            }
        }
    }

    static var status: SMAppService.Status { SMAppService.mainApp.status }

    static var isEnabled: Bool { status == .enabled }

    static var requiresApproval: Bool { status == .requiresApproval }

    static func setEnabled(_ enabled: Bool) throws {
        do {
            if enabled {
                try SMAppService.mainApp.register()
                if SMAppService.mainApp.status == .requiresApproval {
                    throw LoginItemError.requiresApproval
                }
            } else {
                try SMAppService.mainApp.unregister()
            }
            logger.info("ログイン項目を \(enabled ? "登録" : "解除") しました")
        } catch let error as LoginItemError {
            throw error
        } catch {
            logger.error("ログイン項目の操作に失敗: \(error.localizedDescription, privacy: .public)")
            // bundle 外から起動している場合はここに来る
            if Bundle.main.bundleURL.pathExtension != "app" {
                throw LoginItemError.notBundled
            }
            throw LoginItemError.underlying(error)
        }
    }

    /// 「システム設定 > 一般 > ログイン項目」を開く
    static func openSystemSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }
}
