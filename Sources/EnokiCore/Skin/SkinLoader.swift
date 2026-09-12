import Foundation

/// スキンがどこから読み込まれたか
public enum SkinSource: String, Equatable {
    case environment   // 環境変数 ENOKI_SKIN_DIR（開発用）
    case userSelected  // UserDefaults skinDirectory
    case codexPets     // ~/.codex/pets/sakushio_pet
    case bundled       // アプリ内蔵 DefaultSkin

    public var localizedName: String {
        switch self {
        case .environment:  return "環境変数 ENOKI_SKIN_DIR"
        case .userSelected: return "選択したフォルダ"
        case .codexPets:    return "Codex のペットフォルダ"
        case .bundled:      return "内蔵スキン"
        }
    }
}

public struct SkinResolution {
    public let skin: Skin
    public let source: SkinSource
    public let directory: URL
    /// 途中で失敗した候補（ログ用）
    public let failures: [(url: URL, error: Error)]
}

public enum SkinLoader {

    /// 環境変数名（開発用）
    public static let environmentKey = "ENOKI_SKIN_DIR"

    /// Codex の既定ペットフォルダ
    public static var defaultCodexPetURL: URL {
        codexPetsRoot.appendingPathComponent("sakushio_pet", isDirectory: true)
    }

    public static var codexPetsRoot: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".codex/pets", isDirectory: true)
    }

    /// そのディレクトリがスキンとして採用可能か（存在し、マニフェストがある）
    public static func isSkinDirectory(_ url: URL) -> Bool {
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir), isDir.boolValue else {
            return false
        }
        return CodexPetLoader.canLoad(directory: url) || StripManifestLoader.canLoad(directory: url)
    }

    /// 形式を判定して読み込む（pet.json を優先）
    public static func load(directory: URL) throws -> Skin {
        if CodexPetLoader.canLoad(directory: directory) {
            return try CodexPetLoader.load(directory: directory)
        }
        if StripManifestLoader.canLoad(directory: directory) {
            return try StripManifestLoader.load(directory: directory)
        }
        throw SkinError.manifestNotFound(directory)
    }

    /// 解決順に候補を並べる
    public static func candidates(userSelected: String?,
                                  bundled: URL?,
                                  environment: [String: String] = ProcessInfo.processInfo.environment) -> [(SkinSource, URL)] {
        var result: [(SkinSource, URL)] = []
        if let path = environment[environmentKey], !path.isEmpty {
            result.append((.environment, URL(fileURLWithPath: (path as NSString).expandingTildeInPath, isDirectory: true)))
        }
        if let userSelected, !userSelected.isEmpty {
            result.append((.userSelected, URL(fileURLWithPath: (userSelected as NSString).expandingTildeInPath, isDirectory: true)))
        }
        result.append((.codexPets, defaultCodexPetURL))
        if let bundled {
            result.append((.bundled, bundled))
        }
        return result
    }

    /// 解決順に試し、最初に成功したものを返す。
    public static func resolve(userSelected: String?,
                               bundled: URL?,
                               environment: [String: String] = ProcessInfo.processInfo.environment) throws -> SkinResolution {
        var failures: [(url: URL, error: Error)] = []
        for (source, url) in candidates(userSelected: userSelected, bundled: bundled, environment: environment) {
            guard isSkinDirectory(url) else { continue }
            do {
                let skin = try load(directory: url)
                return SkinResolution(skin: skin, source: source, directory: url, failures: failures)
            } catch {
                failures.append((url, error))
            }
        }
        if let last = failures.last { throw last.error }
        throw SkinError.noSkinAvailable
    }

    /// `~/.codex/pets` 直下でスキンとして使えるフォルダを列挙する（メニュー用）
    public static func discoverCodexPets() -> [(url: URL, displayName: String)] {
        let fm = FileManager.default
        guard let entries = try? fm.contentsOfDirectory(at: codexPetsRoot,
                                                        includingPropertiesForKeys: [.isDirectoryKey],
                                                        options: [.skipsHiddenFiles])
        else { return [] }
        return entries
            .filter { isSkinDirectory($0) }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
            .map { url in
                (url, CodexPetLoader.peekDisplayName(directory: url) ?? url.lastPathComponent)
            }
    }
}
