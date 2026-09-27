import CoreGraphics
import Testing
@testable import CubbyCore

@Suite("ScreenshotReducer · selecting")
struct ReducerSelectingTests {
    private typealias Fixture = TopologyFixture
    private let anchor = CGPoint(x: 200, y: 150)

    @Test("拖动不足 4 pt 仍在 hovering；达到 4 pt 进入 selecting")
    func dragThreshold() {
        let pending = SessionHarness.hovering().press(anchor, dragTo: CGPoint(x: 202, y: 152))
        #expect(pending.session.phase == .hovering)
        #expect(pending.session.drag == .none)

        let selecting = pending.send(.mouseDragged(CGPoint(x: 204, y: 150)))
        #expect(selecting.session.phase == .selecting)
        #expect(selecting.session.selection == CGRect(x: 200, y: 150, width: 4, height: 0))
        #expect(selecting.session.drag == .creatingSelection(anchor: anchor, previous: nil))
        #expect(selecting.session.screenID == Fixture.primary.id)
    }

    @Test("selecting 的派生状态：放大镜可见、无工具栏、高亮 = 实时选区")
    func selectingDerived() {
        let session = SessionHarness.hovering().press(anchor, dragTo: CGPoint(x: 500, y: 400)).session
        #expect(session.selection == CGRect(x: 200, y: 150, width: 300, height: 250))
        #expect(session.isMagnifierVisible)
        #expect(!session.isToolbarVisible)
        #expect(session.highlightedRect == session.selection)
        #expect(session.hover == nil)
        #expect(session.cursor == CGPoint(x: 500, y: 400))
    }

    @Test("松开时尺寸 ≥ 4×4 进入 adjusting")
    func releaseToAdjusting() {
        let result = SessionHarness.adjusting()
        #expect(result.session.phase == .adjusting)
        #expect(result.session.selection == SessionHarness.selection)
        #expect(result.session.drag == .none)
        #expect(result.allEffects.isEmpty)
    }

    @Test("松开时选区极小（< 4×4）视为单击，选中悬停目标")
    func tinyReleaseIsClick() {
        let result = SessionHarness.hovering().drag(from: Fixture.editorPoint, to: CGPoint(x: 160, y: 151))
        #expect(result.session.phase == .adjusting)
        #expect(result.session.selection == Fixture.editor.frame)
    }

    @Test("按住 ⇧ 约束为正方形；拖动中按下 ⇧ 立即生效")
    func shiftConstrainsSquare() {
        let free = SessionHarness.hovering().press(anchor, dragTo: CGPoint(x: 300, y: 400))
        #expect(free.session.selection == CGRect(x: 200, y: 150, width: 100, height: 250))
        let square = free.modifiers(.shift)
        #expect(square.session.selection == CGRect(x: 200, y: 150, width: 100, height: 100))
        let released = square.modifiers([])
        #expect(released.session.selection == CGRect(x: 200, y: 150, width: 100, height: 250))
    }

    @Test("按住 ⌥ 以起点为中心扩展")
    func optionExpandsFromCenter() {
        let result = SessionHarness.hovering().modifiers(.option)
            .press(CGPoint(x: 400, y: 400), dragTo: CGPoint(x: 450, y: 420))
        #expect(result.session.selection == CGRect(x: 350, y: 380, width: 100, height: 40))
    }

    @Test("按住空格平移整个选区，松开后继续按对角拖拽")
    func spaceMovesSelection() {
        let drawn = SessionHarness.hovering().press(anchor, dragTo: CGPoint(x: 300, y: 250))
        #expect(drawn.session.selection == CGRect(x: 200, y: 150, width: 100, height: 100))
        let moved = drawn.modifiers(.space).send(.mouseDragged(CGPoint(x: 350, y: 300)))
        #expect(moved.session.selection == CGRect(x: 250, y: 200, width: 100, height: 100))
        #expect(moved.session.drag == .creatingSelection(anchor: CGPoint(x: 250, y: 200), previous: nil))
        let resumed = moved.modifiers([]).send(.mouseDragged(CGPoint(x: 360, y: 310)))
        #expect(resumed.session.selection == CGRect(x: 250, y: 200, width: 110, height: 110))
        #expect(!resumed.session.isWindowCaptureMode)
    }

