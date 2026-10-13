import CoreGraphics
import Testing
@testable import CubbyCore

@Suite("WindowLayer 窗口层级规则")
struct WindowLayerTests {
    private typealias Fixture = TopologyFixture

    private func window(_ id: UInt32, layer: Int, frame: CGRect = CGRect(x: 100, y: 100, width: 600, height: 400))
        -> WindowCandidate
    {
        WindowCandidate(id: id, frame: frame, layer: layer, ownerPID: 77, alpha: 1)
    }

    @Test("覆盖层固定在系统屏蔽层：高于所有应用窗口，低于第三方输入法候选窗与光标")
    func overlayIsShieldingLevel() {
        #expect(WindowLayer.overlay == Int(CGShieldingWindowLevel()))
        #expect(WindowLayer.overlay > Int(CGWindowLevelForKey(.screenSaverWindow)))
        #expect(WindowLayer.overlay < 2_147_483_629)
    }

    @Test("应用的普通、浮动与高层级窗口可选；负层级、Dock / 菜单栏 / 状态栏、输入法候选窗与光标不可选")
    func selectableLayers() {
        for layer in [0, 3, 8, 19, 26, 101, 102, 1000, WindowLayer.overlay - 1] {
            #expect(WindowLayer.isSelectable(layer), "layer \(layer)")
        }
        for layer in [-2_147_483_601, -1, 20, 24, 25, WindowLayer.overlay, 2_147_483_629, 2_147_483_630] {
            #expect(!WindowLayer.isSelectable(layer), "layer \(layer)")
        }
    }

    @Test("浮动的看图窗口压在聊天窗口上：悬停命中看图窗口，Tab 才到聊天窗口")
    func floatingViewerWinsHover() {
        let viewer = window(1, layer: 3)
        let chat = window(2, layer: 0)
        let topology = ScreenTopology(screens: [Fixture.primary], windows: [viewer, chat], ownPID: Fixture.ownPID)
        let candidates = WindowHitTester.candidates(at: CGPoint(x: 300, y: 300), in: topology)
        #expect(candidates.map(\.windowID) == [viewer.id, chat.id, nil])
    }

    @Test("Telegram 的全屏看图窗口（101 级）压在主窗口上：悬停命中看图窗口")
    func telegramMediaViewer() {
        let viewer = window(1, layer: 101, frame: Fixture.primary.frame)
        let main = window(2, layer: 0)
        let topology = ScreenTopology(screens: [Fixture.primary], windows: [viewer, main], ownPID: Fixture.ownPID)
        #expect(WindowHitTester.hoverTarget(at: CGPoint(x: 300, y: 300), topology: topology)?.windowID == viewer.id)
    }
}
