import XCTest
@testable import EnokiCore

final class CodexPetDefaultsTests: XCTestCase {

    /// 仕様表の 9 行（名前 / コマ数 / durations 合計）
    private let expected: [(name: String, row: Int, frameCount: Int, totalMS: Int, loop: Bool)] = [
        ("idle", 0, 6, 1100, true),
        ("running-right", 1, 8, 1060, true),
        ("running-left", 2, 8, 1060, true),
        ("waving", 3, 4, 700, false),
        ("jumping", 4, 5, 840, false),
        ("failed", 5, 8, 1220, false),
        ("waiting", 6, 6, 1010, false),
        ("running", 7, 6, 820, true),
        ("review", 8, 6, 1030, true),
    ]

    func testRowSpecsMatchSpecification() {
        for entry in expected {
            guard let spec = CodexPetDefaults.specsByName[entry.name] else {
                return XCTFail("行定義 \(entry.name) がありません")
            }
            XCTAssertEqual(spec.row, entry.row, "\(entry.name) の row")
            XCTAssertEqual(spec.frameCount, entry.frameCount, "\(entry.name) のコマ数")
            XCTAssertEqual(spec.durationsMS.count, entry.frameCount, "\(entry.name) の durations 個数")
            XCTAssertEqual(spec.totalDurationMS, entry.totalMS, "\(entry.name) の合計時間")
            XCTAssertEqual(spec.loop, entry.loop, "\(entry.name) の loop")
        }
    }

    func testSleepAnimationIsAddedOnTopOfTheNineRows() {
        // 9 行 + sleep
        XCTAssertEqual(CodexPetDefaults.rowSpecs.count, 10)
        guard let sleep = CodexPetDefaults.specsByName["sleep"] else {
            return XCTFail("sleep がありません")
        }
        XCTAssertEqual(sleep.row, 6)
        XCTAssertEqual(sleep.frames, [4, 5])
        XCTAssertEqual(sleep.durationsMS, [1400, 1400])
        XCTAssertTrue(sleep.loop)
    }

    func testGridMatchesCodexSpecification() {
        XCTAssertEqual(CodexPetDefaults.grid.columns, 8)
        XCTAssertEqual(CodexPetDefaults.grid.rows, 9)
        XCTAssertEqual(CodexPetDefaults.grid.cellWidth, 192)
        XCTAssertEqual(CodexPetDefaults.grid.cellHeight, 208)
    }

    func testDefaultStateMapping() {
        let mapping = CodexPetDefaults.stateMapping
        XCTAssertEqual(mapping.idle, ["idle", "idle", "idle", "review", "running"])
        XCTAssertEqual(mapping.idleSwitchInterval, 30...180)
        XCTAssertEqual(mapping.sleepIntro, "waiting")
        XCTAssertEqual(mapping.sleepLoop, "sleep")
        XCTAssertEqual(mapping.drag, "running-right")
        XCTAssertEqual(mapping.reaction, ["waving", "jumping"])
    }
}
