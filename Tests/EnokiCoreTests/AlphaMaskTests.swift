import XCTest
@testable import EnokiCore

final class AlphaMaskTests: XCTestCase {

    /// 画像の左上セルだけ不透明にして、マスクが左上原点で並んでいることを確認する
    func testMaskUsesTopLeftOrigin() throws {
        let dir = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appendingPathComponent("sheet.png")
        try TestSheetFactory.writePNG(to: url, columns: 4, rows: 3, cellWidth: 8, cellHeight: 10,
                                      filled: [(row: 0, column: 0)])

        let image = try SpriteImageDecoder.decode(url: url)
        let mask = AlphaMask.make(from: image)

        XCTAssertEqual(mask.width, 32)
        XCTAssertEqual(mask.height, 30)
        XCTAssertTrue(mask.isOpaque(x: 0, y: 0), "左上セルは不透明")
        XCTAssertTrue(mask.isOpaque(x: 7, y: 9))
        XCTAssertFalse(mask.isOpaque(x: 8, y: 0), "右隣のセルは透明")
        XCTAssertFalse(mask.isOpaque(x: 0, y: 10), "下のセルは透明")
        XCTAssertFalse(mask.isOpaque(x: -1, y: 0), "範囲外は透明扱い")
        XCTAssertFalse(mask.isOpaque(x: 0, y: 30))

        XCTAssertTrue(mask.hasOpaquePixel(in: CGRect(x: 0, y: 0, width: 8, height: 10)))
        XCTAssertFalse(mask.hasOpaquePixel(in: CGRect(x: 8, y: 0, width: 8, height: 10)))
    }
}
