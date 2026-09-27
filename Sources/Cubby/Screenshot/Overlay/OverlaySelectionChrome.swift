import AppKit
import CubbyCore

/// 悬停高亮的样式
enum OverlayHoverStyle: Equatable {
    /// 普通悬停：2 pt 强调色描边（内缩）
    case target
    /// 纯净窗口模式：强调色半透明填充 + 粗描边 + 中央相机徽标
    case windowCapture
}

/// 画布的「装饰」图层：悬停描边、窗口模式、选区描边、8 个手柄、标注选中虚线框、箭头端点与辅助线（§2.5 / §2.10）
///
/// 全部用填充环（evenOdd）而不是居中描边：边界落在设备像素上，Retina 与 1x 屏都锐利。
@MainActor
final class OverlaySelectionChrome {
    let root = CALayer()
    private let hoverRing = CAShapeLayer()
    private let windowFill = CAShapeLayer()
    private let cameraBadge = CALayer()
    private let selectionOuter = CAShapeLayer()
    private let selectionAccent = CAShapeLayer()
    private let annotationOutline = CAShapeLayer()
    private var handleLayers: [SelectionHandle: CAShapeLayer] = [:]
    private var enlargedHandle: SelectionHandle?
    private let arrowChrome = OverlayArrowChrome(accent: OverlayColors.accent)

    init() {
        for layer in [windowFill, hoverRing, selectionOuter, selectionAccent] {
            layer.fillRule = .evenOdd
            root.addSublayer(layer)
        }
        cameraBadge.borderColor = NSColor.white.withAlphaComponent(OverlayTokens.windowModeBadgeBorderAlpha).cgColor
        cameraBadge.borderWidth = OverlayTokens.windowModeBadgeBorderWidth
        cameraBadge.cornerRadius = OverlayTokens.windowModeBadgeDiameter / 2
        cameraBadge.shadowColor = NSColor.black.cgColor
        cameraBadge.shadowOpacity = OverlayTokens.windowModeBadgeShadowOpacity
        cameraBadge.shadowRadius = OverlayTokens.windowModeBadgeShadowRadius
        cameraBadge.shadowOffset = CGSize(width: 0, height: OverlayTokens.windowModeBadgeShadowOffsetY)
        cameraBadge.shadowPath = CGPath(
            ellipseIn: CGRect(
                x: 0, y: 0, width: OverlayTokens.windowModeBadgeDiameter, height: OverlayTokens.windowModeBadgeDiameter),
            transform: nil
        )
        root.addSublayer(cameraBadge)
        annotationOutline.fillColor = nil
        annotationOutline.lineWidth = OverlayTokens.annotationOutlineWidth
        annotationOutline.lineDashPattern = OverlayTokens.annotationOutlineDash
        root.addSublayer(annotationOutline)
        for handle in SelectionHandle.allCases {
            let layer = OverlayHandleLayer.make(accent: OverlayColors.accent)
            handleLayers[handle] = layer
            root.addSublayer(layer)
        }
        root.addSublayer(arrowChrome.root)
        applyColors()
    }

    /// 强调色：每个会话创建时读取一次系统设置
    private func applyColors() {
        let accent = OverlayColors.accent
        hoverRing.fillColor = accent.cgColor
        windowFill.fillColor = accent.withAlphaComponent(OverlayTokens.windowModeFillAlpha).cgColor
        selectionAccent.fillColor = accent.cgColor
        selectionOuter.fillColor = NSColor.black.withAlphaComponent(OverlayTokens.selectionOuterAlpha).cgColor
        annotationOutline.strokeColor = accent.cgColor
        cameraBadge.contents = Self.cameraBadgeImage(accent: accent)
    }

    // MARK: - 悬停

