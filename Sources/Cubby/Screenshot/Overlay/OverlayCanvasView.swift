import AppKit
import CoreImage
import CubbyCore

/// 图层合成滤镜
@MainActor
enum OverlayBlend {
    /// 荧光笔：multiply 合成到冻结帧上（渲染器在透明层里以 0.5 alpha 画，合成后等价于导出时的 multiply）
    static let multiply = CIFilter(name: "CIMultiplyBlendMode")
}

/// 画布某一时刻的内容（普通值，由控制器从会话派生）
struct OverlayCanvasState {
    /// 去遮罩区域（全局点）：选区或悬停目标
    var highlight: CGRect?
    /// 悬停描边的矩形与样式；有选区时为 nil
    var hover: CGRect?
    var hoverStyle: OverlayHoverStyle = .target
    /// 悬停目标是窗口（圆角描边、圆角去遮罩）；整屏为 false
    var hoverIsWindow = false
    /// 首用引导条（本屏底部居中）
    var showsOnboarding = false
    var selection: CGRect?
    var handles: [SelectionHandle] = []
    var activeHandle: SelectionHandle?
    /// 标注层内容（已排除实时层中的标注与荧光笔）
    var annotations: [OverlayAnnotationItem] = []
    /// 荧光笔单独一层，以 multiply 与冻结帧合成（与导出一致：深色文字不被染黄）
    var highlighters: [OverlayAnnotationItem] = []
    /// 实时层：正在画 / 正在拖动的标注
    var live: OverlayAnnotationItem?
    /// 选中标注的 bounds（画虚线框）
    var selectedBounds: CGRect?
    /// 选中箭头的两个端点（画端点手柄，代替虚线框）
    var arrowEndpoints: [CGPoint] = []
    /// 箭头吸附辅助线（正在画 / 改端点的箭头落在 45° 倍数上时）
    var snapGuide: AnnotationSnapGuide?
    var pixelated: CGImage?
    /// 截图翻译的译文层、流光与悬停描边
    var translation = OverlayTranslationState()
}

/// 覆盖层画布（§3.4.5）：图层宿主视图，自下而上
/// `frameLayer`（冻结帧）→ 译文层（截图翻译：译文块、流光、悬停描边）→ `dimLayer`（遮罩）
/// → `highlighterLayer`（荧光笔，multiply）→ `annotationLayer`（文档）
/// → `liveLayer`（拖拽中）→ chrome（描边、手柄、辅助线）→ 首用引导条
///
/// 荧光笔整层垫在其他标注下面，与导出（`AnnotationRenderer.draw(_:in:environment:)`）的顺序一致；
/// 正在画 / 拖动的荧光笔也放在标注层之下（实时层临时降到荧光笔层上方）。
///
/// 图层树不翻转（y 向上），换算见 `OverlaySpace`。所有更新关闭隐式动画，拖拽时每帧只改路径与小图层。
final class OverlayCanvasView: NSView {
    let space: OverlaySpace
    /// 鼠标事件交给控制器翻译
    var onMouseEvent: ((NSEvent) -> Void)?
    /// cursorUpdate 时请求控制器重设光标
    var onCursorUpdate: (() -> Void)?

    private let rootLayer = CALayer()
    private let frameLayer = CALayer()
    private let translationLayer = OverlayTranslationLayer()
    private let dimLayer = CAShapeLayer()
    private let highlighterLayer = OverlayAnnotationLayer()
    private let annotationLayer = OverlayAnnotationLayer()
    private let liveLayer = OverlayLiveStrokeLayer()
    private let chrome = OverlaySelectionChrome()
    private let onboarding = OverlayOnboardingLayer()
    private var lastDim: DimKey?

    /// 遮罩路径的输入：高亮区域 + 是否圆角
    private struct DimKey: Equatable {
        let highlight: CGRect?
        let rounded: Bool
    }