    @Test("空格平移被屏幕边缘挡住时起点只随实际位移")
    func spaceMoveClamped() {
        let drawn = SessionHarness.hovering().press(CGPoint(x: 20, y: 150), dragTo: CGPoint(x: 120, y: 250))
        let moved = drawn.modifiers(.space).send(.mouseDragged(CGPoint(x: 20, y: 250)))
        #expect(moved.session.selection == CGRect(x: 0, y: 150, width: 100, height: 100))
        #expect(moved.session.drag == .creatingSelection(anchor: CGPoint(x: 0, y: 150), previous: nil))
    }

    @Test("选区夹紧在起点所在屏幕，不跨屏")
    func clampedToAnchorScreen() {
        let result = SessionHarness.hovering().drag(from: CGPoint(x: 1400, y: 800), to: CGPoint(x: 1600, y: 850))
        #expect(result.session.selection == CGRect(x: 1400, y: 800, width: 40, height: 50))
        #expect(result.session.screenID == Fixture.primary.id)
    }

    @Test("在外接屏（负坐标）上创建选区")
    func externalScreenSelection() {
        let result = SessionHarness.hovering().drag(from: CGPoint(x: 1500, y: -150), to: CGPoint(x: 1300, y: -300))
        #expect(result.session.selection == CGRect(x: 1440, y: -180, width: 60, height: 30))
        #expect(result.session.screenID == Fixture.external.id)
    }

    @Test("在屏幕空隙按下拖动不产生选区")
    func dragFromGap() {
        let result = SessionHarness.hovering().drag(from: Fixture.gapPoint, to: CGPoint(x: 1100, y: 100))
        #expect(result.session.phase == .hovering)
        #expect(result.session.selection == nil)
    }

    @Test("Esc 放弃拖拽回 hovering；之后的拖动与松开被忽略")
    func escapeAbandonsDrag() {
        let selecting = SessionHarness.hovering().press(anchor, dragTo: CGPoint(x: 500, y: 400))
        let abandoned = selecting.send(.command(.escape))
        #expect(abandoned.effects.isEmpty)
        #expect(abandoned.session.phase == .hovering)
        #expect(abandoned.session.selection == nil)
        #expect(abandoned.session.drag == .none)
        #expect(abandoned.session.hover == .window(Fixture.inspector, screen: Fixture.primary))
        let after = abandoned.send(.mouseDragged(CGPoint(x: 600, y: 500)), .mouseUp(CGPoint(x: 600, y: 500)))
        #expect(after.session.phase == .hovering)
        #expect(after.session.selection == nil)
    }

    @Test("右键同 Esc")
    func rightClickAbandons() {
        let result = SessionHarness.hovering().press(anchor, dragTo: CGPoint(x: 500, y: 400))
            .send(.rightMouseDown(CGPoint(x: 500, y: 400)))
        #expect(result.effects.isEmpty)
        #expect(result.session.phase == .hovering)
    }

    @Test("从已有选区外拖出新选区：Esc 恢复原选区；松开则替换并保留标注")
    func newSelectionFromAdjusting() {
        let annotated = SessionHarness.adjusting()
            .drawingRectangle(CGRect(x: 300, y: 300, width: 50, height: 50))
        let dragging = annotated.press(CGPoint(x: 900, y: 600), dragTo: CGPoint(x: 1000, y: 700))
        #expect(dragging.session.phase == .selecting)
        #expect(
            dragging.session.drag
                == .creatingSelection(anchor: CGPoint(x: 900, y: 600), previous: SessionHarness.selection))

        let restored = dragging.send(.command(.escape))
        #expect(restored.session.phase == .adjusting)
        #expect(restored.session.selection == SessionHarness.selection)
        #expect(restored.session.screenID == Fixture.primary.id)

