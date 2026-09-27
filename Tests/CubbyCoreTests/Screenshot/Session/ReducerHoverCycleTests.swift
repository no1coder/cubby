import CoreGraphics
import Testing
@testable import CubbyCore

@Suite("ScreenshotReducer · 重叠窗口逐层切换（契约扩展）")
struct ReducerHoverCycleTests {
    private typealias Fixture = TopologyFixture
    private let inspector = HoverTarget.window(Fixture.inspector, screen: Fixture.primary)
    private let editor = HoverTarget.window(Fixture.editor, screen: Fixture.primary)
    private let screen = HoverTarget.screen(Fixture.primary)
    private let threshold = ScreenshotReducer.scrollStepThreshold

    private var stack: SessionHarness { SessionHarness.hovering(at: Fixture.stackPoint) }

    @Test("Tab 逐层向后，到整屏停住；⇧Tab 逐层向前，到 0 停住")
    func tabCycles() {
        #expect(stack.session.hover == inspector)
        #expect(stack.session.hoverDepth == 0)
        let forward: ScreenshotEvent = .command(.cycleHover(forward: true))
        let backward: ScreenshotEvent = .command(.cycleHover(forward: false))

        let one = stack.send(forward)
        #expect(one.session.hoverDepth == 1)
        #expect(one.session.hover == editor)
        #expect(one.session.highlightedRect == Fixture.editor.frame)
        let two = one.send(forward)
        #expect(two.session.hoverDepth == 2)
        #expect(two.session.hover == screen)
        let stuck = two.send(forward)
        #expect(stuck.session.hoverDepth == 2)
        #expect(stuck.session.hover == screen)

        let back = stuck.send(backward)
        #expect(back.session.hover == editor)
        let top = back.send(backward, backward)
        #expect(top.session.hoverDepth == 0)
        #expect(top.session.hover == inspector)
    }

    @Test("滚轮：累积到阈值才走一层；向下（deltaY < 0）更深，向上更浅")
    func scrollSteps() {
        let partial = stack.send(.scrolled(deltaY: -(threshold / 2)))
        #expect(partial.session.hoverDepth == 0)
        let stepped = partial.send(.scrolled(deltaY: -(threshold / 2)))
        #expect(stepped.session.hoverDepth == 1)
        #expect(stepped.session.hover == editor)
        let upPartial = stepped.send(.scrolled(deltaY: threshold / 2))
        #expect(upPartial.session.hoverDepth == 1)
        let up = upPartial.send(.scrolled(deltaY: threshold / 2))
        #expect(up.session.hoverDepth == 0)
    }

    @Test("一次大增量（惯性）最多走一层，余量清零")
    func largeDeltaStepsOnce() {
        let result = stack.send(.scrolled(deltaY: -threshold * 10))
        #expect(result.session.hoverDepth == 1)
        let next = result.send(.scrolled(deltaY: -(threshold - 1)))
        #expect(next.session.hoverDepth == 1)
    }

    @Test("反向滚动清空累积；deltaY = 0（手势边界）清空累积")
    func accumulatorResets() {
        let reversed = stack.send(
            .scrolled(deltaY: -(threshold - 1)), .scrolled(deltaY: 1), .scrolled(deltaY: -(threshold - 1)))
        #expect(reversed.session.hoverDepth == 0)
        let boundary = stack.send(
            .scrolled(deltaY: -(threshold - 1)), .scrolled(deltaY: 0), .scrolled(deltaY: -(threshold - 1)))
        #expect(boundary.session.hoverDepth == 0)
    }

    @Test("阈值常量")
    func constants() {
        #expect(ScreenshotReducer.scrollStepThreshold == 40)
        #expect(ScreenshotReducer.scrollPointsPerLine == 40)
    }

