import XCTest
@testable import EnokiCore

final class CodexPetLoaderTests: XCTestCase {

    private var directory: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        directory = try makeTemporaryDirectory()
        // 8×9 グリッド / 1 セル 16×18px = 128×162px
        try TestSheetFactory.writeFullCodexSheet(to: directory.appendingPathComponent("spritesheet.png"))
    }

    override func tearDownWithError() throws {
        if let directory { try? FileManager.default.removeItem(at: directory) }
        try super.tearDownWithError()
    }

    private func writePetJSON(_ json: [String: Any]) throws {
        var root: [String: Any] = [
            "id": "test",
            "displayName": "テスト",
            "spritesheetPath": "spritesheet.png",
        ]
        for (key, value) in json { root[key] = value }
        let data = try JSONSerialization.data(withJSONObject: root, options: [])
        try data.write(to: directory.appendingPathComponent("pet.json"))
    }

    // MARK: - mascot なし = 既定値

    func testLoadsDefaultsWhenMascotKeyIsAbsent() throws {
        try writePetJSON([:])
        let skin = try CodexPetLoader.load(directory: directory)

        XCTAssertEqual(skin.displayName, "テスト")
        XCTAssertEqual(skin.mapping, CodexPetDefaults.stateMapping)

        // 既定の 9 行 + sleep が揃っている
        for spec in CodexPetDefaults.rowSpecs {
            XCTAssertNotNil(skin.animation(named: spec.name), "\(spec.name) がありません")
        }

        let idle = try XCTUnwrap(skin.animation(named: "idle"))
        XCTAssertEqual(idle.frames.count, 6)
        XCTAssertEqual(idle.loop, true)
        // grid 未指定でも画像サイズからセルサイズを推定する
        XCTAssertEqual(idle.frameSize, CGSize(width: 16, height: 18))
        XCTAssertEqual(idle.frames[0], CGRect(x: 0, y: 0, width: 16, height: 18))
        XCTAssertEqual(idle.frames[1], CGRect(x: 16, y: 0, width: 16, height: 18))
        XCTAssertEqual(idle.durations.map { Int(($0 * 1000).rounded()) }, [280, 110, 110, 140, 140, 320])

        let sleep = try XCTUnwrap(skin.animation(named: "sleep"))
        XCTAssertEqual(sleep.frames.count, 2)
        // row 6, column 4/5
        XCTAssertEqual(sleep.frames[0], CGRect(x: 4 * 16, y: 6 * 18, width: 16, height: 18))
        XCTAssertEqual(sleep.durations, [1.4, 1.4])

        // waiting は intro 用なので loop しない
        let waiting = try XCTUnwrap(skin.animation(named: "waiting"))
        XCTAssertFalse(waiting.loop)
    }

    // MARK: - 一部上書き

    func testMascotAnimationOverrideIsMergedPerName() throws {
        try writePetJSON([
            "mascot": [
                "grid": ["columns": 8, "rows": 9, "cellWidth": 16, "cellHeight": 18],
                "animations": [
                    "sleep": ["row": 6, "frames": [0, 1, 2], "durations": [500], "loop": false],
                ],
            ],
        ])
        let skin = try CodexPetLoader.load(directory: directory)

        let sleep = try XCTUnwrap(skin.animation(named: "sleep"))
        XCTAssertEqual(sleep.frames.count, 3)
        XCTAssertEqual(sleep.durations, [0.5, 0.5, 0.5], "durations が 1 要素なら全コマに適用される")
        XCTAssertFalse(sleep.loop)

        // 他は既定のまま
        let idle = try XCTUnwrap(skin.animation(named: "idle"))
        XCTAssertEqual(idle.durations.map { Int(($0 * 1000).rounded()) }, [280, 110, 110, 140, 140, 320])
        XCTAssertEqual(skin.mapping, CodexPetDefaults.stateMapping)
    }

    func testFpsIsConvertedToDurations() throws {
        try writePetJSON([
            "mascot": [
                "animations": ["idle": ["row": 0, "frames": [0, 1, 2, 3], "fps": 8]],
            ],
        ])
        let skin = try CodexPetLoader.load(directory: directory)
        let idle = try XCTUnwrap(skin.animation(named: "idle"))
        XCTAssertEqual(idle.durations.count, 4)
        for duration in idle.durations {
            XCTAssertEqual(duration, 0.125, accuracy: 0.0001)
        }
    }

    func testStatesAreMergedPerKey() throws {
        try writePetJSON([
            "mascot": [
                "states": [
                    "drag": "jumping",
                    "idleSwitchSeconds": [5, 10],
                ],
            ],
        ])
        let skin = try CodexPetLoader.load(directory: directory)
        XCTAssertEqual(skin.mapping.drag, "jumping")
        XCTAssertEqual(skin.mapping.idleSwitchInterval, 5...10)
        // 指定していないキーは既定のまま
        XCTAssertEqual(skin.mapping.idle, CodexPetDefaults.stateMapping.idle)
        XCTAssertEqual(skin.mapping.sleepIntro, "waiting")
        XCTAssertEqual(skin.mapping.reaction, ["waving", "jumping"])
    }

    // MARK: - エラー

    func testMissingAnimationReferenceThrows() throws {
        try writePetJSON([
            "mascot": ["states": ["drag": "存在しない"]],
        ])
        XCTAssertThrowsError(try CodexPetLoader.load(directory: directory)) { error in
            XCTAssertEqual(error as? SkinError, .missingAnimation("存在しない"))
            XCTAssertNotNil((error as? SkinError)?.errorDescription)
        }
    }

    func testMissingSpritesheetThrows() throws {
        try writePetJSON([:])
        try FileManager.default.removeItem(at: directory.appendingPathComponent("spritesheet.png"))
        XCTAssertThrowsError(try CodexPetLoader.load(directory: directory)) { error in
            guard case .spritesheetNotFound = (error as? SkinError) else {
                return XCTFail("spritesheetNotFound を期待: \(error)")
            }
        }
    }

    func testSpritesheetPathFallsBackToPNG() throws {
        // webp が宣言されているが存在しない → 同名の .png にフォールバック
        try writePetJSON(["spritesheetPath": "spritesheet.webp"])
        let skin = try CodexPetLoader.load(directory: directory)
        XCTAssertNotNil(skin.animation(named: "idle"))
    }

    func testFramesAreInferredFromNonTransparentCells() throws {
        // 行 0 の左 3 セルだけ不透明なシートを作る
        let dir = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        try TestSheetFactory.writePNG(to: dir.appendingPathComponent("spritesheet.png"),
                                      columns: 8, rows: 9, cellWidth: 16, cellHeight: 18,
                                      filled: [(0, 0), (0, 1), (0, 2)])
        let root: [String: Any] = [
            "displayName": "推定テスト",
            "spritesheetPath": "spritesheet.png",
            "mascot": [
                "animations": ["blink": ["row": 0]],
                "states": ["idle": ["blink"], "sleep": ["loop": "blink"], "drag": "blink", "reaction": ["blink"]],
            ],
        ]
        try JSONSerialization.data(withJSONObject: root).write(to: dir.appendingPathComponent("pet.json"))

        let skin = try CodexPetLoader.load(directory: dir)
        let blink = try XCTUnwrap(skin.animation(named: "blink"))
        XCTAssertEqual(blink.frames.count, 3, "非透明セルを左から数える")
        XCTAssertEqual(blink.durations, [0.15, 0.15, 0.15], "既定表に無い名前は 150ms")
        XCTAssertEqual(skin.mapping.sleepLoop, "blink")
        XCTAssertEqual(skin.mapping.sleepIntro, "waiting", "intro を書かなければ既定のまま")
    }

    func testDefaultRowsDropFullyTransparentCells() throws {
        // row 1（running-right）は左 6 セルだけ、row 5（failed）は全セル透明、他は全セル不透明
        let dir = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        var filled: [(row: Int, column: Int)] = []
        for row in 0..<9 where row != 5 {
            for column in 0..<8 where !(row == 1 && column >= 6) { filled.append((row, column)) }
        }
        try TestSheetFactory.writePNG(to: dir.appendingPathComponent("spritesheet.png"),
                                      columns: 8, rows: 9, cellWidth: 16, cellHeight: 18, filled: filled)
        let root: [String: Any] = ["displayName": "欠けテスト", "spritesheetPath": "spritesheet.png"]
        try JSONSerialization.data(withJSONObject: root).write(to: dir.appendingPathComponent("pet.json"))

        let skin = try CodexPetLoader.load(directory: dir)

        let drag = try XCTUnwrap(skin.animation(named: "running-right"))
        XCTAssertEqual(drag.frames.count, 6, "透明な末尾 2 セルは再生しない")
        XCTAssertEqual(drag.frames.last, CGRect(x: 5 * 16, y: 1 * 18, width: 16, height: 18))
        XCTAssertEqual(drag.durations.map { Int(($0 * 1000).rounded()) }, [120, 120, 120, 120, 120, 120],
                       "durations は残したコマぶんだけ")

        // 行ごと空のときは従来どおり既定のコマ数を保つ（参照切れでスキン全体を落とさない）
        let failed = try XCTUnwrap(skin.animation(named: "failed"))
        XCTAssertEqual(failed.frames.count, 8)

        // 全セルある行は影響なし
        XCTAssertEqual(try XCTUnwrap(skin.animation(named: "idle")).frames.count, 6)
        XCTAssertEqual(try XCTUnwrap(skin.animation(named: "running-left")).frames.count, 8)
    }

    func testContentsRectIsNormalizedTopLeft() throws {
        try writePetJSON([:])
        let skin = try CodexPetLoader.load(directory: directory)
        let sleep = try XCTUnwrap(skin.animation(named: "sleep"))
        let rect = sleep.contentsRect(at: 0)
        XCTAssertEqual(rect.origin.x, CGFloat(4 * 16) / 128, accuracy: 0.0001)
        XCTAssertEqual(rect.origin.y, CGFloat(6 * 18) / 162, accuracy: 0.0001)
        XCTAssertEqual(rect.width, 16.0 / 128, accuracy: 0.0001)
        XCTAssertEqual(rect.height, 18.0 / 162, accuracy: 0.0001)
    }
}