        let replaced = dragging.send(.mouseUp(CGPoint(x: 1000, y: 700)))
        #expect(replaced.session.phase == .adjusting)
        #expect(replaced.session.selection == CGRect(x: 900, y: 600, width: 100, height: 100))
        #expect(replaced.session.document == annotated.session.document)
    }

    @Test("从已有选区外拖出的新选区过小：视为单击，保留原选区")
    func tinyNewSelectionKeepsPrevious() {
        let result = SessionHarness.adjusting().drag(from: CGPoint(x: 900, y: 600), to: CGPoint(x: 910, y: 601))
        #expect(result.session.phase == .adjusting)
        #expect(result.session.selection == SessionHarness.selection)
    }

    @Test("selecting 下 ↩ / ⌘S / 工具键无效，取色有效")
    func selectingCommands() {
        let selecting = SessionHarness.hovering().press(anchor, dragTo: CGPoint(x: 500, y: 400))
        for command in [ScreenshotCommand.confirm, .save, .selectTool(.arrow), .selectAll, .undo] {
            let result = selecting.send(.command(command))
            #expect(result.effects.isEmpty)
            #expect(result.session.phase == .selecting)
        }
        #expect(selecting.send(.toolbarAction(.copyColor("1, 2, 3"))).effects == [.finish(.copyColor("1, 2, 3"))])
    }

    @Test("selecting 中收到 mouseDown 被忽略")
    func mouseDownWhileSelecting() {
        let selecting = SessionHarness.hovering().press(anchor, dragTo: CGPoint(x: 500, y: 400))
        let result = selecting.send(.mouseDown(CGPoint(x: 10, y: 10), clickCount: 1))
        #expect(result.session.selection == selecting.session.selection)
        #expect(result.session.phase == .selecting)
    }

    @Test("候选栈为空时的过小选区：回到 hovering 而不是卡在 selecting")
    func tinyReleaseWithoutCandidates() throws {
        let preset = try #require(
            ScreenshotDebugScenario.session(named: "selecting", topology: Fixture.twoScreens, styles: .default))
        let stripped = preset.updating { $0.hoverCandidates = [] }
        let result = SessionHarness(session: stripped)
            .send(.mouseDragged(CGPoint(x: 202, y: 151)), .mouseUp(CGPoint(x: 202, y: 151)))
        #expect(result.session.phase == .hovering)
        #expect(result.session.selection == nil)
    }

    @Test("按住空格从已有选区外开始拖新选区：新选区从起点开始，而不是平移旧选区")
    func spaceHeldWhenStartingNewSelection() {
        let result = SessionHarness.adjusting().modifiers(.space)
            .press(CGPoint(x: 900, y: 600), dragTo: CGPoint(x: 1000, y: 700))
        #expect(result.session.phase == .selecting)
        #expect(result.session.selection == CGRect(x: 900, y: 600, width: 100, height: 100))
        let moved = result.send(.mouseDragged(CGPoint(x: 1010, y: 700)))
        #expect(moved.session.selection == CGRect(x: 910, y: 600, width: 100, height: 100))
    }

    @Test("放弃拖拽后按钮未松开就移动：悬停高亮跟随光标，松开处也刷新")
    func hoverFollowsAfterAbandon() {
        let abandoned = SessionHarness.hovering().press(anchor, dragTo: CGPoint(x: 500, y: 400)).send(.command(.escape))
        let dragged = abandoned.send(.mouseDragged(Fixture.editorPoint))
        #expect(dragged.session.hover == .window(Fixture.editor, screen: Fixture.primary))
        #expect(dragged.session.cursor == Fixture.editorPoint)
        let released = dragged.send(.mouseUp(Fixture.desktopPoint))
        #expect(released.session.hover == .screen(Fixture.primary))
        #expect(released.session.phase == .hovering)
        let rightAbandoned = SessionHarness.hovering().press(anchor, dragTo: CGPoint(x: 500, y: 400))
            .send(.rightMouseDown(CGPoint(x: 500, y: 400)), .mouseDragged(CGPoint(x: 3000, y: 700)))
        #expect(rightAbandoned.session.hover == .screen(Fixture.external))
    }
}
