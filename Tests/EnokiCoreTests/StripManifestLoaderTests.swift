import XCTest
@testable import EnokiCore

final class StripManifestLoaderTests: XCTestCase {

    private var directory: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        directory = try makeTemporaryDirectory()
    }

    override func tearDownWithError() throws {
        if let directory { try? FileManager.default.removeItem(at: directory) }
        try super.tearDownWithError()
    }

    /// 横 4 コマ（1 コマ 16×18px）のストリップを書き出す
    private func writeStrip(named name: String, frames: Int) throws {
        try TestSheetFactory.writePNG(to: directory.appendingPathComponent(name),
                                      columns: frames, rows: 1, cellWidth: 16, cellHeight: 18,
                                      filled: (0..<frames).map { (0, $0) })
    }

    private func writeManifest(_ json: [String: Any]) throws {
        try JSONSerialization.data(withJSONObject: json).write(to: directory.appendingPathComponent("manifest.json"))
    }

    func testHorizontalStripWithFPS() throws {
        try writeStrip(named: "idle_1.png", frames: 4)
        try writeManifest([
            "displayName": "ストリップ",
            "animations": [
                "idle_1": ["file": "idle_1.png", "frameCount": 4,
                           "frameWidth": 16, "frameHeight": 18, "fps": 6, "loop": true],
            ],
        ])

        let skin = try StripManifestLoader.load(directory: directory)
        XCTAssertEqual(skin.displayName, "ストリップ")

        let idle = try XCTUnwrap(skin.animation(named: "idle_1"))
        XCTAssertEqual(idle.frames.count, 4)
        XCTAssertEqual(idle.frames[0], CGRect(x: 0, y: 0, width: 16, height: 18))
        XCTAssertEqual(idle.frames[3], CGRect(x: 48, y: 0, width: 16, height: 18))
        for duration in idle.durations {
            XCTAssertEqual(duration, 1.0 / 6.0, accuracy: 0.0001, "fps 6 → 約 166.7ms")
        }
        XCTAssertTrue(idle.loop)

        // states 省略 → idle* から推定、sleep / drag が無ければ idle にフォールバック
        XCTAssertEqual(skin.mapping.idle, ["idle_1"])
        XCTAssertEqual(skin.mapping.sleepLoop, "idle_1")
        XCTAssertEqual(skin.mapping.drag, "idle_1")
        XCTAssertEqual(skin.mapping.reaction, ["idle_1"])
        XCTAssertNil(skin.mapping.sleepIntro)
    }

    func testInferredStatesUseSleepAndDragAndReaction() throws {
        for name in ["idle_1.png", "idle_2.png", "sleep.png", "drag.png", "reaction_wave.png"] {
            try writeStrip(named: name, frames: 2)
        }
        try writeManifest([
            "animations": [
                "idle_1": ["file": "idle_1.png", "frameCount": 2, "frameWidth": 16, "frameHeight": 18, "fps": 4],
                "idle_2": ["file": "idle_2.png", "frameCount": 2, "frameWidth": 16, "frameHeight": 18, "fps": 4],
                "sleep": ["file": "sleep.png", "frameCount": 2, "frameWidth": 16, "frameHeight": 18,
                          "durations": [1400, 1400], "loop": true],
                "drag": ["file": "drag.png", "frameCount": 2, "frameWidth": 16, "frameHeight": 18, "fps": 8],
                "reaction_wave": ["file": "reaction_wave.png", "frameCount": 2, "frameWidth": 16,
                                  "frameHeight": 18, "fps": 8, "loop": false],
            ],
        ])

        let skin = try StripManifestLoader.load(directory: directory)
        XCTAssertEqual(skin.mapping.idle, ["idle_1", "idle_2"])
        XCTAssertEqual(skin.mapping.sleepLoop, "sleep")
        XCTAssertEqual(skin.mapping.drag, "drag")
        XCTAssertEqual(skin.mapping.reaction, ["reaction_wave"])

        let sleep = try XCTUnwrap(skin.animation(named: "sleep"))
        XCTAssertEqual(sleep.durations, [1.4, 1.4])
    }

    func testFrameCountDefaultsToAllCellsAndFrameSizeIsInferred() throws {
        try writeStrip(named: "idle.png", frames: 5)
        try writeManifest([
            "animations": ["idle": ["file": "idle.png", "frameCount": 5]],
        ])
        let skin = try StripManifestLoader.load(directory: directory)
        let idle = try XCTUnwrap(skin.animation(named: "idle"))
        XCTAssertEqual(idle.frames.count, 5)
        XCTAssertEqual(idle.frameSize, CGSize(width: 16, height: 18), "frameCount から幅を推定")
        XCTAssertEqual(idle.durations, [TimeInterval](repeating: 0.15, count: 5), "既定 150ms")
    }

    func testMissingFileThrows() throws {
        try writeManifest(["animations": ["idle": ["file": "nope.png"]]])
        XCTAssertThrowsError(try StripManifestLoader.load(directory: directory)) { error in
            XCTAssertEqual(error as? SkinError, .spritesheetNotFound("nope.png"))
        }
    }
}
