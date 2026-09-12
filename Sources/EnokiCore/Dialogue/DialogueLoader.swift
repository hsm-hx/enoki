import Foundation

/// 台詞 JSON の読み込みで起きた「その会話だけ捨てた」理由
public enum DialogueLoadIssue: Error, Equatable, LocalizedError {
    case notAnObject                      // ルートが辞書でない
    case entryNotAnObject(index: Int)
    case missingID(index: Int)
    case duplicateID(String)
    case unknownCategory(id: String, raw: String)
    case unknownSpeaker(id: String, raw: String)
    case emptyText(id: String)
    case emptyLines(id: String)

    public var errorDescription: String? {
        switch self {
        case .notAnObject:
            return "台詞ファイルのルートがオブジェクトではありません。"
        case .entryNotAnObject(let index):
            return "dialogues[\(index)] がオブジェクトではありません。"
        case .missingID(let index):
            return "dialogues[\(index)] に id がありません。"
        case .duplicateID(let id):
            return "id が重複しています: \(id)"
        case .unknownCategory(let id, let raw):
            return "未知のカテゴリです（\(id)): \(raw)"
        case .unknownSpeaker(let id, let raw):
            return "未知の話し手です（\(id)): \(raw)"
        case .emptyText(let id):
            return "空の台詞があります: \(id)"
        case .emptyLines(let id):
            return "発言が 1 つもありません: \(id)"
        }
    }
}

/// 読み込み結果。壊れた会話は `issues` に理由が入り、`set` からは取り除かれる。
public struct DialogueLoadResult: Equatable {
    public let set: DialogueSet
    public let issues: [DialogueLoadIssue]

    public init(set: DialogueSet, issues: [DialogueLoadIssue]) {
        self.set = set
        self.issues = issues
    }
}

/// `dialogue.json` のローダ。
/// 未知のキーは無視し、「lines が空 / speaker 不明 / category 不明 / id 重複」は
/// **その会話だけ捨てて** 残りを返す（ファイル全体は失敗させない）。
public enum DialogueLoader {

    public static let fileName = "dialogue.json"

    public static func load(data: Data) throws -> DialogueLoadResult {
        let json = try JSONSerialization.jsonObject(with: data, options: [])
        guard let root = json as? [String: Any] else {
            throw DialogueLoadIssue.notAnObject
        }
        let schemaVersion = (root["schema_version"] as? NSNumber)?.intValue ?? 1
        let rawList = root["dialogues"] as? [Any] ?? []

        var conversations: [Conversation] = []
        var issues: [DialogueLoadIssue] = []
        var seenIDs = Set<String>()

        for (index, element) in rawList.enumerated() {
            guard let entry = element as? [String: Any] else {
                issues.append(.entryNotAnObject(index: index))
                continue
            }
            guard let id = (entry["id"] as? String), !id.isEmpty else {
                issues.append(.missingID(index: index))
                continue
            }
            guard !seenIDs.contains(id) else {
                issues.append(.duplicateID(id))
                continue
            }
            guard let categoryRaw = entry["category"] as? String,
                  let category = DialogueCategory(rawValue: categoryRaw) else {
                issues.append(.unknownCategory(id: id, raw: (entry["category"] as? String) ?? "(なし)"))
                continue
            }
            let cooldown = (entry["cooldown"] as? NSNumber)?.doubleValue ?? Conversation.defaultCooldown
            // profiles: 見た目プロファイル専用の台詞（省略 = 全プロファイル共通）
            let profiles = (entry["profiles"] as? [Any])
                .map { $0.compactMap { $0 as? String } }
                .flatMap { $0.isEmpty ? nil : $0 }

            let rawLines = entry["lines"] as? [Any] ?? []
            var lines: [DialogueLine] = []
            var lineFailed = false
            for rawLine in rawLines {
                guard let lineDict = rawLine as? [String: Any] else {
                    issues.append(.emptyText(id: id))
                    lineFailed = true
                    break
                }
                guard let speakerRaw = lineDict["speaker"] as? String,
                      let speaker = Speaker(rawValue: speakerRaw) else {
                    issues.append(.unknownSpeaker(id: id, raw: (lineDict["speaker"] as? String) ?? "(なし)"))
                    lineFailed = true
                    break
                }
                guard let text = lineDict["text"] as? String, !text.trimmed.isEmpty else {
                    issues.append(.emptyText(id: id))
                    lineFailed = true
                    break
                }
                let reaction = (lineDict["reaction"] as? String).flatMap { $0.isEmpty ? nil : $0 }
                lines.append(DialogueLine(speaker: speaker, text: text, reaction: reaction))
            }
            if lineFailed { continue }
            guard !lines.isEmpty else {
                issues.append(.emptyLines(id: id))
                continue
            }

            seenIDs.insert(id)
            conversations.append(Conversation(id: id, category: category, cooldown: cooldown,
                                              lines: lines, profiles: profiles))
        }

        return DialogueLoadResult(set: DialogueSet(schemaVersion: schemaVersion, conversations: conversations),
                                  issues: issues)
    }

    public static func load(url: URL) throws -> DialogueLoadResult {
        try load(data: Data(contentsOf: url))
    }
}

private extension String {
    var trimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }
}
