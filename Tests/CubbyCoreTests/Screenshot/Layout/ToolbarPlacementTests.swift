import CoreGraphics
import Testing
@testable import CubbyCore

@Suite("ToolbarPlacement 工具栏与样式条摆放")
struct ToolbarPlacementTests {
    private static let screen = CGRect(x: 0, y: 0, width: 1440, height: 900)
    private static let toolbar = CGSize(width: 520, height: 36)
    private static let styleBar = CGSize(width: 300, height: 32)

    private func layout(_ selection: CGRect, styleBar: CGSize? = nil, screen: CGRect = screen) -> ToolbarLayout {
        ToolbarPlacement.layout(toolbarSize: Self.toolbar, styleBarSize: styleBar, selection: selection, screen: screen)
    }

    @Test("默认放在选区下方 8 pt、右对齐选区右边缘")
    func placesBelowRightAligned() {
        let result = layout(CGRect(x: 200, y: 150, width: 560, height: 370))
        #expect(result.side == .below)
        #expect(result.toolbar == CGRect(x: 240, y: 528, width: 520, height: 36))
        #expect(result.styleBar == nil)
    }

    @Test("样式条在工具栏下方 6 pt，右对齐工具栏")
    func styleBarBelowToolbar() {
        let result = layout(CGRect(x: 200, y: 150, width: 560, height: 370), styleBar: Self.styleBar)
        #expect(result.side == .below)
        #expect(result.styleBar == CGRect(x: 460, y: 570, width: 300, height: 32))
        #expect(ToolbarPlacement.styleBarSpacing == 6)
    }

    @Test("下方放不下时放到选区上方 8 pt")
    func flipsAbove() {
        let result = layout(CGRect(x: 200, y: 500, width: 560, height: 380))
        #expect(result.side == .above)
        #expect(result.toolbar == CGRect(x: 240, y: 456, width: 520, height: 36))
    }

    @Test("上方时样式条在工具栏更上方（更远离选区）")
    func styleBarAboveToolbar() {
        let result = layout(CGRect(x: 200, y: 500, width: 560, height: 380), styleBar: Self.styleBar)
        #expect(result.side == .above)
        #expect(result.styleBar == CGRect(x: 460, y: 418, width: 300, height: 32))
    }

    @Test("上下都放不下时放在选区内右下角，内缩 8 pt")
    func fallsBackInside() {
        let result = layout(CGRect(x: 100, y: 10, width: 800, height: 870))
        #expect(result.side == .inside)
        #expect(result.toolbar == CGRect(x: 372, y: 836, width: 520, height: 36))
    }

    @Test("选区 = 整屏时 inside，样式条在工具栏上方")
    func fullScreenSelection() {
        let result = layout(Self.screen, styleBar: Self.styleBar)
        #expect(result.side == .inside)
        #expect(result.toolbar == CGRect(x: 912, y: 856, width: 520, height: 36))
        #expect(result.styleBar == CGRect(x: 1132, y: 818, width: 300, height: 32))
    }

    @Test("按工具栏 + 样式条整体高度决定上下")
    func stackHeightDecidesSide() {
        let selection = CGRect(x: 200, y: 300, width: 560, height: 540)
        #expect(layout(selection).side == .below)
        let withStyle = layout(selection, styleBar: Self.styleBar)
        #expect(withStyle.side == .above)
        #expect(withStyle.toolbar == CGRect(x: 240, y: 256, width: 520, height: 36))
        #expect(withStyle.styleBar == CGRect(x: 460, y: 218, width: 300, height: 32))
    }

    @Test("选区比工具栏窄时工具栏以选区中心对齐（评审 P2-10），样式条仍右对齐工具栏")
    func centersOnNarrowSelection() {
        let result = layout(CGRect(x: 400, y: 300, width: 12, height: 10), styleBar: Self.styleBar)
        #expect(result.side == .below)
        #expect(result.toolbar == CGRect(x: 146, y: 318, width: 520, height: 36))
        #expect(result.styleBar == CGRect(x: 366, y: 360, width: 300, height: 32))
    }

    @Test("居中后超出屏幕时再夹紧")
    func centeredThenClamped() {
        let result = layout(CGRect(x: 1400, y: 300, width: 30, height: 30))
        #expect(result.toolbar == CGRect(x: 920, y: 338, width: 520, height: 36))
    }

    @Test("左边缘不足时向右推到屏幕内")
    func pushesRightAtLeftEdge() {
        let result = layout(CGRect(x: 10, y: 150, width: 100, height: 100), styleBar: Self.styleBar)
        #expect(result.toolbar == CGRect(x: 0, y: 258, width: 520, height: 36))
        #expect(result.styleBar == CGRect(x: 220, y: 300, width: 300, height: 32))
    }

    @Test("样式条比工具栏宽时同样夹紧在屏幕左边缘内")
    func wideStyleBarIsClamped() {
        let result = ToolbarPlacement.layout(
            toolbarSize: CGSize(width: 100, height: 36), styleBarSize: CGSize(width: 400, height: 32),
            selection: CGRect(x: 50, y: 100, width: 100, height: 100), screen: Self.screen)
        #expect(result.toolbar == CGRect(x: 50, y: 208, width: 100, height: 36))
        #expect(result.styleBar == CGRect(x: 0, y: 250, width: 400, height: 32))
    }

    @Test("负坐标外接屏上同样夹紧")
    func negativeOriginScreen() {
        let external = CGRect(x: 1440, y: -180, width: 1920, height: 1080)
        let result = layout(CGRect(x: 1500, y: -100, width: 400, height: 300), screen: external)
        #expect(result.side == .below)
        #expect(result.toolbar == CGRect(x: 1440, y: 208, width: 520, height: 36))
    }

    @Test("工具栏比屏幕宽时宽度被夹到屏幕宽")
    func toolbarWiderThanScreen() {
        let result = ToolbarPlacement.layout(
            toolbarSize: CGSize(width: 2000, height: 36), styleBarSize: nil,
            selection: CGRect(x: 200, y: 150, width: 560, height: 370), screen: Self.screen)
        #expect(result.toolbar == CGRect(x: 0, y: 528, width: 1440, height: 36))
    }

    @Test("自定义间距与内缩")
    func customGapAndInset() {
        let below = ToolbarPlacement.layout(
            toolbarSize: Self.toolbar, styleBarSize: nil,
            selection: CGRect(x: 200, y: 150, width: 560, height: 370), screen: Self.screen, gap: 12)
        #expect(below.toolbar.minY == 532)
        let inside = ToolbarPlacement.layout(
            toolbarSize: Self.toolbar, styleBarSize: nil, selection: Self.screen, screen: Self.screen, inset: 20)
        #expect(inside.toolbar == CGRect(x: 900, y: 844, width: 520, height: 36))
    }
}
