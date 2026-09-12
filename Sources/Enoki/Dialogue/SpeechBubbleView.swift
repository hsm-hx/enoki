import AppKit
import EnokiCore

/// 吹き出しの中身。角丸の塗り + 細い枠 + 発言者側に出るしっぽ。
/// NSVisualEffectView は使わず、単純な塗りで描く（マスコットの後ろを覗き込ませないため）。
@MainActor
final class SpeechBubbleView: NSView {

    // MARK: - 見た目の定数

    static let maxTextWidth: CGFloat = 220
    static let horizontalPadding: CGFloat = 12
    static let topPadding: CGFloat = 7
    static let bottomPadding: CGFloat = 8
    static let nameSpacing: CGFloat = 1
    static let cornerRadius: CGFloat = 10
    static let tailWidth: CGFloat = 14
    static let tailHeight: CGFloat = 9
    static let maxLines = 3

    private static let textFont = NSFont.systemFont(ofSize: 13)
    private static let nameFont = NSFont.systemFont(ofSize: 10, weight: .semibold)

    private static let backgroundColor = NSColor(calibratedWhite: 1.0, alpha: 0.94)
    private static let borderColor = NSColor(calibratedWhite: 0.40, alpha: 0.30)
    private static let bodyColor = NSColor(calibratedWhite: 0.12, alpha: 1.0)

    /// 発言者名の色（控えめ）
    private static func nameColor(for speaker: Speaker) -> NSColor {
        switch speaker {
        case .saku:   return NSColor(calibratedRed: 0.20, green: 0.26, blue: 0.46, alpha: 1.0)  // 落ち着いた紺
        case .shiori: return NSColor(calibratedRed: 0.54, green: 0.26, blue: 0.20, alpha: 1.0)  // 落ち着いた赤茶
        }
    }

    // MARK: - 状態

    private let nameLabel = NSTextField(labelWithString: "")
    private let bodyLabel = NSTextField(labelWithString: "")

    private var textSize: NSSize = .zero
    private var nameSize: NSSize = .zero
    /// しっぽの先端の x（このビューの座標）
    private var tailX: CGFloat = 0
    /// true = しっぽが下（吹き出しはマスコットの上）
    private(set) var tailOnBottom = true

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
        layer?.backgroundColor = NSColor.clear.cgColor

        nameLabel.font = Self.nameFont
        nameLabel.isBezeled = false
        nameLabel.drawsBackground = false
        nameLabel.isEditable = false
        nameLabel.isSelectable = false

        bodyLabel.font = Self.textFont
        bodyLabel.isBezeled = false
        bodyLabel.drawsBackground = false
        bodyLabel.isEditable = false
        bodyLabel.isSelectable = false
        bodyLabel.textColor = Self.bodyColor
        bodyLabel.maximumNumberOfLines = Self.maxLines
        bodyLabel.lineBreakMode = .byTruncatingTail
        bodyLabel.cell?.truncatesLastVisibleLine = true

