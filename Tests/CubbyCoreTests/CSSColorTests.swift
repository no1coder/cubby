import Testing
@testable import CubbyCore

@Suite("CSSColor 解析 rgb() / rgba()")
struct CSSColorTests {
    private let orange = RGBAColor(red: 1, green: 136.0 / 255, blue: 0)

    @Test(
        "接受的写法：逗号或空格分隔、大小写不敏感、首尾空白",
        arguments: [
            "rgb(255, 136, 0)", "rgb(255,136,0)", "RGB(255, 136, 0)", "Rgb( 255 , 136 , 0 )",
            "rgb(255 136 0)", "  rgb(255, 136, 0)\n", "rgba(255, 136, 0, 1)", "rgb(255 136 0 / 100%)",
        ])
    func accepted(_ input: String) {
        #expect(CSSColor.parse(input) == orange)
    }

    @Test(
        "alpha：0–1 小数或百分比",
        arguments: [
            ("rgba(0, 0, 0, 0.5)", 0.5), ("rgba(0,0,0,.25)", 0.25), ("rgba(0, 0, 0, 0)", 0.0),
            ("rgba(0, 0, 0, 40%)", 0.4), ("rgb(0 0 0 / 0.75)", 0.75), ("RGBA(0 0 0 / 10%)", 0.1),
            ("rgb(0, 0, 0, 1)", 1.0),
        ])
    func alpha(_ input: String, expected: Double) throws {
        let color = try #require(CSSColor.parse(input))
        #expect(abs(color.alpha - expected) < 0.0001)
        #expect(color.red == 0 && color.green == 0 && color.blue == 0)
    }

    @Test("边界值 0 与 255")
    func bounds() {
        #expect(CSSColor.parse("rgb(0, 0, 0)") == RGBAColor(red: 0, green: 0, blue: 0))
        #expect(CSSColor.parse("rgb(255, 255, 255)") == RGBAColor(red: 1, green: 1, blue: 1))
    }

    @Test(
        "拒绝：越界、数量不对、混用分隔符、非数字",
        arguments: [
            "rgb(300, 0, 0)", "rgb(256, 0, 0)", "rgb(-1, 0, 0)", "rgb(1,2)", "rgb(1, 2, 3, 4, 5)",
            "rgba(1, 2, 3, 1.5)", "rgba(1, 2, 3, 150%)", "rgba(1, 2, 3, -0.1)", "rgb(a, b, c)",
            "rgb(1,,2,3)", "rgb(255, 136 0)", "rgb(1 2 3 0.5)", "rgb(1, 2, 3 / 0.5)", "rgb()", "rgb(",
            "rgb(1, 2, 3", "rgb 1 2 3", "rgb(1, 2, 3)x", "hsl(0, 0%, 0%)", "rgb(1e2, 0, 0)", "rgb(0x10, 0, 0)",
            "rgb(1, 2, 3%)", "",
        ])
    func rejected(_ input: String) {
        #expect(CSSColor.parse(input) == nil)
    }

    @Test(
        "普通句子里出现 rgb 字样：不是颜色",
        arguments: [
            "Use rgb(255, 0, 0) for errors", "rgb(255, 0, 0) is red", "the rgb values", "rgb",
            "background: rgb(0, 0, 0);",
        ])
    func sentences(_ input: String) {
        #expect(CSSColor.parse(input) == nil)
        #expect(ContentClassifier.kind(forText: input) != .color)
    }
}

@Suite("ColorText 颜色文本（HEX 或 CSS rgb）")
struct ColorTextTests {
    @Test("HEX 与 rgb() 都能解析为同一颜色")
    func parsesBoth() {
        #expect(ColorText.parse("#FF8800") == ColorText.parse("rgb(255, 136, 0)"))
        #expect(ColorText.parse("#FF8800") != nil)
        #expect(ColorText.parse("orange") == nil)
    }

    @Test("CSS rgb() / rgba() 识别为颜色条目", arguments: ["rgb(255, 136, 0)", "RGBA(0 0 0 / 50%)", " rgb(1,2,3) "])
    func classifiesCSS(_ input: String) {
        #expect(ContentClassifier.kind(forText: input) == .color)
    }

    @Test("放大镜 RGB 读数（CSS 格式）可被解析回同一颜色，并识别为颜色")
    func magnifierReadingRoundTrips() {
        let color = RGBAColor(red: 1, green: 136.0 / 255, blue: 0)
        let text = ColorFormatter.string(color, format: .rgb)
        #expect(text == "rgb(255, 136, 0)")
        #expect(ColorText.parse(text) == color)
        #expect(ContentClassifier.kind(forText: text) == .color)
    }
}
