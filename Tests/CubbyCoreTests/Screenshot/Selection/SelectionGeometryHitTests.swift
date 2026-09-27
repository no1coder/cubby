import CoreGraphics
import Testing
@testable import CubbyCore

/// 命中测试用例：选区固定为 (100, 100, 200, 100)
struct HitCase: Sendable, CustomTestStringConvertible {
    let label: String
    let point: CGPoint
    let expected: SelectionHitRegion

    var testDescription: String { label }
}

@Suite("SelectionGeometry 命中、移动与夹紧")
struct SelectionGeometryHitTests {
    private static let bounds = CGRect(x: 0, y: 0, width: 1000, height: 800)
    private static let rect = CGRect(x: 100, y: 100, width: 200, height: 100)

    @Test(
        "手柄优先于边带，边带优先于内部",
        arguments: [
            HitCase(label: "左上角手柄", point: CGPoint(x: 104, y: 104), expected: .handle(.topLeft)),
            HitCase(label: "上边中点手柄", point: CGPoint(x: 205, y: 95), expected: .handle(.top)),
            HitCase(label: "右下角手柄", point: CGPoint(x: 307, y: 207), expected: .handle(.bottomRight)),
            HitCase(label: "上边带", point: CGPoint(x: 150, y: 102), expected: .handle(.top)),
            HitCase(label: "右边带", point: CGPoint(x: 298, y: 170), expected: .handle(.right)),
            HitCase(label: "下边带", point: CGPoint(x: 250, y: 203), expected: .handle(.bottom)),
            HitCase(label: "左边带", point: CGPoint(x: 97, y: 130), expected: .handle(.left)),
            HitCase(label: "内部", point: CGPoint(x: 150, y: 150), expected: .inside),
            HitCase(label: "外部", point: CGPoint(x: 50, y: 50), expected: .outside),
            HitCase(label: "手柄容差边界（恰好 8）", point: CGPoint(x: 92, y: 150), expected: .handle(.left)),
            HitCase(label: "超出手柄容差与边带", point: CGPoint(x: 91, y: 150), expected: .outside),
            HitCase(label: "边带边界（恰好 3）", point: CGPoint(x: 150, y: 103), expected: .handle(.top)),
            HitCase(label: "刚出边带进入内部", point: CGPoint(x: 150, y: 103.5), expected: .inside),
            HitCase(label: "右边缘之外的边带", point: CGPoint(x: 302, y: 130), expected: .handle(.right)),
        ])
    func hitRegions(_ item: HitCase) {
        #expect(SelectionGeometry.hitRegion(at: item.point, in: Self.rect) == item.expected)
    }

    @Test("重叠的手柄取中心最近者")
    func nearestHandleWins() {
        // 16×20 选区只有四角手柄；容差 12 时左上与右上的命中区重叠
        let small = CGRect(x: 100, y: 100, width: 16, height: 20)
        let right = SelectionGeometry.hitRegion(at: CGPoint(x: 109, y: 101), in: small, handleTolerance: 12)
        #expect(right == .handle(.topRight))
        let left = SelectionGeometry.hitRegion(at: CGPoint(x: 107, y: 101), in: small, handleTolerance: 12)
        #expect(left == .handle(.topLeft))
    }

    @Test("自定义容差与边带宽度")
    func customTolerances() {
        let point = CGPoint(x: 88, y: 150)
        #expect(SelectionGeometry.hitRegion(at: point, in: Self.rect) == .outside)
        #expect(SelectionGeometry.hitRegion(at: point, in: Self.rect, handleTolerance: 12) == .handle(.left))
        let band = CGPoint(x: 150, y: 106)
        #expect(SelectionGeometry.hitRegion(at: band, in: Self.rect) == .inside)
        #expect(SelectionGeometry.hitRegion(at: band, in: Self.rect, edgeBand: 12) == .handle(.top))
    }

    @Test("小于 16 pt 的选区没有手柄，但边带仍可拖，角落取角手柄")
    func tinySelectionUsesBands() {
        let tiny = CGRect(x: 100, y: 100, width: 12, height: 10)
        #expect(SelectionGeometry.hitRegion(at: CGPoint(x: 100, y: 100), in: tiny) == .handle(.topLeft))
        #expect(SelectionGeometry.hitRegion(at: CGPoint(x: 112, y: 110), in: tiny) == .handle(.bottomRight))
        #expect(SelectionGeometry.hitRegion(at: CGPoint(x: 100, y: 105), in: tiny) == .handle(.left))
        #expect(SelectionGeometry.hitRegion(at: CGPoint(x: 106, y: 105), in: tiny) == .inside)
        #expect(SelectionGeometry.hitRegion(at: CGPoint(x: 120, y: 105), in: tiny) == .outside)
    }

