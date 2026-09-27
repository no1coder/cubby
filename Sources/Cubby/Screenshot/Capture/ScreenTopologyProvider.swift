import AppKit
import CubbyCore

/// NSScreen → CaptureScreen，以及 AppKit 屏幕坐标 ↔ 全局点的换算。
/// 这是 App 层唯一做坐标换算的地方（设计文档 §3.2）：
/// - AppKit：主屏左下角为原点，y 向上（NSEvent.mouseLocation、NSScreen.frame、NSWindow.frame）；
/// - 全局点：主屏左上角为原点，y 向下（CoreGraphics、ScreenCaptureKit、Core 的一切几何）。
@MainActor
enum ScreenTopologyProvider {
    /// 所有屏幕；顺序与 NSScreen.screens 一致（第一块为主屏）
    static func screens() -> [CaptureScreen] {
        NSScreen.screens.compactMap(captureScreen(for:))
    }

    static func captureScreen(for screen: NSScreen) -> CaptureScreen? {
        guard let id = displayID(of: screen) else { return nil }
        return CaptureScreen(id: id, frame: toGlobal(screen.frame), scale: screen.backingScaleFactor)
    }

    static func nsScreen(for screen: CaptureScreen) -> NSScreen? {
        NSScreen.screens.first { displayID(of: $0) == screen.id }
    }

    // MARK: - 换算

    static func toGlobal(_ appKitPoint: CGPoint) -> CGPoint {
        CGPoint(x: appKitPoint.x, y: primaryHeight - appKitPoint.y)
    }

    static func toGlobal(_ appKitRect: CGRect) -> CGRect {
        CGRect(
            x: appKitRect.minX,
            y: primaryHeight - appKitRect.maxY,
            width: appKitRect.width,
            height: appKitRect.height
        )
    }

    static func toAppKit(_ globalPoint: CGPoint) -> CGPoint {
        CGPoint(x: globalPoint.x, y: primaryHeight - globalPoint.y)
    }

    static func toAppKit(_ globalRect: CGRect) -> CGRect {
        CGRect(
            x: globalRect.minX,
            y: primaryHeight - globalRect.maxY,
            width: globalRect.width,
            height: globalRect.height
        )
    }

    // MARK: - 私有

    /// 主屏（菜单栏所在屏，NSScreen.screens 的第一个）高度：两套坐标系以它为翻转轴
    private static var primaryHeight: CGFloat {
        NSScreen.screens.first?.frame.height ?? 0
    }

    private static func displayID(of screen: NSScreen) -> UInt32? {
        let key = NSDeviceDescriptionKey("NSScreenNumber")
        return (screen.deviceDescription[key] as? NSNumber)?.uint32Value
    }
}