    /// isWindow：窗口目标用 10 pt 圆角（与 macOS 窗口一致），整屏目标保持直角
    func updateHover(_ rect: CGRect?, style: OverlayHoverStyle, isWindow: Bool, space: OverlaySpace) {
        guard let rect, space.intersects(rect) else {
            hoverRing.path = nil
            windowFill.path = nil
            cameraBadge.isHidden = true
            return
        }
        let aligned = space.pixelAligned(rect.intersection(space.screen.frame))
        let layerRect = space.layerRect(aligned)
        let isWindowMode = style == .windowCapture
        let width = isWindowMode ? OverlayTokens.windowModeStrokeWidth : OverlayTokens.hoverStrokeWidth
        let radius = isWindow ? OverlayTokens.windowCornerRadius : 0
        let inner = layerRect.insetBy(dx: width, dy: width)
        hoverRing.path = Self.ring(outer: layerRect, inner: inner, radius: radius, width: width)
        windowFill.path = isWindowMode ? Self.roundedRect(inner, radius: max(radius - width, 0)) : nil
        cameraBadge.isHidden = !isWindowMode
        if isWindowMode {
            let side = OverlayTokens.windowModeBadgeDiameter
            cameraBadge.frame = CGRect(
                x: space.pixelRounded(layerRect.midX - side / 2),
                y: space.pixelRounded(layerRect.midY - side / 2),
                width: side,
                height: side
            )
            cameraBadge.contentsScale = space.scale
        }
    }

    // MARK: - 选区

    /// selection 为 nil 时清空描边与手柄；activeHandle 为悬停或正在拖动的手柄（放大显示）
    func updateSelection(
        _ selection: CGRect?,
        handles: [SelectionHandle],
        activeHandle: SelectionHandle?,
        space: OverlaySpace
    ) {
        guard let selection, space.intersects(selection) else {
            selectionAccent.path = nil
            selectionOuter.path = nil
            layoutHandles([], active: nil, selection: .zero, space: space)
            return
        }
        let aligned = space.pixelAligned(selection)
        let layerRect = space.layerRect(aligned)
        // 1 pt 强调色骑在选区边上（Retina 上内外各半，1x 屏整根在外），外侧再 1 pt 半透明黑
        let inner = (space.scale * 0.5).rounded(.down) / space.scale
        let outer = OverlayTokens.selectionStrokeWidth - inner
        let accentOuter = layerRect.insetBy(dx: -outer, dy: -outer)
        selectionAccent.path = Self.ring(outer: accentOuter, inner: layerRect.insetBy(dx: inner, dy: inner))
        let blackWidth = OverlayTokens.selectionOuterStrokeWidth
        selectionOuter.path = Self.ring(
            outer: accentOuter.insetBy(dx: -blackWidth, dy: -blackWidth),
            inner: accentOuter
        )
        layoutHandles(handles, active: activeHandle, selection: aligned, space: space)
    }

    private func layoutHandles(
        _ visible: [SelectionHandle],
        active: SelectionHandle?,
        selection: CGRect,
        space: OverlaySpace
    ) {
        let strokeWidth = OverlayHandleLayer.strokeWidth(for: space)
        for (handle, layer) in handleLayers {
            layer.lineWidth = strokeWidth
            guard visible.contains(handle) else {
                layer.isHidden = true
                continue
            }
            // 只改 position：放大中的手柄带 transform，设置 frame 的结果未定义
            let center = space.layerPoint(handle.center(in: selection))
            layer.position = CGPoint(x: space.pixelRounded(center.x), y: space.pixelRounded(center.y))
            layer.isHidden = false
        }
        setEnlargedHandle(visible.contains { $0 == active } ? active : nil)
    }

    /// 悬停 / 拖动的手柄放大到 10 pt（0.1 s；减弱动态效果时不做动画）
    private func setEnlargedHandle(_ handle: SelectionHandle?) {
        guard handle != enlargedHandle else { return }
        let scale = OverlayTokens.handleHoverDiameter / OverlayTokens.handleDiameter
        let animate = !OverlayMotion.isReduced
        if let old = enlargedHandle.flatMap({ handleLayers[$0] }) {
            setTransform(CATransform3DIdentity, on: old, animated: animate)
        }
        if let new = handle.flatMap({ handleLayers[$0] }) {
            setTransform(CATransform3DMakeScale(scale, scale, 1), on: new, animated: animate)
        }
        enlargedHandle = handle
    }

