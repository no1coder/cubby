import CoreGraphics

/// 一块屏幕的覆盖层坐标换算（§3.2 / §3.4.5）
///
/// - 全局点：主屏左上原点、y 向下（Core 的一切几何）；
/// - 视图坐标：覆盖层根视图是翻转视图，`view = global − screen.frame.origin`；
/// - 图层坐标：画布图层树不翻转（y 向上），`layer.y = screen.height − view.y`；
/// - 设备像素：`view × scale`，用于把细线对齐到像素网格。
public struct OverlaySpace: Equatable, Sendable {
    public let screen: CaptureScreen

    public init(screen: CaptureScreen) {
        self.screen = screen
    }

    public var size: CGSize {
        screen.frame.size
    }

    public var scale: CGFloat {
        screen.scale
    }

    // MARK: - 全局点 ↔ 视图（翻转）

    public func viewPoint(_ global: CGPoint) -> CGPoint {
        CGPoint(x: global.x - screen.frame.minX, y: global.y - screen.frame.minY)
    }

    public func viewRect(_ global: CGRect) -> CGRect {
        global.standardized.offsetBy(dx: -screen.frame.minX, dy: -screen.frame.minY)
    }

    public func globalPoint(fromView point: CGPoint) -> CGPoint {
        CGPoint(x: point.x + screen.frame.minX, y: point.y + screen.frame.minY)
    }

    public func globalRect(fromView rect: CGRect) -> CGRect {
        rect.offsetBy(dx: screen.frame.minX, dy: screen.frame.minY)
    }

    // MARK: - 全局点 → 图层（y 向上）

    public func layerPoint(_ global: CGPoint) -> CGPoint {
        let local = viewPoint(global)
        return CGPoint(x: local.x, y: size.height - local.y)
    }

    public func layerRect(_ global: CGRect) -> CGRect {
        let local = viewRect(global)
        return CGRect(x: local.minX, y: size.height - local.maxY, width: local.width, height: local.height)
    }

    // MARK: - 像素对齐

    /// 向外取整到设备像素（与导出的 `CaptureScreen.pixelRect` 同一口径：显示的就是导出的）
    public func pixelAligned(_ global: CGRect) -> CGRect {
        let local = viewRect(global)
        let pixels = CGRect(
            x: local.minX * scale,
            y: local.minY * scale,
            width: local.width * scale,
            height: local.height * scale
        ).integral
        let aligned = CGRect(
            x: pixels.minX / scale,
            y: pixels.minY / scale,
            width: pixels.width / scale,
            height: pixels.height / scale
        )
        return globalRect(fromView: aligned)
    }

    /// 四舍五入到设备像素
    public func pixelRounded(_ value: CGFloat) -> CGFloat {
        (value * scale).rounded() / scale
    }

    /// 线宽为 width 的描边中心线：让描边两侧都落在像素边界上（奇数像素宽的线需要半像素偏移）
    public func strokeCenter(_ value: CGFloat, width: CGFloat) -> CGFloat {
        let pixels = (width * scale).rounded()
        let isOdd = Int(pixels) % 2 == 1
        let snapped = (value * scale).rounded()
        return (isOdd ? snapped + 0.5 : snapped) / scale
    }

    /// 是否与该屏相交
    public func intersects(_ global: CGRect) -> Bool {
        !global.isNull && global.intersects(screen.frame)
    }
}
