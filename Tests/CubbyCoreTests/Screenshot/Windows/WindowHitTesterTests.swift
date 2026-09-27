import CoreGraphics
import Testing
@testable import CubbyCore

@Suite("WindowHitTester 悬停窗口识别")
struct WindowHitTesterTests {
    private typealias Fixture = TopologyFixture

    private func topmost(_ point: CGPoint, in windows: [WindowCandidate] = Fixture.windows) -> WindowCandidate? {
        WindowHitTester.topmost(at: point, in: windows, excludingPID: Fixture.ownPID)
    }

    @Test("z 序取最前的普通窗口")
    func picksFrontmost() {
        let back = WindowCandidate(
            id: 1, frame: CGRect(x: 0, y: 0, width: 500, height: 500), layer: 0, ownerPID: 1, alpha: 1)
        let front = WindowCandidate(
            id: 2, frame: CGRect(x: 100, y: 100, width: 100, height: 100), layer: 0, ownerPID: 2, alpha: 1)
        #expect(topmost(CGPoint(x: 150, y: 150), in: [front, back]) == front)
        #expect(topmost(CGPoint(x: 50, y: 50), in: [front, back]) == back)
    }

    @Test("跳过自身进程的窗口，命中其后的窗口")
    func skipsOwnWindows() {
        #expect(topmost(CGPoint(x: 400, y: 400)) == Fixture.editor)
    }

    @Test("过滤 layer ≠ 0、全透明与小于 2×2 的窗口")
    func filtersNonNormalWindows() {
        #expect(topmost(CGPoint(x: 1000, y: 10)) == nil)
        #expect(topmost(CGPoint(x: 850, y: 650)) == nil)
        #expect(topmost(CGPoint(x: 900.5, y: 750.5)) == nil)
    }

    @Test("恰好 2×2 的窗口可以命中")
    func acceptsTwoByTwo() {
        let small = WindowCandidate(
            id: 3, frame: CGRect(x: 10, y: 10, width: 2, height: 2), layer: 0, ownerPID: 3, alpha: 0.5)
        #expect(topmost(CGPoint(x: 11, y: 11), in: [small]) == small)
    }

    @Test("右 / 下边缘不属于窗口")
    func excludesMaxEdges() {
        #expect(topmost(CGPoint(x: 700, y: 150)) == nil)
        #expect(topmost(CGPoint(x: 699.9, y: 299.9)) == Fixture.editor)
    }

    @Test("命中窗口：选区 = 窗口 frame")
    func hoverWindow() {
        let target = WindowHitTester.hoverTarget(at: Fixture.editorPoint, topology: Fixture.twoScreens)
        #expect(target == .window(Fixture.editor, screen: Fixture.primary))
        #expect(target?.selectionRect == Fixture.editor.frame)
        #expect(target?.screen == Fixture.primary)
    }

    @Test("跨屏窗口：选区 = 窗口 ∩ 光标所在屏幕")
    func spanningWindowIsIntersected() {
        let onPrimary = WindowHitTester.hoverTarget(at: CGPoint(x: 1300, y: 300), topology: Fixture.twoScreens)
        #expect(onPrimary?.selectionRect == CGRect(x: 1200, y: 200, width: 240, height: 300))
        #expect(onPrimary?.screen == Fixture.primary)
        let onExternal = WindowHitTester.hoverTarget(at: CGPoint(x: 1500, y: 300), topology: Fixture.twoScreens)
        #expect(onExternal?.selectionRect == CGRect(x: 1440, y: 200, width: 360, height: 300))
        #expect(onExternal?.screen == Fixture.external)
    }

    @Test("没有窗口时为整屏")
    func desktopIsWholeScreen() {
        let target = WindowHitTester.hoverTarget(at: Fixture.desktopPoint, topology: Fixture.twoScreens)
        #expect(target == .screen(Fixture.primary))
        #expect(target?.selectionRect == Fixture.primary.frame)
        #expect(target?.screen == Fixture.primary)
    }

    @Test("菜单栏（layer 25）上等于整屏")
    func menuBarIsWholeScreen() {
        let target = WindowHitTester.hoverTarget(at: CGPoint(x: 1000, y: 10), topology: Fixture.twoScreens)
        #expect(target == .screen(Fixture.primary))
    }

    @Test("外接屏桌面为外接整屏")
    func externalDesktop() {
        let target = WindowHitTester.hoverTarget(at: CGPoint(x: 3000, y: 700), topology: Fixture.twoScreens)
        #expect(target == .screen(Fixture.external))
        #expect(target?.selectionRect == Fixture.external.frame)
    }

    @Test("屏幕之间的空隙没有悬停目标")
    func gapHasNoTarget() {
        #expect(WindowHitTester.hoverTarget(at: Fixture.gapPoint, topology: Fixture.twoScreens) == nil)
        #expect(WindowHitTester.hoverTarget(at: .zero, topology: Fixture.empty) == nil)
    }

    @Test("candidates：光标下所有窗口按 z 序从前往后，最后是整屏")
    func candidatesInZOrder() {
        let stack = WindowHitTester.candidates(at: Fixture.stackPoint, in: Fixture.twoScreens)
        #expect(
            stack == [
                .window(Fixture.inspector, screen: Fixture.primary),
                .window(Fixture.editor, screen: Fixture.primary),
                .screen(Fixture.primary),
            ])
    }

    @Test("candidates 沿用 topmost 的过滤规则")
    func candidatesFilter() {
        // (400, 400) 在自身窗口与编辑器内：自身窗口被排除
        let stack = WindowHitTester.candidates(at: CGPoint(x: 400, y: 400), in: Fixture.twoScreens)
        #expect(stack == [.window(Fixture.editor, screen: Fixture.primary), .screen(Fixture.primary)])
        // 菜单栏、透明窗口、1×1 窗口都不算
        #expect(
            WindowHitTester.candidates(at: CGPoint(x: 1000, y: 10), in: Fixture.twoScreens) == [
                .screen(Fixture.primary)
            ])
        #expect(
            WindowHitTester.candidates(at: CGPoint(x: 850, y: 650), in: Fixture.twoScreens) == [
                .screen(Fixture.primary)
            ])
    }

    @Test("candidates：跨屏窗口取光标所在屏，空隙为空数组")
    func candidatesScreens() {
        let external = WindowHitTester.candidates(at: CGPoint(x: 1500, y: 300), in: Fixture.twoScreens)
        #expect(external == [.window(Fixture.spanning, screen: Fixture.external), .screen(Fixture.external)])
        #expect(WindowHitTester.candidates(at: Fixture.gapPoint, in: Fixture.twoScreens).isEmpty)
    }

    @Test("candidates 的第一项与 hoverTarget 一致")
    func firstCandidateMatchesHoverTarget() {
        for point in [Fixture.stackPoint, Fixture.editorPoint, Fixture.desktopPoint, CGPoint(x: 1300, y: 300)] {
            let first = WindowHitTester.candidates(at: point, in: Fixture.twoScreens).first
            #expect(first == WindowHitTester.hoverTarget(at: point, topology: Fixture.twoScreens))
        }
    }

    @Test("HoverTarget.windowID：窗口为其 id，整屏为 nil")
    func windowID() {
        #expect(HoverTarget.window(Fixture.editor, screen: Fixture.primary).windowID == 14)
        #expect(HoverTarget.screen(Fixture.primary).windowID == nil)
    }
}
