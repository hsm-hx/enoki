import Foundation
import CoreGraphics

/// スプライトシート 1 枚。`image` は CGImage（参照型）なので struct でも実体は共有される。
public struct SpriteSheet {
    public let image: CGImage
    /// 画像 1px が何 pt に相当するか（1 = 等倍、2 = Retina 素材）
    public let pixelScale: CGFloat
    public let alphaMask: AlphaMask

    public init(image: CGImage, pixelScale: CGFloat, alphaMask: AlphaMask) {
        self.image = image
        self.pixelScale = pixelScale
        self.alphaMask = alphaMask
    }

    public init(image: CGImage, pixelScale: CGFloat) {
        self.init(image: image, pixelScale: pixelScale, alphaMask: AlphaMask.make(from: image))
    }

    public var pixelSize: CGSize { CGSize(width: image.width, height: image.height) }
}

/// 1 アニメーション。frames は **左上原点のピクセル座標**、全コマ同サイズ。
public struct SpriteAnimation {
    public let name: String
    public let sheet: SpriteSheet
    public let frames: [CGRect]
    public let durations: [TimeInterval]   // 秒
    public let loop: Bool

    public init(name: String, sheet: SpriteSheet, frames: [CGRect], durations: [TimeInterval], loop: Bool) {
        self.name = name
        self.sheet = sheet
        self.frames = frames
        self.durations = durations
        self.loop = loop
    }

    public var frameSize: CGSize { frames.first?.size ?? .zero }
    public var frameCount: Int { frames.count }
    /// 表示サイズ（pt）
    public var pointSize: CGSize {
        let s = sheet.pixelScale <= 0 ? 1 : sheet.pixelScale
        return CGSize(width: frameSize.width / s, height: frameSize.height / s)
    }

    /// CALayer.contentsRect 用の正規化矩形（単位座標・左上原点）
    public func contentsRect(at index: Int) -> CGRect {
        guard frames.indices.contains(index) else { return CGRect(x: 0, y: 0, width: 1, height: 1) }
        let f = frames[index]
        let w = CGFloat(sheet.image.width)
        let h = CGFloat(sheet.image.height)
        guard w > 0, h > 0 else { return CGRect(x: 0, y: 0, width: 1, height: 1) }
        return CGRect(x: f.minX / w, y: f.minY / h, width: f.width / w, height: f.height / h)
    }

    public func duration(at index: Int) -> TimeInterval {
        guard durations.indices.contains(index) else { return 0.15 }
        return max(0.016, durations[index])
    }
}

/// 状態 → アニメーション名の対応。
public struct StateMapping: Equatable {
    /// idle プール。同じ名前を重複させると重み付けになる。
    public var idle: [String]
    /// idle アニメーションを切り替える間隔（秒）の範囲
    public var idleSwitchInterval: ClosedRange<TimeInterval>
    /// スリープ導入（1 度だけ再生）。nil ならいきなり loop へ。
    public var sleepIntro: String?
    public var sleepLoop: String
    public var drag: String
    /// クリック時のリアクション（ランダムに 1 つ）
    public var reaction: [String]

    public init(idle: [String],
                idleSwitchInterval: ClosedRange<TimeInterval>,
                sleepIntro: String?,
                sleepLoop: String,
                drag: String,
                reaction: [String]) {
        self.idle = idle
        self.idleSwitchInterval = idleSwitchInterval
        self.sleepIntro = sleepIntro
        self.sleepLoop = sleepLoop
        self.drag = drag
        self.reaction = reaction
    }

    /// この mapping が参照する全アニメーション名
    public var referencedNames: [String] {
        var names = idle + reaction
        names.append(sleepLoop)
        names.append(drag)
        if let intro = sleepIntro { names.append(intro) }
        return names
    }
}

/// 読み込み済みスキン。
public struct Skin {
    public let displayName: String
    public let sourceURL: URL
    public let animations: [String: SpriteAnimation]
    public let mapping: StateMapping

    public init(displayName: String, sourceURL: URL, animations: [String: SpriteAnimation], mapping: StateMapping) throws {
        // 検証: 空アニメーション / 参照切れはエラー
        for (name, anim) in animations where anim.frames.isEmpty {
            throw SkinError.emptyAnimation(name)
        }
        for name in mapping.referencedNames where animations[name] == nil {
            throw SkinError.missingAnimation(name)
        }
        if mapping.idle.isEmpty { throw SkinError.missingAnimation("idle") }
        self.displayName = displayName
        self.sourceURL = sourceURL
        self.animations = animations
        self.mapping = mapping
    }

    public func animation(named name: String) -> SpriteAnimation? { animations[name] }

    /// 最初に表示する idle アニメーション（mapping.idle の先頭）
    public var defaultIdleName: String { mapping.idle.first ?? "idle" }
}

/// スキン読み込みエラー（メッセージは日本語）
public enum SkinError: Error, LocalizedError, Equatable {
    case directoryNotFound(URL)
    case manifestNotFound(URL)
    case manifestUnreadable(String)
    case spritesheetNotFound(String)
    case imageDecodeFailed(URL)
    case missingAnimation(String)
    case emptyAnimation(String)
    case invalidGrid(String)
    case noSkinAvailable

    public var errorDescription: String? {
        switch self {
        case .directoryNotFound(let url):
            return "スキンのフォルダが見つかりません: \(url.path)"
        case .manifestNotFound(let url):
            return "pet.json も manifest.json も見つかりません: \(url.path)"
        case .manifestUnreadable(let detail):
            return "マニフェストの読み込みに失敗しました: \(detail)"
        case .spritesheetNotFound(let name):
            return "スプライトシートが見つかりません: \(name)"
        case .imageDecodeFailed(let url):
            return "画像を読み込めませんでした: \(url.lastPathComponent)"
        case .missingAnimation(let name):
            return "アニメーション「\(name)」が定義されていません。"
        case .emptyAnimation(let name):
            return "アニメーション「\(name)」にコマがありません。"
        case .invalidGrid(let detail):
            return "スプライトシートの分割指定が不正です: \(detail)"
        case .noSkinAvailable:
            return "利用できるスキンが見つかりませんでした。"
        }
    }
}
