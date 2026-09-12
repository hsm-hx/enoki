import XCTest
@testable import EnokiCore

final class WindowPlacementTests: XCTestCase {

    // 左下原点のスクリーン座標
    private let main = CGRect(x: 0, y: 0, width: 1440, height: 875)      // visibleFrame
    private let secondary = CGRect(x: 1440, y: 0, width: 1920, height: 1055)
    private let size = CGSize(width: 192, height: 208)

    private var screens: [CGRect] { [main, secondary] }

    func testDefaultOriginIsBottomRightOfMainScreen() {
        let origin = WindowPlacement.defaultOrigin(size: size, within: main)
        XCTAssertEqual(origin.x, main.maxX - size.width - 24)
        XCTAssertEqual(origin.y, main.minY + 24)
    }

    func testSavedOriginOffScreenFallsBackToDefault() {
        let saved = CGPoint(x: -5000, y: -5000)
        let origin = WindowPlacement.resolve(saved: saved, size: size, screens: screens, mainScreen: main)
        XCTAssertEqual(origin, WindowPlacement.defaultOrigin(size: size, within: main))
    }

    func testSavedOriginWithTooSmallOverlapFallsBackToDefault() {
        // 右端から 20pt だけ覗いている（40pt 未満）
        let saved = CGPoint(x: secondary.maxX - 20, y: 200)
        let origin = WindowPlacement.resolve(saved: saved, size: size, screens: screens, mainScreen: main)
        XCTAssertEqual(origin, WindowPlacement.defaultOrigin(size: size, within: main))
    }

    func testSavedOriginPartiallyOffScreenIsClamped() {
        // 十分に重なっているが右にはみ出している → その画面に収める
        let saved = CGPoint(x: main.maxX - 100, y: 300)
        let origin = WindowPlacement.resolve(saved: saved, size: size, screens: screens, mainScreen: main)
        XCTAssertEqual(origin.x, main.maxX - size.width)
        XCTAssertEqual(origin.y, 300)
    }

    func testSavedOriginInsideScreenIsKept() {
        let saved = CGPoint(x: 500, y: 400)
        let origin = WindowPlacement.resolve(saved: saved, size: size, screens: screens, mainScreen: main)
        XCTAssertEqual(origin, saved)
    }

    func testChoosesTheScreenWithTheLargestOverlap() {
        // 2 画面にまたがるが、右画面側に大きく載っている
        let saved = CGPoint(x: secondary.minX - 40, y: 500)
        let origin = WindowPlacement.resolve(saved: saved, size: size, screens: screens, mainScreen: main)
        XCTAssertEqual(origin.x, secondary.minX, "交差の大きい右画面へクランプされる")
        XCTAssertEqual(origin.y, 500)
    }

    func testClampKeepsWindowInsideVisibleFrame() {
        let clamped = WindowPlacement.clamp(origin: CGPoint(x: -50, y: -50), size: size, within: main)
        XCTAssertEqual(clamped, CGPoint(x: main.minX, y: main.minY))

        let clamped2 = WindowPlacement.clamp(origin: CGPoint(x: 9999, y: 9999), size: size, within: main)
        XCTAssertEqual(clamped2, CGPoint(x: main.maxX - size.width, y: main.maxY - size.height))
    }

    func testClampWithOversizedWindowAlignsToBottomLeft() {
        let huge = CGSize(width: 5000, height: 5000)
        let clamped = WindowPlacement.clamp(origin: CGPoint(x: 100, y: 100), size: huge, within: main)
        XCTAssertEqual(clamped, CGPoint(x: main.minX, y: main.minY))
    }

    func testSettleUsesScreenUnderMouse() {
        // ウィンドウは主に左画面にあるが、マウスは右画面 → マウス側の画面に収める
        let origin = CGPoint(x: 1430, y: 100)
        let settled = WindowPlacement.settle(origin: origin,
                                             size: size,
                                             mouseLocation: CGPoint(x: 2000, y: 500),
                                             screens: screens,
                                             mainScreen: main)
        XCTAssertEqual(settled.x, secondary.minX)
        XCTAssertEqual(settled.y, 100)
    }

    func testScaleChangeKeepsBottomCenter() {
        let origin = CGPoint(x: 1000, y: 100)
        let oldSize = CGSize(width: 192, height: 208)
        let newSize = CGSize(width: 288, height: 312)   // 1.5 倍
        let moved = WindowPlacement.originPreservingBottomCenter(origin: origin, oldSize: oldSize, newSize: newSize)
        XCTAssertEqual(moved.y, origin.y, "下端は固定")
        XCTAssertEqual(moved.x + newSize.width / 2, origin.x + oldSize.width / 2, "中央は固定")
    }

    func testNoSavedOriginUsesDefault() {
        let origin = WindowPlacement.resolve(saved: nil, size: size, screens: screens, mainScreen: main)
        XCTAssertEqual(origin, WindowPlacement.defaultOrigin(size: size, within: main))
    }
}
