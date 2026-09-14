import Foundation

/// `profiles.json` の読み込みで「その項目だけ捨てた」理由
public enum AppearanceProfileLoadIssue: Error, Equatable, LocalizedError {
    case notAnObject                       // ルートが辞書でない
    case entryNotAnObject(index: Int)
    case missingID(index: Int)
    case duplicateID(String)

    public var errorDescription: String? {
        switch self {
        case .notAnObject:
            return "プロファイルファイルのルートがオブジェクトではありません。"
        case .entryNotAnObject(let index):
            return "profiles[\(index)] がオブジェクトではありません。"
        case .missingID(let index):
            return "profiles[\(index)] に id がありません。"
        case .duplicateID(let id):
            return "プロファイル id が重複しています: \(id)"
        }
    }
}

/// 読み込み結果。壊れた項目は `issues` に理由が入り、`profiles` からは取り除かれる。
public struct AppearanceProfileLoadResult: Equatable {
    public let schemaVersion: Int
    public let profiles: [AppearanceProfile]
    public let issues: [AppearanceProfileLoadIssue]

    public init(schemaVersion: Int, profiles: [AppearanceProfile], issues: [AppearanceProfileLoadIssue]) {
        self.schemaVersion = schemaVersion
        self.profiles = profiles
        self.issues = issues
    }

    public func profile(id: String) -> AppearanceProfile? {
        profiles.first { $0.id == id }
    }
}

/// `profiles.json` のローダ。
/// 未知のキーは無視し、「id が無い / 空 / 重複」の項目だけ捨てて残りを返す（DialogueLoader と同じ流儀）。
/// `default` が無ければ先頭に補う。
public enum AppearanceProfileLoader {

    public static let fileName = "profiles.json"

    public static func load(data: Data) throws -> AppearanceProfileLoadResult {
        let json = try JSONSerialization.jsonObject(with: data, options: [])
        guard let root = json as? [String: Any] else {
            throw AppearanceProfileLoadIssue.notAnObject
        }
        let schemaVersion = (root["schema_version"] as? NSNumber)?.intValue ?? 1
        let rawList = root["profiles"] as? [Any] ?? []

        var profiles: [AppearanceProfile] = []
        var issues: [AppearanceProfileLoadIssue] = []
        var seenIDs = Set<String>()

        for (index, element) in rawList.enumerated() {
            guard let entry = element as? [String: Any] else {
                issues.append(.entryNotAnObject(index: index))
                continue
            }
            guard let id = (entry["id"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines), !id.isEmpty else {
                issues.append(.missingID(index: index))
                continue
            }
            guard !seenIDs.contains(id) else {
                issues.append(.duplicateID(id))
                continue
            }
            seenIDs.insert(id)
            profiles.append(AppearanceProfile(
                id: id,
                displayName: (entry["displayName"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? id,
                spriteSet: (entry["spriteSet"] as? String).flatMap { $0.isEmpty ? nil : $0 },
                spriteSetsByPhase: (entry["spriteSetsByPhase"] as? [String: Any])
                    .map { $0.compactMapValues { $0 as? String }.filter { !$0.value.isEmpty } },
                dialogueCategories: (entry["dialogueCategories"] as? [Any])?.compactMap { $0 as? String },
                disabledDialogueCategories: (entry["disabledDialogueCategories"] as? [Any])?.compactMap { $0 as? String } ?? [],
                special: (entry["special"] as? NSNumber)?.boolValue ?? false,
                transitionAnimation: (entry["transitionAnimation"] as? String).flatMap { $0.isEmpty ? nil : $0 }))
        }

        // default が無ければ補う（解決ロジックの最後の受け皿）
        if !seenIDs.contains(AppearanceProfile.ID.default) {
            profiles.insert(.fallbackDefault, at: 0)
        }

        return AppearanceProfileLoadResult(schemaVersion: schemaVersion, profiles: profiles, issues: issues)
    }

    public static func load(url: URL) throws -> AppearanceProfileLoadResult {
        try load(data: Data(contentsOf: url))
    }
}
