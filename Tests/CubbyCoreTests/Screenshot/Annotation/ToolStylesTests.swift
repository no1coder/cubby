import Foundation
import Testing
@testable import CubbyCore

@Suite("ToolStyles 每工具样式记忆")
struct ToolStylesTests {
    @Test("默认值 = 每个工具的 defaultStyle", arguments: ScreenshotTool.allCases)
    func defaults(tool: ScreenshotTool) {
        #expect(ToolStyles.default.style(for: tool) == tool.defaultStyle)
    }

    @Test("setting 返回新值，只改指定工具，原值不变")
    func settingIsImmutable() {
        let blue = AnnotationStyle(color: .blue, weight: .heavy)
        let updated = ToolStyles.default.setting(blue, for: .arrow)

        #expect(updated.style(for: .arrow) == blue)
        #expect(updated.style(for: .rectangle) == ScreenshotTool.rectangle.defaultStyle)
        #expect(ToolStyles.default.style(for: .arrow) == ScreenshotTool.arrow.defaultStyle)
        #expect(updated != ToolStyles.default)
    }

    @Test("设回默认样式后与 default 相等")
    func equalityIsByValue() {
        let styles = ToolStyles.default
            .setting(AnnotationStyle(color: .green, weight: .light), for: .pen)
            .setting(ScreenshotTool.pen.defaultStyle, for: .pen)
        #expect(styles == ToolStyles.default)
    }

    @Test("encoded 后 decode 往返一致")
    func roundTrip() {
        let styles = ToolStyles.default
            .setting(AnnotationStyle(color: .white, weight: .heavy), for: .text)
            .setting(AnnotationStyle(color: .green, weight: .light), for: .highlighter)
        #expect(ToolStyles.decode(styles.encoded()) == styles)
    }

    @Test("编码为以工具 rawValue 为键的有序 JSON")
    func encodedShape() throws {
        let json = try #require(String(data: ToolStyles.default.encoded(), encoding: .utf8))
        #expect(json.contains("\"arrow\":{\"color\":\"red\",\"weight\":\"regular\"}"))
        #expect(json.contains("\"highlighter\":{\"color\":\"yellow\",\"weight\":\"regular\"}"))
        #expect(ToolStyles.default.encoded() == ToolStyles.default.encoded())
    }

    @Test(
        "nil、损坏数据、非对象 JSON 一律回退默认值",
        arguments: [
            nil,
            Data(),
            Data("not json".utf8),
            Data("[1, 2, 3]".utf8),
            Data("\"arrow\"".utf8),
        ]
    )
    func invalidDataFallsBack(data: Data?) {
        #expect(ToolStyles.decode(data) == .default)
    }

    @Test("未知工具键忽略，已知键照常生效")
    func unknownToolKeysIgnored() {
        let json = """
            {"lasso": {"color": "blue", "weight": "heavy"},
             "arrow": {"color": "green", "weight": "light"}}
            """
        let styles = ToolStyles.decode(Data(json.utf8))
        #expect(styles.style(for: .arrow) == AnnotationStyle(color: .green, weight: .light))
        #expect(styles.style(for: .rectangle) == ScreenshotTool.rectangle.defaultStyle)
    }

    @Test("单个条目无效（未知颜色 / 档位 / 类型错误）时只跳过该条目")
    func invalidEntriesSkipped() {
        let json = """
            {"arrow": {"color": "pink", "weight": "heavy"},
             "pen": {"color": "blue", "weight": "huge"},
             "text": 42,
             "number": {"color": "purple", "weight": "heavy"}}
            """
        let styles = ToolStyles.decode(Data(json.utf8))
        #expect(styles.style(for: .arrow) == ScreenshotTool.arrow.defaultStyle)
        #expect(styles.style(for: .pen) == ScreenshotTool.pen.defaultStyle)
        #expect(styles.style(for: .text) == ScreenshotTool.text.defaultStyle)
        #expect(styles.style(for: .number) == AnnotationStyle(color: .purple, weight: .heavy))
    }

    @Test("显式 null 条目只跳过自身")
    func nullEntriesSkipped() {
        let json = """
            {"arrow": null, "pen": {"color": "blue", "weight": "heavy"}}
            """
        let styles = ToolStyles.decode(Data(json.utf8))
        #expect(styles.style(for: .arrow) == ScreenshotTool.arrow.defaultStyle)
        #expect(styles.style(for: .pen) == AnnotationStyle(color: .blue, weight: .heavy))
    }

    @Test("缺失的工具使用默认样式")
    func missingToolsUseDefaults() {
        let styles = ToolStyles.decode(Data("{}".utf8))
        #expect(styles == .default)
    }

    @Test("可作为 Codable 嵌入其他结构")
    func nestedCodable() throws {
        struct Wrapper: Codable, Equatable {
            let styles: ToolStyles
        }
        let wrapper = Wrapper(
            styles: ToolStyles.default.setting(AnnotationStyle(color: .black, weight: .heavy), for: .rectangle))
        let data = try JSONEncoder().encode(wrapper)
        #expect(try JSONDecoder().decode(Wrapper.self, from: data) == wrapper)
    }
}
