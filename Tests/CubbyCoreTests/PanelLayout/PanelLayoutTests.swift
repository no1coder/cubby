import Carbon.HIToolbox
import Testing
@testable import CubbyCore

/// 面板排布（docs/UI-UPGRADE-PLAN.md 第 3、4 节）：位置到排布的映射、顶栏布局按钮的循环顺序、新快捷键默认值
@Suite("PanelPosition / PanelLayout 面板排布")
struct PanelLayoutTests {
    @Test(
        "每个位置对应的排布",
        arguments: [
            (PanelPosition.mouse, PanelLayout.floating),
            (.statusItem, .floating),
            (.center, .floating),
            (.dockRight, .sidebar),
            (.dockBottom, .shelf),
        ])
    func layoutOfPosition(_ position: PanelPosition, _ layout: PanelLayout) {
        #expect(position.layout == layout)
    }

    @Test(
        "布局按钮循环：任一浮动位置 → 右侧 → 底部",
        arguments: [PanelPosition.mouse, .statusItem, .center])
    func floatingCyclesToSidebar(_ position: PanelPosition) {
        #expect(position.cycledLayout(floatingFallback: .center) == .dockRight)
        #expect(PanelPosition.dockRight.cycledLayout(floatingFallback: position) == .dockBottom)
    }

    @Test("布局按钮从底部回到上次选的浮动位置", arguments: [PanelPosition.mouse, .statusItem, .center])
    func shelfReturnsToRememberedFloating(_ floating: PanelPosition) {
        #expect(PanelPosition.dockBottom.cycledLayout(floatingFallback: floating) == floating)
    }

    @Test("记住的浮动位置不是浮动排布时回到「鼠标旁」", arguments: [PanelPosition.dockRight, .dockBottom])
    func shelfFallsBackToMouse(_ fallback: PanelPosition) {
        #expect(PanelPosition.dockBottom.cycledLayout(floatingFallback: fallback) == .mouse)
    }

    @Test("完整循环三次回到起点")
    func fullCycle() {
        let start = PanelPosition.statusItem
        let cycled = start.cycledLayout(floatingFallback: start)
            .cycledLayout(floatingFallback: start)
            .cycledLayout(floatingFallback: start)
        #expect(cycled == start)
    }

    @Test("只有横条是横向排列")
    func horizontalLayouts() {
        #expect(PanelLayout.allCases.filter(\.isHorizontal) == [.shelf])
    }

    @Test("图片网格列数：浮动与侧栏两列，横条一排方卡")
    func imageGridColumns() {
        #expect(PanelLayout.floating.imageGridColumns == 2)
        #expect(PanelLayout.sidebar.imageGridColumns == 2)
        #expect(PanelLayout.shelf.imageGridColumns == 1)
    }

    @Test("停靠位置可从原始值恢复，显示名各不相同")
    func dockRawValues() {
        #expect(PanelPosition(rawValue: "dockRight") == .dockRight)
        #expect(PanelPosition(rawValue: "dockBottom") == .dockBottom)
        #expect(PanelPosition.dockRight.displayName != PanelPosition.dockBottom.displayName)
    }

    @Test("「只看图片」默认快捷键为 ⌃⇧V")
    func imagesDefault() {
        let hotKey = HotKey.imagesDefault
        #expect(hotKey.keyCode == UInt32(kVK_ANSI_V))
        #expect(hotKey.modifiers == UInt32(controlKey | shiftKey))
        #expect(hotKey.displayName == "⌃⇧V")
    }

    @Test("晾衣绳默认快捷键为 ⌃⌥T")
    func clotheslineDefault() {
        let hotKey = HotKey.clotheslineDefault
        #expect(hotKey.keyCode == UInt32(kVK_ANSI_T))
        #expect(hotKey.modifiers == UInt32(controlKey | optionKey))
        #expect(hotKey.displayName == "⌃⌥T")
    }

    @Test("四个默认全局快捷键互不相同")
    func defaultsAreDistinct() {
        let defaults = [HotKey.default, .screenshotDefault, .imagesDefault, .clotheslineDefault]
        #expect(Set(defaults.map(\.displayName)).count == defaults.count)
    }
}