    init(frame: FrozenFrame) {
        space = OverlaySpace(screen: frame.screen)
        super.init(frame: CGRect(origin: .zero, size: frame.screen.frame.size))
        configureLayers(image: frame.image)
        // 每个会话为每块屏幕各建一个画布；同一轮事件循环内只算一次会话（首用引导计数）
        OverlayOnboarding.sessionWillBegin()
        // 图层宿主视图：先设置 layer 再打开 wantsLayer，图层树完全由这里管理
        layer = rootLayer
        wantsLayer = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    private func configureLayers(image: CGImage) {
        let bounds = CGRect(origin: .zero, size: space.size)
        rootLayer.frame = bounds
        rootLayer.backgroundColor = NSColor.black.cgColor
        frameLayer.frame = bounds
        frameLayer.contents = image
        frameLayer.contentsGravity = .resize
        frameLayer.contentsScale = space.scale
        frameLayer.magnificationFilter = .nearest
        dimLayer.frame = bounds
        dimLayer.fillRule = .evenOdd
        dimLayer.fillColor = NSColor.black.withAlphaComponent(OverlayTokens.dimAlpha).cgColor
        for layer in [highlighterLayer, annotationLayer] {
            layer.frame = bounds
            layer.contentsScale = space.scale
            layer.needsDisplayOnBoundsChange = false
        }
        highlighterLayer.compositingFilter = OverlayBlend.multiply
        liveLayer.contentsScale = space.scale
        liveLayer.isHidden = true
        chrome.root.frame = bounds
        let stack: [CALayer] = [
            frameLayer, translationLayer.root, dimLayer, highlighterLayer, annotationLayer, liveLayer, chrome.root,
            onboarding.layer,
        ]
        for (index, layer) in stack.enumerated() {
            layer.zPosition = CGFloat(index)
            rootLayer.addSublayer(layer)
        }
    }

    // MARK: - 渲染

    func apply(_ state: OverlayCanvasState) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        // 悬停在窗口上时去遮罩区域与描边一样是圆角；有选区后是直角
        updateDim(DimKey(highlight: state.highlight, rounded: state.hover != nil && state.hoverIsWindow))
        translationLayer.update(state.translation, space: space)
        let target = OverlayRenderTarget(screen: space.screen, pixelated: state.pixelated)
        highlighterLayer.update(items: state.highlighters, target: target)
        annotationLayer.update(items: state.annotations, target: target)
        liveLayer.update(item: state.live, target: target, space: space)
        let liveIsHighlighter = state.live?.annotation.tool == .highlighter
        if (liveLayer.compositingFilter != nil) != liveIsHighlighter {
            liveLayer.compositingFilter = liveIsHighlighter ? OverlayBlend.multiply : nil
            // 荧光笔在荧光笔层与标注层之间；其他标注在标注层之上
            liveLayer.zPosition = liveIsHighlighter ? highlighterLayer.zPosition + 0.5 : annotationLayer.zPosition + 1
        }
        chrome.updateHover(state.hover, style: state.hoverStyle, isWindow: state.hoverIsWindow, space: space)
        chrome.updateSelection(
            state.selection,
            handles: state.handles,
            activeHandle: state.activeHandle,
            space: space
        )
        chrome.updateAnnotationOutline(state.selectedBounds, space: space)
        chrome.updateArrowEndpoints(state.arrowEndpoints, space: space)
        chrome.updateSnapGuide(state.snapGuide, space: space)
        onboarding.update(visible: state.showsOnboarding, space: space)
        CATransaction.commit()
    }

    /// 遮罩 = 整屏 − 高亮区域（evenOdd）；高亮不在本屏时整屏压暗
    private func updateDim(_ key: DimKey) {
        guard lastDim != key else { return }
        lastDim = key
        let path = CGMutablePath()
        path.addRect(CGRect(origin: .zero, size: space.size))
        if let highlight = key.highlight, space.intersects(highlight) {
            let hole = space.layerRect(space.pixelAligned(highlight.intersection(space.screen.frame)))
            let radius = key.rounded ? OverlayTokens.windowCornerRadius : 0
            path.addPath(OverlaySelectionChrome.roundedRect(hole, radius: radius))
        }
        dimLayer.path = path
    }

    // MARK: - 鼠标

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(
            NSTrackingArea(
                rect: .zero,
                options: [.mouseMoved, .activeAlways, .inVisibleRect, .cursorUpdate],
                owner: self,
                userInfo: nil
            )
        )
    }

    /// 窗口坐标 → 全局点
    func globalPoint(for event: NSEvent) -> CGPoint {
        let local = convert(event.locationInWindow, from: nil)
        return space.globalPoint(fromView: CGPoint(x: local.x, y: space.size.height - local.y))
    }

    override func mouseMoved(with event: NSEvent) { onMouseEvent?(event) }
    override func mouseDown(with event: NSEvent) {
        // 首用引导：第一次按下鼠标即淡出（随后这次事件驱动的渲染会收起引导条）
        OverlayOnboarding.dismiss()
        onMouseEvent?(event)
    }
    override func mouseDragged(with event: NSEvent) { onMouseEvent?(event) }
    override func mouseUp(with event: NSEvent) { onMouseEvent?(event) }
    override func rightMouseDown(with event: NSEvent) { onMouseEvent?(event) }
    override func scrollWheel(with event: NSEvent) { onMouseEvent?(event) }
    override func cursorUpdate(with event: NSEvent) { onCursorUpdate?() }
}

#if DEBUG
/// 仅调试构建：端到端测试读取画布上的箭头装饰（辅助线、端点手柄）
extension OverlayCanvasView {
    var debugSnapGuideVisible: Bool {
        chrome.debugArrowChrome.debugGuideVisible
    }

    /// 可见端点手柄的中心（全局点）
    var debugArrowEndpointCenters: [CGPoint] {
        chrome.debugArrowChrome.debugEndpointPositions.map { layerPoint in
            space.globalPoint(fromView: CGPoint(x: layerPoint.x, y: space.size.height - layerPoint.y))
        }
    }
}
#endif
