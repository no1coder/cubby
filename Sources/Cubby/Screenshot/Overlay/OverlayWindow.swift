import AppKit
import CubbyCore

/// 每块屏幕一个的截图覆盖层窗口（§3.4.5）
///
/// 与 `ClipPanel` 同族：不激活应用、可以成为 key；区别在于
/// - 层级 `.statusBar`（25）：盖住菜单栏与 Dock，同时低于输入法候选窗、工具提示与弹出菜单（§2.10）；
/// - 不透明、黑底、无阴影：内容就是冻结帧；
/// - 失去 key 时**不**关闭（§2.12）：系统弹窗抢走焦点后，点击覆盖层即可恢复。
final class OverlayWindow: NSPanel {
    /// 窗口所覆盖的屏幕
    let captureScreen: CaptureScreen

    init(screen: CaptureScreen, appKitFrame: NSRect) {
        captureScreen = screen
        super.init(
            contentRect: appKitFrame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        level = .statusBar
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        acceptsMouseMovedEvents = true
        hasShadow = false
        isOpaque = true
        backgroundColor = .black
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        isMovable = false
        animationBehavior = .none
        becomesKeyOnlyIfNeeded = false
        setFrame(appKitFrame, display: false)
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    /// 无边框窗口也可能被限制在可见区域内（避开菜单栏）；覆盖层必须铺满整屏
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect {
        frameRect
    }
}
