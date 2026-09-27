import CoreGraphics

/// 渲染环境：把全局点映射到目标位图像素
///
/// 目标位图的一个像素 = context 的一个用户单位（CoreGraphics 默认左下原点）。
/// 在 `CALayer.draw(in:)` 里使用时，context 已带 contentsScale：先 `scaleBy(1 / contentsScale)`
/// 回到像素单位，再传 `scale = screen.scale`、`targetPixelSize = screen.pixelSize`。
///
/// `@unchecked Sendable` 的理由：只包含值类型与不可变的 CGImage（CGImage 不可变）。
public struct RenderEnvironment: @unchecked Sendable {
    /// 目标位图左上角对应的全局点
    public let origin: CGPoint
    /// 点 → 像素
    public let scale: CGFloat
    /// 目标位图的像素尺寸（用于翻转 y 轴）
    public let targetPixelSize: CGSize
    /// 马赛克用：整帧像素化副本（与目标同一 scale）；nil 时马赛克画半透明灰块占位
    public let pixelatedFrame: CGImage?
    /// 像素化副本左上角对应的全局点（即该屏 `frame.origin`）
    public let frameOrigin: CGPoint

    public init(
        origin: CGPoint,
        scale: CGFloat,
        targetPixelSize: CGSize,
        pixelatedFrame: CGImage?,
        frameOrigin: CGPoint
    ) {
        self.origin = origin
        self.scale = scale
        self.targetPixelSize = targetPixelSize
        self.pixelatedFrame = pixelatedFrame
        self.frameOrigin = frameOrigin
    }
}
