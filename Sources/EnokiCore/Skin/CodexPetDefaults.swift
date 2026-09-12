import Foundation
import CoreGraphics

/// スプライトシートのグリッド定義
public struct SpriteGrid: Equatable {
    public var columns: Int
    public var rows: Int
    public var cellWidth: Int
    public var cellHeight: Int

    public init(columns: Int, rows: Int, cellWidth: Int, cellHeight: Int) {
        self.columns = columns
        self.rows = rows
        self.cellWidth = cellWidth
        self.cellHeight = cellHeight
    }

    /// row / column から左上原点のピクセル矩形を作る
    public func rect(row: Int, column: Int) -> CGRect {
        CGRect(x: CGFloat(column * cellWidth),
               y: CGFloat(row * cellHeight),
               width: CGFloat(cellWidth),
               height: CGFloat(cellHeight))
    }
}

/// 行 1 つぶんの既定アニメーション定義
public struct CodexRowSpec: Equatable {
    public let name: String
    public let row: Int
    /// 使用するコマの列番号
    public let frames: [Int]
    /// 各コマの表示時間（ミリ秒）
    public let durationsMS: [Int]
    public let loop: Bool

    public init(name: String, row: Int, frames: [Int], durationsMS: [Int], loop: Bool) {
        self.name = name
        self.row = row
        self.frames = frames
        self.durationsMS = durationsMS
        self.loop = loop
    }

    public var frameCount: Int { frames.count }
    public var totalDurationMS: Int { durationsMS.reduce(0, +) }
}

/// Codex Pet 形式（8列×9行 / 192×208px）の既定値。
public enum CodexPetDefaults {

    public static let grid = SpriteGrid(columns: 8, rows: 9, cellWidth: 192, cellHeight: 208)

    public static let pixelScale: CGFloat = 1

    /// Codex 固定の 9 行
    public static let rowSpecs: [CodexRowSpec] = [
        CodexRowSpec(name: "idle", row: 0, frames: Array(0..<6),
                     durationsMS: [280, 110, 110, 140, 140, 320], loop: true),
        CodexRowSpec(name: "running-right", row: 1, frames: Array(0..<8),
                     durationsMS: [120, 120, 120, 120, 120, 120, 120, 220], loop: true),
        CodexRowSpec(name: "running-left", row: 2, frames: Array(0..<8),
                     durationsMS: [120, 120, 120, 120, 120, 120, 120, 220], loop: true),
        CodexRowSpec(name: "waving", row: 3, frames: Array(0..<4),
                     durationsMS: [140, 140, 140, 280], loop: false),
        CodexRowSpec(name: "jumping", row: 4, frames: Array(0..<5),
                     durationsMS: [140, 140, 140, 140, 280], loop: false),
        CodexRowSpec(name: "failed", row: 5, frames: Array(0..<8),
                     durationsMS: [140, 140, 140, 140, 140, 140, 140, 240], loop: false),
        // waiting は sleep の intro として使うので loop しない
        CodexRowSpec(name: "waiting", row: 6, frames: Array(0..<6),
                     durationsMS: [150, 150, 150, 150, 150, 260], loop: false),
        CodexRowSpec(name: "running", row: 7, frames: Array(0..<6),
                     durationsMS: [120, 120, 120, 120, 120, 220], loop: true),
        CodexRowSpec(name: "review", row: 8, frames: Array(0..<6),
                     durationsMS: [150, 150, 150, 150, 150, 280], loop: true),
        // 追加: waiting 行の末尾 2 コマ（sleep_01 / sleep_02）を寝息としてループ
        CodexRowSpec(name: "sleep", row: 6, frames: [4, 5],
                     durationsMS: [1400, 1400], loop: true),
    ]

    public static let specsByName: [String: CodexRowSpec] = {
        var map: [String: CodexRowSpec] = [:]
        for spec in rowSpecs { map[spec.name] = spec }
        return map
    }()

    /// 既定の状態マッピング
    public static let stateMapping = StateMapping(
        idle: ["idle", "idle", "idle", "review", "running"],
        idleSwitchInterval: 30...180,
        sleepIntro: "waiting",
        sleepLoop: "sleep",
        drag: "running-right",
        reaction: ["waving", "jumping"]
    )

    /// 名前から既定のコマ数を引く（`frames` 省略時に使う）
    public static func defaultFrames(for name: String) -> [Int]? { specsByName[name]?.frames }
    /// 名前から既定の durations(ms) を引く
    public static func defaultDurationsMS(for name: String) -> [Int]? { specsByName[name]?.durationsMS }
    public static func defaultLoop(for name: String) -> Bool? { specsByName[name]?.loop }
}
