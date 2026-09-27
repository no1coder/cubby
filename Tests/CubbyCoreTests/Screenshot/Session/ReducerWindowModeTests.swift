import CoreGraphics
import Testing
@testable import CubbyCore

@Suite("ScreenshotReducer · 纯净窗口截图模式（契约扩展）")
struct ReducerWindowModeTests {
    private typealias Fixture = TopologyFixture

    private var overEditor: SessionHarness { SessionHarness.hovering(at: Fixture.editorPoint) }

    /// 单独按下再松开空格
    private func tapSpace(_ harness: SessionHarness, holding modifiers: KeyModifiers = []) -> SessionHarness {
        harness.modifiers(modifiers.union(.space)).modifiers(modifiers)
    }

    @Test("悬停在窗口上单独按一下空格进入窗口模式，再按一下退出")
    func spaceTapToggles() {
        let pressed = overEditor.modifiers(.space)
        #expect(!pressed.session.isWindowCaptureMode)
        let on = pressed.modifiers([])
        #expect(on.session.isWindowCaptureMode)
        #expect(!on.session.isMagnifierVisible)
        #expect(on.session.highlightedRect == Fixture.editor.frame)
        let off = tapSpace(on)
        #expect(!off.session.isWindowCaptureMode)
        #expect(off.session.isMagnifierVisible)
    }

    @Test("目标是整屏时空格不起作用")
    func spaceOnScreenTargetIgnored() {
        let result = tapSpace(SessionHarness.hovering())
        #expect(!result.session.isWindowCaptureMode)
    }

    @Test("单击：截取窗口（默认带阴影）；按住 ⌥ 单击不带阴影")
    func clickCapturesWindow() {
        let on = tapSpace(overEditor)
        let clicked = on.click(Fixture.editorPoint)
        #expect(clicked.effects == [.finish(.captureWindow(windowID: Fixture.editor.id, includeShadow: true))])
        #expect(clicked.session.phase == .hovering)
        let noShadow = on.modifiers(.option).click(Fixture.editorPoint)
        #expect(noShadow.effects == [.finish(.captureWindow(windowID: Fixture.editor.id, includeShadow: false))])
    }

    @Test("↩ 截取当前窗口（带阴影）")
    func confirmCapturesWindow() {
        let result = tapSpace(overEditor).send(.command(.confirm))
        #expect(result.effects == [.finish(.captureWindow(windowID: Fixture.editor.id, includeShadow: true))])
    }

    @Test("Esc 取消整个会话")
    func escapeCancels() {
        #expect(tapSpace(overEditor).send(.command(.escape)).effects == [.finish(.cancel)])
    }

    @Test("右键取消整个会话")
    func rightClickCancels() {
        #expect(tapSpace(overEditor).send(.rightMouseDown(Fixture.editorPoint)).effects == [.finish(.cancel)])
    }

    @Test("Tab / 滚轮切换目标仍有效；切到整屏时自动退出窗口模式")
    func cyclingInWindowMode() {
        let on = tapSpace(SessionHarness.hovering(at: Fixture.stackPoint))
        #expect(on.session.isWindowCaptureMode)
        let editorLevel = on.send(.command(.cycleHover(forward: true)))
        #expect(editorLevel.session.isWindowCaptureMode)
        #expect(
            editorLevel.click(Fixture.stackPoint).effects == [
                .finish(.captureWindow(windowID: Fixture.editor.id, includeShadow: true))
            ])
        let screenLevel = editorLevel.send(.scrolled(deltaY: -ScreenshotReducer.scrollStepThreshold))
        #expect(screenLevel.session.hover == .screen(Fixture.primary))
        #expect(!screenLevel.session.isWindowCaptureMode)
    }

    @Test("窗口模式下移到桌面：模式保留但单击 / ↩ 无效，回到窗口后可截取")
    func desktopInWindowMode() {
        let desktop = tapSpace(overEditor).send(.mouseMoved(Fixture.desktopPoint))
        #expect(desktop.session.isWindowCaptureMode)
        #expect(desktop.session.highlightedRect == nil)
        #expect(desktop.click(Fixture.desktopPoint).effects.isEmpty)
        #expect(desktop.click(Fixture.desktopPoint).session.phase == .hovering)
        #expect(desktop.send(.command(.confirm)).effects.isEmpty)
        let back = desktop.send(.mouseMoved(Fixture.editorPoint)).click(Fixture.editorPoint)
        #expect(back.effects == [.finish(.captureWindow(windowID: Fixture.editor.id, includeShadow: true))])
    }

    @Test("窗口模式下拖动不创建选区，松开也不截取")
    func dragInWindowMode() {
        let result = tapSpace(overEditor).drag(from: Fixture.editorPoint, to: CGPoint(x: 400, y: 400))
        #expect(result.session.phase == .hovering)
        #expect(result.session.selection == nil)
        #expect(result.allEffects.isEmpty)
    }

    @Test("按住空格期间按下鼠标：不算单独按空格，松开空格不切换")
    func spaceWithMouseIsNotTap() {
        let result = overEditor.modifiers(.space)
            .send(.mouseDown(Fixture.editorPoint, clickCount: 1))
            .modifiers([])
        #expect(!result.session.isWindowCaptureMode)
    }

    @Test("按住空格期间有命令：不算单独按空格")
    func spaceWithCommandIsNotTap() {
        let result = SessionHarness.hovering(at: Fixture.stackPoint).modifiers(.space)
            .send(.command(.cycleHover(forward: true)))
            .modifiers([])
        #expect(!result.session.isWindowCaptureMode)
    }

    @Test("按住 ⇧ 时点空格同样切换")
    func spaceTapWithShift() {
        let result = tapSpace(overEditor.modifiers(.shift), holding: .shift)
        #expect(result.session.isWindowCaptureMode)
    }

    @Test("selecting 中按住空格是平移选区，不切换窗口模式")
    func spaceInSelecting() {
        let result = overEditor.press(Fixture.editorPoint, dragTo: CGPoint(x: 300, y: 300))
            .modifiers(.space).send(.mouseDragged(CGPoint(x: 310, y: 300))).modifiers([])
        #expect(result.session.phase == .selecting)
        #expect(!result.session.isWindowCaptureMode)
    }

    @Test("adjusting 中空格无效")
    func spaceInAdjusting() {
        let result = tapSpace(SessionHarness.adjusting())
        #expect(!result.session.isWindowCaptureMode)
        #expect(result.session.phase == .adjusting)
    }

    @Test("窗口模式下 ⌘A 进入 adjusting 并退出窗口模式")
    func selectAllLeavesWindowMode() {
        let result = tapSpace(overEditor).send(.command(.selectAll))
        #expect(result.session.phase == .adjusting)
        #expect(!result.session.isWindowCaptureMode)
    }

    @Test("工具栏发来的窗口截取只在窗口模式下有效")
    func toolbarCaptureWindow() {
        let outcome = ScreenshotOutcome.captureWindow(windowID: Fixture.editor.id, includeShadow: true)
        #expect(tapSpace(overEditor).send(.toolbarAction(outcome)).effects == [.finish(outcome)])
        #expect(overEditor.send(.toolbarAction(outcome)).effects.isEmpty)
    }
}
