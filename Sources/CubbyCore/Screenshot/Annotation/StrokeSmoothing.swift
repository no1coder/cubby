import CoreGraphics
import Foundation

/// 自由笔迹（画笔 / 荧光笔 / 马赛克）的抽稀与平滑
public enum StrokeSmoothing {
    /// 单点笔迹生成的小圆半径（点）；渲染与命中时单点另按线宽画实心圆
    public static let singlePointRadius: CGFloat = 0.5

    /// 抽稀：保留首点，之后只保留与上一个保留点距离 ≥ minDistance 的点
    public static func thinned(_ points: [CGPoint], minDistance: CGFloat = 1.5) -> [CGPoint] {
        guard var last = points.first else { return [] }
        var result = [last]
        for point in points.dropFirst() where hypot(point.x - last.x, point.y - last.y) >= minDistance {
            result.append(point)
            last = point
        }
        return result
    }

    /// 经过所有点的平滑曲线：Catmull-Rom（tension 0.5 为标准形式）转三次 Bézier
    /// - 0 点为空路径；1 点为半径 `singlePointRadius` 的小圆；2 点为直线段
    public static func path(through points: [CGPoint], tension: CGFloat = 0.5) -> CGPath {
        let path = CGMutablePath()
        switch points.count {
        case 0:
            return path
        case 1:
            let center = points[0]
            let radius = singlePointRadius
            path.addEllipse(
                in: CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2)
            )
            return path
        default:
            path.move(to: points[0])
            if points.count == 2 {
                path.addLine(to: points[1])
                return path
            }
            addCatmullRom(points, tension: tension, to: path)
            return path
        }
    }

    /// 对每段 P1→P2（邻点 P0、P3，首尾重复端点）生成控制点：
    /// cp1 = P1 + (P2 − P0) × tension / 3，cp2 = P2 − (P3 − P1) × tension / 3
    private static func addCatmullRom(_ points: [CGPoint], tension: CGFloat, to path: CGMutablePath) {
        let lastIndex = points.count - 1
        for index in 0..<lastIndex {
            let p0 = points[max(index - 1, 0)]
            let p1 = points[index]
            let p2 = points[index + 1]
            let p3 = points[min(index + 2, lastIndex)]
            let control1 = CGPoint(
                x: p1.x + (p2.x - p0.x) * tension / 3,
                y: p1.y + (p2.y - p0.y) * tension / 3
            )
            let control2 = CGPoint(
                x: p2.x - (p3.x - p1.x) * tension / 3,
                y: p2.y - (p3.y - p1.y) * tension / 3
            )
            path.addCurve(to: p2, control1: control1, control2: control2)
        }
    }
}