    @Test("在同一叠窗口内移动保持 depth；换到另一叠时归零")
    func depthFollowsStack() {
        let deep = stack.send(.command(.cycleHover(forward: true)))
        let sameStack = deep.send(.mouseMoved(CGPoint(x: 650, y: 450)))
        #expect(sameStack.session.hoverDepth == 1)
        #expect(sameStack.session.hover == editor)
        let otherStack = sameStack.send(.mouseMoved(Fixture.editorPoint))
        #expect(otherStack.session.hoverDepth == 0)
        #expect(otherStack.session.hover == editor)
        let back = otherStack.send(.mouseMoved(Fixture.stackPoint))
        #expect(back.session.hoverDepth == 0)
        #expect(back.session.hover == inspector)
    }

    @Test("换叠时未满阈值的滚动累积被清空")
    func stackChangeResetsScroll() {
        let result = stack.send(
            .scrolled(deltaY: -(threshold - 1)), .mouseMoved(Fixture.editorPoint), .mouseMoved(Fixture.stackPoint),
            .scrolled(deltaY: -1))
        #expect(result.session.hoverDepth == 0)
    }

    @Test("单击、↩、双击都使用当前 depth 的目标")
    func actionsUseCurrentDepth() {
        let deep = stack.send(.command(.cycleHover(forward: true)))
        let clicked = deep.click(Fixture.stackPoint)
        #expect(clicked.session.selection == Fixture.editor.frame)
        let confirmed = deep.send(.command(.confirm))
        #expect(confirmed.effects == [.finish(.copy)])
        #expect(confirmed.session.selection == Fixture.editor.frame)
        let screenLevel = deep.send(.command(.cycleHover(forward: true))).click(Fixture.stackPoint)
        #expect(screenLevel.session.selection == Fixture.primary.frame)
        let doubleClicked = deep.click(Fixture.stackPoint).send(.mouseDown(Fixture.stackPoint, clickCount: 2))
        #expect(doubleClicked.effects == [.finish(.copy)])
        #expect(doubleClicked.session.selection == Fixture.editor.frame)
    }

    @Test("拖出的选区过小视为单击：同样使用当前 depth")
    func tinyDragUsesDepth() {
        let result = stack.send(.command(.cycleHover(forward: true)))
            .drag(from: Fixture.stackPoint, to: CGPoint(x: 610, y: 401))
        #expect(result.session.selection == Fixture.editor.frame)
    }

    @Test("Esc 放弃拖拽回 hovering：仍在同一叠内保留 depth，换叠则归零")
    func depthAfterAbandonedDrag() {
        let deep = stack.send(.command(.cycleHover(forward: true)))
        let sameStack = deep.press(Fixture.stackPoint, dragTo: CGPoint(x: 650, y: 450)).send(.command(.escape))
        #expect(sameStack.session.hoverDepth == 1)
        #expect(sameStack.session.hover == editor)
        #expect(sameStack.send(.mouseMoved(Fixture.stackPoint)).session.hover == editor)
        // (700, 500) 已不在编辑器内：候选变为 [检查器, 整屏]
        let otherStack = deep.press(Fixture.stackPoint, dragTo: CGPoint(x: 700, y: 500)).send(.command(.escape))
        #expect(otherStack.session.hoverDepth == 0)
        #expect(otherStack.session.hover == inspector)
    }

    @Test("空隙中切换无效；进入 adjusting 后 depth 归零")
    func edgeCases() {
        let gap = SessionHarness.hovering(at: Fixture.gapPoint).send(.command(.cycleHover(forward: true)))
        #expect(gap.session.hoverDepth == 0)
        #expect(gap.session.hover == nil)
        let gapScroll = SessionHarness.hovering(at: Fixture.gapPoint).send(.scrolled(deltaY: -threshold))
        #expect(gapScroll.session.hoverDepth == 0)
        let selected = stack.send(.command(.cycleHover(forward: true))).click(Fixture.stackPoint)
        #expect(selected.session.hoverDepth == 0)
    }
}
