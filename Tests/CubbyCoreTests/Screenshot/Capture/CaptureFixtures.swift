import CoreGraphics
import Foundation
@testable import CubbyCore

/// 截图测试用的屏幕与窗口拓扑：固定坐标，覆盖 2x 主屏 + 1x 负坐标外接屏
enum CaptureFixtures {
    static let ownPID: pid_t = 4242
    static let otherPID: pid_t = 1001

    /// 主屏 1440×900 @2x 于 (0, 0)
    static let primary = CaptureScreen(id: 1, frame: CGRect(x: 0, y: 0, width: 1440, height: 900), scale: 2)

    /// 外接屏 1920×1080 @1x 于 (1440, −180)
    static let external = CaptureScreen(
        id: 2,
        frame: CGRect(x: 1440, y: -180, width: 1920, height: 1080),
        scale: 1
    )

    /// 主屏上的普通窗口
    static let editorWindow = WindowCandidate(
        id: 10,
        frame: CGRect(x: 100, y: 100, width: 600, height: 400),
        layer: 0,
        ownerPID: otherPID,
        alpha: 1
    )

    /// 横跨两块屏幕的普通窗口
    static let spanningWindow = WindowCandidate(
        id: 11,
        frame: CGRect(x: 1200, y: 200, width: 600, height: 300),
        layer: 0,
        ownerPID: otherPID,
        alpha: 1
    )

    /// 菜单栏（layer 25，不算普通窗口）
    static let menuBar = WindowCandidate(
        id: 12,
        frame: CGRect(x: 0, y: 0, width: 1440, height: 24),
        layer: 25,
        ownerPID: 1,
        alpha: 1
    )

    /// 属于 Cubby 自身的窗口
    static let ownWindow = WindowCandidate(
        id: 13,
        frame: CGRect(x: 300, y: 300, width: 200, height: 200),
        layer: 0,
        ownerPID: ownPID,
        alpha: 1
    )

    static func topology(twoScreens: Bool = true) -> ScreenTopology {
        ScreenTopology(
            screens: twoScreens ? [primary, external] : [primary],
            windows: [menuBar, ownWindow, editorWindow, spanningWindow],
            ownPID: ownPID
        )
    }
}
