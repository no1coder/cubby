import CoreGraphics
import Testing
@testable import CubbyCore

@Suite("TextBlockBuilder 行 → 翻译块")
struct TextBlockBuilderTests {
    private func line(_ text: String, x: CGFloat = 10, y: CGFloat, width: CGFloat = 200, height: CGFloat = 16)
        -> RecognizedLine
    {
        RecognizedLine(text: text, frame: CGRect(x: x, y: y, width: width, height: height))
    }

    // MARK: - 拼接

    @Test("拉丁文字行间以空格连接，去掉首尾空白")
    func latinJoin() {
        #expect(
            TextBlockBuilder.joined(["Keep files and ", "  photos in iCloud."]) == "Keep files and photos in iCloud.")
    }

    @Test("行尾连字符接小写字母时去掉连字符并直接相连")
    func dehyphenates() {
        #expect(
            TextBlockBuilder.joined(["Remove infor-", "mation you no longer need."])
                == "Remove information you no longer need.")
    }

    @Test("连字符后不是小写字母时保留连字符（复合词不加空格）；独立的破折号照常加空格")
    func keepsHyphen() {
        #expect(TextBlockBuilder.joined(["Apple-", "Watch"]) == "Apple-Watch")
        #expect(TextBlockBuilder.joined(["Pages 10-", "20"]) == "Pages 10-20")
        #expect(TextBlockBuilder.joined(["Choose one -", "or both"]) == "Choose one - or both")
    }

    @Test("CJK 行间直接相连")
    func cjkJoin() {
        #expect(
            TextBlockBuilder.joined(["\u{4F60}\u{7684} Mac \u{5DF2}\u{4F7F}", "\u{7528} 186 GB"])
                == "\u{4F60}\u{7684} Mac \u{5DF2}\u{4F7F}\u{7528} 186 GB")
        #expect(
            TextBlockBuilder.joined(["\u{30B9}\u{30C8}\u{30EC}", "\u{30FC}\u{30B8}"])
                == "\u{30B9}\u{30C8}\u{30EC}\u{30FC}\u{30B8}")
    }

    @Test("CJK 标点结尾时不加空格；CJK 与拉丁文字相接时加空格")
    func mixedJoin() {
        #expect(TextBlockBuilder.joined(["\u{6253}\u{5F00}\u{3002}", "Cubby"]) == "\u{6253}\u{5F00}\u{3002}Cubby")
        #expect(
            TextBlockBuilder.joined(["\u{6253}\u{5F00}", "Cubby \u{8BBE}\u{7F6E}"])
                == "\u{6253}\u{5F00} Cubby \u{8BBE}\u{7F6E}")
        #expect(TextBlockBuilder.joined(["Open", "\u{8BBE}\u{7F6E}"]) == "Open \u{8BBE}\u{7F6E}")
    }

    @Test("韩文按词间空格连接")
    func hangulJoin() {
        #expect(
            TextBlockBuilder.joined(["\u{C800}\u{C7A5}", "\u{acf5}\u{AC04}"]) == "\u{C800}\u{C7A5} \u{acf5}\u{AC04}")
    }

    @Test("空行被忽略")
    func skipsEmpty() {
        #expect(TextBlockBuilder.joined(["", "Hello", "  ", "world"]) == "Hello world")
        #expect(TextBlockBuilder.joined([]) == "")
    }

    // MARK: - 对齐

    @Test("单行块取 leading")
    func singleLineLeading() {
        #expect(TextBlockBuilder.alignment(of: [CGRect(x: 50, y: 0, width: 30, height: 16)]) == .leading)
    }

    @Test("左缘差 ≤ 0.5 × 中位行高 → leading")
    func leading() {
        let frames = [
            CGRect(x: 10, y: 0, width: 300, height: 16),
            CGRect(x: 17, y: 20, width: 120, height: 16),
        ]
        #expect(TextBlockBuilder.alignment(of: frames) == .leading)
    }

    @Test("中线对齐且左缘不齐 → center")
    func center() {
        let frames = [
            CGRect(x: 10, y: 0, width: 300, height: 16),
            CGRect(x: 90, y: 20, width: 142, height: 16),
        ]
        #expect(TextBlockBuilder.alignment(of: frames) == .center)
    }

    @Test("右缘对齐 → trailing")
    func trailing() {
        let frames = [
            CGRect(x: 10, y: 0, width: 300, height: 16),
            CGRect(x: 200, y: 20, width: 106, height: 16),
        ]
        #expect(TextBlockBuilder.alignment(of: frames) == .trailing)
    }

    @Test("三种都不齐时退回 leading")
    func ragged() {
        let frames = [
            CGRect(x: 10, y: 0, width: 300, height: 16),
            CGRect(x: 60, y: 20, width: 80, height: 16),
        ]
        #expect(TextBlockBuilder.alignment(of: frames) == .leading)
    }

    // MARK: - 分块与编号

    @Test("每组一块；组内行按从上到下排序并拼接")
    func groupsBecomeBlocks() {
        let blocks = TextBlockBuilder.blocks(from: [
            [line("photos in iCloud.", y: 30), line("Keep files and", y: 10)]
        ])
        #expect(blocks.count == 1)
        #expect(blocks[0].id == 0)
        #expect(blocks[0].lines.map(\.text) == ["Keep files and", "photos in iCloud."])
        #expect(blocks[0].text == "Keep files and photos in iCloud.")
        #expect(blocks[0].alignment == .leading)
    }

    @Test("id 按阅读顺序：先上后下，同一行先左后右，从 0 连续编号")
    func readingOrder() {
        let blocks = TextBlockBuilder.blocks(from: [
            [line("Bottom", y: 200)],
            [line("Right", x: 300, y: 12, width: 60)],
            [line("Left", x: 10, y: 10, width: 60)],
            [line("Middle", y: 100)],
        ])
        #expect(blocks.map(\.text) == ["Left", "Right", "Middle", "Bottom"])
        #expect(blocks.map(\.id) == [0, 1, 2, 3])
    }

    @Test("空文本的行与空组被丢弃，文本去掉首尾空白")
    func dropsEmpty() {
        let blocks = TextBlockBuilder.blocks(from: [
            [], [line("   ", y: 0)], [line(" Save ", y: 40), line("", y: 60)],
        ])
        #expect(blocks.count == 1)
        #expect(blocks[0].lines == [line("Save", y: 40)])
        #expect(blocks[0].text == "Save")
    }

    @Test("块的对齐由行框推断")
    func blockAlignment() {
        let blocks = TextBlockBuilder.blocks(from: [
            [line("Welcome to Cubby", x: 100, y: 0, width: 200), line("A tidy clipboard", x: 120, y: 20, width: 160)]
        ])
        #expect(blocks[0].alignment == .center)
    }
}
