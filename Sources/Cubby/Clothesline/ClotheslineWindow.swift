import AppKit

/// 晾衣绳窗口：屏幕顶部、与屏幕同宽的透明非激活面板，层级低于菜单栏（从菜单栏下方滑出时被菜单栏盖住）。
/// 不成为 key：悬停由控制器轮询指针计算；透明处的点击穿透到下面的窗口。
/// 不加 fullScreenAuxiliary：全屏应用的空间里不出现
final class ClotheslineWindow: NSPanel {
    init() {
        super.init(
            contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        level = Self.restingLevel
        collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        isReleasedWhenClosed = false
        hidesOnDeactivate = false
        animationBehavior = .none
        acceptsMouseMovedEvents = true
    }

    /// 平时的层级：低于菜单栏
    static let restingLevel = NSWindow.Level(rawValue: NSWindow.Level.mainMenu.rawValue - 1)

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    /// 绳子在某块屏幕上的落位：菜单栏正下方、与屏幕同宽
    static func frame(on screen: NSScreen, height: CGFloat) -> CGRect {
        let top = screen.visibleFrame.maxY
        return CGRect(x: screen.frame.minX, y: top - height, width: screen.frame.width, height: height)
    }
}
