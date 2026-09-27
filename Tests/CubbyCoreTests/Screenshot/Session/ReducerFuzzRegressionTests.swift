import CoreGraphics
import Testing
@testable import CubbyCore

/// 模糊测试（ReducerFuzzTests）发现并缩减出的最小序列，逐个固化为具名回归测试
@Suite("ScreenshotReducer · 模糊测试发现的回归用例")
struct ReducerFuzzRegressionTests {
    private typealias Fixture = TopologyFixture

    /// 重放序列并在每一步检查全部不变量；返回第一个违反（nil = 全部成立）
    private func firstViolation(
        _ events: [ScreenshotEvent],
        topology: ScreenTopology,
        start: FuzzStart
    ) -> InvariantViolation? {
        var replayer = FuzzReplayer(topology: topology, start: start)
        for event in events {
            if let violation = replayer.apply(event).violation {
                return violation
            }
        }
        return nil
    }

    // MARK: - 缩放手柄时固定边漂移（像素吸附）

    @Test("@2x：拖左边手柄到 .25 坐标，吸附后右边仍固定在原处")
    func resizeKeepsFixedEdgeOnRetina() {
        let adjusting = SessionHarness.hovering().drag(from: CGPoint(x: 20, y: 20), to: CGPoint(x: 80, y: 60))
        #expect(adjusting.session.selection == CGRect(x: 20, y: 20, width: 60, height: 40))
        let result = adjusting.drag(from: CGPoint(x: 20, y: 40), to: CGPoint(x: 25.25, y: 40))
        let selection = result.session.selection
        #expect(selection?.maxX == 80)
        #expect(selection?.minY == 20)
        #expect(selection?.maxY == 60)
        #expect(selection == CGRect(x: 25, y: 20, width: 55, height: 40))
    }

    @Test("@1x 外接屏：拖左上角到 .5 坐标，吸附后右边与下边都不动")
    func resizeKeepsFixedEdgesOnExternal() {
        let adjusting = SessionHarness.hovering()
            .drag(from: CGPoint(x: 1500, y: -100), to: CGPoint(x: 1600, y: 0))
        #expect(adjusting.session.selection == CGRect(x: 1500, y: -100, width: 100, height: 100))
        let result = adjusting.drag(from: CGPoint(x: 1500, y: -100), to: CGPoint(x: 1510.5, y: -89.5))
        // 89.5 × 89.5 pt 四舍五入为 90 × 90 px，右边与下边保持在 1600 / 0
        #expect(result.session.selection == CGRect(x: 1510, y: -90, width: 90, height: 90))
    }

    @Test("⇧ 拖角手柄：正方形吸附后对角仍固定")
    func squareCornerResizeKeepsOppositeCorner() {
        let adjusting = SessionHarness.hovering().drag(from: CGPoint(x: 20, y: 20), to: CGPoint(x: 80, y: 80))
        let result = adjusting.modifiers(.shift)
            .drag(from: CGPoint(x: 20, y: 20), to: CGPoint(x: 30.25, y: 25.25))
        let selection = result.session.selection
        #expect(selection?.maxX == 80)
        #expect(selection?.maxY == 80)
        #expect(selection?.width == selection?.height)
    }

    @Test("模糊测试最小序列：左下屏上拖右上角，固定的下边从 1100 漂到 1100.5")
    func fuzzResizeTopRightOnLowerScreen() {
        let events: [ScreenshotEvent] = [
            .mouseDown(CGPoint(x: -80.0, y: 1010.0), clickCount: 1),
            .mouseUp(CGPoint(x: -80.0, y: 1010.0)),
            .mouseDown(CGPoint(x: -0.0, y: 900.0), clickCount: 1),
            .mouseDragged(CGPoint(x: -110.0, y: 991.75)),
        ]
        let start = FuzzStart.initial(cursor: CGPoint(x: 983.4106624098504, y: 15.75))
        #expect(firstViolation(events, topology: FuzzTopologies.threeScreens, start: start) == nil)
    }

    @Test("模糊测试最小序列：外接屏上 ⇧ 以外拖左下角，固定的右边从 3220 漂到 3221")
    func fuzzResizeBottomLeftOnExternal() {
        let events: [ScreenshotEvent] = [
            .mouseDown(CGPoint(x: 3220.0, y: -180.0), clickCount: 1),
            .mouseDragged(CGPoint(x: 780.0, y: -20.0)),
            .mouseUp(CGPoint(x: 780.0, y: -20.0)),
            .mouseDown(CGPoint(x: 1439.5, y: -17.0), clickCount: 1),
            .mouseDragged(CGPoint(x: 1450.0, y: 910.0)),
        ]
        let start = FuzzStart.initial(cursor: CGPoint(x: 943.25, y: 793.3))
        #expect(firstViolation(events, topology: Fixture.twoScreens, start: start) == nil)
    }

