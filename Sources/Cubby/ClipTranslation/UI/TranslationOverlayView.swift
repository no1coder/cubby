import AppKit
import CubbyCore
import ImageIO
import SwiftUI

/// 图片原图之上的译文层（设计文档 §5.3）：每个到达的块一层 CALayer，用 TranslationPainter.draw 按缩放后的
/// RenderEnvironment 重画，并以 180 ms 淡入；卷帘用遮罩层裁出右侧；悬停与拖动分隔线也在这里处理
/// （预览面板不可成为 key，用 activeAlways 的跟踪区域与 acceptsFirstMouse，见 R1）
struct TranslationOverlayView: NSViewRepresentable {
    struct Model: Equatable {
        var blocks: [TranslatedImageBlock]
        /// 图片的点尺寸（像素 / DPI 倍率）：块坐标所在的坐标系
        var imagePointSize: CGSize
        /// 卷帘位置 0…1；nil 表示不裁切
        var wipe: Double?
        /// 按住 ⌥ 看原文、「原文」视图
        var hidesTranslation: Bool
        var highlighted: Int?
    }

    let model: Model
    let onHover: (Int?) -> Void
    /// 拖动分隔线：新位置 0…1
    let onWipe: (Double) -> Void

    func makeNSView(context: Context) -> TranslationOverlayNSView {
        let view = TranslationOverlayNSView()
        view.onHover = onHover
        view.onWipe = onWipe
        view.apply(model)
        return view
    }

    func updateNSView(_ view: TranslationOverlayNSView, context: Context) {
        view.onHover = onHover
        view.onWipe = onWipe
        view.apply(model)
    }
}

final class TranslationOverlayNSView: NSView {
    var onHover: ((Int?) -> Void)?
    var onWipe: ((Double) -> Void)?

    /// 分隔线两侧可拖动的半宽（原型 18pt 热区，拖柄直径 28）
    static let dividerHitHalfWidth: CGFloat = 14
    private static let fadeDuration: CFTimeInterval = 0.18

    private var model = TranslationOverlayView.Model(
        blocks: [], imagePointSize: .zero, wipe: nil, hidesTranslation: false, highlighted: nil)
    private let container = CALayer()
    private let wipeMask = CALayer()
    private let outline = CAShapeLayer()
    private var blockLayers: [Int: ClipTranslationBlockLayer] = [:]
    private var isDragging = false
    private var hovered: Int?

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.masksToBounds = true
        layer?.addSublayer(container)
        wipeMask.backgroundColor = NSColor.black.cgColor
        outline.fillColor = nil
        outline.strokeColor = NSColor.controlAccentColor.withAlphaComponent(0.7).cgColor
        outline.lineWidth = 1.5
        layer?.addSublayer(outline)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(
            NSTrackingArea(
                rect: .zero, options: [.activeAlways, .mouseMoved, .mouseEnteredAndExited, .inVisibleRect],
                owner: self))
    }

    func apply(_ newModel: TranslationOverlayView.Model) {
        let previous = model
        model = newModel
        syncBlocks(animated: previous.imagePointSize == newModel.imagePointSize)
        CATransaction.begin()
        CATransaction.setAnimationDuration(Motion.fade)
        container.opacity = newModel.hidesTranslation ? 0 : 1
        CATransaction.commit()
        layoutOverlay()
    }

    override func layout() {
        super.layout()
        layoutOverlay()
    }

    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        let scale = window?.backingScaleFactor ?? 2
        blockLayers.values.forEach {
            $0.contentsScale = scale
            $0.setNeedsDisplay()
        }
    }

    // MARK: - 块

    /// 图片点 → 本视图坐标（左下原点）的缩放
    private var factor: CGFloat {
        model.imagePointSize.width > 0 ? bounds.width / model.imagePointSize.width : 0
    }

    private func syncBlocks(animated: Bool) {
        let ids = Set(model.blocks.map(\.block.blockID))
        for (id, layer) in blockLayers where !ids.contains(id) {
            layer.removeFromSuperlayer()
            blockLayers[id] = nil
        }
        for item in model.blocks {
            if let existing = blockLayers[item.block.blockID], existing.block == item.block { continue }
            blockLayers[item.block.blockID]?.removeFromSuperlayer()
            let layer = ClipTranslationBlockLayer(block: item.block)
            layer.contentsScale = window?.backingScaleFactor ?? 2
            container.addSublayer(layer)
            blockLayers[item.block.blockID] = layer
            if animated {
                let fade = CABasicAnimation(keyPath: "opacity")
                fade.fromValue = 0
                fade.toValue = 1
                fade.duration = Self.fadeDuration
                layer.add(fade, forKey: "fade")
            }
        }
    }

    private func layoutOverlay() {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        container.frame = bounds
        for layer in blockLayers.values {
            layer.place(factor: factor, viewHeight: bounds.height)
        }
        if let wipe = model.wipe {
            let x = bounds.width * wipe
            wipeMask.frame = CGRect(x: x, y: 0, width: max(bounds.width - x, 0), height: bounds.height)
            container.mask = wipeMask
        } else {
            container.mask = nil
        }
        outline.path = highlightPath()
        CATransaction.commit()
    }

    private func highlightPath() -> CGPath? {
        guard let id = model.highlighted, !model.hidesTranslation,
            let block = model.blocks.first(where: { $0.block.blockID == id })?.block
        else { return nil }
        let rect = viewRect(block.eraseFrame).insetBy(dx: -1, dy: -1)
        return CGPath(roundedRect: rect, cornerWidth: 2, cornerHeight: 2, transform: nil)
    }

    /// 图片点（左上原点）→ 本视图坐标（左下原点）
    private func viewRect(_ rect: CGRect) -> CGRect {
        CGRect(
            x: rect.minX * factor, y: bounds.height - rect.maxY * factor, width: rect.width * factor,
            height: rect.height * factor)
    }

    // MARK: - 指针

    override func mouseMoved(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        updateHover(at: point)
        if nearDivider(point) { NSCursor.resizeLeftRight.set() } else { NSCursor.arrow.set() }
    }

    override func mouseEntered(with event: NSEvent) {
        mouseMoved(with: event)
    }

    override func mouseExited(with event: NSEvent) {
        updateHover(at: nil)
        NSCursor.arrow.set()
    }

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        guard nearDivider(point) else {
            super.mouseDown(with: event)
            return
        }
        isDragging = true
        updateHover(at: nil)
        onWipe?(wipeValue(at: point))
    }

    override func mouseDragged(with event: NSEvent) {
        guard isDragging else { return }
        onWipe?(wipeValue(at: convert(event.locationInWindow, from: nil)))
    }

    override func mouseUp(with event: NSEvent) {
        isDragging = false
    }

    private func nearDivider(_ point: CGPoint) -> Bool {
        guard let wipe = model.wipe, bounds.width > 0 else { return false }
        return abs(point.x - bounds.width * wipe) <= Self.dividerHitHalfWidth
    }

    private func wipeValue(at point: CGPoint) -> Double {
        bounds.width > 0 ? min(max(point.x / bounds.width, 0), 1) : 0.5
    }

    private func updateHover(at point: CGPoint?) {
        let id = point.flatMap(block(at:))
        guard id != hovered else { return }
        hovered = id
        onHover?(id)
    }

    /// 指针下的块（后到达的在上层）
    private func block(at point: CGPoint) -> Int? {
        guard !model.hidesTranslation, !isDragging, factor > 0 else { return nil }
        if let wipe = model.wipe, point.x < bounds.width * wipe { return nil }
        let imagePoint = CGPoint(x: point.x / factor, y: (bounds.height - point.y) / factor)
        return model.blocks.last { $0.block.eraseFrame.contains(imagePoint) }?.block.blockID
    }
}

