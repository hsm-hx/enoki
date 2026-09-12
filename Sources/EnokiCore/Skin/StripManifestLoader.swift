import Foundation
import CoreGraphics

/// `manifest.json` 形式（1 アニメーション = 1 ストリップ画像）のローダ。
/// 当初要件との互換用。`pet.json` がある場合はそちらが優先される。
public enum StripManifestLoader {

    public static let manifestName = "manifest.json"

    public static func canLoad(directory: URL) -> Bool {
        FileManager.default.fileExists(atPath: directory.appendingPathComponent(manifestName).path)
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

        let displayName = (root["displayName"] as? String) ?? directory.lastPathComponent
        let pixelScale = CGFloat(StateMappingParser.numeric(root["pixelScale"]) ?? 1)

        guard let animJSON = root["animations"] as? [String: Any], !animJSON.isEmpty else {
            throw SkinError.manifestUnreadable("animations が空です。")
        }

        var sheetCache: [String: SpriteSheet] = [:]
        var animations: [String: SpriteAnimation] = [:]

        for (name, value) in animJSON {
            guard let entry = value as? [String: Any] else { continue }
            let fileName = (entry["file"] as? String) ?? "\(name).png"
            let sheet: SpriteSheet
            if let cached = sheetCache[fileName] {
                sheet = cached
            } else {
                let url = directory.appendingPathComponent(fileName)
                guard FileManager.default.fileExists(atPath: url.path) else {
                    throw SkinError.spritesheetNotFound(fileName)
                }
                let image = try SpriteImageDecoder.decode(url: url)
                sheet = SpriteSheet(image: image, pixelScale: pixelScale > 0 ? pixelScale : 1)
                sheetCache[fileName] = sheet
            }

            animations[name] = try makeAnimation(name: name, json: entry, sheet: sheet)
        }

        let mapping = StateMappingParser.merge(
            base: inferMapping(from: animations),
            json: root["states"] as? [String: Any]
        )

        return try Skin(displayName: displayName, sourceURL: directory, animations: animations, mapping: mapping)
    }

    // MARK: - private

    private static func makeAnimation(name: String, json: [String: Any], sheet: SpriteSheet) throws -> SpriteAnimation {
        let imageWidth = sheet.image.width
        let imageHeight = sheet.image.height

        var frameWidth = Int(StateMappingParser.numeric(json["frameWidth"]) ?? 0)
        var frameHeight = Int(StateMappingParser.numeric(json["frameHeight"]) ?? 0)
        let declaredCount = StateMappingParser.numeric(json["frameCount"]).map { Int($0) }

        if frameHeight <= 0 { frameHeight = imageHeight }
        if frameWidth <= 0 {
            if let count = declaredCount, count > 0, frameHeight == imageHeight {
                frameWidth = imageWidth / count
            } else {
                frameWidth = imageWidth
            }
        }
        guard frameWidth > 0, frameHeight > 0, frameWidth <= imageWidth, frameHeight <= imageHeight else {
            throw SkinError.invalidGrid("アニメーション「\(name)」のコマサイズが画像 \(imageWidth)×\(imageHeight)px に対して不正です。")
        }

        let columns = max(1, imageWidth / frameWidth)
        let rows = max(1, imageHeight / frameHeight)
        let total = columns * rows
        let count = min(declaredCount ?? total, total)
        guard count > 0 else { throw SkinError.emptyAnimation(name) }

        // 左→右、上→下の順に切り出す
        var frames: [CGRect] = []
        frames.reserveCapacity(count)
        for index in 0..<count {
            let column = index % columns
            let row = index / columns
            frames.append(CGRect(x: CGFloat(column * frameWidth),
                                 y: CGFloat(row * frameHeight),
                                 width: CGFloat(frameWidth),
                                 height: CGFloat(frameHeight)))
        }

        let durations = StateMappingParser.durations(json: json, frameCount: count, fallbackMS: nil)
        let loop = (json["loop"] as? Bool) ?? true

        return SpriteAnimation(name: name, sheet: sheet, frames: frames, durations: durations, loop: loop)
    }

    /// states 省略時の推定
    static func inferMapping(from animations: [String: SpriteAnimation]) -> StateMapping {
        let names = animations.keys.sorted()
        let idle = names.filter { $0.hasPrefix("idle") }
        let reaction = names.filter { $0.hasPrefix("reaction") }
        let fallback = idle.first ?? names.first ?? "idle"

        let idlePool = idle.isEmpty ? [fallback] : idle
        let sleepLoop = animations["sleep"] != nil ? "sleep" : fallback
        let drag = animations["drag"] != nil ? "drag" : fallback
        let reactionPool = reaction.isEmpty ? idlePool : reaction

        return StateMapping(
            idle: idlePool,
            idleSwitchInterval: 30...180,
            sleepIntro: animations["sleep_intro"] != nil ? "sleep_intro" : nil,
            sleepLoop: sleepLoop,
            drag: drag,
            reaction: reactionPool
        )
    }
}
