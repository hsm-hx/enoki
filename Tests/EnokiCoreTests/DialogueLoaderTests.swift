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
        // デモ用の 1 人ぶん: 6 カテゴリ × 5 件
        XCTAssertEqual(result.set.conversations.count, 30)
    }

    func testBundledDialogueHasFiveConversationsPerCategory() throws {
        let result = try DialogueLoader.load(url: bundledDialogueURL)
        XCTAssertEqual(DialogueCategory.allCases.count, 11)

        for category in [DialogueCategory.work, .water, .break, .lunch, .encouragement, .ambient] {
            XCTAssertEqual(result.set.conversations.filter { $0.category == category }.count, 5,
                           "\(category.rawValue) の件数")
        }
        // 同梱デモは 1 人用なので、2 人の会話（pair）とプロファイル専用の台詞は入れていない
        XCTAssertTrue(result.set.conversations.allSatisfy { $0.category != .pair })
        XCTAssertTrue(result.set.conversations.allSatisfy { $0.profiles == nil })
        XCTAssertTrue(result.set.conversations.allSatisfy { $0.matches(profileID: "any_profile") })
    }

    func testBundledDialogueIsSoloAndCentersTheBubble() throws {
        let result = try DialogueLoader.load(url: bundledDialogueURL)

        XCTAssertEqual(result.set.declaredSpeakers.map(\.id), ["shiori"])
        XCTAssertEqual(result.set.speakers, [.shiori])
        XCTAssertTrue(result.set.isSolo, "同梱デモは 1 人用")

        let style = result.set.speakerStyles.style(for: .shiori)
        XCTAssertEqual(style.displayName, "栞")
        XCTAssertEqual(style.anchor, 0.5, "1 人用の吹き出しは中央に出す")
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
                XCTAssertEqual(line.speaker, .shiori)
                XCTAssertFalse(line.text.isEmpty)
                XCTAssertNil(line.reaction)   // 現状の素材には reaction は入っていない
            }
        }
    }

    // MARK: - 壊れた入力

    private func load(_ json: String) throws -> DialogueLoadResult {
        try DialogueLoader.load(data: Data(json.utf8))
    }

    func testSpeakerIDIsFreeFormWhenSpeakersAreNotDeclared() throws {
        // speakers を書いていないファイルでは、どんな id でも話者として扱う（自分のキャラクター名で書ける）
        let result = try load("""
        {
          "schema_version": 1,
          "dialogues": [
            {"id": "a", "category": "water", "cooldown": 60, "lines": [{"speaker": "mike", "text": "水"}]},
            {"id": "b", "category": "ambient", "lines": [{"speaker": "mike", "text": "……"}]}
          ]
        }
        """)
        XCTAssertEqual(result.issues, [])
        XCTAssertEqual(result.set.speakers, [Speaker("mike")])
        XCTAssertTrue(result.set.isSolo)
        let style = result.set.speakerStyles.style(for: Speaker("mike"))
        XCTAssertEqual(style.displayName, "mike", "宣言が無ければ id をそのまま名前にする")
        XCTAssertEqual(style.anchor, 0.5, "1 人だけなら中央")
    }

    func testUndeclaredSpeakerDropsOnlyThatConversationWhenSpeakersAreDeclared() throws {
        // speakers を書いたファイルでは、宣言していない id（打ち間違いなど）はその会話だけ捨てる
        let result = try load("""
        {
          "schema_version": 1,
          "speakers": [{"id": "saku", "displayName": "朔"}, {"id": "shiori", "displayName": "栞"}],
          "dialogues": [
            {"id": "a", "category": "water", "cooldown": 60, "lines": [{"speaker": "saku", "text": "水"}]},
            {"id": "b", "category": "water", "lines": [{"speaker": "hiiragi", "text": "？"}]},
            {"id": "c", "category": "pair", "lines": [{"speaker": "shiori", "text": "はい"}]}
          ]
        }
        """)
        XCTAssertEqual(result.set.conversations.map(\.id), ["a", "c"])
        XCTAssertEqual(result.issues, [.unknownSpeaker(id: "b", raw: "hiiragi")])
        XCTAssertFalse(result.set.isSolo)
    }

    func testMissingSpeakerIsAlwaysDropped() throws {
        let result = try load("""
        {
          "dialogues": [
            {"id": "a", "category": "ambient", "lines": [{"speaker": "  ", "text": "空"}]},
            {"id": "b", "category": "ambient", "lines": [{"text": "speaker なし"}]},
            {"id": "c", "category": "ambient", "lines": [{"speaker": "me", "text": "ここにいます"}]}
          ]
        }
        """)
        XCTAssertEqual(result.set.conversations.map(\.id), ["c"])
        XCTAssertEqual(result.issues, [.unknownSpeaker(id: "a", raw: "(なし)"),
                                       .unknownSpeaker(id: "b", raw: "(なし)")])
    }

    // MARK: - 話者の宣言（speakers）

    func testDeclaredSpeakersDecideNameAndAnchor() throws {
        let result = try load("""
        {
          "speakers": [
            {"id": "mike", "displayName": "ミケ", "anchor": 0.35},
            {"id": "kuro", "displayName": "クロ"}
          ],
          "dialogues": [
            {"id": "a", "category": "pair", "lines": [
              {"speaker": "kuro", "text": "……"},
              {"speaker": "mike", "text": "にゃあ"}
            ]}
          ]
        }
        """)
        XCTAssertEqual(result.issues, [])
        // 宣言の順が立ち位置と色の順になる（台詞の登場順ではない）
        XCTAssertEqual(result.set.speakerStyles.order, ["mike", "kuro"])
        let mike = result.set.speakerStyles.style(for: Speaker("mike"))
        XCTAssertEqual(mike.displayName, "ミケ")
        XCTAssertEqual(mike.anchor, 0.35, "宣言した anchor が優先される")
        XCTAssertEqual(mike.colorIndex, 0)
        let kuro = result.set.speakerStyles.style(for: Speaker("kuro"))
        XCTAssertEqual(kuro.displayName, "クロ")
        XCTAssertEqual(kuro.anchor, 0.75, "anchor 省略時は 2 人用の既定（右 3/4）")
        XCTAssertEqual(kuro.colorIndex, 1)
    }

    func testTwoSpeakersWithoutDeclarationKeepLeftAndRight() throws {
        let result = try load("""
        {
          "dialogues": [
            {"id": "a", "category": "pair", "lines": [
              {"speaker": "saku", "text": "ひいらぎ"},
              {"speaker": "shiori", "text": "はい"}
            ]}
          ]
        }
        """)
        XCTAssertEqual(result.set.speakerStyles.style(for: .saku).anchor, 0.25)
        XCTAssertEqual(result.set.speakerStyles.style(for: .shiori).anchor, 0.75)
        // 同梱してきた id は宣言が無くても日本語名を既定にする（互換）
        XCTAssertEqual(result.set.speakerStyles.style(for: .saku).displayName, "朔")
        XCTAssertEqual(result.set.speakerStyles.style(for: .shiori).displayName, "栞")
    }

    func testThreeSpeakersAreSpreadEvenly() throws {
        let result = try load("""
        {
          "speakers": [{"id": "a"}, {"id": "b"}, {"id": "c"}],
          "dialogues": [
            {"id": "x", "category": "pair", "lines": [
              {"speaker": "a", "text": "1"}, {"speaker": "b", "text": "2"}, {"speaker": "c", "text": "3"}
            ]}
          ]
        }
        """)
        XCTAssertEqual(result.set.speakerStyles.style(for: Speaker("a")).anchor, 0.25)
        XCTAssertEqual(result.set.speakerStyles.style(for: Speaker("b")).anchor, 0.5)
        XCTAssertEqual(result.set.speakerStyles.style(for: Speaker("c")).anchor, 0.75)
    }

    func testBrokenSpeakerDeclarationIsSkipped() throws {
        let result = try load("""
        {
          "speakers": [{"displayName": "id なし"}, {"id": "mike"}, {"id": "mike"}],
          "dialogues": [
            {"id": "a", "category": "ambient", "lines": [{"speaker": "mike", "text": "にゃあ"}]}
          ]
        }
        """)
        XCTAssertEqual(result.issues, [.invalidSpeakerDeclaration(index: 0),
                                       .invalidSpeakerDeclaration(index: 2)])
        XCTAssertEqual(result.set.declaredSpeakers.map(\.id), ["mike"])
        XCTAssertEqual(result.set.conversations.map(\.id), ["a"])
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
