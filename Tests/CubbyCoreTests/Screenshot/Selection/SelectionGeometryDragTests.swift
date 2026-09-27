import CoreGraphics
import Testing
@testable import CubbyCore

/// 拖拽归一化用例：起点固定为 (100, 100)
struct NormalizeCase: Sendable, CustomTestStringConvertible {
    let label: String
    let point: CGPoint
    let square: Bool
    let center: Bool
    let expected: CGRect

    var testDescription: String { label }
}

@Suite("SelectionGeometry 拖拽创建选区")
struct SelectionGeometryDragTests {
    private static let bounds = CGRect(x: 0, y: 0, width: 1000, height: 800)
    private static let anchor = CGPoint(x: 100, y: 100)

    @Test(
        "四个象限归一化、正方形与中心扩展",
        arguments: [
            NormalizeCase(
                label: "右下", point: CGPoint(x: 150, y: 180), square: false, center: false,
                expected: CGRect(x: 100, y: 100, width: 50, height: 80)),
            NormalizeCase(
                label: "左下", point: CGPoint(x: 50, y: 180), square: false, center: false,
                expected: CGRect(x: 50, y: 100, width: 50, height: 80)),
            NormalizeCase(
                label: "左上", point: CGPoint(x: 50, y: 20), square: false, center: false,
                expected: CGRect(x: 50, y: 20, width: 50, height: 80)),
            NormalizeCase(
                label: "右上", point: CGPoint(x: 150, y: 20), square: false, center: false,
                expected: CGRect(x: 100, y: 20, width: 50, height: 80)),
            NormalizeCase(
                label: "⇧ 右下", point: CGPoint(x: 160, y: 130), square: true, center: false,
                expected: CGRect(x: 100, y: 100, width: 30, height: 30)),
            NormalizeCase(
                label: "⇧ 左下", point: CGPoint(x: 40, y: 130), square: true, center: false,
                expected: CGRect(x: 70, y: 100, width: 30, height: 30)),
            NormalizeCase(
                label: "⇧ 左上", point: CGPoint(x: 40, y: 70), square: true, center: false,
                expected: CGRect(x: 70, y: 70, width: 30, height: 30)),
            NormalizeCase(
                label: "⇧ 右上", point: CGPoint(x: 160, y: 70), square: true, center: false,
                expected: CGRect(x: 100, y: 70, width: 30, height: 30)),
            NormalizeCase(
                label: "⌥ 中心扩展", point: CGPoint(x: 130, y: 120), square: false, center: true,
                expected: CGRect(x: 70, y: 80, width: 60, height: 40)),
            NormalizeCase(
                label: "⇧⌥ 中心正方形", point: CGPoint(x: 130, y: 120), square: true, center: true,
                expected: CGRect(x: 80, y: 80, width: 40, height: 40)),
            NormalizeCase(
                label: "零位移", point: CGPoint(x: 100, y: 100), square: false, center: false,
                expected: CGRect(x: 100, y: 100, width: 0, height: 0)),
        ])
    func normalizes(_ item: NormalizeCase) {
        let rect = SelectionGeometry.normalized(
            from: Self.anchor,
            to: item.point,
            constrainSquare: item.square,
            fromCenter: item.center,
            bounds: Self.bounds
        )
        #expect(rect == item.expected)
    }

    @Test("拖出屏幕时夹紧到 bounds")
    func clampsToBounds() {
        let rect = SelectionGeometry.normalized(
            from: Self.anchor, to: CGPoint(x: 1200, y: 900),
            constrainSquare: false, fromCenter: false, bounds: Self.bounds)
        #expect(rect == CGRect(x: 100, y: 100, width: 900, height: 700))
    }

    @Test("夹紧后仍是正方形（取较小边）")
    func clampedSquareStaysSquare() {
        let rect = SelectionGeometry.normalized(
            from: CGPoint(x: 900, y: 100), to: CGPoint(x: 1100, y: 400),
            constrainSquare: true, fromCenter: false, bounds: Self.bounds)
        #expect(rect == CGRect(x: 900, y: 100, width: 100, height: 100))
    }

    @Test("中心扩展按到最近边的距离对称夹紧")
    func centerExpansionClampsSymmetrically() {
        let rect = SelectionGeometry.normalized(
            from: CGPoint(x: 50, y: 400), to: CGPoint(x: 150, y: 450),
            constrainSquare: false, fromCenter: true, bounds: Self.bounds)
        #expect(rect == CGRect(x: 0, y: 350, width: 100, height: 100))
    }

    @Test("⇧⌥ 夹紧后仍是以起点为中心的正方形")
    func centeredSquareClamps() {
        let rect = SelectionGeometry.normalized(
            from: CGPoint(x: 50, y: 400), to: CGPoint(x: 250, y: 600),
            constrainSquare: true, fromCenter: true, bounds: Self.bounds)
        #expect(rect == CGRect(x: 0, y: 350, width: 100, height: 100))
    }

    @Test("起点在 bounds 外时先夹回 bounds")
    func anchorOutsideBoundsIsClamped() {
        let rect = SelectionGeometry.normalized(
            from: CGPoint(x: -10, y: 100), to: CGPoint(x: 50, y: 150),
            constrainSquare: false, fromCenter: false, bounds: Self.bounds)
        #expect(rect == CGRect(x: 0, y: 100, width: 50, height: 50))
    }

    @Test("负坐标外接屏同样正确")
    func negativeOriginBounds() {
        let external = CGRect(x: 1440, y: -180, width: 1920, height: 1080)
        let rect = SelectionGeometry.normalized(
            from: CGPoint(x: 1500, y: -100), to: CGPoint(x: 1400, y: -300),
            constrainSquare: false, fromCenter: false, bounds: external)
        #expect(rect == CGRect(x: 1440, y: -180, width: 60, height: 80))
    }

    @Test("常量符合规格")
    func constants() {
        #expect(SelectionGeometry.minSize == CGSize(width: 4, height: 4))
        #expect(SelectionGeometry.dragThreshold == 4)
    }
}
