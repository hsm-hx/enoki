import Foundation
import CoreGraphics
import ImageIO
@testable import EnokiCore

/// テスト用のスプライトシート PNG をその場で生成するヘルパ（バイナリをリポジトリに置かない）
enum TestSheetFactory {

    /// 指定グリッドの PNG を作って書き出す。`filled` に指定した (row, column) だけ不透明にする。
    @discardableResult
    static func writePNG(to url: URL,
                         columns: Int,
                         rows: Int,
                         cellWidth: Int,
                         cellHeight: Int,
                         filled: [(row: Int, column: Int)]) throws -> CGImage {
        let width = columns * cellWidth
        let height = rows * cellHeight
        guard let ctx = CGContext(data: nil,
                                  width: width,
                                  height: height,
                                  bitsPerComponent: 8,
                                  bytesPerRow: 0,
                                  space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { throw TestError.contextFailed }

        ctx.clear(CGRect(x: 0, y: 0, width: width, height: height))
        ctx.setFillColor(CGColor(red: 1, green: 0, blue: 0, alpha: 1))
        for cell in filled {
            // グリッドは左上原点、CGContext は左下原点
            let y = height - (cell.row + 1) * cellHeight
            ctx.fill(CGRect(x: cell.column * cellWidth, y: y, width: cellWidth, height: cellHeight))
        }

        guard let image = ctx.makeImage() else { throw TestError.contextFailed }
        guard let dest = CGImageDestinationCreateWithURL(url as CFURL, "public.png" as CFString, 1, nil) else {
            throw TestError.writeFailed
        }
        CGImageDestinationAddImage(dest, image, nil)
        guard CGImageDestinationFinalize(dest) else { throw TestError.writeFailed }
        return image
    }

    /// 全セルを不透明にした Codex 互換（8×9）の小さいシート
    static func writeFullCodexSheet(to url: URL, cellWidth: Int = 16, cellHeight: Int = 18) throws {
        var filled: [(row: Int, column: Int)] = []
        for row in 0..<9 {
            for column in 0..<8 { filled.append((row, column)) }
        }
        try writePNG(to: url, columns: 8, rows: 9, cellWidth: cellWidth, cellHeight: cellHeight, filled: filled)
    }

    enum TestError: Error { case contextFailed, writeFailed }
}

/// テストごとの一時ディレクトリ
func makeTemporaryDirectory(_ name: String = UUID().uuidString) throws -> URL {
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("EnokiCoreTests", isDirectory: true)
        .appendingPathComponent(name, isDirectory: true)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}
