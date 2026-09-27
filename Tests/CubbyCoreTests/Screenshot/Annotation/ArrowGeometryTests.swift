import CoreGraphics
import Testing
@testable import CubbyCore

@Suite("ArrowGeometry 锥形箭头与 45° 吸附")
struct ArrowGeometryTests {
    private let tail = CGPoint(x: 20, y: 30)
    private let head = CGPoint(x: 220, y: 130)

    @Test("箭头长 = clamp(线宽 × 6, 10, 28)，翼宽 = 箭头长 × 0.8")
    func headDimensions() {
        #expect(ArrowGeometry.headLength(for: 1) == 10)
        #expect(ArrowGeometry.headLength(for: 3) == 18)
        #expect(ArrowGeometry.headLength(for: 5) == 28)
        #expect(ArrowGeometry.headWidth(for: 3) == 18 * 0.8)
    }

    @Test("路径外接矩形包含首尾两端")
    func boundingBoxContainsEnds() {
        let box = ArrowGeometry.taperedPath(from: tail, to: head, lineWidth: 3).boundingBoxOfPath
        let tolerant = box.insetBy(dx: -0.01, dy: -0.01)
        #expect(tolerant.contains(tail))
        #expect(tolerant.contains(head))
    }

    @Test("头部三角包含靠近 to 的点，箭杆包含中点")
    func headAndShaftFilled() {
        let path = ArrowGeometry.taperedPath(from: CGPoint(x: 0, y: 0), to: CGPoint(x: 100, y: 0), lineWidth: 3)
        #expect(path.contains(CGPoint(x: 99, y: 0)))
        #expect(path.contains(CGPoint(x: 88, y: 3)))
        #expect(path.contains(CGPoint(x: 50, y: 0)))
        #expect(!path.contains(CGPoint(x: 50, y: 3)))
        #expect(!path.contains(CGPoint(x: 101, y: 0)))
    }

    @Test("箭杆从尾到颈逐渐变宽")
    func shaftTapers() {
        let path = ArrowGeometry.taperedPath(from: CGPoint(x: 0, y: 0), to: CGPoint(x: 200, y: 0), lineWidth: 4)
        // 尾宽 2（半宽 1），颈宽 4.8（半宽 2.4）
        #expect(!path.contains(CGPoint(x: 5, y: 1.5)))
        #expect(path.contains(CGPoint(x: 170, y: 1.5)))
    }

    @Test("长度短于箭头长时仍有路径，且只画箭头")
    func shortArrow() {
        let path = ArrowGeometry.taperedPath(from: CGPoint(x: 0, y: 0), to: CGPoint(x: 8, y: 0), lineWidth: 3)
        #expect(!path.isEmpty)
        #expect(path.contains(CGPoint(x: 6, y: 0)))
        let box = path.boundingBoxOfPath
        #expect(box.minX >= -0.01 && box.maxX <= 8.01)
    }

    @Test("零长度箭头退化为小圆点，路径非空")
    func zeroLength() {
        let point = CGPoint(x: 5, y: 5)
        let path = ArrowGeometry.taperedPath(from: point, to: point, lineWidth: 3)
        #expect(!path.isEmpty)
        #expect(path.contains(point))
    }

    @Test(
        "snapped45：8 个方向吸附到最近的 45° 倍数，长度取投影",
        arguments: [
            (CGPoint(x: 10, y: 1), CGPoint(x: 10, y: 0)),
            (CGPoint(x: 10, y: 9), CGPoint(x: 9.5, y: 9.5)),
            (CGPoint(x: 1, y: 10), CGPoint(x: 0, y: 10)),
            (CGPoint(x: -9, y: 10), CGPoint(x: -9.5, y: 9.5)),
            (CGPoint(x: -10, y: 2), CGPoint(x: -10, y: 0)),
            (CGPoint(x: -9, y: -10), CGPoint(x: -9.5, y: -9.5)),
            (CGPoint(x: 0.5, y: -10), CGPoint(x: 0, y: -10)),
            (CGPoint(x: 10, y: -9), CGPoint(x: 9.5, y: -9.5)),
        ]
    )
    func snapsEightDirections(point: CGPoint, expected: CGPoint) {
        let anchor = CGPoint(x: 100, y: 100)
        let moved = CGPoint(x: anchor.x + point.x, y: anchor.y + point.y)
        let snapped = ArrowGeometry.snapped45(from: anchor, to: moved)
        #expect(abs(snapped.x - (anchor.x + expected.x)) < 0.0001)
        #expect(abs(snapped.y - (anchor.y + expected.y)) < 0.0001)
    }

    @Test("snapped45：起点与终点重合时返回起点")
    func snapIdentity() {
        let anchor = CGPoint(x: 3, y: 4)
        #expect(ArrowGeometry.snapped45(from: anchor, to: anchor) == anchor)
    }
}

