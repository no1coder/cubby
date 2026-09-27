import CoreGraphics
import Testing
@testable import CubbyCore

/// 手柄缩放用例：选区固定为 (100, 100, 200, 100)
struct ResizeCase: Sendable, CustomTestStringConvertible {
    let handle: SelectionHandle
    let point: CGPoint
    let expected: CGRect

    var testDescription: String { "\(handle)" }
}

@Suite("SelectionGeometry 手柄缩放")
struct SelectionGeometryResizeTests {
    private static let bounds = CGRect(x: 0, y: 0, width: 1000, height: 800)
    private static let rect = CGRect(x: 100, y: 100, width: 200, height: 100)

    private func resize(
        _ handle: SelectionHandle,
        to point: CGPoint,
        square: Bool = false,
        minSize: CGSize = SelectionGeometry.minSize
    ) -> CGRect {
        SelectionGeometry.resizing(
            Self.rect, handle: handle, to: point, constrainSquare: square, minSize: minSize, bounds: Self.bounds)
    }

    @Test(
        "8 个手柄各自只移动对应的边，对边固定",
        arguments: [
            ResizeCase(
                handle: .topLeft, point: CGPoint(x: 80, y: 90), expected: CGRect(x: 80, y: 90, width: 220, height: 110)),
            ResizeCase(
                handle: .top, point: CGPoint(x: 999, y: 90), expected: CGRect(x: 100, y: 90, width: 200, height: 110)),
            ResizeCase(
                handle: .topRight, point: CGPoint(x: 320, y: 90),
                expected: CGRect(x: 100, y: 90, width: 220, height: 110)),
            ResizeCase(
                handle: .right, point: CGPoint(x: 320, y: 999),
                expected: CGRect(x: 100, y: 100, width: 220, height: 100)),
            ResizeCase(
                handle: .bottomRight, point: CGPoint(x: 320, y: 210),
                expected: CGRect(x: 100, y: 100, width: 220, height: 110)),
            ResizeCase(
                handle: .bottom, point: CGPoint(x: 0, y: 210), expected: CGRect(x: 100, y: 100, width: 200, height: 110)
            ),
            ResizeCase(
                handle: .bottomLeft, point: CGPoint(x: 80, y: 210),
                expected: CGRect(x: 80, y: 100, width: 220, height: 110)),
            ResizeCase(
                handle: .left, point: CGPoint(x: 80, y: 0), expected: CGRect(x: 80, y: 100, width: 220, height: 100)),
        ])
    func resizesEachHandle(_ item: ResizeCase) {
        #expect(resize(item.handle, to: item.point) == item.expected)
    }

    @Test(
        "越过对边时不翻转，停在最小尺寸",
        arguments: [
            ResizeCase(
                handle: .right, point: CGPoint(x: 50, y: 150), expected: CGRect(x: 100, y: 100, width: 4, height: 100)),
            ResizeCase(
                handle: .left, point: CGPoint(x: 400, y: 150), expected: CGRect(x: 296, y: 100, width: 4, height: 100)),
            ResizeCase(
                handle: .top, point: CGPoint(x: 150, y: 500), expected: CGRect(x: 100, y: 196, width: 200, height: 4)),
            ResizeCase(
                handle: .bottom, point: CGPoint(x: 150, y: 0), expected: CGRect(x: 100, y: 100, width: 200, height: 4)),
            ResizeCase(
                handle: .bottomRight, point: CGPoint(x: 0, y: 0), expected: CGRect(x: 100, y: 100, width: 4, height: 4)),
            ResizeCase(
                handle: .topLeft, point: CGPoint(x: 900, y: 700), expected: CGRect(x: 296, y: 196, width: 4, height: 4)),
        ])
    func stopsAtMinimumSize(_ item: ResizeCase) {
        #expect(resize(item.handle, to: item.point) == item.expected)
    }

    @Test("自定义最小尺寸")
    func customMinimumSize() {
        let rect = resize(.right, to: CGPoint(x: 50, y: 150), minSize: CGSize(width: 20, height: 20))
        #expect(rect == CGRect(x: 100, y: 100, width: 20, height: 100))
    }

