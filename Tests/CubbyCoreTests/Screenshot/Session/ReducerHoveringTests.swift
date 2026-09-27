import CoreGraphics
import Testing
@testable import CubbyCore

@Suite("ScreenshotReducer · hovering")
struct ReducerHoveringTests {
    private typealias Fixture = TopologyFixture

    @Test("移动鼠标更新光标与悬停目标（窗口 / 整屏 / 外接屏 / 空隙）")
    func mouseMovedUpdatesHover() {
        let start = SessionHarness.hovering()
        #expect(start.session.hover == .screen(Fixture.primary))

        let overEditor = start.send(.mouseMoved(Fixture.editorPoint))
        #expect(overEditor.session.cursor == Fixture.editorPoint)
        #expect(overEditor.session.hover == .window(Fixture.editor, screen: Fixture.primary))

        let external = overEditor.send(.mouseMoved(CGPoint(x: 3000, y: 700)))
        #expect(external.session.hover == .screen(Fixture.external))

        let gap = external.send(.mouseMoved(Fixture.gapPoint))
        #expect(gap.session.hover == nil)
        #expect(gap.session.highlightedRect == nil)
        #expect(gap.effects.isEmpty)
    }

    @Test("未带拓扑的 initial 在第一次移动后才有悬停目标")
    func initialWithoutTopology() {
        let session = ScreenshotSession.initial(styles: .default, cursor: Fixture.editorPoint)
        let harness = SessionHarness(session: session).send(.mouseMoved(Fixture.editorPoint))
        #expect(harness.session.hover == .window(Fixture.editor, screen: Fixture.primary))
    }

    @Test("单击窗口：选区 = 窗口 frame，进入 adjusting")
    func clickWindow() {
        let result = SessionHarness.hovering().click(Fixture.editorPoint)
        #expect(result.session.phase == .adjusting)
        #expect(result.session.selection == Fixture.editor.frame)
        #expect(result.session.screenID == Fixture.primary.id)
        #expect(result.session.hover == nil)
        #expect(result.session.isToolbarVisible)
        #expect(result.allEffects.isEmpty)
    }

    @Test("单击桌面：选区 = 整屏")
    func clickDesktop() {
        let result = SessionHarness.hovering().click(Fixture.desktopPoint)
        #expect(result.session.phase == .adjusting)
        #expect(result.session.selection == Fixture.primary.frame)
    }

    @Test("单击跨屏窗口：选区 = 窗口 ∩ 光标所在屏")
    func clickSpanningWindow() {
        let result = SessionHarness.hovering().click(CGPoint(x: 1500, y: 300))
        #expect(result.session.selection == CGRect(x: 1440, y: 200, width: 360, height: 300))
        #expect(result.session.screenID == Fixture.external.id)
    }

    @Test("在屏幕空隙单击没有效果")
    func clickInGap() {
        let result = SessionHarness.hovering().click(Fixture.gapPoint)
        #expect(result.session.phase == .hovering)
        #expect(result.session.selection == nil)
    }

    @Test("移动不足 4 pt 视为单击")
    func jitterIsClick() {
        let result = SessionHarness.hovering()
            .send(
                .mouseDown(Fixture.editorPoint, clickCount: 1),
                .mouseDragged(CGPoint(x: 152, y: 152)),
                .mouseUp(CGPoint(x: 152, y: 152)))
        #expect(result.session.phase == .adjusting)
        #expect(result.session.selection == Fixture.editor.frame)
    }

    @Test("↩ / ⌘C 以悬停目标直接完成（复制）")
    func confirmHoverTarget() {
        let result = SessionHarness.hovering(at: Fixture.editorPoint).send(.command(.confirm))
        #expect(result.effects == [.finish(.copy)])
        #expect(result.session.selection == Fixture.editor.frame)
        #expect(result.session.screenID == Fixture.primary.id)
    }

    @Test("悬停在空隙时 ↩ 没有效果")
    func confirmWithoutTarget() {
        let result = SessionHarness.hovering(at: Fixture.gapPoint).send(.command(.confirm))
        #expect(result.effects.isEmpty)
        #expect(result.session.phase == .hovering)
    }

    @Test("⌘A：选区 = 光标所在整屏，进入 adjusting")
    func selectAll() {
        let result = SessionHarness.hovering(at: Fixture.editorPoint).send(.command(.selectAll))
        #expect(result.session.phase == .adjusting)
        #expect(result.session.selection == Fixture.primary.frame)
        #expect(result.session.screenID == Fixture.primary.id)
        let external = SessionHarness.hovering(at: CGPoint(x: 3000, y: 0)).send(.command(.selectAll))
        #expect(external.session.selection == Fixture.external.frame)
        let gap = SessionHarness.hovering(at: Fixture.gapPoint).send(.command(.selectAll))
        #expect(gap.session.phase == .hovering)
    }

    @Test("右键取消会话")
    func rightClickCancels() {
        let result = SessionHarness.hovering().send(.rightMouseDown(Fixture.editorPoint))
        #expect(result.effects == [.finish(.cancel)])
    }

    @Test("按住 ⇧ 放大镜切到 RGB，松开恢复 HEX")
    func shiftTogglesColorFormat() {
        let held = SessionHarness.hovering().modifiers(.shift)
        #expect(held.session.colorFormat == .rgb)
        #expect(held.session.modifiers == .shift)
        #expect(held.modifiers([]).session.colorFormat == .hex)
    }

    @Test("取色：放大镜可见时完成并带上读数；空读数忽略")
    func copyColor() {
        let result = SessionHarness.hovering().send(.toolbarAction(.copyColor("#FF8800")))
        #expect(result.effects == [.finish(.copyColor("#FF8800"))])
        let empty = SessionHarness.hovering().send(.toolbarAction(.copyColor("")))
        #expect(empty.effects.isEmpty)
    }

    @Test("C 命令本身不带读数：reducer 不产生效果（由覆盖层带读数发 toolbarAction）")
    func copyColorCommandIsInert() {
        let result = SessionHarness.hovering().send(.command(.copyColor))
        #expect(result.effects.isEmpty)
        #expect(result.session == SessionHarness.hovering().session)
    }

    @Test(
        "hovering 下无效的命令",
        arguments: [
            ScreenshotCommand.undo, .redo, .save, .pin, .extractText, .selectTool(.rectangle),
            .nudge(.left, large: false), .deleteAnnotation, .commitText,
        ])
    func inertCommands(_ command: ScreenshotCommand) {
        let start = SessionHarness.hovering(at: Fixture.editorPoint)
        let result = start.send(.command(command))
        #expect(result.session == start.session)
        #expect(result.effects.isEmpty)
    }

    @Test("hovering 下工具栏出口与样式事件无效")
    func inertToolbarActions() {
        let start = SessionHarness.hovering(at: Fixture.editorPoint)
        for outcome in [ScreenshotOutcome.copy, .save, .pin, .extractText] {
            #expect(start.send(.toolbarAction(outcome)).effects.isEmpty)
        }
        let styled = start.send(.styleChanged(AnnotationStyle(color: .blue, weight: .heavy)))
        #expect(styled.session == start.session)
        #expect(styled.effects.isEmpty)
        #expect(start.send(.textChanged("x")).session == start.session)
        #expect(start.send(.textCommitted("x")).session == start.session)
    }

    @Test("工具栏 ✕ 在任何阶段都直接取消")
    func toolbarCancel() {
        #expect(SessionHarness.hovering().send(.toolbarAction(.cancel)).effects == [.finish(.cancel)])
    }
}
