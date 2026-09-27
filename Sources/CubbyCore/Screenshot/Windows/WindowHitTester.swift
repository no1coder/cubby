import CoreGraphics
import Darwin

/// 悬停目标：光标下的普通窗口，或（没有窗口时）光标所在的整块屏幕
public enum HoverTarget: Equatable, Sendable {
    case window(WindowCandidate, screen: CaptureScreen)
    case screen(CaptureScreen)

    /// 窗口 ∩ 屏幕；整屏则为屏幕 frame
    public var selectionRect: CGRect {
        switch self {
        case .window(let window, let screen):
            window.frame.standardized.intersection(screen.frame)
        case .screen(let screen):
            screen.frame
        }
    }

    /// 目标所在的屏幕（跨屏窗口取光标所在屏）
    public var screen: CaptureScreen {
        switch self {
        case .window(_, let screen): screen
        case .screen(let screen): screen
        }
    }

    /// 窗口目标的 CGWindowID；整屏为 nil（契约扩展：纯净窗口截图用）
    public var windowID: UInt32? {
        switch self {
        case .window(let window, _): window.id
        case .screen: nil
        }
    }
}

/// 悬停窗口识别（§2.3 hovering）：按 z 序找光标下的普通窗口
public enum WindowHitTester {
    /// 窗口宽高下限（小于它的窗口多为不可见的辅助窗口）
    private static let minimumWindowSide: CGFloat = 2

    /// 第一个满足 layer == 0、alpha > 0、宽高 ≥ 2、ownerPID != excludingPID 且包含 point 的窗口
    public static func topmost(
        at point: CGPoint,
        in windows: [WindowCandidate],
        excludingPID: pid_t
    ) -> WindowCandidate? {
        windows.first { isCandidate($0, at: point, excludingPID: excludingPID) }
    }

    /// 光标所在屏幕上的悬停目标；光标不在任何屏幕内（屏幕间空隙）时为 nil
    public static func hoverTarget(at point: CGPoint, topology: ScreenTopology) -> HoverTarget? {
        candidates(at: point, in: topology).first
    }

    /// 光标下所有可选目标（契约扩展：重叠窗口逐层切换）
    ///
    /// 过滤规则同 `topmost`，窗口按 z 序从前往后，最后追加光标所在的整屏作为兜底；
    /// 光标不在任何屏幕内时为空数组。第一项总是等于 `hoverTarget(at:topology:)`。
    public static func candidates(at point: CGPoint, in topology: ScreenTopology) -> [HoverTarget] {
        guard let screen = topology.screen(containing: point) else { return [] }
        let windows = topology.windows
            .filter { isCandidate($0, at: point, excludingPID: topology.ownPID) }
            .map { HoverTarget.window($0, screen: screen) }
        return windows + [.screen(screen)]
    }

    /// 可以被悬停识别 / 选区磁吸的普通窗口（不看位置），按 z 序
    static func eligibleWindows(in topology: ScreenTopology) -> [WindowCandidate] {
        topology.windows.filter { isEligible($0, excludingPID: topology.ownPID) }
    }

    private static func isCandidate(_ window: WindowCandidate, at point: CGPoint, excludingPID: pid_t) -> Bool {
        isEligible(window, excludingPID: excludingPID) && window.frame.standardized.contains(point)
    }

    private static func isEligible(_ window: WindowCandidate, excludingPID: pid_t) -> Bool {
        let frame = window.frame.standardized
        return window.layer == 0
            && window.alpha > 0
            && frame.width >= minimumWindowSide
            && frame.height >= minimumWindowSide
            && window.ownerPID != excludingPID
    }
}