#if DEBUG
extension TranslationOverlayNSView {
    /// 面板 E2E：跟踪区域按真实光标位置判断进出，合成的鼠标移动不会触发它，脚本直接交给悬停处理。
    /// point 为窗口坐标；nil 表示移出
    func debugHover(atWindowPoint point: CGPoint?) {
        updateHover(at: point.map { convert($0, from: nil) })
    }
}
#endif

/// 一块译文的图层：只覆盖该块的范围，用 TranslationPainter 画（与截图翻译同一绘制）
final class ClipTranslationBlockLayer: CALayer {
    let block: TranslatedBlock
    private var factor: CGFloat = 1

    init(block: TranslatedBlock) {
        self.block = block
        super.init()
        needsDisplayOnBoundsChange = true
    }

    override init(layer: Any) {
        let other = layer as? ClipTranslationBlockLayer
        block = other?.block ?? ClipTranslationBlockLayer.emptyBlock
        factor = other?.factor ?? 1
        super.init(layer: layer)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    /// 按缩放放到视图坐标（左下原点）里；外扩 2pt 容纳描边与字形
    func place(factor newFactor: CGFloat, viewHeight: CGFloat) {
        let union = block.eraseFrame.union(block.textFrame).insetBy(dx: -2, dy: -2)
        let rect = CGRect(
            x: union.minX * newFactor, y: viewHeight - union.maxY * newFactor, width: union.width * newFactor,
            height: union.height * newFactor)
        guard rect != frame || newFactor != factor else { return }
        factor = newFactor
        frame = rect
        setNeedsDisplay()
    }

    override func draw(in ctx: CGContext) {
        guard factor > 0 else { return }
        let union = block.eraseFrame.union(block.textFrame).insetBy(dx: -2, dy: -2)
        // 本层左上角对应的图片点；目标「像素」即本层的点（上下文已含 contentsScale）
        let environment = RenderEnvironment(
            origin: union.origin, scale: factor, targetPixelSize: bounds.size, pixelatedFrame: nil,
            frameOrigin: .zero)
        TranslationPainter.draw([block], in: ctx, environment: environment)
    }

    private static let emptyBlock = TranslatedBlock(
        blockID: -1, eraseFrame: .zero, backdrop: .solid(.white), text: "", textFrame: .zero, fontSize: 1,
        isBold: false, textColor: .black, alignment: .leading)
}

/// 历史图片的点倍率：只读文件头的 DPI，换算规则与合成屏幕同一处（HistoryImageFrame.scale，设计文档 §5.1）
enum ImagePointScale {
    static func read(_ url: URL?) -> CGFloat {
        let properties = url.flatMap { CGImageSourceCreateWithURL($0 as CFURL, nil) }
            .flatMap { CGImageSourceCopyPropertiesAtIndex($0, 0, nil) as? [CFString: Any] }
        let dpi = (properties?[kCGImagePropertyDPIWidth] as? NSNumber)?.doubleValue
        return HistoryImageFrame.scale(dpi: dpi)
    }
}
