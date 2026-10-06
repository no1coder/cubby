import CoreGraphics
import Testing
@testable import CubbyCore

/// 词块排版（docs/TEXT-PICK-DESIGN.md §3）：横距 4、行距 6、空行多留 8；放不下换行；换行另起一行；
/// 比一行还宽的块收窄到行宽；按行二分查找命中与重绘范围
@Suite("TextPickLayout 词块排版")
struct TextPickLayoutTests {
    private let metrics = TextPickLayout.Metrics(itemSpacing: 4, lineSpacing: 6, paragraphSpacing: 8)

    private func layout(_ widths: [CGFloat], breaks: [Int] = [], width: CGFloat = 100, height: CGFloat = 22)
        -> TextPickLayout
    {
        TextPickLayout.make(
            sizes: widths.map { CGSize(width: $0, height: height) }, lineBreaks: breaks, width: width,
            metrics: metrics)
    }

    @Test("没有词块：高度 0，没有行")
    func empty() {
        let result = layout([])
        #expect(result.frames.isEmpty)
        #expect(result.rows.isEmpty)
        #expect(result.height == 0)
        #expect(result.index(at: .zero) == nil)
        #expect(result.nearestIndex(to: .zero) == nil)
        #expect(result.indices(intersecting: CGRect(x: 0, y: 0, width: 10, height: 10)).isEmpty)
    }

    @Test("同一行从左到右排，块间距 4")
    func singleRow() {
        let result = layout([20, 30])
        #expect(
            result.frames == [CGRect(x: 0, y: 0, width: 20, height: 22), CGRect(x: 24, y: 0, width: 30, height: 22)])
        #expect(result.height == 22)
        #expect(result.rows == [TextPickLayout.Row(tokens: 0..<2, minY: 0, maxY: 22)])
    }

    @Test("放不下时换行，行距 6；恰好放满不换行")
    func wraps() {
        let result = layout([40, 40, 40])
        #expect(result.frames.map(\.minY) == [0, 0, 28])
        #expect(result.frames[2].minX == 0)
        #expect(result.height == 50)
        let exact = layout([48, 48])
        #expect(exact.frames.map(\.minY) == [0, 0])
    }

    @Test("换行另起一行；两个及以上换行多留段距 8；首块前的换行不留空")
    func lineBreaks() {
        let result = layout([10, 10, 10, 10], breaks: [3, 1, 0, 2])
        #expect(result.frames.map(\.minY) == [0, 28, 28, 64])
        #expect(result.rows.map(\.tokens) == [0..<1, 1..<3, 3..<4])
        #expect(result.height == 86)
    }

    @Test("缺少的换行数按 0 处理")
    func missingLineBreaks() {
        let result = layout([10, 10], breaks: [0])
        #expect(result.frames.map(\.minY) == [0, 0])
    }

    @Test("比一行还宽的块收窄到行宽，并独占一行")
    func clampsWideTokens() {
        let result = layout([30, 250, 30])
        #expect(result.frames[1] == CGRect(x: 0, y: 28, width: 100, height: 22))
        #expect(result.frames[2].minY == 56)
    }

    @Test("容器宽度不为正时按 1 处理，不会死循环")
    func degenerateWidth() {
        let result = layout([10, 10], width: 0)
        #expect(result.frames.map(\.width) == [1, 1])
        #expect(result.rows.count == 2)
    }

    @Test("同一行高度不同时按最高的块计行高，其余块垂直居中")
    func mixedHeights() {
        let result = TextPickLayout.make(
            sizes: [CGSize(width: 10, height: 22), CGSize(width: 10, height: 18)], lineBreaks: [], width: 100,
            metrics: metrics)
        #expect(result.frames[1].minY == 2)
        #expect(result.rows[0].maxY == 22)
    }

    // MARK: - 命中

    @Test("index(at:) 只在块内命中")
    func exactHit() {
        let result = layout([40, 40, 40])
        #expect(result.index(at: CGPoint(x: 5, y: 5)) == 0)
        #expect(result.index(at: CGPoint(x: 50, y: 10)) == 1)
        #expect(result.index(at: CGPoint(x: 10, y: 30)) == 2)
        #expect(result.index(at: CGPoint(x: 42, y: 5)) == nil)
        #expect(result.index(at: CGPoint(x: 10, y: 25)) == nil)
        #expect(result.index(at: CGPoint(x: 90, y: 30)) == nil)
        #expect(result.index(at: CGPoint(x: 10, y: -1)) == nil)
    }

    @Test("nearestIndex(to:) 用于拖选：落在间隙、行外或上下方时取最近的块")
    func nearestHit() {
        let result = layout([40, 40, 40])
        #expect(result.nearestIndex(to: CGPoint(x: 41, y: 5)) == 0)
        #expect(result.nearestIndex(to: CGPoint(x: 43, y: 5)) == 1)
        #expect(result.nearestIndex(to: CGPoint(x: 99, y: 5)) == 1)
        #expect(result.nearestIndex(to: CGPoint(x: 99, y: 30)) == 2)
        #expect(result.nearestIndex(to: CGPoint(x: 50, y: -40)) == 1)
        #expect(result.nearestIndex(to: CGPoint(x: 0, y: 500)) == 2)
        #expect(result.nearestIndex(to: CGPoint(x: 50, y: 24)) == 1)
        #expect(result.nearestIndex(to: CGPoint(x: 50, y: 27)) == 2)
    }

    @Test("indices(intersecting:) 只返回与矩形相交的行里的块（重绘脏区）")
    func dirtyRect() {
        let result = layout([40, 40, 40, 40, 40])
        #expect(result.rows.count == 3)
        #expect(result.indices(intersecting: CGRect(x: 0, y: 30, width: 100, height: 5)) == 2..<4)
        #expect(result.indices(intersecting: CGRect(x: 0, y: 0, width: 100, height: 500)) == 0..<5)
        #expect(result.indices(intersecting: CGRect(x: 0, y: 23, width: 100, height: 4)).isEmpty)
        #expect(result.indices(intersecting: CGRect(x: 0, y: 600, width: 100, height: 4)).isEmpty)
        #expect(result.rowRange(intersecting: CGRect(x: 0, y: 30, width: 100, height: 40)) == 1..<3)
        #expect(result.rowRange(intersecting: CGRect(x: 0, y: 23, width: 100, height: 4)).isEmpty)
        #expect(result.row(containing: 3) == 1)
        #expect(result.row(containing: 9) == nil)
    }

    @Test("上千个块的排版与查找保持线性 / 对数")
    func manyTokens() {
        let widths = (0..<5_000).map { CGFloat(10 + $0 % 50) }
        let result = layout(widths, width: 412)
        #expect(result.frames.count == 5_000)
        let middle = result.frames[2_500]
        #expect(result.index(at: CGPoint(x: middle.midX, y: middle.midY)) == 2_500)
        #expect(result.frames.allSatisfy { $0.maxX <= 412 })
    }
}
