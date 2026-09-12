import AppKit
import EnokiCore
import os

@MainActor
protocol MascotViewDelegate: AnyObject {
    func mascotViewDragBegan(_ view: MascotView)
    func mascotViewDragEnded(_ view: MascotView)
    func mascotViewClicked(_ view: MascotView)
}

/// スプライトを表示するビュー。
/// 描画はビットマップを作り直さず、`layer.contents` に 1 枚のシートを置いて
/// `layer.contentsRect` だけを差し替える。
@MainActor
final class MascotView: NSView {

    weak var delegate: MascotViewDelegate?

    private static let logger = Logger(subsystem: "com.enoki.mascot", category: "drag")

    private(set) var animation: SpriteAnimation?
    private(set) var frameIndex: Int = 0

    private var interpolation: InterpolationMode = .linear

    // ドラッグ判定
    private static let dragThreshold: CGFloat = 3
    private var mouseDownLocation: NSPoint = .zero
    private var mouseDownWindowOrigin: NSPoint = .zero
    private var isDragging = false

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        commonInit()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        commonInit()
    }

    private func commonInit() {
        wantsLayer = true
        layerContentsRedrawPolicy = .never
        let layer = CALayer()
        layer.contentsGravity = .resize
        layer.magnificationFilter = .linear
        layer.minificationFilter = .trilinear
        layer.isOpaque = false
        layer.backgroundColor = NSColor.clear.cgColor
        self.layer = layer
    }

    override var isFlipped: Bool { false }
    override var isOpaque: Bool { false }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    // MARK: - 表示更新

    /// アニメーションとコマ位置を反映する。シートが同じ CGImage なら contents は差し替えない。
    func apply(animation: SpriteAnimation, frameIndex: Int) {
        guard let layer else { return }
        let sheetChanged = (self.animation?.sheet.image !== animation.sheet.image)
        self.animation = animation
        self.frameIndex = frameIndex

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        if sheetChanged || layer.contents == nil {
            layer.contents = animation.sheet.image
        }
        layer.contentsRect = Self.layerContentsRect(animation.contentsRect(at: frameIndex))
        CATransaction.commit()
    }

    /// `SpriteAnimation.contentsRect` は左上原点の単位座標だが、macOS の CALayer は
    /// （このビューは非 flipped なので）contentsRect の原点が **左下** になる。
    /// そのまま渡すと行が上下逆になり、別の行（例: drag のつもりで running）を表示してしまう。
    static func layerContentsRect(_ topLeft: CGRect) -> CGRect {
        CGRect(x: topLeft.minX, y: 1 - topLeft.maxY, width: topLeft.width, height: topLeft.height)
    }

    /// コマ番号だけを更新する高速パス
    func setFrameIndex(_ index: Int) {
        guard let layer, let animation, animation.frames.indices.contains(index) else { return }
        frameIndex = index
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        layer.contentsRect = Self.layerContentsRect(animation.contentsRect(at: index))
        CATransaction.commit()
    }

    func setInterpolation(_ mode: InterpolationMode) {
        interpolation = mode
        layer?.magnificationFilter = (mode == .nearest) ? .nearest : .linear
        layer?.minificationFilter = .trilinear
    }

    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        layer?.contentsScale = window?.backingScaleFactor ?? 2.0
    }

    // MARK: - ヒットテスト（透明部分は透過）

    override func hitTest(_ point: NSPoint) -> NSView? {
        guard let superview else {
            return isOpaquePixel(atViewPoint: point) ? self : nil
        }
        let local = convert(point, from: superview)
        guard bounds.contains(local) else { return nil }
        return isOpaquePixel(atViewPoint: local) ? self : nil
    }

    /// ビュー座標（左下原点）→ シートのピクセル座標（左上原点）に変換してアルファを見る
    func isOpaquePixel(atViewPoint point: NSPoint) -> Bool {
        guard let animation, animation.frames.indices.contains(frameIndex) else { return false }
        guard bounds.width > 0, bounds.height > 0 else { return false }

        let u = point.x / bounds.width
        // ビューは下端原点、画像は上端原点なので Y を反転する
        let v = 1.0 - (point.y / bounds.height)
        guard u >= 0, u <= 1, v >= 0, v <= 1 else { return false }

        let rect = animation.frames[frameIndex]
        let px = Int((rect.minX + u * rect.width).rounded(.down))
        let py = Int((rect.minY + v * rect.height).rounded(.down))
        return animation.sheet.alphaMask.isOpaque(x: px, y: py)
    }

    // MARK: - マウス

    override func mouseDown(with event: NSEvent) {
        mouseDownLocation = NSEvent.mouseLocation
        mouseDownWindowOrigin = window?.frame.origin ?? .zero
        isDragging = false
        Self.logger.info("mouseDown t=\(event.timestamp) clicks=\(event.clickCount) mouse=\(self.mouseDownLocation.x),\(self.mouseDownLocation.y) origin=\(self.mouseDownWindowOrigin.x),\(self.mouseDownWindowOrigin.y)")
    }

    override func mouseDragged(with event: NSEvent) {
        guard let window else { return }
        let current = NSEvent.mouseLocation
        let dx = current.x - mouseDownLocation.x
        let dy = current.y - mouseDownLocation.y

        if !isDragging {
            guard hypot(dx, dy) >= MascotView.dragThreshold else { return }
            isDragging = true
            Self.logger.info("dragBegan t=\(event.timestamp) mouse=\(current.x),\(current.y)")
            delegate?.mascotViewDragBegan(self)
        }
        // ドラッグ中はクランプしない（スクリーン座標でそのまま追従）
        window.setFrameOrigin(NSPoint(x: mouseDownWindowOrigin.x + dx,
                                      y: mouseDownWindowOrigin.y + dy))
    }

    override func mouseUp(with event: NSEvent) {
        let mouse = NSEvent.mouseLocation
        Self.logger.info("mouseUp t=\(event.timestamp) dragging=\(self.isDragging) mouse=\(mouse.x),\(mouse.y) origin=\(self.window?.frame.origin.x ?? 0),\(self.window?.frame.origin.y ?? 0)")
        if isDragging {
            isDragging = false
            delegate?.mascotViewDragEnded(self)
        } else {
            delegate?.mascotViewClicked(self)
        }
    }
}
