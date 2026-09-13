import XCTest
@testable import EnokiCore

final class DialogueLoaderTests: XCTestCase {

    /// 同梱の Sources/Enoki/Resources/DialogueText/dialogue.json
    private var bundledDialogueURL: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()          // Tests/EnokiCoreTests
            .deletingLastPathComponent()          // Tests
            .deletingLastPathComponent()          // リポジトリのルート
            .appendingPathComponent("Sources/Enoki/Resources/DialogueText/dialogue.json")
    }

    func testBundledDialogueLoads() throws {
        let result = try DialogueLoader.load(url: bundledDialogueURL)
        XCTAssertEqual(result.issues, [], "同梱の台詞ファイルに壊れた会話があります")
        XCTAssertEqual(result.set.schemaVersion, 1)
        // 42（共通）+ 4（casual 専用）+ 50（renofa 専用）
        XCTAssertEqual(result.set.conversations.count, 96)
    }

    func testBundledDialogueHasSixCommonConversationsPerCategory() throws {
        let result = try DialogueLoader.load(url: bundledDialogueURL)
        XCTAssertEqual(DialogueCategory.allCases.count, 11)

        // プロファイル共通（profiles 指定なし）の台詞は、元の 7 カテゴリに 6 件ずつ
        let common = result.set.conversations.filter { $0.profiles == nil }
        XCTAssertEqual(common.count, 42)
        for category in [DialogueCategory.work, .water, .break, .lunch, .encouragement, .ambient, .pair] {
            XCTAssertEqual(common.filter { $0.category == category }.count, 6, "\(category.rawValue) の件数")
        }
    }

    func testBundledDialogueHasProfileSpecificConversations() throws {
        let result = try DialogueLoader.load(url: bundledDialogueURL)

        let casual = result.set.conversations.filter { $0.profiles == ["casual"] }
        XCTAssertEqual(casual.count, 4)
        XCTAssertTrue(casual.allSatisfy { [.ambient, .pair].contains($0.category) })
        XCTAssertTrue(casual.allSatisfy { $0.matches(profileID: "casual") })
        XCTAssertFalse(casual.contains { $0.matches(profileID: AppearanceProfile.ID.default) })

        let renofa = result.set.conversations.filter { $0.profiles == ["renofa"] }
        XCTAssertEqual(renofa.count, 50)
        XCTAssertTrue(renofa.allSatisfy { ConversationScheduler.renofaCategories.contains($0.category) })
        XCTAssertTrue(renofa.allSatisfy { $0.matches(profileID: "renofa") })
        XCTAssertFalse(renofa.contains { $0.matches(profileID: AppearanceProfile.ID.default) })

        // 局面ごとの台詞（§11.3）。すべて renofa プロファイル限定。
        for (category, count) in [(DialogueCategory.renofa, 14), (.renofaPreMatch, 12),
                                  (.renofaMatch, 12), (.renofaPostMatch, 12)] {
            XCTAssertEqual(renofa.filter { $0.category == category }.count, count, "\(category.rawValue) の件数")
        }

        // profiles の無い会話はどのプロファイルでも使える
        let common = try XCTUnwrap(result.set.conversation(id: "ambient_001"))
        XCTAssertNil(common.profiles)
        XCTAssertTrue(common.matches(profileID: "renofa"))
    }

    func testBundledDialogueContentIsSane() throws {
        let result = try DialogueLoader.load(url: bundledDialogueURL)
        let ids = result.set.conversations.map(\.id)
        XCTAssertEqual(Set(ids).count, ids.count, "id が重複しています")

        for conversation in result.set.conversations {
            XCTAssertFalse(conversation.lines.isEmpty, "\(conversation.id) の発言が空です")
            XCTAssertLessThanOrEqual(conversation.lines.count, 4, "\(conversation.id) の発言が多すぎます")
            XCTAssertGreaterThan(conversation.cooldown, 0)
            for line in conversation.lines {
                XCTAssertTrue(Speaker.allCases.contains(line.speaker))
                XCTAssertFalse(line.text.isEmpty)
                XCTAssertNil(line.reaction)   // 現状の素材には reaction は入っていない
            }
        }
    }

    // MARK: - 壊れた入力

    private func load(_ json: String) throws -> DialogueLoadResult {
        try DialogueLoader.load(data: Data(json.utf8))
    }

    func testUnknownSpeakerDropsOnlyThatConversation() throws {
        let result = try load("""
        {
          "schema_version": 1,
          "dialogues": [
            {"id": "a", "category": "water", "cooldown": 60, "lines": [{"speaker": "saku", "text": "水"}]},
            {"id": "b", "category": "water", "lines": [{"speaker": "hiiragi", "text": "？"}]},
            {"id": "c", "category": "pair", "lines": [{"speaker": "shiori", "text": "はい"}]}
          ]
        }
        """)
        XCTAssertEqual(result.set.conversations.map(\.id), ["a", "c"])
        XCTAssertEqual(result.issues, [.unknownSpeaker(id: "b", raw: "hiiragi")])
    }

    func testEmptyLinesAndUnknownCategoryAndDuplicateID() throws {
        let result = try load("""
        {
          "dialogues": [
            {"id": "a", "category": "ambient", "lines": [{"speaker": "saku", "text": "……"}], "unknownKey": 1},
            {"id": "a", "category": "ambient", "lines": [{"speaker": "saku", "text": "重複"}]},
            {"id": "b", "category": "ambient", "lines": []},
            {"id": "c", "category": "nap", "lines": [{"speaker": "saku", "text": "？"}]},
            {"category": "ambient", "lines": [{"speaker": "saku", "text": "id なし"}]}
          ]
        }
        """)
        XCTAssertEqual(result.set.conversations.map(\.id), ["a"])
        XCTAssertEqual(result.issues, [.duplicateID("a"),
                                       .emptyLines(id: "b"),
                                       .unknownCategory(id: "c", raw: "nap"),
                                       .missingID(index: 4)])
        // schema_version が無ければ 1、cooldown が無ければ既定値
        XCTAssertEqual(result.set.schemaVersion, 1)
        XCTAssertEqual(result.set.conversations.first?.cooldown, Conversation.defaultCooldown)
    }

    func testInvalidRootThrows() {
        XCTAssertThrowsError(try load("[1, 2, 3]"))
        XCTAssertThrowsError(try DialogueLoader.load(data: Data("こわれている".utf8)))
    }
}
