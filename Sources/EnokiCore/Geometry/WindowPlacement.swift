import Foundation
import CoreGraphics

/// ウィンドウ位置の計算（純関数のみ）。
/// 座標系は AppKit のスクリーン座標（**左下原点**）、矩形は `NSScreen.visibleFrame` 相当。
public enum WindowPlacement {

    /// 画面端からのマージン（既定位置）
    public static let defaultMargin: CGFloat = 24
    /// 保存位置を「その画面にある」とみなす最小の交差サイズ
    public static let minimumVisibleOverlap: CGSize = CGSize(width: 40, height: 40)

    /// 保存位置を検証して採用する。採用できなければメイン画面の右下。
    public static func resolve(saved: CGPoint?,
                               size: CGSize,
                               screens: [CGRect],
                               mainScreen: CGRect) -> CGPoint {
        if let saved {
            let rect = CGRect(origin: saved, size: size)
            if let screen = screenWithSufficientOverlap(for: rect, screens: screens) {
                return clamp(origin: saved, size: size, within: screen)
            }
        }
        return defaultOrigin(size: size, within: mainScreen)
    }

    /// メイン画面の右下（右・下に 24pt マージン）
    public static func defaultOrigin(size: CGSize, within visibleFrame: CGRect) -> CGPoint {
        let origin = CGPoint(x: visibleFrame.maxX - size.width - defaultMargin,
                             y: visibleFrame.minY + defaultMargin)
        return clamp(origin: origin, size: size, within: visibleFrame)
    }

    /// 矩形が visibleFrame に完全に収まるように原点をクランプする。
    /// 画面より大きい場合は左下を優先して合わせる。
    public static func clamp(origin: CGPoint, size: CGSize, within visibleFrame: CGRect) -> CGPoint {
        var x = origin.x
        var y = origin.y
        let maxX = visibleFrame.maxX - size.width
        let maxY = visibleFrame.maxY - size.height
        x = min(x, max(visibleFrame.minX, maxX))
        x = max(x, visibleFrame.minX)
        y = min(y, max(visibleFrame.minY, maxY))
        y = max(y, visibleFrame.minY)
        return CGPoint(x: x, y: y)
    }

    /// 十分な面積で交差している画面（最も交差面積が大きいもの）
    public static func screenWithSufficientOverlap(for rect: CGRect, screens: [CGRect]) -> CGRect? {
        var best: CGRect?
        var bestArea: CGFloat = 0
        for screen in screens {
            let inter = screen.intersection(rect)
            guard !inter.isNull,
                  inter.width >= minimumVisibleOverlap.width,
                  inter.height >= minimumVisibleOverlap.height else { continue }
            let area = inter.width * inter.height
            if area > bestArea {
                bestArea = area
                best = screen
            }
        }
        return best
    }

    /// 点を含む画面。無ければ矩形と最も交差する画面。どちらも無ければ nil。
    public static func screen(containing point: CGPoint,
                              orIntersecting rect: CGRect,
                              screens: [CGRect]) -> CGRect? {
        if let hit = screens.first(where: { $0.contains(point) }) { return hit }
        var best: CGRect?
        var bestArea: CGFloat = 0
        for screen in screens {
            let inter = screen.intersection(rect)
            guard !inter.isNull else { continue }
            let area = inter.width * inter.height
            if area > bestArea {
                bestArea = area
                best = screen
            }
        }
        return best
    }

    /// ドラッグ終了時のクランプ: マウス位置のある画面（無ければ最も交差する画面）へ収める
    public static func settle(origin: CGPoint,
                              size: CGSize,
                              mouseLocation: CGPoint,
                              screens: [CGRect],
                              mainScreen: CGRect) -> CGPoint {
        let rect = CGRect(origin: origin, size: size)
        let screen = self.screen(containing: mouseLocation, orIntersecting: rect, screens: screens) ?? mainScreen
        return clamp(origin: origin, size: size, within: screen)
    }

    /// 表示倍率変更時: **下端中央を固定**して新しいサイズの原点を求める
    public static func originPreservingBottomCenter(origin: CGPoint,
                                                    oldSize: CGSize,
                                                    newSize: CGSize) -> CGPoint {
        let centerX = origin.x + oldSize.width / 2
        return CGPoint(x: centerX - newSize.width / 2, y: origin.y)
    }
}