@Suite("StrokeSmoothing 抽稀与平滑")
struct StrokeSmoothingTests {
    @Test("抽稀：与上一个保留点距离 < 1.5 的点被丢弃，首点保留")
    func thinning() {
        let points = [
            CGPoint(x: 0, y: 0), CGPoint(x: 1, y: 0), CGPoint(x: 1.6, y: 0),
            CGPoint(x: 2.5, y: 0), CGPoint(x: 3.2, y: 0), CGPoint(x: 10, y: 0),
        ]
        #expect(
            StrokeSmoothing.thinned(points) == [
                CGPoint(x: 0, y: 0), CGPoint(x: 1.6, y: 0), CGPoint(x: 3.2, y: 0), CGPoint(x: 10, y: 0),
            ])
    }

    @Test("抽稀阈值边界：恰好 1.5 保留，略小于丢弃")
    func thinningThreshold() {
        let kept = StrokeSmoothing.thinned([CGPoint(x: 0, y: 0), CGPoint(x: 0, y: 1.5)])
        let dropped = StrokeSmoothing.thinned([CGPoint(x: 0, y: 0), CGPoint(x: 0, y: 1.49)])
        #expect(kept.count == 2)
        #expect(dropped == [CGPoint(x: 0, y: 0)])
    }

    @Test("抽稀：自定义阈值、空与单点")
    func thinningEdgeCases() {
        #expect(StrokeSmoothing.thinned([]).isEmpty)
        #expect(StrokeSmoothing.thinned([CGPoint(x: 1, y: 1)]) == [CGPoint(x: 1, y: 1)])
        let points = [CGPoint(x: 0, y: 0), CGPoint(x: 4, y: 0), CGPoint(x: 6, y: 0)]
        #expect(StrokeSmoothing.thinned(points, minDistance: 5) == [CGPoint(x: 0, y: 0), CGPoint(x: 6, y: 0)])
    }

    @Test("0 点 → 空路径")
    func emptyPath() {
        #expect(StrokeSmoothing.path(through: []).isEmpty)
    }

    @Test("1 点 → 以该点为圆心的小圆")
    func singlePointCircle() {
        let path = StrokeSmoothing.path(through: [CGPoint(x: 10, y: 20)])
        let box = path.boundingBoxOfPath
        #expect(!path.isEmpty)
        #expect(abs(box.midX - 10) < 0.001 && abs(box.midY - 20) < 0.001)
        #expect(box.width <= 2)
    }

    @Test("2 点 → 直线段")
    func twoPointsLine() {
        let path = StrokeSmoothing.path(through: [CGPoint(x: 0, y: 0), CGPoint(x: 10, y: 5)])
        let elements = PathElements(path)
        #expect(elements.kinds == [.moveToPoint, .addLineToPoint])
        #expect(elements.endPoints == [CGPoint(x: 0, y: 0), CGPoint(x: 10, y: 5)])
    }

    @Test("≥ 3 点 → 三次 Bézier，曲线经过所有输入点")
    func curvePassesThroughPoints() {
        let points = [CGPoint(x: 0, y: 0), CGPoint(x: 20, y: 30), CGPoint(x: 50, y: 10), CGPoint(x: 80, y: 40)]
        let elements = PathElements(StrokeSmoothing.path(through: points))
        #expect(elements.kinds == [.moveToPoint, .addCurveToPoint, .addCurveToPoint, .addCurveToPoint])
        #expect(elements.endPoints == points)
    }

    @Test("张力 0.5 的 Catmull-Rom 控制点")
    func controlPoints() {
        let points = [CGPoint(x: 0, y: 0), CGPoint(x: 30, y: 0), CGPoint(x: 60, y: 30)]
        let elements = PathElements(StrokeSmoothing.path(through: points))
        // 第一段：P0 = P1 = (0,0)，P2 = (30,0)，P3 = (60,30)
        // cp1 = P1 + (P2 − P0) / 6 = (5, 0)；cp2 = P2 − (P3 − P1) / 6 = (20, −5)
        #expect(elements.controlPoints[1] == [CGPoint(x: 5, y: 0), CGPoint(x: 20, y: -5), CGPoint(x: 30, y: 0)])
    }

    @Test("张力 0 退化为折线（控制点与端点重合）")
    func zeroTension() {
        let points = [CGPoint(x: 0, y: 0), CGPoint(x: 30, y: 0), CGPoint(x: 60, y: 30)]
        let elements = PathElements(StrokeSmoothing.path(through: points, tension: 0))
        #expect(elements.controlPoints[1] == [CGPoint(x: 0, y: 0), CGPoint(x: 30, y: 0), CGPoint(x: 30, y: 0)])
    }
}

/// 把 CGPath 拆成元素，便于断言
struct PathElements {
    var kinds: [CGPathElementType] = []
    var controlPoints: [[CGPoint]] = []

    init(_ path: CGPath) {
        var kinds: [CGPathElementType] = []
        var points: [[CGPoint]] = []
        path.applyWithBlock { pointer in
            let element = pointer.pointee
            kinds.append(element.type)
            let count: Int
            switch element.type {
            case .moveToPoint, .addLineToPoint: count = 1
            case .addQuadCurveToPoint: count = 2
            case .addCurveToPoint: count = 3
            case .closeSubpath: count = 0
            @unknown default: count = 0
            }
            points.append((0..<count).map { element.points[$0] })
        }
        self.kinds = kinds
        self.controlPoints = points
    }

    /// 每个元素的终点（closeSubpath 跳过）
    var endPoints: [CGPoint] {
        controlPoints.compactMap(\.last)
    }
}
