import CoreGraphics
import Darwin

/// 屏幕与窗口的几何拓扑（不含位图，可比较），供 reducer、摆放算法与测试使用
public struct ScreenTopology: Equatable, Sendable {
    /// 所有屏幕；顺序即查找优先级
    public let screens: [CaptureScreen]
    /// 窗口列表，前 → 后（z 序）
    public let windows: [WindowCandidate]
    /// Cubby 自身的进程号，悬停识别时排除
    public let ownPID: pid_t
    /// 例外：Cubby 自己可以被悬停选中的窗口（设置、使用说明等普通窗口），其余自有窗口照常排除
    public let selectableOwnWindowIDs: Set<UInt32>

    public init(
        screens: [CaptureScreen], windows: [WindowCandidate], ownPID: pid_t, selectableOwnWindowIDs: Set<UInt32> = []
    ) {
        self.screens = screens
        self.windows = windows
        self.ownPID = ownPID
        self.selectableOwnWindowIDs = selectableOwnWindowIDs
    }

    /// 包含该全局点的第一块屏幕；落在屏幕之间的空隙时为 nil
    public func screen(containing point: CGPoint) -> CaptureScreen? {
        screens.first { $0.contains(point) }
    }

    /// 按 CGDirectDisplayID 查找屏幕
    public func screen(id: UInt32) -> CaptureScreen? {
        screens.first { $0.id == id }
    }
}