    @Test("16–40 pt 的选区只有四角手柄，边中点走边带")
    func mediumSelectionHasCornerHandlesOnly() {
        let medium = CGRect(x: 100, y: 100, width: 30, height: 30)
        #expect(SelectionGeometry.hitRegion(at: CGPoint(x: 115, y: 99), in: medium) == .handle(.top))
        #expect(SelectionGeometry.hitRegion(at: CGPoint(x: 115, y: 95), in: medium) == .outside)
        #expect(SelectionGeometry.hitRegion(at: CGPoint(x: 106, y: 106), in: medium) == .handle(.topLeft))
    }

    @Test("窄于边带的选区：两侧边带重叠时取较近的一侧")
    func overlappingBandsPickNearest() {
        let narrow = CGRect(x: 100, y: 100, width: 4, height: 100)
        #expect(SelectionGeometry.hitRegion(at: CGPoint(x: 101, y: 150), in: narrow) == .handle(.left))
        #expect(SelectionGeometry.hitRegion(at: CGPoint(x: 103, y: 150), in: narrow) == .handle(.right))
        let flat = CGRect(x: 100, y: 100, width: 100, height: 4)
        #expect(SelectionGeometry.hitRegion(at: CGPoint(x: 150, y: 101), in: flat) == .handle(.top))
        #expect(SelectionGeometry.hitRegion(at: CGPoint(x: 150, y: 103), in: flat) == .handle(.bottom))
    }

    @Test(
        "visibleHandles 三档退化",
        arguments: [
            (CGSize(width: 50, height: 50), 8),
            (CGSize(width: 40, height: 40), 8),
            (CGSize(width: 39, height: 100), 4),
            (CGSize(width: 100, height: 16), 4),
            (CGSize(width: 100, height: 15), 0),
            (CGSize(width: 0, height: 0), 0),
        ])
    func visibleHandles(_ size: CGSize, _ count: Int) {
        let handles = SelectionGeometry.visibleHandles(for: CGRect(origin: .zero, size: size))
        #expect(handles.count == count)
        let allCorners = handles.allSatisfy { $0.isCorner }
        #expect(count != 4 || allCorners)
    }

    @Test("移动后夹紧在 bounds 内")
    func movedClamps() {
        let moved = SelectionGeometry.moved(Self.rect, by: CGVector(dx: 30, dy: -20), bounds: Self.bounds)
        #expect(moved == CGRect(x: 130, y: 80, width: 200, height: 100))
        let outRight = SelectionGeometry.moved(Self.rect, by: CGVector(dx: 5000, dy: 0), bounds: Self.bounds)
        #expect(outRight == CGRect(x: 800, y: 100, width: 200, height: 100))
        let outTop = SelectionGeometry.moved(Self.rect, by: CGVector(dx: 0, dy: -5000), bounds: Self.bounds)
        #expect(outTop == CGRect(x: 100, y: 0, width: 200, height: 100))
    }

    @Test("比 bounds 大的矩形被夹到左上并缩小到 bounds")
    func oversizedClampsToTopLeft() {
        let huge = CGRect(x: 300, y: 300, width: 5000, height: 5000)
        #expect(SelectionGeometry.clamped(huge, to: Self.bounds) == Self.bounds)
        let wide = CGRect(x: -50, y: 700, width: 1200, height: 50)
        #expect(SelectionGeometry.clamped(wide, to: Self.bounds) == CGRect(x: 0, y: 700, width: 1000, height: 50))
    }

    @Test("clamped 接受反向矩形")
    func clampStandardizes() {
        let flipped = CGRect(x: 300, y: 200, width: -200, height: -100)
        #expect(SelectionGeometry.clamped(flipped, to: Self.bounds) == Self.rect)
    }

    @Test(
        "方向键微调 1 / 10 pt",
        arguments: [
            (NudgeDirection.up, CGFloat(1), CGRect(x: 100, y: 99, width: 200, height: 100)),
            (NudgeDirection.down, CGFloat(10), CGRect(x: 100, y: 110, width: 200, height: 100)),
            (NudgeDirection.left, CGFloat(10), CGRect(x: 90, y: 100, width: 200, height: 100)),
            (NudgeDirection.right, CGFloat(1), CGRect(x: 101, y: 100, width: 200, height: 100)),
        ])
    func nudges(_ direction: NudgeDirection, _ step: CGFloat, _ expected: CGRect) {
        #expect(SelectionGeometry.nudged(Self.rect, direction, step: step, bounds: Self.bounds) == expected)
    }

    @Test("贴边时微调不出界")
    func nudgeAtEdgeIsClamped() {
        let atEdge = CGRect(x: 0, y: 0, width: 50, height: 50)
        #expect(SelectionGeometry.nudged(atEdge, .left, step: 10, bounds: Self.bounds) == atEdge)
        #expect(SelectionGeometry.nudged(atEdge, .up, step: 1, bounds: Self.bounds) == atEdge)
    }
}
