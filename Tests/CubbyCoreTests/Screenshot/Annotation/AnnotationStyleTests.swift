import CoreGraphics
import Foundation
import Testing
@testable import CubbyCore

@Suite("AnnotationColor 标注调色板")
struct AnnotationColorTests {
    @Test(
        "8 色 HEX 与设计规格一致",
        arguments: [
            (AnnotationColor.red, "#FF3B30"),
            (.orange, "#FF9500"),
            (.yellow, "#FFCC00"),
            (.green, "#34C759"),
            (.blue, "#007AFF"),
            (.purple, "#AF52DE"),
            (.black, "#000000"),
            (.white, "#FFFFFF"),
        ]
    )
    func hexValues(color: AnnotationColor, hex: String) {
        #expect(color.hex == hex)
    }

    @Test("HEX 往返：rgba 与解析 hex 的结果一致且不透明", arguments: AnnotationColor.allCases)
    func hexRoundTrip(color: AnnotationColor) throws {
        let parsed = try #require(HexColor.parse(color.hex))
        #expect(parsed == color.rgba)
        #expect(color.rgba.alpha == 1)
    }

    @Test("顺序与 rawValue 稳定（持久化依赖 rawValue）")
    func orderAndRawValues() {
        #expect(
            AnnotationColor.allCases.map(\.rawValue) == [
                "red", "orange", "yellow", "green", "blue", "purple", "black", "white",
            ])
    }

    @Test("显示名非空且各不相同")
    func displayNames() {
        let names = AnnotationColor.allCases.map(\.displayName)
        #expect(names.allSatisfy { !$0.isEmpty })
        #expect(Set(names).count == names.count)
    }
}

@Suite("AnnotationStyle 标注样式")
struct AnnotationStyleTests {
    @Test("withColor / withWeight 返回新值，原值不变")
    func immutableUpdates() {
        let original = AnnotationStyle(color: .red, weight: .regular)
        let recolored = original.withColor(.blue)
        let reweighted = original.withWeight(.heavy)

        #expect(recolored == AnnotationStyle(color: .blue, weight: .regular))
        #expect(reweighted == AnnotationStyle(color: .red, weight: .heavy))
        #expect(original == AnnotationStyle(color: .red, weight: .regular))
    }

    @Test("JSON 编解码往返")
    func codableRoundTrip() throws {
        let style = AnnotationStyle(color: .purple, weight: .light)
        let data = try JSONEncoder().encode(style)
        #expect(try JSONDecoder().decode(AnnotationStyle.self, from: data) == style)
    }

    @Test("StrokeWeight 三档顺序与 rawValue")
    func weights() {
        #expect(StrokeWeight.allCases.map(\.rawValue) == ["light", "regular", "heavy"])
    }
}

@Suite("ScreenshotTool 工具定义")
struct ScreenshotToolTests {
    @Test(
        "快捷字符与 SF Symbol",
        arguments: [
            (ScreenshotTool.pointer, Character("v"), "cursorarrow"),
            (.rectangle, "r", "rectangle"),
            (.ellipse, "o", "oval"),
            (.arrow, "a", "arrow.up.right"),
            (.pen, "p", "pencil.line"),
            (.highlighter, "h", "highlighter"),
            (.mosaic, "m", "checkerboard.rectangle"),
            (.text, "t", "textformat"),
            (.number, "n", "1.circle"),
        ]
    )
    func shortcutsAndSymbols(tool: ScreenshotTool, character: Character, symbol: String) {
        #expect(tool.shortcutCharacter == character)
        #expect(tool.symbolName == symbol)
    }

    @Test("按字符查找工具：大小写不敏感，未知字符为 nil")
    func toolForShortcut() {
        #expect(ScreenshotTool.tool(forShortcut: "r") == .rectangle)
        #expect(ScreenshotTool.tool(forShortcut: "R") == .rectangle)
        #expect(ScreenshotTool.tool(forShortcut: "v") == .pointer)
        #expect(ScreenshotTool.tool(forShortcut: "x") == nil)
        #expect(ScreenshotTool.tool(forShortcut: "\u{0130}") == nil)
        #expect(ScreenshotTool.tool(forShortcut: "\u{00DF}") == nil)
    }

    @Test("显示名非空且各不相同")
    func displayNames() {
        let names = ScreenshotTool.allCases.map(\.displayName)
        #expect(names.allSatisfy { !$0.isEmpty })
        #expect(Set(names).count == names.count)
    }

    @Test("只有指针与马赛克不使用颜色")
    func usesColor() {
        let colorless = ScreenshotTool.allCases.filter { !$0.usesColor }
        #expect(colorless == [.pointer, .mosaic])
    }

    @Test("默认样式：荧光笔黄色，其余红色；全部 regular", arguments: ScreenshotTool.allCases)
    func defaultStyles(tool: ScreenshotTool) {
        let expectedColor: AnnotationColor = tool == .highlighter ? .yellow : .red
        #expect(tool.defaultStyle == AnnotationStyle(color: expectedColor, weight: .regular))
    }

    @Test(
        "线宽表（§2.6）",
        arguments: [
            (ScreenshotTool.rectangle, [2.0, 3, 5]),
            (.ellipse, [2, 3, 5]),
            (.arrow, [2, 3, 5]),
            (.pen, [2, 4, 6]),
            (.highlighter, [12, 18, 26]),
            (.mosaic, [12, 24, 40]),
            (.text, [0, 0, 0]),
            (.number, [0, 0, 0]),
            (.pointer, [0, 0, 0]),
        ]
    )
    func strokeWidths(tool: ScreenshotTool, expected: [Double]) {
        #expect(StrokeWeight.allCases.map { Double(tool.strokeWidth(for: $0)) } == expected)
    }

    @Test("笔刷宽：荧光笔 12 / 18 / 26，马赛克 12 / 24 / 40，其余 0")
    func brushWidths() {
        #expect(StrokeWeight.allCases.map { ScreenshotTool.highlighter.brushWidth(for: $0) } == [12, 18, 26])
        #expect(StrokeWeight.allCases.map { ScreenshotTool.mosaic.brushWidth(for: $0) } == [12, 24, 40])
        #expect(ScreenshotTool.pen.brushWidth(for: .heavy) == 0)
    }

    @Test("字号：文字 14 / 20 / 28；序号 = 直径 × 0.6；其余 0")
    func fontSizes() {
        #expect(StrokeWeight.allCases.map { ScreenshotTool.text.fontSize(for: $0) } == [14, 20, 28])
        #expect(ScreenshotTool.number.fontSize(for: .regular) == 26 * 0.6)
        #expect(ScreenshotTool.arrow.fontSize(for: .regular) == 0)
    }

    @Test("序号直径 20 / 26 / 32；其余 0")
    func badgeDiameters() {
        #expect(StrokeWeight.allCases.map { ScreenshotTool.number.badgeDiameter(for: $0) } == [20, 26, 32])
        #expect(ScreenshotTool.text.badgeDiameter(for: .regular) == 0)
    }

    @Test("档位显示名：文字用 S / M / L，其余用粗细")
    func weightDisplayNames() {
        let textNames = StrokeWeight.allCases.map { ScreenshotTool.text.weightDisplayName($0) }
        let lineNames = StrokeWeight.allCases.map { ScreenshotTool.arrow.weightDisplayName($0) }
        #expect(Set(textNames).count == 3)
        #expect(Set(lineNames).count == 3)
        #expect(textNames != lineNames)
    }
}
