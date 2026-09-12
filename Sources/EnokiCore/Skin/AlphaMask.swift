import Foundation
import CoreGraphics

/// ヒットテスト用のアルファマスク。
/// 画像 1 枚ぶんの「不透明かどうか」を 1 バイト / 画素で保持する。
/// 座標系は CGImage と同じ **左上原点**（x: 0..<width, y: 0..<height）。
public struct AlphaMask: Sendable {
    public let width: Int
    public let height: Int
    /// 1 = 不透明 (alpha > threshold), 0 = 透明
    public let bits: [UInt8]

    /// alpha がこの値より大きい画素を不透明とみなす
    public static let threshold: UInt8 = 8

    public init(width: Int, height: Int, bits: [UInt8]) {
        self.width = width
        self.height = height
        self.bits = bits
    }

    /// 全面不透明なマスク（アルファ抽出に失敗したときのフォールバック）
    public static func opaque(width: Int, height: Int) -> AlphaMask {
        AlphaMask(width: width, height: height, bits: [UInt8](repeating: 1, count: max(0, width * height)))
    }

    /// CGImage から生成する。`alphaOnly` の 8bit コンテキストへ描画して取り出す。
    /// 1536×1872 で約 2.9MB。
    public static func make(from image: CGImage) -> AlphaMask {
        let w = image.width
        let h = image.height
        guard w > 0, h > 0 else { return AlphaMask(width: 0, height: 0, bits: []) }

        var buffer = [UInt8](repeating: 0, count: w * h)
        let ok: Bool = buffer.withUnsafeMutableBytes { raw -> Bool in
            guard let base = raw.baseAddress,
                  let ctx = CGContext(
                      data: base,
                      width: w,
                      height: h,
                      bitsPerComponent: 8,
                      bytesPerRow: w,
                      space: CGColorSpaceCreateDeviceGray(),
                      bitmapInfo: CGImageAlphaInfo.alphaOnly.rawValue
                  )
            else { return false }
            ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
            return true
        }
        guard ok else { return .opaque(width: w, height: h) }

        // CGBitmapContext のメモリ配置は行が上→下（先頭バイトが画像の左上）なので、
        // そのまま左上原点のマスクとして使える。
        let t = threshold
        var bits = [UInt8](repeating: 0, count: w * h)
        for index in 0..<(w * h) {
            bits[index] = buffer[index] > t ? 1 : 0
        }
        return AlphaMask(width: w, height: h, bits: bits)
    }

    /// 左上原点のピクセル座標で不透明かどうか
    public func isOpaque(x: Int, y: Int) -> Bool {
        guard x >= 0, y >= 0, x < width, y < height else { return false }
        return bits[y * width + x] == 1
    }

    /// 指定矩形（左上原点ピクセル）の中に不透明画素があるか
    public func hasOpaquePixel(in rect: CGRect) -> Bool {
        let x0 = max(0, Int(rect.minX.rounded(.down)))
        let y0 = max(0, Int(rect.minY.rounded(.down)))
        let x1 = min(width, Int(rect.maxX.rounded(.up)))
        let y1 = min(height, Int(rect.maxY.rounded(.up)))
        guard x0 < x1, y0 < y1 else { return false }
        for y in y0..<y1 {
            let row = y * width
            for x in x0..<x1 where bits[row + x] == 1 { return true }
        }
        return false
    }
}
