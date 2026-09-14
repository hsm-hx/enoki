import AppKit
import EnokiCore
import os

/// 吹き出しのウィンドウ。
/// マスコット窓の **子ウィンドウ** にすることで、ドラッグに自動で追従し、
/// `ignoresMouseEvents = true` なのでドラッグ・クリックの邪魔もしない。
@MainActor
final class SpeechBubbleWindow: NSPanel {

    /// マスコット窓との隙間
    static let gap: CGFloat = 2
    /// 画面端からの余白
    static let screenMargin: CGFloat = 6
    static let fadeInDuration: TimeInterval = 0.2
    static let fadeOutDuration: TimeInterval = 0.3

    private static let logger = Logger(subsystem: "com.enoki.mascot", category: "bubble")

    private let bubbleView = SpeechBubbleView()
    private weak var attachedParent: NSWindow?

    init() {
        super.init(contentRect: NSRect(x: 0, y: 0, width: 100, height: 40),
                   styleMask: [.borderless, .nonactivatingPanel],
                   backing: .buffered,
                   defer: false)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        ignoresMouseEvents = true
        isMovable = false
        isMovableByWindowBackground = false
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        animationBehavior = .none
        isExcludedFromWindowsMenu = true
        collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        level = .floating
        alphaValue = 0
        contentView = bubbleView
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    // MARK: - 表示

    /// 1 発言を表示する（フェードイン）
    func show(line: DialogueLine, style: SpeakerStyle, over parent: NSWindow) {
        let size = bubbleView.configure(line: line, style: style)
        let parentFrame = parent.frame
        let screen = parent.screen ?? NSScreen.main ?? NSScreen.screens.first
        let visible = screen?.visibleFrame ?? parentFrame

        // 上に出せるか？ 収まらなければ下に出す
        var tailOnBottom = true
        var originY = parentFrame.maxY + Self.gap
        if originY + size.height > visible.maxY - Self.screenMargin {
            tailOnBottom = false
            originY = parentFrame.minY - Self.gap - size.height
        }
        originY = min(max(originY, visible.minY + Self.screenMargin), max(visible.maxY - size.height - Self.screenMargin, visible.minY))

        // 発言者の立ち位置にしっぽを向ける（1 人なら中央、2 人なら左 1/4・右 3/4。§11.2 の `speakers`）
        let anchorX = parentFrame.minX + parentFrame.width * style.anchor
        var originX = anchorX - size.width / 2
        let minX = visible.minX + Self.screenMargin
        let maxX = max(visible.maxX - size.width - Self.screenMargin, minX)
        originX = min(max(originX, minX), maxX)

        level = parent.level
        setFrame(NSRect(x: originX.rounded(), y: originY.rounded(), width: size.width, height: size.height), display: false)

        let range = SpeechBubbleView.tailRange(forWidth: size.width)
        let tailX = min(max(anchorX - originX.rounded(), range.lowerBound), range.upperBound)
        bubbleView.setTail(x: tailX, onBottom: tailOnBottom)
        bubbleView.needsDisplay = true

        attach(to: parent)
        Self.logger.info("吹き出し \(style.id, privacy: .public): frame=\(self.frame.origin.x),\(self.frame.origin.y) \(self.frame.width)x\(self.frame.height) tailX=\(tailX) 下向き=\(tailOnBottom) 文字数=\(line.text.count)")
        NSAnimationContext.runAnimationGroup { context in
            context.duration = Self.fadeInDuration
            animator().alphaValue = 1
        }
    }

    /// フェードアウトして閉じる
    func dismiss(animated: Bool = true, completion: (() -> Void)? = nil) {
        guard isVisible || alphaValue > 0 else {
            detach()
            completion?()
            return
        }
        guard animated else {
            alphaValue = 0
            detach()
            completion?()
            return
        }
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = Self.fadeOutDuration
            animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            MainActor.assumeIsolated {
                self?.alphaValue = 0
                self?.detach()
                completion?()
            }
        })
    }

    // MARK: - 親子関係

    private func attach(to parent: NSWindow) {
        if attachedParent !== parent {
            detach()
            parent.addChildWindow(self, ordered: .above)
            attachedParent = parent
        } else if !isVisible {
            parent.addChildWindow(self, ordered: .above)
        }
        orderFront(nil)
    }

    private func detach() {
        attachedParent?.removeChildWindow(self)
        orderOut(nil)
    }
}
