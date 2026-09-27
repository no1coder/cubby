import CoreGraphics
import Testing
@testable import CubbyCore

/// 一个手柄及其期望移动的边
struct HandleEdgeCase: Sendable, CustomTestStringConvertible {
    let handle: SelectionHandle
    let left: Bool
    let right: Bool
    let top: Bool
    let bottom: Bool
    let center: CGPoint

    var testDescription: String { "\(handle)" }
}

@Suite("SelectionHandle 选区手柄")
struct SelectionHandleTests {
    /// 选区 (10, 20, 100, 50)：minX 10、maxX 110、minY 20、maxY 70
    private static let rect = CGRect(x: 10, y: 20, width: 100, height: 50)

    @Test(
        "每个手柄移动的边与中心点",
        arguments: [
            HandleEdgeCase(
                handle: .topLeft, left: true, right: false, top: true, bottom: false, center: CGPoint(x: 10, y: 20)),
            HandleEdgeCase(
                handle: .top, left: false, right: false, top: true, bottom: false, center: CGPoint(x: 60, y: 20)),
            HandleEdgeCase(
                handle: .topRight, left: false, right: true, top: true, bottom: false, center: CGPoint(x: 110, y: 20)),
            HandleEdgeCase(
                handle: .right, left: false, right: true, top: false, bottom: false, center: CGPoint(x: 110, y: 45)),
            HandleEdgeCase(
                handle: .bottomRight, left: false, right: true, top: false, bottom: true,
                center: CGPoint(x: 110, y: 70)),
            HandleEdgeCase(
                handle: .bottom, left: false, right: false, top: false, bottom: true, center: CGPoint(x: 60, y: 70)),
            HandleEdgeCase(
                handle: .bottomLeft, left: true, right: false, top: false, bottom: true, center: CGPoint(x: 10, y: 70)),
            HandleEdgeCase(
                handle: .left, left: true, right: false, top: false, bottom: false, center: CGPoint(x: 10, y: 45)),
        ])
    func edgesAndCenter(_ item: HandleEdgeCase) {
        #expect(item.handle.movesLeftEdge == item.left)
        #expect(item.handle.movesRightEdge == item.right)
        #expect(item.handle.movesTopEdge == item.top)
        #expect(item.handle.movesBottomEdge == item.bottom)
        #expect(item.handle.center(in: Self.rect) == item.center)
    }

    @Test("四个角手柄与四个边手柄")
    func cornersAndEdges() {
        let corners = SelectionHandle.allCases.filter(\.isCorner)
        #expect(corners == [.topLeft, .topRight, .bottomRight, .bottomLeft])
        #expect(SelectionHandle.allCases.count == 8)
    }

    @Test("反向矩形按标准化后的边计算中心")
    func centerUsesStandardizedRect() {
        let flipped = CGRect(x: 110, y: 70, width: -100, height: -50)
        #expect(SelectionHandle.topLeft.center(in: flipped) == CGPoint(x: 10, y: 20))
    }

    @Test(
        "方向键向量（y 向下）",
        arguments: [
            (NudgeDirection.up, CGVector(dx: 0, dy: -1)),
            (NudgeDirection.down, CGVector(dx: 0, dy: 1)),
            (NudgeDirection.left, CGVector(dx: -1, dy: 0)),
            (NudgeDirection.right, CGVector(dx: 1, dy: 0)),
        ])
    func nudgeVectors(_ direction: NudgeDirection, _ expected: CGVector) {
        #expect(direction.vector == expected)
    }
}
