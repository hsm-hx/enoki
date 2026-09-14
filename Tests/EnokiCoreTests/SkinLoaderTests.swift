import XCTest
@testable import EnokiCore

/// スキンの解決順（§6.1）。ファイルには触らず、候補の並びだけを検証する。
final class SkinLoaderTests: XCTestCase {

    private func candidates(userSelected: String? = nil,
                            bundled: URL? = URL(fileURLWithPath: "/App/Resources/DefaultSkin", isDirectory: true),
                            environment: [String: String] = [:]) -> [(SkinSource, URL)] {
        SkinLoader.candidates(userSelected: userSelected, bundled: bundled, environment: environment)
    }

    func testOrderIsEnvironmentThenUserSelectedThenCodexPetsThenBundled() {
        let result = candidates(userSelected: "/private/tmp/user-selected-skin",
                                environment: [SkinLoader.environmentKey: "/tmp/dev-skin"])
        XCTAssertEqual(result.map(\.0), [.environment, .userSelected, .codexPets, .bundled])
        XCTAssertEqual(result[0].1.path, "/tmp/dev-skin")
        XCTAssertEqual(result[1].1.path, "/private/tmp/user-selected-skin")
        XCTAssertEqual(result[2].1, SkinLoader.defaultCodexPetURL)
        XCTAssertEqual(result[3].1.path, "/App/Resources/DefaultSkin")
    }

    func testFreshInstallFallsBackToBundledSkin() {
        // 何も設定していない人（環境変数なし・スキン未選択）でも、最後に内蔵スキンへ落ちる
        let result = candidates()
        XCTAssertEqual(result.map(\.0), [.codexPets, .bundled])
        XCTAssertEqual(result.last?.1.path, "/App/Resources/DefaultSkin")
    }

    func testEmptyValuesAreSkipped() {
        let result = candidates(userSelected: "", environment: [SkinLoader.environmentKey: ""])
        XCTAssertEqual(result.map(\.0), [.codexPets, .bundled])
    }

    func testTildeIsExpanded() {
        let result = candidates(userSelected: "~/skins/mine",
                                environment: [SkinLoader.environmentKey: "~/dev-skin"])
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        XCTAssertEqual(result[0].1.path, home + "/dev-skin")
        XCTAssertEqual(result[1].1.path, home + "/skins/mine")
    }

    func testBundledIsOmittedWhenMissing() {
        let result = candidates(bundled: nil)
        XCTAssertEqual(result.map(\.0), [.codexPets])
    }

    func testDefaultCodexPetURLIsUnderCodexPetsRoot() {
        XCTAssertEqual(SkinLoader.defaultCodexPetURL.deletingLastPathComponent().path,
                       SkinLoader.codexPetsRoot.path)
    }
}