    private func setTransform(_ transform: CATransform3D, on layer: CALayer, animated: Bool) {
        if animated {
            let animation = CABasicAnimation(keyPath: "transform")
            animation.fromValue = NSValue(caTransform3D: layer.presentation()?.transform ?? layer.transform)
            animation.toValue = NSValue(caTransform3D: transform)
            animation.duration = OverlayTokens.handleAnimationDuration
            layer.add(animation, forKey: "handleScale")
        }
        layer.transform = transform
    }

    // MARK: - 标注选中框

    /// 沿标注 bounds 外扩 4 pt 的 1 pt 强调色虚线（4-2）；与 `AnnotationRenderer.drawSelectionOutline` 同一规格
    func updateAnnotationOutline(_ bounds: CGRect?, space: OverlaySpace) {
        guard let bounds, !bounds.isNull, space.intersects(bounds) else {
            annotationOutline.path = nil
            return
        }
        let inset = AnnotationRenderer.selectionOutlineInset
        let rect = space.layerRect(bounds.insetBy(dx: -inset, dy: -inset))
        let width = OverlayTokens.annotationOutlineWidth
        let minX = space.strokeCenter(rect.minX, width: width)
        let maxX = space.strokeCenter(rect.maxX, width: width)
        let minY = space.strokeCenter(rect.minY, width: width)
        let maxY = space.strokeCenter(rect.maxY, width: width)
        annotationOutline.path = CGPath(
            rect: CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY),
            transform: nil
        )
    }

    // MARK: - 箭头

    func updateArrowEndpoints(_ points: [CGPoint], space: OverlaySpace) {
        arrowChrome.updateEndpoints(points, space: space)
    }

    func updateSnapGuide(_ guide: AnnotationSnapGuide?, space: OverlaySpace) {
        arrowChrome.updateGuide(guide, space: space)
    }

    // MARK: - 工具

    /// 填充环（evenOdd）；radius > 0 时外圈为该圆角、内圈圆角减去环宽，保持环宽均匀
    private static func ring(outer: CGRect, inner: CGRect, radius: CGFloat = 0, width: CGFloat = 0) -> CGPath {
        let path = CGMutablePath()
        path.addPath(roundedRect(outer, radius: radius))
        if inner.width > 0, inner.height > 0 {
            path.addPath(roundedRect(inner, radius: max(radius - width, 0)))
        }
        return path
    }

    /// 圆角矩形；圆角不超过短边的一半
    static func roundedRect(_ rect: CGRect, radius: CGFloat) -> CGPath {
        let corner = min(radius, rect.width / 2, rect.height / 2)
        guard corner > 0 else { return CGPath(rect: rect, transform: nil) }
        return CGPath(roundedRect: rect, cornerWidth: corner, cornerHeight: corner, transform: nil)
    }

    /// 强调色圆底 + 白色相机符号
    private static func cameraBadgeImage(accent: NSColor) -> NSImage {
        let side = OverlayTokens.windowModeBadgeDiameter
        let configuration = NSImage.SymbolConfiguration(
            pointSize: OverlayTokens.windowModeBadgeSymbolSize,
            weight: .semibold
        )
        .applying(NSImage.SymbolConfiguration(paletteColors: [.white]))
        let symbol = NSImage(systemSymbolName: "camera.fill", accessibilityDescription: nil)?
            .withSymbolConfiguration(configuration)
        return NSImage(size: NSSize(width: side, height: side), flipped: false) { rect in
            accent.setFill()
            NSBezierPath(ovalIn: rect).fill()
            if let symbol {
                let size = symbol.size
                symbol.draw(
                    in: CGRect(
                        x: rect.midX - size.width / 2, y: rect.midY - size.height / 2, width: size.width,
                        height: size.height))
            }
            return true
        }
    }
}

#if DEBUG
extension OverlaySelectionChrome {
    var debugArrowChrome: OverlayArrowChrome {
        arrowChrome
    }
}
#endif
