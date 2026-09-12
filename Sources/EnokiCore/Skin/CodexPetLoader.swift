import Foundation
import CoreGraphics
import ImageIO

/// ImageIO で 1 枚目の画像を読み出す共通ヘルパ（PNG / WebP / JPEG など）
enum SpriteImageDecoder {
    static func decode(url: URL) throws -> CGImage {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              CGImageSourceGetCount(source) > 0,
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil)
        else {
            throw SkinError.imageDecodeFailed(url)
        }
        return image
    }
}

/// `states` ブロック（pet.json の `mascot.states` / manifest.json の `states`）の解析。
enum StateMappingParser {
    /// base に JSON の内容をキー単位でマージする
    static func merge(base: StateMapping, json: [String: Any]?) -> StateMapping {
        guard let json else { return base }
        var mapping = base

        if let idle = json["idle"] as? [String], !idle.isEmpty {
            mapping.idle = idle
        } else if let idle = json["idle"] as? String {
            mapping.idle = [idle]
        }

        if let seconds = json["idleSwitchSeconds"] as? [Any], seconds.count == 2 {
            let lo = numeric(seconds[0]) ?? base.idleSwitchInterval.lowerBound
            let hi = numeric(seconds[1]) ?? base.idleSwitchInterval.upperBound
            let lower = max(1, min(lo, hi))
            let upper = max(lower, hi)
            mapping.idleSwitchInterval = lower...upper
        }

        if let sleep = json["sleep"] as? [String: Any] {
            // "intro" は明示的に null を書くと intro 無しになる
            if sleep.keys.contains("intro") {
                mapping.sleepIntro = sleep["intro"] as? String
            }
            if let loop = sleep["loop"] as? String { mapping.sleepLoop = loop }
        } else if let sleep = json["sleep"] as? String {
            mapping.sleepIntro = nil
            mapping.sleepLoop = sleep
        }

        if let drag = json["drag"] as? String { mapping.drag = drag }

        if let reaction = json["reaction"] as? [String], !reaction.isEmpty {
            mapping.reaction = reaction
        } else if let reaction = json["reaction"] as? String {
            mapping.reaction = [reaction]
        }

        return mapping
    }

    static func numeric(_ value: Any?) -> Double? {
        if let d = value as? Double { return d }
        if let i = value as? Int { return Double(i) }
        if let n = value as? NSNumber { return n.doubleValue }
        return nil
    }

    /// `durations`(ms 配列 / 単一値) または `fps` からコマ数ぶんの秒配列を作る。
    /// どちらも無ければ fallback（ms 配列）を、それも無ければ 150ms。
    static func durations(json: [String: Any], frameCount: Int, fallbackMS: [Int]?) -> [TimeInterval] {
        func expand(_ ms: [Double]) -> [TimeInterval] {
            guard !ms.isEmpty else { return [TimeInterval](repeating: 0.15, count: frameCount) }
            if ms.count == 1 { return [TimeInterval](repeating: ms[0] / 1000.0, count: frameCount) }
            var out = ms.map { $0 / 1000.0 }
            if out.count < frameCount {
                out.append(contentsOf: [TimeInterval](repeating: out.last ?? 0.15, count: frameCount - out.count))
            }
            return Array(out.prefix(frameCount))
        }

        if let raw = json["durations"] as? [Any] {
            return expand(raw.compactMap { numeric($0) })
        }
        if let single = numeric(json["durations"]) {
            return expand([single])
        }
        if let fps = numeric(json["fps"]), fps > 0 {
            return [TimeInterval](repeating: 1.0 / fps, count: frameCount)
        }
        if let fallbackMS, !fallbackMS.isEmpty {
            return expand(fallbackMS.map(Double.init))
        }
        return [TimeInterval](repeating: 0.15, count: frameCount)
    }
}

/// Codex Pet 形式（`pet.json` + スプライトシート）のローダ。
public enum CodexPetLoader {

    public static let manifestName = "pet.json"

    /// そのディレクトリがこの形式かどうか
    public static func canLoad(directory: URL) -> Bool {
        FileManager.default.fileExists(atPath: directory.appendingPathComponent(manifestName).path)
    }

