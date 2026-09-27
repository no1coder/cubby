import AppKit
import SwiftUI

/// 不激活应用的浮动面板：可以接收键盘输入，同时让原来的应用保持前台，粘贴目标不变
final class ClipPanel: NSPanel {
    var onResignKey: (() -> Void)?
    private let isKeyable: Bool

    /// - Parameter isKeyable: 预览等辅助面板传 false，避免抢走主面板的键盘焦点
    init(size: NSSize, isKeyable: Bool = true) {
        self.isKeyable = isKeyable
        super.init(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: true
        )
        isFloatingPanel = true
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient, .ignoresCycle]
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        animationBehavior = .none
    }

    override var canBecomeKey: Bool { isKeyable }
    override var canBecomeMain: Bool { false }

    override func resignKey() {
        super.resignKey()
        onResignKey?()
    }
}

/// 首次点击即响应（面板不激活应用，默认的 first mouse 行为会吞掉点击）
final class FirstMouseHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}
