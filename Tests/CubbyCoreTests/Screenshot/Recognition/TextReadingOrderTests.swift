import CoreGraphics
import Testing
@testable import CubbyCore

@Suite("TextReadingOrder 识别结果的阅读顺序")
struct TextReadingOrderTests {
    /// box 为 Vision 的归一化坐标：左下原点、y 向上
    private func fragment(_ text: String, x: CGFloat, y: CGFloat, width: CGFloat = 0.2, height: CGFloat = 0.05)
        -> TextReadingOrder.Fragment
    {
        TextReadingOrder.Fragment(text: text, box: CGRect(x: x, y: y, width: width, height: height))
    }

    @Test("空输入：空串")
    func empty() {
        #expect(TextReadingOrder.lines([]).isEmpty)
        #expect(TextReadingOrder.text([]) == "")
    }

    @Test("从上到下分行（y 越大越靠上）")
    func topToBottom() {
        let fragments = [
            fragment("third", x: 0.1, y: 0.1),
            fragment("first", x: 0.1, y: 0.8),
            fragment("second", x: 0.1, y: 0.5),
        ]
        #expect(TextReadingOrder.lines(fragments) == ["first", "second", "third"])
        #expect(TextReadingOrder.text(fragments) == "first\nsecond\nthird")
    }

    @Test("同一行内从左到右，以空格连接")
    func sameRowLeftToRight() {
        let fragments = [
            fragment("right", x: 0.6, y: 0.5),
            fragment("left", x: 0.1, y: 0.5),
            fragment("middle", x: 0.35, y: 0.5),
        ]
        #expect(TextReadingOrder.lines(fragments) == ["left middle right"])
    }

    @Test("轻微倾斜或字号不同仍算同一行")
    func toleratesSkew() {
        let fragments = [
            fragment("Name", x: 0.05, y: 0.50, height: 0.06),
            fragment("Value", x: 0.60, y: 0.52, height: 0.03),
            fragment("Next", x: 0.05, y: 0.30),
        ]
        #expect(TextReadingOrder.lines(fragments) == ["Name Value", "Next"])
    }

    @Test("垂直中心不在上一行范围内：另起一行")
    func separateRows() {
        let fragments = [
            fragment("upper", x: 0.5, y: 0.60, height: 0.05),
            fragment("lower", x: 0.1, y: 0.50, height: 0.05),
        ]
        #expect(TextReadingOrder.lines(fragments) == ["upper", "lower"])
    }

    @Test("去掉首尾空白并丢弃空片段")
    func trimsAndDropsEmpty() {
        let fragments = [
            fragment("  hello \n", x: 0.1, y: 0.5),
            fragment("   ", x: 0.5, y: 0.5),
            fragment("", x: 0.1, y: 0.2),
        ]
        #expect(TextReadingOrder.lines(fragments) == ["hello"])
    }
}