    @Test("拖出屏幕时夹紧到 bounds")
    func clampsToBounds() {
        #expect(resize(.right, to: CGPoint(x: 2000, y: 150)) == CGRect(x: 100, y: 100, width: 900, height: 100))
        #expect(resize(.topLeft, to: CGPoint(x: -50, y: -50)) == CGRect(x: 0, y: 0, width: 300, height: 200))
    }

    @Test("⇧ 角手柄约束为正方形（取较小边），对角固定")
    func squareCorner() {
        #expect(
            resize(.bottomRight, to: CGPoint(x: 400, y: 250), square: true)
                == CGRect(x: 100, y: 100, width: 150, height: 150))
        #expect(
            resize(.topLeft, to: CGPoint(x: 0, y: 50), square: true) == CGRect(x: 150, y: 50, width: 150, height: 150))
        #expect(
            resize(.topRight, to: CGPoint(x: 500, y: 0), square: true) == CGRect(x: 100, y: 0, width: 200, height: 200))
        #expect(
            resize(.bottomLeft, to: CGPoint(x: 0, y: 260), square: true)
                == CGRect(x: 140, y: 100, width: 160, height: 160))
    }

    @Test("⇧ 角手柄在 bounds 内夹紧后仍是正方形")
    func squareCornerClamped() {
        let rect = resize(.bottomRight, to: CGPoint(x: 1200, y: 1200), square: true)
        #expect(rect == CGRect(x: 100, y: 100, width: 700, height: 700))
    }

    @Test("⇧ 越过对边时正方形停在最小尺寸")
    func squareStopsAtMinimum() {
        #expect(
            resize(.bottomRight, to: CGPoint(x: 0, y: 0), square: true) == CGRect(x: 100, y: 100, width: 4, height: 4))
    }

    @Test("⇧ 边手柄：另一边等长并保持居中")
    func squareEdge() {
        // 右边拖到 x = 250：宽 150，高也为 150，以原中线 y = 150 居中
        #expect(
            resize(.right, to: CGPoint(x: 250, y: 0), square: true) == CGRect(x: 100, y: 75, width: 150, height: 150))
        // 下边拖到 y = 260：高 160，宽 160，以原中线 x = 200 居中
        #expect(
            resize(.bottom, to: CGPoint(x: 0, y: 260), square: true) == CGRect(x: 120, y: 100, width: 160, height: 160))
        // 左边拖到 x = 200：宽 100，右边固定
        #expect(
            resize(.left, to: CGPoint(x: 200, y: 0), square: true) == CGRect(x: 200, y: 100, width: 100, height: 100))
        // 上边拖到 y = 80：高 120，下边固定
        #expect(resize(.top, to: CGPoint(x: 0, y: 80), square: true) == CGRect(x: 140, y: 80, width: 120, height: 120))
    }

    @Test("⇧ 边手柄受垂直方向可用空间限制")
    func squareEdgeLimitedByPerpendicularSpace() {
        // 宽 500 但以 y = 150 居中最多只能高 300
        #expect(
            resize(.right, to: CGPoint(x: 600, y: 0), square: true) == CGRect(x: 100, y: 0, width: 300, height: 300))
    }

    @Test("⇧ 边手柄受水平方向可用空间限制")
    func squareEdgeLimitedByHorizontalSpace() {
        let narrow = CGRect(x: 0, y: 0, width: 300, height: 800)
        let rect = SelectionGeometry.resizing(
            CGRect(x: 100, y: 100, width: 100, height: 100), handle: .bottom, to: CGPoint(x: 0, y: 500),
            constrainSquare: true, bounds: narrow)
        // 以 x = 150 居中，左右各 150 → 最大 300；高 400 被限制到 300
        #expect(rect == CGRect(x: 0, y: 100, width: 300, height: 300))
    }

    @Test("默认最小尺寸参数")
    func defaultMinSizeArgument() {
        let rect = SelectionGeometry.resizing(
            Self.rect, handle: .right, to: CGPoint(x: 0, y: 0), constrainSquare: false, bounds: Self.bounds)
        #expect(rect.width == 4)
    }
}
