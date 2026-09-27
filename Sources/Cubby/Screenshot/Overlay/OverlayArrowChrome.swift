import AppKit
import CubbyCore

/// 手柄图层（选区 8 个手柄与箭头端点手柄共用）：Ø8 白填充、强调色描边、极淡阴影
@MainActor
enum OverlayHandleLayer {
    static func make(accent: NSColor) -> CAShapeLayer {
        let layer = CAShapeLayer()
        let diameter = OverlayTokens.handleDiameter
        let circle = CGPath(ellipseIn: CGRect(x: 0, y: 0, width: diameter, height: diameter), transform: nil)
        layer.path = circle
        layer.bounds = CGRect(x: 0, y: 0, width: diameter, height: diameter)
        layer.fillColor = NSColor.white.cgColor
        layer.strokeColor = accent.cgColor
        layer.lineWidth = OverlayTokens.handleStrokeWidth
        layer.shadowColor = NSColor.black.cgColor
        layer.shadowOpacity = OverlayTokens.handleShadowOpacity
        layer.shadowRadius = OverlayTokens.handleShadowRadius
        layer.shadowOffset = CGSize(width: 0, height: OverlayTokens.handleShadowOffsetY)
        // 明确阴影形状，避免每帧离屏计算
        layer.shadowPath = circle
        return layer
    }

    /// 1x 屏上 1.5 px 描边落在半像素上会糊，取 2 px
    static func strokeWidth(for space: OverlaySpace) -> CGFloat {
        space.scale < 2 ? OverlayTokens.handleStrokeWidthLowDensity : OverlayTokens.handleStrokeWidth
    }
}

/// 箭头的装饰：选中箭头的两个端点手柄（评审 P2-4）与智能吸附的延长辅助线（评审 §7）
@MainActor
final class OverlayArrowChrome {
    let root = CALayer()
    private let guide = CAShapeLayer()
    private let endpoints: [CAShapeLayer]

    init(accent: NSColor) {
        endpoints = ArrowEnd.allCases.map { _ in OverlayHandleLayer.make(accent: accent) }
        guide.fillColor = nil
        guide.strokeColor = accent.withAlphaComponent(OverlayTokens.snapGuideAlpha).cgColor
        guide.lineWidth = OverlayTokens.snapGuideWidth
        root.addSublayer(guide)
        endpoints.forEach(root.addSublayer)
    }

    /// 端点手柄：中心落在箭头两端（对齐到设备像素）
    func updateEndpoints(_ points: [CGPoint], space: OverlaySpace) {
        let width = OverlayHandleLayer.strokeWidth(for: space)
        for (index, layer) in endpoints.enumerated() {
            guard index < points.count,
                space.intersects(CGRect(origin: points[index], size: .zero).insetBy(dx: -1, dy: -1))
            else {
                layer.isHidden = true
                continue
            }
            let center = space.layerPoint(points[index])
            layer.position = CGPoint(x: space.pixelRounded(center.x), y: space.pixelRounded(center.y))
            layer.lineWidth = width
            layer.isHidden = false
        }
    }

    /// 辅助线：沿箭头所在的轴向两端延长到屏幕边缘；水平 / 竖直线按像素对齐保证 1 pt 锐利
    func updateGuide(_ snap: AnnotationSnapGuide?, space: OverlaySpace) {
        guard let snap, let segment = Self.extended(snap, across: space) else {
            guide.path = nil
            return
        }
        let width = OverlayTokens.snapGuideWidth
        var start = space.layerPoint(segment.start)
        var end = space.layerPoint(segment.end)
        if start.y == end.y {
            start.y = space.strokeCenter(start.y, width: width)
            end.y = start.y
        } else if start.x == end.x {
            start.x = space.strokeCenter(start.x, width: width)
            end.x = start.x
        }
        let path = CGMutablePath()
        path.move(to: start)
        path.addLine(to: end)
        guide.path = path
    }

    /// 过 from、to 的直线与屏幕矩形的交线段（全局点）；长度为 0 时 nil
    static func extended(_ snap: AnnotationSnapGuide, across space: OverlaySpace) -> (start: CGPoint, end: CGPoint)? {
        let dx = snap.to.x - snap.from.x
        let dy = snap.to.y - snap.from.y
        guard dx != 0 || dy != 0 else { return nil }
        let frame = space.screen.frame
        // 参数方程 p = from + t·(dx, dy)，求 t 在屏幕内的区间（Liang–Barsky）
        var low = -CGFloat.infinity
        var high = CGFloat.infinity
        let checks: [(CGFloat, CGFloat, CGFloat)] = [
            (dx, snap.from.x, frame.minX), (dx, snap.from.x, frame.maxX),
            (dy, snap.from.y, frame.minY), (dy, snap.from.y, frame.maxY),
        ]
        for (delta, origin, edge) in checks where delta != 0 {
            let t = (edge - origin) / delta
            if (edge == frame.minX || edge == frame.minY) == (delta > 0) {
                low = max(low, t)
            } else {
                high = min(high, t)
            }
        }
        guard low.isFinite, high.isFinite, low < high else { return nil }
        let point = { (t: CGFloat) in CGPoint(x: snap.from.x + t * dx, y: snap.from.y + t * dy) }
        return (point(low), point(high))
    }
}

#if DEBUG
/// 仅调试构建：端到端测试读取箭头装饰的状态
extension OverlayArrowChrome {
    /// 辅助线是否正在显示
    var debugGuideVisible: Bool {
        guide.path != nil
    }

    /// 可见端点手柄的中心（图层坐标）
    var debugEndpointPositions: [CGPoint] {
        endpoints.filter { !$0.isHidden }.map(\.position)
    }
}
#endif
