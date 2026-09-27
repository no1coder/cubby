import AppKit
import CubbyCore

/// 画布上与截图翻译有关的内容（普通值，由控制器从会话派生）
struct OverlayTranslationState: Equatable {
    /// 一块等译文的文字（流光）
    struct Shimmer: Equatable {
        let id: Int
        /// 全局点
        let rect: CGRect
    }

    /// 本屏的译文块
    var blocks: [TranslatedBlock] = []
    var display: TranslationDisplay = .hidden
    /// 进行中新到达的块淡入；撤销 / 重做 / 切换原文时直接出现
    var animatesArrivals = false
    var shimmers: [Shimmer] = []
    /// 流光的相位按块在选区里的横向位置错开（原型 --d），这是选区
    var shimmerSpan: CGRect?
    /// 悬停看原文时那块译文的描边（全局点）
    var outline: CGRect?
}

/// 译文层（冻结帧之上、遮罩与标注之下）：每块一个小图层，只重绘变化的那块；
/// 流光与悬停描边在它上面。图层树不翻转（y 向上），换算见 `OverlaySpace`
@MainActor
final class OverlayTranslationLayer {
    let root = CALayer()
    private let blocksLayer = CALayer()
    private let maskLayer = CALayer()
    private let shimmerLayer = CALayer()
    private let outlineLayer = CAShapeLayer()
    private var blockLayers: [Int: TranslationBlockLayer] = [:]
    private var shimmerLayers: [Int: CALayer] = [:]
    private var last: OverlayTranslationState?

    init() {
        blocksLayer.opacity = 0
        maskLayer.backgroundColor = NSColor.black.cgColor
        outlineLayer.fillColor = nil
        outlineLayer.lineWidth = OverlayTokens.translationOutlineWidth
        outlineLayer.isHidden = true
        for layer in [blocksLayer, shimmerLayer, outlineLayer] {
            root.addSublayer(layer)
        }
    }

    func update(_ state: OverlayTranslationState, space: OverlaySpace) {
        guard state != last else { return }
        let bounds = CGRect(origin: .zero, size: space.size)
        for layer in [root, blocksLayer, shimmerLayer, outlineLayer] {
            layer.frame = bounds
        }
        updateBlocks(state.blocks, animated: state.animatesArrivals, space: space)
        updateDisplay(state.display, space: space)
        updateShimmers(state.shimmers, span: state.shimmerSpan, space: space)
        updateOutline(state.outline, space: space)
        last = state
    }

    // MARK: - 译文块

    /// 新增或内容变了的块换新图层（进行中时 180 ms 淡入，旧图层淡入结束后再移除）；没有了的块直接移除
    private func updateBlocks(_ blocks: [TranslatedBlock], animated: Bool, space: OverlaySpace) {
        let wanted = Dictionary(blocks.map { ($0.blockID, $0) }) { _, latest in latest }
        for (id, layer) in blockLayers where wanted[id] == nil {
            layer.removeFromSuperlayer()
            blockLayers[id] = nil
        }
        let fades = animated && !OverlayMotion.isReduced
        for block in blocks where blockLayers[block.blockID]?.block != block {
            let layer = TranslationBlockLayer()
            layer.configure(block, space: space)
            blocksLayer.addSublayer(layer)
            let replaced = blockLayers[block.blockID]
            blockLayers[block.blockID] = layer
            guard fades else {
                replaced?.removeFromSuperlayer()
                continue
            }
            layer.add(Self.fadeIn(duration: OverlayTokens.translationBlockFadeDuration), forKey: "arrive")
            if let replaced {
                Task { @MainActor in
                    try? await Task.sleep(for: OverlayTokens.translationReplaceDelay)
                    replaced.removeFromSuperlayer()
                }
            }
        }
    }

    /// 整层显示 / 隐藏（0.12 s 淡变）；卷帘时只保留分隔线右侧
    private func updateDisplay(_ display: TranslationDisplay, space: OverlaySpace) {
        let opacity: Float = display == .hidden ? 0 : 1
        if blocksLayer.opacity != opacity {
            if !OverlayMotion.isReduced {
                let fade = CABasicAnimation(keyPath: "opacity")
                fade.fromValue = blocksLayer.opacity
                fade.toValue = opacity
                fade.duration = OverlayTokens.translationDisplayFadeDuration
                fade.timingFunction = CAMediaTimingFunction(name: .easeOut)
                blocksLayer.add(fade, forKey: "display")
            }
            blocksLayer.opacity = opacity
        }
        guard case .split(let x) = display else {
            blocksLayer.mask = nil
            return
        }
        let left = space.viewPoint(CGPoint(x: x, y: space.screen.frame.minY)).x
        maskLayer.frame = CGRect(x: left, y: 0, width: max(space.size.width - left, 0), height: space.size.height)
        blocksLayer.mask = maskLayer
    }

    // MARK: - 流光

