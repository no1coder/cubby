import CoreGraphics

/// 一块屏幕：CGDirectDisplayID、全局点 frame（主屏左上原点、y 向下）、缩放
///
/// 负责三种坐标之间的换算（见设计文档 §3.2）：
/// - 全局点：Core 的一切几何都用它；
/// - 屏幕局部点：`global − frame.origin`；
/// - 屏幕局部像素：局部点 × `scale`，即冻结帧位图的坐标（左上原点）。
public struct CaptureScreen: Hashable, Sendable, Identifiable {
    /// CGDirectDisplayID
    public let id: UInt32
    /// 全局点坐标下的屏幕矩形
    public let frame: CGRect
    /// 点 → 像素的缩放（Retina 为 2）
    public let scale: CGFloat

    public init(id: UInt32, frame: CGRect, scale: CGFloat) {
        self.id = id
        self.frame = frame
        self.scale = scale
    }

    /// 整屏的原生像素尺寸（四舍五入到整数像素）
    public var pixelSize: CGSize {
        CGSize(width: (frame.width * scale).rounded(), height: (frame.height * scale).rounded())
    }

    /// 全局点 → 屏幕局部点
    public func localPoint(_ global: CGPoint) -> CGPoint {
        CGPoint(x: global.x - frame.minX, y: global.y - frame.minY)
    }

    /// 全局点 → 屏幕局部像素坐标，向下取整到像素
    public func pixelPoint(_ global: CGPoint) -> CGPoint {
        let local = localPoint(global)
        return CGPoint(x: (local.x * scale).rounded(.down), y: (local.y * scale).rounded(.down))
    }

    /// 全局点矩形 → 屏幕局部像素矩形：× scale 后向外取整（integral），再与整屏像素范围相交
    /// - Returns: 无交集时返回 `CGRect.zero`
    public func pixelRect(_ global: CGRect) -> CGRect {
        let local = global.standardized.offsetBy(dx: -frame.minX, dy: -frame.minY)
        let scaled = CGRect(
            x: local.minX * scale,
            y: local.minY * scale,
            width: local.width * scale,
            height: local.height * scale
        ).integral
        let clipped = scaled.intersection(CGRect(origin: .zero, size: pixelSize))
        return clipped.isNull || clipped.isEmpty ? .zero : clipped
    }

    /// 点是否在屏幕内：左 / 上边缘包含，右 / 下边缘不含
    public func contains(_ global: CGPoint) -> Bool {
        global.x >= frame.minX && global.x < frame.maxX && global.y >= frame.minY && global.y < frame.maxY
    }
}
