import CoreGraphics
import Testing
@testable import CubbyCore

/// 停靠排布与详情区（预览 / 翻译卡）的位置（docs/UI-UPGRADE-PLAN.md 第 3 节）
@Suite("PanelPlacement 停靠与详情区")
struct PanelPlacementDockTests {
    /// 1440 × 900 的屏幕去掉 25pt 菜单栏
    private let screen = CGRect(x: 0, y: 0, width: 1440, height: 875)
    private let sidebarSize = CGSize(width: 400, height: 620)
    private let shelfSize = CGSize(width: 380, height: 304)

    // MARK: - 停靠

    @Test("右侧侧栏：宽度取 size.width，整高，四周留白 8")
    func dockRight() {
        let frame = PanelPlacement.docked(.right, size: sidebarSize, visibleFrame: screen)
        #expect(frame == CGRect(x: 1032, y: 8, width: 400, height: 859))
    }

    @Test("底部横条：整宽，高度取 size.height，四周留白 8")
    func dockBottom() {
        let frame = PanelPlacement.docked(.bottom, size: shelfSize, visibleFrame: screen)
        #expect(frame == CGRect(x: 8, y: 8, width: 1424, height: 304))
    }

    @Test("留白默认值为 8，可自定义")
    func customMargin() {
        #expect(PanelPlacement.dockMargin == 8)
        let frame = PanelPlacement.docked(.right, size: sidebarSize, visibleFrame: screen, margin: 0)
        #expect(frame == CGRect(x: 1040, y: 0, width: 400, height: 875))
    }

    @Test("非零原点的副屏同样贴在它自己的边缘")
    func secondaryScreen() {
        let secondary = CGRect(x: -1440, y: 100, width: 1440, height: 900)
        #expect(
            PanelPlacement.docked(.right, size: sidebarSize, visibleFrame: secondary)
                == CGRect(x: -408, y: 108, width: 400, height: 884))
        #expect(
            PanelPlacement.docked(.bottom, size: shelfSize, visibleFrame: secondary)
                == CGRect(x: -1432, y: 108, width: 1424, height: 304))
    }

    @Test("尺寸超过可见区域时收缩到可见区域内")
    func oversizedIsClamped() {
        let small = CGRect(x: 0, y: 0, width: 300, height: 200)
        #expect(
            PanelPlacement.docked(.right, size: sidebarSize, visibleFrame: small)
                == CGRect(x: 8, y: 8, width: 284, height: 184))
        #expect(
            PanelPlacement.docked(.bottom, size: shelfSize, visibleFrame: small)
                == CGRect(x: 8, y: 8, width: 284, height: 184))
    }

    @Test("可见区域小于留白时退回整个可见区域", arguments: [PanelPlacement.DockEdge.right, .bottom])
    func degenerateScreen(_ edge: PanelPlacement.DockEdge) {
        let tiny = CGRect(x: 10, y: 10, width: 12, height: 40)
        #expect(PanelPlacement.docked(edge, size: sidebarSize, visibleFrame: tiny) == tiny)
    }

    // MARK: - 详情区：浮动面板与侧栏

    @Test("浮动面板：放在左侧、顶部对齐，高度取内容高度")
    func detailBesideFloating() {
        let host = CGRect(x: 600, y: 200, width: 380, height: 620)
        let frame = PanelPlacement.detailFrame(
            width: 440, height: 300, host: host, layout: .floating, visibleFrame: screen, maxHeight: 620)
        #expect(frame == CGRect(x: 152, y: 520, width: 440, height: 300))
        #expect(frame.maxY == host.maxY)
    }

    @Test("浮动面板：左侧放不下时放到右侧")
    func detailFlipsRight() {
        let host = CGRect(x: 100, y: 200, width: 380, height: 620)
        let frame = PanelPlacement.detailFrame(
            width: 440, height: 300, host: host, layout: .floating, visibleFrame: screen, maxHeight: 620)
        #expect(frame == CGRect(x: 488, y: 520, width: 440, height: 300))
    }

    @Test("侧栏：放在左侧，最高不超过 maxHeight")
    func detailBesideSidebar() {
        let host = PanelPlacement.docked(.right, size: sidebarSize, visibleFrame: screen)
        let frame = PanelPlacement.detailFrame(
            width: 440, height: 2000, host: host, layout: .sidebar, visibleFrame: screen, maxHeight: 620)
        #expect(frame == CGRect(x: 584, y: 247, width: 440, height: 620))
        #expect(frame.maxY == host.maxY)
    }

    @Test("浮动面板：内容高于面板时以面板高度为上限")
    func detailCappedByHost() {
        let host = CGRect(x: 600, y: 300, width: 380, height: 400)
        let frame = PanelPlacement.detailFrame(
            width: 440, height: 900, host: host, layout: .floating, visibleFrame: screen, maxHeight: 620)
        #expect(frame.height == 400)
        #expect(frame.maxY == host.maxY)
    }

    // MARK: - 详情区：横条

    private var shelf: CGRect {
        PanelPlacement.docked(.bottom, size: shelfSize, visibleFrame: screen)
    }

    @Test("横条：放在正上方，水平居中于选中卡片，底部对齐横条上方")
    func detailAboveShelf() {
        let frame = PanelPlacement.detailFrame(
            width: 440, height: 400, host: shelf, layout: .shelf, visibleFrame: screen, maxHeight: 620,
            anchorX: 700)
        #expect(frame == CGRect(x: 480, y: 320, width: 440, height: 400))
        #expect(frame.minY == shelf.maxY + 8)
    }

    @Test("横条：没有选中卡片时居中于横条")
    func detailCentersOnShelf() {
        let frame = PanelPlacement.detailFrame(
            width: 440, height: 400, host: shelf, layout: .shelf, visibleFrame: screen, maxHeight: 620)
        #expect(frame.midX == shelf.midX)
    }

    @Test("横条：高度不超过横条上方剩余空间与 maxHeight 中较小者")
    func detailCappedByRoom() {
        let tall = PanelPlacement.detailFrame(
            width: 440, height: 2000, host: shelf, layout: .shelf, visibleFrame: screen, maxHeight: 620)
        // 剩余空间 875 - 312 - 8 = 555 < 620
        #expect(tall.height == 555)
        #expect(tall.maxY == screen.maxY)

        let capped = PanelPlacement.detailFrame(
            width: 440, height: 2000, host: shelf, layout: .shelf, visibleFrame: screen, maxHeight: 500)
        #expect(capped.height == 500)
    }

    @Test("横条：选中卡片贴近屏幕边缘时详情区被夹回屏幕内", arguments: [(CGFloat(40), CGFloat(0)), (1420, 1000)])
    func detailClampedHorizontally(_ anchorX: CGFloat, _ expectedX: CGFloat) {
        let frame = PanelPlacement.detailFrame(
            width: 440, height: 300, host: shelf, layout: .shelf, visibleFrame: screen, maxHeight: 620,
            anchorX: anchorX)
        #expect(frame.minX == expectedX)
        #expect(frame.minY == shelf.maxY + 8)
    }

    @Test("横条：屏幕比详情区窄时宽度收缩到屏幕宽度")
    func detailNarrowScreen() {
        let narrow = CGRect(x: 0, y: 0, width: 400, height: 875)
        let host = PanelPlacement.docked(.bottom, size: shelfSize, visibleFrame: narrow)
        let frame = PanelPlacement.detailFrame(
            width: 440, height: 300, host: host, layout: .shelf, visibleFrame: narrow, maxHeight: 620)
        #expect(frame == CGRect(x: 0, y: 320, width: 400, height: 300))
    }
}
