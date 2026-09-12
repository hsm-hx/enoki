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
        XCTAssertEqual(result.set.conversations.count, 42)
    }

    func testBundledDialogueHasSixConversationsPerCategory() throws {
        let result = try DialogueLoader.load(url: bundledDialogueURL)
        XCTAssertEqual(DialogueCategory.allCases.count, 7)
        for category in DialogueCategory.allCases {
            XCTAssertEqual(result.set.conversations(in: category).count, 6, "\(category.rawValue) の件数")
        }
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