    /// 底色 accent 0.07 + 扫光 accent 0.38，1.1 s 一轮；相位按块在选区里的横向位置错开
    private func updateShimmers(_ shimmers: [OverlayTranslationState.Shimmer], span: CGRect?, space: OverlaySpace) {
        let wanted = Set(shimmers.map(\.id))
        for (id, layer) in shimmerLayers where !wanted.contains(id) {
            layer.removeFromSuperlayer()
            shimmerLayers[id] = nil
        }
        for shimmer in shimmers where shimmerLayers[shimmer.id] == nil && space.intersects(shimmer.rect) {
            let layer = Self.shimmerLayer(for: shimmer.rect, span: span, space: space)
            shimmerLayer.addSublayer(layer)
            shimmerLayers[shimmer.id] = layer
        }
    }

    private static func shimmerLayer(for rect: CGRect, span: CGRect?, space: OverlaySpace) -> CALayer {
        let accent = OverlayColors.accent
        let base = CALayer()
        base.frame = space.layerRect(space.pixelAligned(rect))
        base.backgroundColor = accent.withAlphaComponent(OverlayTokens.shimmerBaseAlpha).cgColor
        base.cornerRadius = OverlayTokens.shimmerCornerRadius
        base.masksToBounds = true
        let width = base.bounds.width * OverlayTokens.shimmerSweepWidth
        let sweep = CAGradientLayer()
        sweep.frame = CGRect(x: -width, y: 0, width: width, height: base.bounds.height)
        sweep.colors = [
            accent.withAlphaComponent(0).cgColor, accent.withAlphaComponent(OverlayTokens.shimmerSweepAlpha).cgColor,
            accent.withAlphaComponent(0).cgColor,
        ]
        sweep.startPoint = CGPoint(x: 0, y: 0.5)
        sweep.endPoint = CGPoint(x: 1, y: 0.5)
        base.addSublayer(sweep)
        let duration = OverlayMotion.isReduced ? OverlayTokens.shimmerReducedDuration : OverlayTokens.shimmerDuration
        let move = CABasicAnimation(keyPath: "transform.translation.x")
        move.fromValue = 0
        move.toValue = base.bounds.width + width
        move.duration = duration
        move.repeatCount = .infinity
        move.timingFunction = CAMediaTimingFunction(name: .linear)
        if let span, span.width > 0 {
            move.timeOffset = duration * Double(max(rect.minX - span.minX, 0) / span.width)
        }
        sweep.add(move, forKey: "sweep")
        return base
    }

    // MARK: - 悬停描边

    private func updateOutline(_ rect: CGRect?, space: OverlaySpace) {
        guard let rect, space.intersects(rect) else {
            outlineLayer.isHidden = true
            return
        }
        let inset = -(OverlayTokens.translationOutlineOffset + OverlayTokens.translationOutlineWidth / 2)
        outlineLayer.path = CGPath(rect: space.layerRect(rect.insetBy(dx: inset, dy: inset)), transform: nil)
        outlineLayer.strokeColor =
            OverlayColors.accent.withAlphaComponent(OverlayTokens.translationOutlineAlpha).cgColor
        outlineLayer.isHidden = false
    }

    private static func fadeIn(duration: TimeInterval) -> CAAnimation {
        let fade = CABasicAnimation(keyPath: "opacity")
        fade.fromValue = 0
        fade.toValue = 1
        fade.duration = duration
        fade.timingFunction = CAMediaTimingFunction(name: .easeOut)
        return fade
    }
}

/// 一块译文：图层只覆盖这块的抹除 + 排版区域（对齐到设备像素），由 `TranslationPainter` 绘制
final class TranslationBlockLayer: CALayer {
    private(set) var block: TranslatedBlock?
    /// 图层左上角对应的全局点
    private var globalOrigin: CGPoint = .zero
    private var screen: CaptureScreen?

    @MainActor
    func configure(_ block: TranslatedBlock, space: OverlaySpace) {
        self.block = block
        screen = space.screen
        let covered = block.eraseFrame.union(block.textFrame).insetBy(dx: -1, dy: -1)
        let aligned = space.pixelAligned(covered.intersection(space.screen.frame))
        globalOrigin = aligned.origin
        contentsScale = space.scale
        frame = space.layerRect(aligned)
        needsDisplayOnBoundsChange = false
        setNeedsDisplay()
    }

    override func draw(in ctx: CGContext) {
        guard let block, let screen else { return }
        let scale = contentsScale
        ctx.scaleBy(x: 1 / scale, y: 1 / scale)
        let environment = RenderEnvironment(
            origin: globalOrigin,
            scale: screen.scale,
            targetPixelSize: CGSize(width: (bounds.width * scale).rounded(), height: (bounds.height * scale).rounded()),
            pixelatedFrame: nil,
            frameOrigin: screen.frame.origin
        )
        TranslationPainter.draw([block], in: ctx, environment: environment)
    }
}