    // MARK: - 按下后退出窗口模式，松开仍截取窗口

    @Test("窗口模式下按下、Tab 切到整屏（自动退出窗口模式）后在窗口上松开：按普通单击处理，不截取窗口")
    func releaseAfterLeavingWindowModeIsNormalClick() {
        let pressed = SessionHarness.hovering(at: Fixture.stackPoint)
            .modifiers(.space).modifiers([])
            .send(.mouseDown(Fixture.stackPoint, clickCount: 1))
        #expect(pressed.session.isWindowCaptureMode)
        let left = pressed.send(.command(.cycleHover(forward: true)), .command(.cycleHover(forward: true)))
        #expect(left.session.hover == .screen(Fixture.primary))
        #expect(!left.session.isWindowCaptureMode)
        let released = left.send(.mouseUp(Fixture.editorPoint))
        #expect(released.allEffects.isEmpty)
        #expect(released.session.phase == .adjusting)
        #expect(released.session.selection == Fixture.editor.frame)
    }

    @Test("仍在窗口模式时按下再松开：照常截取窗口")
    func releaseInWindowModeStillCaptures() {
        let result = SessionHarness.hovering(at: Fixture.stackPoint)
            .modifiers(.space).modifiers([])
            .send(.mouseDown(Fixture.stackPoint, clickCount: 1), .command(.cycleHover(forward: true)))
            .send(.mouseUp(Fixture.stackPoint))
        #expect(result.effects == [.finish(.captureWindow(windowID: Fixture.editor.id, includeShadow: true))])
    }

    @Test("模糊测试最小序列：窗口模式下按下、滚轮切到整屏后松开，仍发出 captureWindow")
    func fuzzCaptureWindowAfterLeavingMode() {
        let events: [ScreenshotEvent] = [
            .rightMouseDown(CGPoint(x: 170.0, y: 0.0)),
            .mouseMoved(CGPoint(x: 350.0, y: 260.0)),
            .modifiersChanged([.space]),
            .modifiersChanged([]),
            .mouseDown(CGPoint(x: -1200.0, y: 1050.0), clickCount: 1),
            .scrolled(deltaY: -57.72408192844758),
            .mouseUp(CGPoint(x: 560.0, y: 300.0)),
        ]
        let start = FuzzStart.scenario("annotating:text")
        #expect(firstViolation(events, topology: FuzzTopologies.threeScreens, start: start) == nil)
    }

    // MARK: - 丢失 mouseUp 后打开文字编辑器，残留拖拽卡死

    @Test("拖手柄途中丢了 mouseUp、文字工具再次按下：进入编辑时不残留拖拽，提交后命令恢复可用")
    func textEditingClearsStaleDrag() {
        let resizing = SessionHarness.adjusting()
            .send(.command(.selectTool(.text)))
            .press(CGPoint(x: 760, y: 300), dragTo: CGPoint(x: 800, y: 300))
        guard case .resizing = resizing.session.drag else {
            Issue.record("expected a resize drag, got \(resizing.session.drag)")
            return
        }
        // 松开事件丢失，下一次按下直接到来
        let editing = resizing.send(.mouseDown(CGPoint(x: 300, y: 300), clickCount: 1))
        #expect(editing.session.phase == .editingText)
        #expect(editing.session.drag == .none)
        let committed = editing.send(.textChanged("Hi"), .command(.commitText), .mouseUp(CGPoint(x: 300, y: 300)))
        #expect(committed.session.phase == .annotating)
        #expect(committed.session.isToolbarVisible)
        let undone = committed.send(.command(.undo))
        #expect(undone.session.document.annotations.isEmpty)
    }

    @Test("模糊测试最小序列：拖右边手柄时再次按下（文字工具）进入编辑，残留 resizing")
    func fuzzStaleResizeIntoTextEditing() {
        let events: [ScreenshotEvent] = [
            .mouseDown(CGPoint(x: 1220.0, y: 380.0), clickCount: 1),
            .mouseUp(CGPoint(x: 1220.0, y: 380.0)),
            .command(.selectTool(.text)),
            .mouseDown(CGPoint(x: 1440.0, y: 350.0), clickCount: 1),
            .mouseDragged(CGPoint(x: 1440.0, y: 450.0)),
            .mouseDown(CGPoint(x: 340.0, y: 20.0), clickCount: 2),
        ]
        let start = FuzzStart.initial(cursor: CGPoint(x: 2209.999, y: 194.0))
        #expect(firstViolation(events, topology: Fixture.twoScreens, start: start) == nil)
    }
}
