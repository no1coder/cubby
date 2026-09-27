import CoreGraphics
import Darwin
@testable import CubbyCore

/// 截图会话测试用的屏幕 / 窗口拓扑（与设计文档 §5.1 描述一致）
///
/// 主屏 1440×900 @2x 于 (0, 0)；外接 1920×1080 @1x 于 (1440, −180)。
/// 窗口（前 → 后）：菜单栏（layer 25）、Cubby 自身窗口、全透明窗口、1×1 窗口、检查器窗口（压在编辑器上）、
/// 编辑器窗口、跨屏窗口。
enum TopologyFixture {
    static let ownPID: pid_t = 999

    static let primary = CaptureScreen(id: 1, frame: CGRect(x: 0, y: 0, width: 1440, height: 900), scale: 2)
    static let external = CaptureScreen(id: 2, frame: CGRect(x: 1440, y: -180, width: 1920, height: 1080), scale: 1)

    static let menuBar = WindowCandidate(
        id: 10, frame: CGRect(x: 0, y: 0, width: 1440, height: 24), layer: 25, ownerPID: 50, alpha: 1)
    static let ownWindow = WindowCandidate(
        id: 11, frame: CGRect(x: 300, y: 300, width: 200, height: 200), layer: 0, ownerPID: ownPID, alpha: 1)
    static let transparent = WindowCandidate(
        id: 12, frame: CGRect(x: 800, y: 600, width: 100, height: 100), layer: 0, ownerPID: 60, alpha: 0)
    static let tiny = WindowCandidate(
        id: 13, frame: CGRect(x: 900, y: 750, width: 1, height: 1), layer: 0, ownerPID: 61, alpha: 1)
    static let inspector = WindowCandidate(
        id: 16, frame: CGRect(x: 500, y: 300, width: 400, height: 300), layer: 0, ownerPID: 102, alpha: 1)
    static let editor = WindowCandidate(
        id: 14, frame: CGRect(x: 100, y: 100, width: 600, height: 400), layer: 0, ownerPID: 100, alpha: 1)
    static let spanning = WindowCandidate(
        id: 15, frame: CGRect(x: 1200, y: 200, width: 600, height: 300), layer: 0, ownerPID: 101, alpha: 1)

    static let windows = [menuBar, ownWindow, transparent, tiny, inspector, editor, spanning]

    static let twoScreens = ScreenTopology(screens: [primary, external], windows: windows, ownPID: ownPID)
    static let singleScreen = ScreenTopology(screens: [primary], windows: [editor], ownPID: ownPID)
    static let noWindows = ScreenTopology(screens: [primary], windows: [], ownPID: ownPID)
    static let empty = ScreenTopology(screens: [], windows: [], ownPID: ownPID)

    /// 桌面上一个没有窗口的点（主屏）
    static let desktopPoint = CGPoint(x: 1000, y: 800)
    /// 编辑器窗口内的点
    static let editorPoint = CGPoint(x: 150, y: 150)
    /// 检查器与编辑器重叠处的点：候选为 [检查器, 编辑器, 整屏]
    static let stackPoint = CGPoint(x: 600, y: 400)
    /// 主屏与外接屏之间的空隙（主屏上方、外接屏左侧）
    static let gapPoint = CGPoint(x: 1000, y: -100)
}
