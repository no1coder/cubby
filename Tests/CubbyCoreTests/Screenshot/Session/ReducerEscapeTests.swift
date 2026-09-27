import CoreGraphics
import Testing
@testable import CubbyCore

@Suite("ScreenshotReducer · Esc 语义（含 PM Q1：有标注时二次确认）")
struct ReducerEscapeTests {
    private typealias Fixture = TopologyFixture
    private let hint = ScreenshotEffect.showHint(.pressEscapeAgainToDiscard)

    /// adjusting + 一个矩形标注
    private var annotated: SessionHarness {
        SessionHarness.adjusting().drawingRectangle(CGRect(x: 300, y: 300, width: 100, height: 100))
    }

    @Test("没有标注：Esc 在 hovering / adjusting / annotating 直接取消")
    func escapeWithoutAnnotations() {
        for harness in [SessionHarness.hovering(), .adjusting(), .annotating(.arrow)] {
            let result = harness.send(.command(.escape))
            #expect(result.effects == [.finish(.cancel)])
            #expect(!result.session.isDiscardArmed)
        }
    }

    @Test("有标注：第一次 Esc 进入待确认并提示，第二次 Esc 取消")
    func escapeTwiceWithAnnotations() {
        let armed = annotated.send(.command(.escape))
        #expect(armed.effects == [hint])
        #expect(armed.session.isDiscardArmed)
        #expect(armed.session.phase == .adjusting)
        #expect(armed.session.document == annotated.session.document)
        let cancelled = armed.send(.command(.escape))
        #expect(cancelled.effects == [.finish(.cancel)])
    }

    @Test("annotating 与（右键后的）hovering 同样需要二次确认")
    func escapeArmsInOtherPhases() {
        let annotating = annotated.send(.command(.selectTool(.arrow)), .command(.escape))
        #expect(annotating.effects == [hint])
        let hovering = annotated.send(.rightMouseDown(Fixture.desktopPoint), .command(.escape))
        #expect(hovering.session.phase == .hovering)
        #expect(hovering.effects == [hint])
        #expect(hovering.send(.command(.escape)).effects == [.finish(.cancel)])
    }

    @Test(
        "待确认时收到其他事件：先解除，再照常处理该事件",
        arguments: [
            ScreenshotEvent.mouseDown(CGPoint(x: 400, y: 300), clickCount: 1),
            .command(.selectTool(.arrow)),
            .command(.nudge(.left, large: false)),
            .command(.redo),
            .styleChanged(AnnotationStyle(color: .blue, weight: .heavy)),
            .scrolled(deltaY: -100),
            .toolbarAction(.copyColor("#000000")),
            .mouseDragged(CGPoint(x: 10, y: 10)),
            .mouseUp(CGPoint(x: 10, y: 10)),
        ])
    func otherEventsDisarm(_ event: ScreenshotEvent) {
        let armed = annotated.send(.command(.escape))
        let result = armed.send(event)
        #expect(!result.session.isDiscardArmed)
        #expect(!result.effects.contains(.finish(.cancel)))
        let again = result.send(.command(.escape))
        #expect(again.effects == [hint])
    }

    @Test("待确认时的事件照常生效（例如选工具）")
    func disarmingEventStillApplies() {
        let result = annotated.send(.command(.escape), .command(.selectTool(.arrow)))
        #expect(result.session.tool == .arrow)
        #expect(result.session.phase == .annotating)
    }

    @Test("待确认时右键：解除并清除选区")
    func rightClickDisarms() {
        let result = annotated.send(.command(.escape), .rightMouseDown(Fixture.desktopPoint))
        #expect(!result.session.isDiscardArmed)
        #expect(result.session.phase == .hovering)
    }

    @Test("待确认时 ↩：解除并照常完成")
    func confirmDisarms() {
        let result = annotated.send(.command(.escape), .command(.confirm))
        #expect(result.effects == [.finish(.copy)])
        #expect(!result.session.isDiscardArmed)
    }

    @Test("鼠标移动与修饰键变化不解除待确认")
    func passiveEventsKeepArmed() {
        let result = annotated.send(.command(.escape), .mouseMoved(CGPoint(x: 10, y: 10)), .modifiersChanged(.shift))
        #expect(result.session.isDiscardArmed)
        #expect(result.send(.command(.escape)).effects == [.finish(.cancel)])
    }

    @Test("selecting 中 Esc 只放弃拖拽，不进入待确认")
    func escapeInSelectingNeverArms() {
        let result = annotated.press(CGPoint(x: 900, y: 600), dragTo: CGPoint(x: 1000, y: 700)).send(.command(.escape))
        #expect(result.effects.isEmpty)
        #expect(!result.session.isDiscardArmed)
        #expect(result.session.phase == .adjusting)
    }

    @Test("撤销到没有标注后，Esc 恢复为直接取消")
    func undoneToEmpty() {
        let result = annotated.send(.command(.undo), .command(.escape))
        #expect(result.effects == [.finish(.cancel)])
    }

    @Test("工具栏 ✕ 不需要二次确认")
    func toolbarCancelIsImmediate() {
        #expect(annotated.send(.toolbarAction(.cancel)).effects == [.finish(.cancel)])
    }

    @Test("画第一个标注的过程中按 Esc：文档仍为空，直接取消")
    func escapeWhileDrawingFirst() {
        let result = SessionHarness.annotating(.rectangle)
            .press(CGPoint(x: 300, y: 300), dragTo: CGPoint(x: 400, y: 400))
            .send(.command(.escape))
        #expect(result.effects == [.finish(.cancel)])
    }

    @Test("hovering 且有标注：右键与 Esc 一样需要二次确认（PM 决定）")
    func rightClickInHoveringNeedsConfirmation() {
        let hovering = annotated.send(.rightMouseDown(Fixture.desktopPoint))
        #expect(hovering.session.phase == .hovering)
        let armed = hovering.send(.rightMouseDown(Fixture.desktopPoint))
        #expect(armed.effects == [hint])
        #expect(armed.session.isDiscardArmed)
        #expect(armed.send(.rightMouseDown(Fixture.desktopPoint)).effects == [.finish(.cancel)])
        #expect(armed.send(.command(.escape)).effects == [.finish(.cancel)])
        let escapeFirst = hovering.send(.command(.escape))
        #expect(escapeFirst.effects == [hint])
        #expect(escapeFirst.send(.rightMouseDown(Fixture.desktopPoint)).effects == [.finish(.cancel)])
    }

    @Test("hovering 且无标注：右键仍直接取消")
    func rightClickInHoveringWithoutAnnotations() {
        #expect(SessionHarness.hovering().send(.rightMouseDown(Fixture.desktopPoint)).effects == [.finish(.cancel)])
    }
}
