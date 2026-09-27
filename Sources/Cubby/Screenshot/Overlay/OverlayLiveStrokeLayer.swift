import CubbyCore
import QuartzCore

/// 一个待绘制的标注及其序号（序号由文档顺序推导，非序号标注为 nil）
struct OverlayAnnotationItem: Equatable {
    let annotation: Annotation
    let numberLabel: Int?
}

/// 标注的渲染环境：一块屏幕 + 马赛克用的像素化副本
struct OverlayRenderTarget {
    let screen: CaptureScreen
    let pixelated: CGImage?

    /// 目标位图左上角为 origin、像素尺寸为 pixelSize 时的环境
    func environment(origin: CGPoint, pixelSize: CGSize) -> RenderEnvironment {
        RenderEnvironment(
            origin: origin,
            scale: screen.scale,
            targetPixelSize: pixelSize,
            pixelatedFrame: pixelated,
            frameOrigin: screen.frame.origin
        )
    }
}

/// 整屏的标注层：只在文档（或像素化副本）变化时重绘（§3.4.5）
///
/// `AnnotationRenderer` 约定 context 的 1 个单位 = 1 个目标像素，因此 `draw(in:)` 先 `scaleBy(1 / contentsScale)`。
final class OverlayAnnotationLayer: CALayer {
    private var items: [OverlayAnnotationItem] = []
    private var target: OverlayRenderTarget?
    private var hasPixelated = false

    /// 内容不变时不触发重绘
    func update(items: [OverlayAnnotationItem], target: OverlayRenderTarget) {
        let pixelatedReady = target.pixelated != nil
        let needsMosaic = items.contains { $0.annotation.tool == .mosaic }
        let changed =
            items != self.items || self.target?.screen != target.screen
            || (needsMosaic && pixelatedReady != hasPixelated)
        self.target = target
        hasPixelated = pixelatedReady
        guard changed else { return }
        self.items = items
        if items.isEmpty {
            // 没有标注时释放整屏位图，多屏时不为空屏幕占内存
            contents = nil
        } else {
            setNeedsDisplay()
        }
    }

    override func draw(in ctx: CGContext) {
        guard let target, !items.isEmpty else { return }
        let scale = contentsScale
        ctx.scaleBy(x: 1 / scale, y: 1 / scale)
        let environment = target.environment(
            origin: target.screen.frame.origin,
            pixelSize: CGSize(width: bounds.width * scale, height: bounds.height * scale)
        )
        for item in items {
            AnnotationRenderer.draw(item.annotation, numberLabel: item.numberLabel, in: ctx, environment: environment)
        }
    }
}

/// 实时层：拖拽中的标注（正在画的、正在拖动的）
///
/// 图层只覆盖标注的外接矩形（对齐到设备像素），每帧只重绘这一小块，保证画笔与拖动 60 fps。
final class OverlayLiveStrokeLayer: CALayer {
    private var item: OverlayAnnotationItem?
    private var target: OverlayRenderTarget?
    /// 图层左上角对应的全局点
    private var globalOrigin: CGPoint = .zero

    func update(item: OverlayAnnotationItem?, target: OverlayRenderTarget, space: OverlaySpace) {
        guard let item else {
            clear()
            return
        }
        guard item != self.item || target.screen != self.target?.screen || target.pixelated !== self.target?.pixelated
        else { return }
        let bounds = item.annotation.bounds
        guard !bounds.isNull, space.intersects(bounds) else {
            clear()
            return
        }
        // 外扩 2 pt 容纳抗锯齿边缘，再与屏幕相交、对齐到像素
        let padding = OverlayTokens.liveLayerPadding
        let padded = bounds.insetBy(dx: -padding, dy: -padding).intersection(space.screen.frame)
        let aligned = space.pixelAligned(padded)
        self.item = item
        self.target = target
        globalOrigin = aligned.origin
        frame = space.layerRect(aligned)
        isHidden = false
        setNeedsDisplay()
    }

    private func clear() {
        guard item != nil || !isHidden else { return }
        item = nil
        contents = nil
        isHidden = true
    }

    override func draw(in ctx: CGContext) {
        guard let item, let target else { return }
        let scale = contentsScale
        ctx.scaleBy(x: 1 / scale, y: 1 / scale)
        let environment = target.environment(
            origin: globalOrigin,
            pixelSize: CGSize(width: (bounds.width * scale).rounded(), height: (bounds.height * scale).rounded())
        )
        AnnotationRenderer.draw(item.annotation, numberLabel: item.numberLabel, in: ctx, environment: environment)
    }
}
