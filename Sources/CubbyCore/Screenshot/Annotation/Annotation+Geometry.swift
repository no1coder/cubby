import CoreGraphics
import Foundation

/// 标注的外接矩形与命中测试
extension Annotation {
    /// 命中测试描边轮廓的斜接上限（与渲染一致）
    private static let hitMiterLimit: CGFloat = 10

    /// 当前工具与档位下的线宽（荧光笔 / 马赛克为笔刷宽）
    var lineWidth: CGFloat {
        tool.strokeWidth(for: style.weight)
    }

    /// 序号徽标直径
    var badgeDiameter: CGFloat {
        tool.badgeDiameter(for: style.weight)
    }

    /// 文字字号
    var fontSize: CGFloat {
        tool.fontSize(for: style.weight)
    }

    /// 几何外接矩形 + 线宽 / 笔刷 / 徽标半径的外扩（全局点）；空点列为 `CGRect.null`
    public var bounds: CGRect {
        switch shape {
        case .rectangle(let rect), .ellipse(let rect):
            return rect.standardized.insetBy(dx: -lineWidth / 2, dy: -lineWidth / 2)
        case .arrow(let from, let to):
            return ArrowGeometry.taperedPath(from: from, to: to, lineWidth: lineWidth).boundingBoxOfPath
        case .pen(let points), .highlighter(let points), .mosaic(let points):
            return Self.freehandBounds(points, width: lineWidth)
        case .text(let text, let origin, let maxWidth):
            return CGRect(origin: origin, size: TextLayout.size(of: text, fontSize: fontSize, maxWidth: maxWidth))
        case .number(let center):
            return Self.square(center: center, side: badgeDiameter)
        }
    }

    /// 命中测试：线条类按到线的距离（≤ 线宽 / 2 + tolerance），箭头按填充区域，
    /// 文字按排版框，序号按圆形区域；矩形 / 椭圆内部空白不命中
    public func hitTest(_ point: CGPoint, tolerance: CGFloat) -> Bool {
        switch shape {
        case .rectangle(let rect):
            return Self.strokeHit(CGPath(rect: rect.standardized, transform: nil), point, lineWidth + tolerance * 2)
        case .ellipse(let rect):
            return Self.strokeHit(
                CGPath(ellipseIn: rect.standardized, transform: nil), point, lineWidth + tolerance * 2)
        case .arrow(let from, let to):
            let path = ArrowGeometry.taperedPath(from: from, to: to, lineWidth: lineWidth)
            return path.contains(point) || Self.strokeHit(path, point, tolerance * 2)
        case .pen(let points), .highlighter(let points), .mosaic(let points):
            return Self.freehandHit(points, point, radius: lineWidth / 2 + tolerance)
        case .text:
            return bounds.insetBy(dx: -tolerance, dy: -tolerance).contains(point)
        case .number(let center):
            return Self.distance(center, point) <= badgeDiameter / 2 + tolerance
        }
    }

    // MARK: - 几何工具

    static func square(center: CGPoint, side: CGFloat) -> CGRect {
        CGRect(x: center.x - side / 2, y: center.y - side / 2, width: side, height: side)
    }

    static func distance(_ lhs: CGPoint, _ rhs: CGPoint) -> CGFloat {
        hypot(lhs.x - rhs.x, lhs.y - rhs.y)
    }

    private static func freehandBounds(_ points: [CGPoint], width: CGFloat) -> CGRect {
        switch points.count {
        case 0:
            return .null
        case 1:
            return square(center: points[0], side: width)
        default:
            let box = StrokeSmoothing.path(through: points).boundingBoxOfPath
            return box.insetBy(dx: -width / 2, dy: -width / 2)
        }
    }

    private static func freehandHit(_ points: [CGPoint], _ point: CGPoint, radius: CGFloat) -> Bool {
        switch points.count {
        case 0:
            return false
        case 1:
            return distance(points[0], point) <= radius
        default:
            return strokeHit(StrokeSmoothing.path(through: points), point, radius * 2)
        }
    }

    /// 点是否落在以 width 描边后的路径轮廓内（圆头圆角）
    private static func strokeHit(_ path: CGPath, _ point: CGPoint, _ width: CGFloat) -> Bool {
        guard width > 0 else { return false }
        let outline = path.copy(
            strokingWithWidth: width,
            lineCap: .round,
            lineJoin: .round,
            miterLimit: hitMiterLimit
        )
        return outline.contains(point)
    }
}