    /// pet.json から displayName だけを取り出す（メニューの一覧用。失敗したら nil）
    public static func peekDisplayName(directory: URL) -> String? {
        let url = directory.appendingPathComponent(manifestName)
        guard let data = try? Data(contentsOf: url),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return nil }
        return (json["displayName"] as? String) ?? (json["id"] as? String)
    }

    public static func load(directory: URL) throws -> Skin {
        let manifestURL = directory.appendingPathComponent(manifestName)
        guard FileManager.default.fileExists(atPath: manifestURL.path) else {
            throw SkinError.manifestNotFound(directory)
        }
        let data: Data
        do { data = try Data(contentsOf: manifestURL) }
        catch { throw SkinError.manifestUnreadable(error.localizedDescription) }

        guard let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
            throw SkinError.manifestUnreadable("\(manifestName) が JSON オブジェクトではありません。")
        }

        let displayName = (root["displayName"] as? String)
            ?? (root["id"] as? String)
            ?? directory.lastPathComponent

        // --- スプライトシートの解決 -------------------------------------
        let sheetURL = try resolveSpritesheetURL(directory: directory, declared: root["spritesheetPath"] as? String)
        let image = try SpriteImageDecoder.decode(url: sheetURL)

        // --- mascot 拡張キー -------------------------------------------
        let mascot = root["mascot"] as? [String: Any]

        var grid = CodexPetDefaults.grid
        if let gridJSON = mascot?["grid"] as? [String: Any] {
            grid.columns = Int(StateMappingParser.numeric(gridJSON["columns"]) ?? Double(grid.columns))
            grid.rows = Int(StateMappingParser.numeric(gridJSON["rows"]) ?? Double(grid.rows))
            grid.cellWidth = Int(StateMappingParser.numeric(gridJSON["cellWidth"]) ?? Double(grid.cellWidth))
            grid.cellHeight = Int(StateMappingParser.numeric(gridJSON["cellHeight"]) ?? Double(grid.cellHeight))
        } else {
            // grid 指定が無い場合、画像サイズから 8×9 のセルサイズを推定する
            if image.width % CodexPetDefaults.grid.columns == 0,
               image.height % CodexPetDefaults.grid.rows == 0 {
                grid.cellWidth = image.width / grid.columns
                grid.cellHeight = image.height / grid.rows
            }
        }
        guard grid.columns > 0, grid.rows > 0, grid.cellWidth > 0, grid.cellHeight > 0 else {
            throw SkinError.invalidGrid("columns/rows/cellWidth/cellHeight は 1 以上である必要があります。")
        }
        guard grid.columns * grid.cellWidth <= image.width, grid.rows * grid.cellHeight <= image.height else {
            throw SkinError.invalidGrid("グリッド \(grid.columns)×\(grid.rows)（\(grid.cellWidth)×\(grid.cellHeight)px）が画像 \(image.width)×\(image.height)px に収まりません。")
        }

        let pixelScale = CGFloat(StateMappingParser.numeric(mascot?["pixelScale"]) ?? Double(CodexPetDefaults.pixelScale))
        let sheet = SpriteSheet(image: image, pixelScale: pixelScale > 0 ? pixelScale : 1)

        // --- アニメーション: 既定値をベースに、名前単位で上書き -----------
        var animations: [String: SpriteAnimation] = [:]
        for spec in CodexPetDefaults.rowSpecs {
            guard spec.row < grid.rows else { continue }
            // 既定表のコマ数より実際の素材が短い（末尾セルが透明）ことがあるので、
            // 完全に透明なセルは再生コマから外す。durations も同じコマだけ残す。
            var pairs = Array(zip(spec.frames, spec.durationsMS)).filter { $0.0 < grid.columns }
            let visible = pairs.filter { sheet.alphaMask.hasOpaquePixel(in: grid.rect(row: spec.row, column: $0.0)) }
            if !visible.isEmpty { pairs = visible }   // 行ごと空なら従来どおり（参照切れで落とさない）
            guard !pairs.isEmpty else { continue }
            animations[spec.name] = SpriteAnimation(
                name: spec.name,
                sheet: sheet,
                frames: pairs.map { grid.rect(row: spec.row, column: $0.0) },
                durations: pairs.map { TimeInterval($0.1) / 1000.0 },
                loop: spec.loop
            )
        }

        if let animJSON = mascot?["animations"] as? [String: Any] {
            for (name, value) in animJSON {
                guard let entry = value as? [String: Any] else { continue }
                animations[name] = try makeAnimation(name: name, json: entry, grid: grid, sheet: sheet)
            }
        }

        // --- states -----------------------------------------------------
        let mapping = StateMappingParser.merge(
            base: CodexPetDefaults.stateMapping,
            json: mascot?["states"] as? [String: Any]
        )

        return try Skin(displayName: displayName, sourceURL: directory, animations: animations, mapping: mapping)
    }

    // MARK: - private

    private static func resolveSpritesheetURL(directory: URL, declared: String?) throws -> URL {
        let fm = FileManager.default
        var candidates: [String] = []
        if let declared, !declared.isEmpty {
            candidates.append(declared)
            // 宣言されたファイルが無い場合は同名の .png → .webp を試す
            let base = (declared as NSString).deletingPathExtension
            candidates.append(base + ".png")
            candidates.append(base + ".webp")
        }
        candidates.append(contentsOf: ["spritesheet.png", "spritesheet.webp"])

        for name in candidates {
            let url = directory.appendingPathComponent(name)
            if fm.fileExists(atPath: url.path) { return url }
        }
        throw SkinError.spritesheetNotFound(declared ?? "spritesheet.png")
    }

    /// `mascot.animations` の 1 エントリから SpriteAnimation を作る
    private static func makeAnimation(name: String,
                                      json: [String: Any],
                                      grid: SpriteGrid,
                                      sheet: SpriteSheet) throws -> SpriteAnimation {
        guard let rowValue = StateMappingParser.numeric(json["row"]) else {
            throw SkinError.invalidGrid("アニメーション「\(name)」に row がありません。")
        }
        let row = Int(rowValue)
        guard row >= 0, row < grid.rows else {
            throw SkinError.invalidGrid("アニメーション「\(name)」の row=\(row) が範囲外です。")
        }

        // frames: 明示 → 既定表 → 行内の非透明セルを左から数える
        var columns: [Int]
        if let raw = json["frames"] as? [Any] {
            columns = raw.compactMap { StateMappingParser.numeric($0).map { Int($0) } }
        } else if let defaults = CodexPetDefaults.defaultFrames(for: name) {
            // 既定表を使う場合は、シート上で透明なセルを外す（frames 明示時はそのまま尊重）
            let visible = defaults.filter { $0 < grid.columns && sheet.alphaMask.hasOpaquePixel(in: grid.rect(row: row, column: $0)) }
            columns = visible.isEmpty ? defaults : visible
        } else {
            columns = nonTransparentColumns(row: row, grid: grid, mask: sheet.alphaMask)
        }
        columns = columns.filter { $0 >= 0 && $0 < grid.columns }
        if columns.isEmpty { throw SkinError.emptyAnimation(name) }

        let durations = StateMappingParser.durations(
            json: json,
            frameCount: columns.count,
            fallbackMS: CodexPetDefaults.defaultDurationsMS(for: name)
        )
        let loop = (json["loop"] as? Bool) ?? CodexPetDefaults.defaultLoop(for: name) ?? true

        return SpriteAnimation(
            name: name,
            sheet: sheet,
            frames: columns.map { grid.rect(row: row, column: $0) },
            durations: durations,
            loop: loop
        )
    }

    /// 行内で中身のある（非透明画素を含む）セルを左から順に列挙する
    private static func nonTransparentColumns(row: Int, grid: SpriteGrid, mask: AlphaMask) -> [Int] {
        var result: [Int] = []
        for column in 0..<grid.columns {
            if mask.hasOpaquePixel(in: grid.rect(row: row, column: column)) {
                result.append(column)
            } else if !result.isEmpty {
                break   // 連続した使用セルの終わり
            }
        }
        return result
    }
}
