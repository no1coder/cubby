import CoreGraphics
import Darwin

/// 悬停识别的窗口候选：来自 ScreenCaptureKit / CGWindowList 的几何信息（不含标题等隐私字段）
public struct WindowCandidate: Hashable, Sendable {
    /// CGWindowID
    public let id: UInt32
    /// 全局点坐标下的窗口矩形
    public let frame: CGRect
    /// 窗口层级；0 = 普通窗口
    public let layer: Int
    /// 所属进程
    public let ownerPID: pid_t
    /// 窗口透明度（0...1）
    public let alpha: Double

    public init(id: UInt32, frame: CGRect, layer: Int, ownerPID: pid_t, alpha: Double) {
        self.id = id
        self.frame = frame
        self.layer = layer
        self.ownerPID = ownerPID
        self.alpha = alpha
    }
}
