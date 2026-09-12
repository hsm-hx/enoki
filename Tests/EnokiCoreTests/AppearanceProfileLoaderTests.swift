import XCTest
@testable import EnokiCore

final class AppearanceProfileLoaderTests: XCTestCase {

    /// 同梱の Sources/Enoki/Resources/Profiles/profiles.json
    private var bundledProfilesURL: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()          // Tests/EnokiCoreTests
            .deletingLastPathComponent()          // Tests
            .deletingLastPathComponent()          // リポジトリのルート
            .appendingPathComponent("Sources/Enoki/Resources/Profiles/profiles.json")
    }

    // MARK: - 同梱ファイル

    func testBundledProfilesLoad() throws {
        let result = try AppearanceProfileLoader.load(url: bundledProfilesURL)
        XCTAssertEqual(result.issues, [], "同梱の profiles.json に壊れた項目があります")
        XCTAssertEqual(result.schemaVersion, 1)
        XCTAssertEqual(result.profiles.map(\.id), ["default", "work", "casual", "renofa"])

        let ids = result.profiles.map(\.id)
        XCTAssertEqual(Set(ids).count, ids.count, "id が重複しています")
        XCTAssertNotNil(result.profile(id: AppearanceProfile.ID.default))
        XCTAssertNotNil(result.profile(id: AppearanceProfile.ID.work))
        XCTAssertNotNil(result.profile(id: AppearanceProfile.ID.casual))
    }

    func testBundledProfileContents() throws {
        let result = try AppearanceProfileLoader.load(url: bundledProfilesURL)

        let standard = try XCTUnwrap(result.profile(id: "default"))
        XCTAssertNil(standard.spriteSet, "default はベーススキンを使う")
        XCTAssertNil(standard.dialogueCategories)
        XCTAssertFalse(standard.special)

        let work = try XCTUnwrap(result.profile(id: "work"))
        XCTAssertEqual(work.spriteSet, "saku_shiori_work")
        XCTAssertFalse(work.special)

        let casual = try XCTUnwrap(result.profile(id: "casual"))
        XCTAssertEqual(casual.spriteSet, "saku_shiori_casual")
        XCTAssertEqual(casual.allowedCategories(base: Set(DialogueCategory.allCases)),
                       [.ambient, .pair, .encouragement])

        let renofa = try XCTUnwrap(result.profile(id: "renofa"))
        XCTAssertEqual(renofa.spriteSet, "saku_shiori_renofa")
        XCTAssertTrue(renofa.special, "renofa は仕事中モードの切り替えで消えない")
        XCTAssertEqual(renofa.allowedCategories(base: Set(DialogueCategory.allCases)),
                       [.renofa, .ambient, .pair, .encouragement])
    }

    // MARK: - allowedCategories

    func testAllowedCategoriesIntersectsBaseAndIgnoresUnknownNames() {
        let profile = AppearanceProfile(id: "x", displayName: "X",
                                        dialogueCategories: ["ambient", "pair", "encouragement", "nap"],
                                        disabledDialogueCategories: ["pair", "sabbatical"])
        // base に無いものは増えない、未知の名前（nap / sabbatical）は無視、disabled が最後に効く
        XCTAssertEqual(profile.allowedCategories(base: [.ambient, .pair, .work]), [.ambient])
        // dialogueCategories が nil なら base − disabled
        let open = AppearanceProfile(id: "y", displayName: "Y", disabledDialogueCategories: ["work"])
        XCTAssertEqual(open.allowedCategories(base: [.ambient, .work]), [.ambient])
    }

    // MARK: - 壊れた入力

    private func load(_ json: String) throws -> AppearanceProfileLoadResult {
        try AppearanceProfileLoader.load(data: Data(json.utf8))
    }

    func testDropsBrokenEntriesOnly() throws {
        let result = try load("""
        {
          "schema_version": 2,
          "profiles": [
            {"id": "default", "displayName": "Default"},
            {"id": "", "displayName": "空 id"},
            {"displayName": "id なし"},
            {"id": "default", "displayName": "重複"},
            42,
            {"id": "winter", "displayName": "Winter", "spriteSet": "saku_shiori_winter", "unknownKey": true}
          ]
        }
        """)
        XCTAssertEqual(result.profiles.map(\.id), ["default", "winter"])
        XCTAssertEqual(result.issues, [.missingID(index: 1),
                                       .missingID(index: 2),
                                       .duplicateID("default"),
                                       .entryNotAnObject(index: 4)])
        XCTAssertEqual(result.schemaVersion, 2)
        XCTAssertEqual(result.profile(id: "winter")?.spriteSet, "saku_shiori_winter")
    }

    func testDefaultIsAddedWhenMissing() throws {
        let result = try load("""
        {"profiles": [{"id": "work", "displayName": "Work", "spriteSet": "w"}]}
        """)
        XCTAssertEqual(result.profiles.map(\.id), ["default", "work"])
        XCTAssertEqual(result.profile(id: "default"), .fallbackDefault)

        // profiles が空でも default だけは返る
        let empty = try load("{}")
        XCTAssertEqual(empty.profiles, [.fallbackDefault])
    }

    func testInvalidRootThrows() {
        XCTAssertThrowsError(try load("[1, 2, 3]"))
        XCTAssertThrowsError(try AppearanceProfileLoader.load(data: Data("こわれている".utf8)))
    }
}
