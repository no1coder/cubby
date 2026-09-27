import CoreGraphics
import Testing
@testable import CubbyCore

@Suite("TranslationBarPlacement 翻译条的摆放")
struct TranslationBarPlacementTests {
    private static let screen = CGRect(x: 0, y: 0, width: 1440, height: 900)
    private static let toolbar = CGSize(width: 520, height: 36)
    private static let bar = CGSize(width: 640, height: 36)
    private static let styleBar = CGSize(width: 300, height: 36)

    private func layout(_ selection: CGRect, bar: CGSize? = bar, styleBar: CGSize? = nil) -> TranslationBarLayout {
        TranslationBarPlacement.layout(
            toolbarSize: Self.toolbar, translationBarSize: bar, styleBarSize: styleBar, selection: selection,
            screen: Self.screen)
    }

    @Test("工具栏在下方：翻译条在工具栏下方 6 pt，右对齐工具栏；样式条排在翻译条之后")
    func belowToolbar() {
        let result = layout(CGRect(x: 200, y: 150, width: 560, height: 370), styleBar: Self.styleBar)
        #expect(result.toolbar == CGRect(x: 240, y: 528, width: 520, height: 36))
        #expect(result.translationBar == CGRect(x: 120, y: 570, width: 640, height: 36))
        #expect(result.styleBar == CGRect(x: 460, y: 612, width: 300, height: 36))
    }

    @Test("工具栏在上方：翻译条在工具栏上方，样式条更上方")
    func aboveToolbar() {
        let result = layout(CGRect(x: 200, y: 500, width: 560, height: 380), styleBar: Self.styleBar)
        #expect(result.toolbar == CGRect(x: 240, y: 456, width: 520, height: 36))
        #expect(result.translationBar == CGRect(x: 120, y: 414, width: 640, height: 36))
        #expect(result.styleBar == CGRect(x: 460, y: 372, width: 300, height: 36))
    }

    @Test("选区 = 整屏：inside，翻译条在工具栏上方")
    func insideSelection() {
        let result = layout(Self.screen)
        #expect(Self.screen.contains(result.toolbar))
        #expect(result.translationBar.map { $0.maxY + TranslationBarPlacement.spacing } == result.toolbar.minY)
        #expect(result.translationBar?.maxX == result.toolbar.maxX)
        #expect(result.styleBar == nil)
    }

    @Test("只有样式条时与 ToolbarPlacement 一致；都没有时只有工具栏")
    func matchesToolbarPlacement() {
        let selection = CGRect(x: 200, y: 150, width: 560, height: 370)
        let styleOnly = layout(selection, bar: nil, styleBar: Self.styleBar)
        let reference = ToolbarPlacement.layout(
            toolbarSize: Self.toolbar, styleBarSize: Self.styleBar, selection: selection, screen: Self.screen)
        #expect(styleOnly.toolbar == reference.toolbar)
        #expect(styleOnly.styleBar == reference.styleBar)
        #expect(styleOnly.translationBar == nil)
        let none = layout(selection, bar: nil)
        #expect(none.translationBar == nil && none.styleBar == nil)
    }

    @Test("翻译条比屏幕左侧空间宽时夹回屏幕内")
    func clampedToScreen() {
        let result = layout(CGRect(x: 10, y: 150, width: 300, height: 370))
        #expect(result.translationBar?.minX == 0)
        #expect(result.translationBar?.width == Self.bar.width)
    }

    @Test("上下是否放得下按工具栏 + 翻译条 + 样式条的整体高度判断")
    func stackHeightDecidesSide() {
        // 下方剩 100 pt：工具栏 + 翻译条（8 + 36 + 6 + 36 = 86）放得下，再加样式条就放不下
        let selection = CGRect(x: 200, y: 300, width: 560, height: 500)
        #expect(layout(selection).toolbar.minY > selection.maxY)
        #expect(layout(selection, styleBar: Self.styleBar).toolbar.maxY < selection.minY)
    }
}
