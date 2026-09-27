import Testing
@testable import CubbyCore

@Suite("ColorFormatter 颜色格式化")
struct ColorFormatterTests {
    private let orange = RGBAColor(red: 1, green: 136.0 / 255, blue: 0)

    @Test("HEX 为大写 #RRGGBB")
    func hex() {
        #expect(ColorFormatter.string(orange, format: .hex) == "#FF8800")
        #expect(
            ColorFormatter.string(RGBAColor(red: 10.0 / 255, green: 11.0 / 255, blue: 12.0 / 255), format: .hex)
                == "#0A0B0C")
    }

    @Test("RGB 为 CSS 格式 rgb(r, g, b)，分量为 0–255 整数")
    func rgb() {
        #expect(ColorFormatter.string(orange, format: .rgb) == "rgb(255, 136, 0)")
        #expect(ColorFormatter.string(RGBAColor(red: 0, green: 0, blue: 0), format: .rgb) == "rgb(0, 0, 0)")
    }

    @Test("分量四舍五入并夹紧到 0–255，忽略 alpha")
    func roundsAndClamps() {
        let odd = RGBAColor(red: 1.2, green: -0.3, blue: 0.5, alpha: 0.2)
        #expect(ColorFormatter.string(odd, format: .hex) == "#FF0080")
        #expect(ColorFormatter.string(odd, format: .rgb) == "rgb(255, 0, 128)")
    }

    @Test("HEX 结果可被 HexColor 解析回同一颜色")
    func hexRoundTrips() {
        let text = ColorFormatter.string(orange, format: .hex)
        #expect(HexColor.parse(text) == orange)
    }
}