        addSubview(nameLabel)
        addSubview(bodyLabel)
    }

    override var isFlipped: Bool { false }
    override var isOpaque: Bool { false }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }   // クリックは常に下へ抜く

    // MARK: - 内容

    /// 表示内容を入れ、必要なウィンドウサイズ（しっぽ込み）を返す
    @discardableResult
    func configure(line: DialogueLine) -> NSSize {
        nameLabel.stringValue = line.speaker.displayName
        nameLabel.textColor = Self.nameColor(for: line.speaker)
        bodyLabel.stringValue = line.text

        nameSize = Self.measure(line.speaker.displayName, font: Self.nameFont, maxLines: 1)
        textSize = Self.measure(line.text, font: Self.textFont, maxLines: Self.maxLines)

        let contentWidth = max(textSize.width, nameSize.width)
        let width = contentWidth + Self.horizontalPadding * 2
        let bubbleHeight = Self.topPadding + nameSize.height + Self.nameSpacing + textSize.height + Self.bottomPadding
        needsLayout = true
        needsDisplay = true
        return NSSize(width: ceil(width), height: ceil(bubbleHeight + Self.tailHeight))
    }

    /// しっぽの位置と向きを決める
    func setTail(x: CGFloat, onBottom: Bool) {
        tailX = x
        tailOnBottom = onBottom
        needsLayout = true
        needsDisplay = true
    }

    /// しっぽの先端 x として使える範囲（枠の角と重ならないように）
    static func tailRange(forWidth width: CGFloat) -> ClosedRange<CGFloat> {
        let inset = cornerRadius + tailWidth / 2 + 1
        let lower = min(inset, width / 2)
        let upper = max(width - inset, width / 2)
        return lower...upper
    }

    private static func measure(_ text: String, font: NSFont, maxLines: Int) -> NSSize {
        guard !text.isEmpty else { return .zero }
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineBreakMode = .byWordWrapping
        let attributes: [NSAttributedString.Key: Any] = [.font: font, .paragraphStyle: paragraph]
        let bounding = (text as NSString).boundingRect(
            with: NSSize(width: maxTextWidth, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: attributes)
        let lineHeight = ceil(font.ascender - font.descender + font.leading)
        let height = min(ceil(bounding.height), lineHeight * CGFloat(maxLines))
        return NSSize(width: min(ceil(bounding.width) + 1, maxTextWidth), height: max(height, lineHeight))
    }

    // MARK: - レイアウト

    private var bubbleRect: NSRect {
        let height = bounds.height - Self.tailHeight
        return NSRect(x: 0,
                      y: tailOnBottom ? Self.tailHeight : 0,
                      width: bounds.width,
                      height: max(0, height))
    }

    override func layout() {
        super.layout()
        let bubble = bubbleRect
        let contentWidth = bubble.width - Self.horizontalPadding * 2
        // 非 flipped なので上から積む
        let nameY = bubble.maxY - Self.topPadding - nameSize.height
        nameLabel.frame = NSRect(x: bubble.minX + Self.horizontalPadding,
                                 y: nameY,
                                 width: contentWidth,
                                 height: nameSize.height)
        bodyLabel.frame = NSRect(x: bubble.minX + Self.horizontalPadding,
                                 y: nameY - Self.nameSpacing - textSize.height,
                                 width: contentWidth,
                                 height: textSize.height)
    }

    // MARK: - 描画

    override func draw(_ dirtyRect: NSRect) {
        let path = Self.bubblePath(rect: bubbleRect.insetBy(dx: 0.5, dy: 0.5),
                                   radius: Self.cornerRadius,
                                   tailX: tailX,
                                   tailOnBottom: tailOnBottom)
        Self.backgroundColor.setFill()
        path.fill()
        Self.borderColor.setStroke()
        path.lineWidth = 1
        path.stroke()
    }

    /// 角丸 + しっぽを 1 本の閉じたパスとして作る（継ぎ目が出ないように）
    static func bubblePath(rect: NSRect, radius: CGFloat, tailX: CGFloat, tailOnBottom: Bool) -> NSBezierPath {
        let path = NSBezierPath()
        let r = min(radius, min(rect.width, rect.height) / 2)
        let minX = rect.minX, maxX = rect.maxX, minY = rect.minY, maxY = rect.maxY
        let halfTail = tailWidth / 2
        let tip = min(max(tailX, minX + r + halfTail), maxX - r - halfTail)
        let tailLeft = tip - halfTail
        let tailRight = tip + halfTail

        // 上辺（左 → 右）
        path.move(to: NSPoint(x: minX + r, y: maxY))
        if !tailOnBottom {
            path.line(to: NSPoint(x: tailLeft, y: maxY))
            path.line(to: NSPoint(x: tip, y: maxY + tailHeight))
            path.line(to: NSPoint(x: tailRight, y: maxY))
        }
        path.line(to: NSPoint(x: maxX - r, y: maxY))
        path.appendArc(withCenter: NSPoint(x: maxX - r, y: maxY - r), radius: r,
                       startAngle: 90, endAngle: 0, clockwise: true)
        // 右辺（上 → 下）
        path.line(to: NSPoint(x: maxX, y: minY + r))
        path.appendArc(withCenter: NSPoint(x: maxX - r, y: minY + r), radius: r,
                       startAngle: 0, endAngle: -90, clockwise: true)
        // 下辺（右 → 左）
        if tailOnBottom {
            path.line(to: NSPoint(x: tailRight, y: minY))
            path.line(to: NSPoint(x: tip, y: minY - tailHeight))
            path.line(to: NSPoint(x: tailLeft, y: minY))
        }
        path.line(to: NSPoint(x: minX + r, y: minY))
        path.appendArc(withCenter: NSPoint(x: minX + r, y: minY + r), radius: r,
                       startAngle: -90, endAngle: 180, clockwise: true)
        // 左辺（下 → 上）
        path.line(to: NSPoint(x: minX, y: maxY - r))
        path.appendArc(withCenter: NSPoint(x: minX + r, y: maxY - r), radius: r,
                       startAngle: 180, endAngle: 90, clockwise: true)
        path.close()
        return path
    }
}
