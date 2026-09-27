import CoreGraphics
import Testing
@testable import CubbyCore

/// 评审 §7「打破常规」的交互：箭头智能吸附、选区边缘磁吸、箭头端点手柄、⇧ 直线、键盘选色 / 调粗细
@Suite("ScreenshotReducer · 智能交互")
struct ReducerSmartInteractionTests {
    private typealias Fixture = TopologyFixture
    private let tail = CGPoint(x: 300, y: 300)

    private func arrow(_ harness: SessionHarness) -> (from: CGPoint, to: CGPoint)? {
        switch harness.session.drag {
        case .drawing(let annotation):
            guard case .arrow(let from, let to) = annotation.shape else { return nil }
            return (from, to)
        default:
            guard case .arrow(let from, let to) = harness.session.document.annotations.last?.shape else { return nil }
            return (from, to)
        }
    }

    // MARK: - 箭头智能吸附（C8）

    @Test("不按 ⇧：±3° 内吸附到 0° / 45° / 90°，长度取投影；显示辅助线")
    func arrowMagnet() {
        let flat = SessionHarness.annotating(.arrow).press(tail, dragTo: CGPoint(x: 400, y: 303))
        #expect(arrow(flat)?.to == CGPoint(x: 400, y: 300))
        #expect(flat.session.arrowSnapGuide == AnnotationSnapGuide(from: tail, to: CGPoint(x: 400, y: 300)))

        let diagonal = SessionHarness.annotating(.arrow).press(tail, dragTo: CGPoint(x: 400, y: 402))
        #expect(arrow(diagonal)?.to == CGPoint(x: 401, y: 401))
        #expect(diagonal.session.arrowSnapGuide != nil)

        let vertical = SessionHarness.annotating(.arrow).press(tail, dragTo: CGPoint(x: 297, y: 200))
        #expect(arrow(vertical)?.to == CGPoint(x: 300, y: 200))
    }

    @Test("超出 ±3°：保持原方向，不显示辅助线")
    func arrowOutsideTolerance() {
        let free = SessionHarness.annotating(.arrow).press(tail, dragTo: CGPoint(x: 400, y: 310))
        #expect(arrow(free)?.to == CGPoint(x: 400, y: 310))
        #expect(free.session.arrowSnapGuide == nil)
    }

    @Test("按住 ⇧：仍强制吸附到最近的 45°")
    func arrowShiftForces45() {
        let shifted = SessionHarness.annotating(.arrow).modifiers(.shift).press(tail, dragTo: CGPoint(x: 400, y: 330))
        #expect(arrow(shifted)?.to == ArrowGeometry.snapped45(from: tail, to: CGPoint(x: 400, y: 330)))
        #expect(shifted.session.arrowSnapGuide != nil)
    }

    @Test("松开后辅助线消失，文档里的箭头是吸附后的方向")
    func arrowGuideEndsOnMouseUp() {
        let done = SessionHarness.annotating(.arrow).press(tail, dragTo: CGPoint(x: 400, y: 303))
            .send(.mouseUp(CGPoint(x: 400, y: 303)))
        #expect(done.session.arrowSnapGuide == nil)
        #expect(arrow(done)?.to == CGPoint(x: 400, y: 300))
    }

    // MARK: - 选区边缘磁吸（C9）

    @Test("创建选区：起点与终点在窗口边缘 6 pt 内吸附过去")
    func creatingSnapsToWindowEdges() {
        let created = SessionHarness.hovering()
            .drag(from: CGPoint(x: 104, y: 250), to: CGPoint(x: 400, y: 497))
        #expect(created.session.selection == CGRect(x: 100, y: 250, width: 300, height: 250))
    }

    @Test("创建选区：屏幕边缘同样吸附")
    func creatingSnapsToScreenEdges() {
        let created = SessionHarness.hovering()
            .drag(from: CGPoint(x: 1000, y: 700), to: CGPoint(x: 1436, y: 896))
        #expect(created.session.selection == CGRect(x: 1000, y: 700, width: 440, height: 200))
    }

    @Test("按住 ⌘ 临时关闭吸附")
    func commandDisablesSnapping() {
        let created = SessionHarness.hovering().modifiers(.command)
            .drag(from: CGPoint(x: 104, y: 250), to: CGPoint(x: 400, y: 497))
        #expect(created.session.selection == CGRect(x: 104, y: 250, width: 296, height: 247))
    }

    @Test("超出 6 pt 不吸附")
    func farEdgesDoNotSnap() {
        let created = SessionHarness.hovering()
            .drag(from: CGPoint(x: 110, y: 250), to: CGPoint(x: 400, y: 490))
        #expect(created.session.selection == CGRect(x: 110, y: 250, width: 290, height: 240))
    }

    @Test("两端吸到同一条线时不压扁选区：光标那一端不吸附")
    func snappingNeverCollapses() {
        let created = SessionHarness.hovering()
            .drag(from: CGPoint(x: 102, y: 250), to: CGPoint(x: 105, y: 300))
        #expect(created.session.selection == CGRect(x: 100, y: 250, width: 5, height: 50))
        #expect(created.session.phase == .adjusting)
    }

    @Test("缩放手柄：只吸附被拖动的边，对边固定")
    func resizingSnapsMovingEdges() {
        let resized = SessionHarness.adjusting()
            .drag(from: CGPoint(x: 760, y: 520), to: CGPoint(x: 897, y: 596))
        #expect(resized.session.selection == CGRect(x: 200, y: 150, width: 700, height: 450))
    }

    @Test("移动选区：最近的边吸附，尺寸不变")
    func movingSnapsWithoutResizing() {
        let moved = SessionHarness.adjusting()
            .drag(from: CGPoint(x: 480, y: 330), to: CGPoint(x: 383, y: 330))
        #expect(moved.session.selection == CGRect(x: 100, y: 150, width: 560, height: 370))
    }

    @Test("只吸附与选区在同一带内的窗口边：远处窗口的延长线不吸")
    func ignoresUnrelatedWindowEdges() {
        // 编辑器 y 为 100...500；选区在 y 700 以下时它的左边（x = 100）不参与吸附
        let created = SessionHarness.hovering()
            .drag(from: CGPoint(x: 104, y: 700), to: CGPoint(x: 400, y: 800))
        #expect(created.session.selection == CGRect(x: 104, y: 700, width: 296, height: 100))
    }

    // MARK: - 箭头端点手柄（C10）

    private func selectedArrow() -> SessionHarness {
        SessionHarness.annotating(.arrow)
            .drag(from: tail, to: CGPoint(x: 500, y: 300))
            .send(.command(.selectTool(.pointer)))
            .click(CGPoint(x: 400, y: 300))
    }

    @Test("选中箭头后显示两端手柄")
    func arrowHandlesVisible() {
        let selected = selectedArrow()
        #expect(selected.session.selectedAnnotationValue?.tool == .arrow)
        #expect(selected.session.selectedArrowEndpoints == [tail, CGPoint(x: 500, y: 300)])
        #expect(selected.send(.mouseMoved(CGPoint(x: 502, y: 301))).session.cursorKind == .move)
    }

    @Test("拖动箭头头部重新指向；一次撤销回到原位")
    func draggingArrowHead() {
        let selected = selectedArrow()
        let before = selected.session.document
        let dragged = selected.drag(from: CGPoint(x: 500, y: 300), to: CGPoint(x: 520, y: 360), CGPoint(x: 500, y: 400))
        #expect(arrow(dragged)?.from == tail)
        #expect(arrow(dragged)?.to == CGPoint(x: 500, y: 400))
        #expect(dragged.session.selection == selected.session.selection)
        #expect(dragged.session.document.undone().annotations == before.annotations)
        #expect(dragged.session.selectedArrowEndpoints == [tail, CGPoint(x: 500, y: 400)])
    }

    @Test("拖动箭头尾部；端点拖动同样智能吸附")
    func draggingArrowTailSnaps() {
        let dragged = selectedArrow().drag(from: tail, to: CGPoint(x: 250, y: 302))
        #expect(arrow(dragged)?.from == CGPoint(x: 250, y: 300))
        #expect(arrow(dragged)?.to == CGPoint(x: 500, y: 300))
    }

    @Test("拖动中显示实时箭头与辅助线；右键回到拖动前")
    func arrowEndDragInProgress() {
        let selected = selectedArrow()
        let dragging = selected.press(CGPoint(x: 500, y: 300), dragTo: CGPoint(x: 600, y: 302))
        guard case .movingArrowEnd(_, let end) = dragging.session.drag else {
            Issue.record("应处于端点拖动")
            return
        }
        #expect(end == .head)
        #expect(dragging.session.arrowSnapGuide == AnnotationSnapGuide(from: tail, to: CGPoint(x: 600, y: 300)))
        let reverted = dragging.send(.rightMouseDown(CGPoint(x: 600, y: 302)))
        #expect(reverted.session.document.annotations == selected.session.document.annotations)
    }

    @Test("箭头工具激活时，按在选中箭头的端点上是重新指向而不是新画一支")
    func arrowToolRepointsSelectedArrow() {
        let selected = selectedArrow().send(.command(.selectTool(.arrow)))
        let dragged = selected.drag(from: CGPoint(x: 500, y: 300), to: CGPoint(x: 500, y: 450))
        #expect(dragged.session.document.annotations.count == 1)
        #expect(arrow(dragged)?.to == CGPoint(x: 500, y: 450))
    }

    // MARK: - ⇧ 画笔直线（C11）

    @Test("按住 ⇧ 的画笔 / 荧光笔只保留首尾两点", arguments: [ScreenshotTool.pen, .highlighter])
    func shiftStraightLine(tool: ScreenshotTool) {
        let drawn = SessionHarness.annotating(tool).modifiers(.shift)
            .drag(from: tail, to: CGPoint(x: 320, y: 340), CGPoint(x: 360, y: 280), CGPoint(x: 400, y: 320))
        switch drawn.session.document.annotations.last?.shape {
        case .pen(let points), .highlighter(let points):
            #expect(points == [tail, CGPoint(x: 400, y: 320)])
        default:
            Issue.record("应画出 \(tool)")
        }
    }

    @Test("不按 ⇧ 时画笔保留全部点")
    func freehandKeepsPoints() {
        let drawn = SessionHarness.annotating(.pen)
            .drag(from: tail, to: CGPoint(x: 320, y: 340), CGPoint(x: 360, y: 280), CGPoint(x: 400, y: 320))
        guard case .pen(let points) = drawn.session.document.annotations.last?.shape else {
            Issue.record("应画出画笔")
            return
        }
        #expect(points.count == 4)
    }

    // MARK: - 键盘选色与调粗细（C12）

    @Test("没有选中标注：数字键改当前工具的颜色并持久化")
    func digitColorsTool() {
        let changed = SessionHarness.annotating(.rectangle).send(.command(.selectColor(.blue)))
        #expect(changed.session.styles.style(for: .rectangle).color == .blue)
        #expect(changed.effects == [.stylesChanged(changed.session.styles)])
    }

    @Test("有选中标注：改这条标注（以及它所属工具的默认样式）")
    func digitColorsSelection() {
        let selected = SessionHarness.adjusting()
            .drawingRectangle(CGRect(x: 300, y: 300, width: 100, height: 100))
            .send(.command(.selectTool(.pointer)))
            .click(CGPoint(x: 300, y: 350))
        let recolored = selected.send(.command(.selectColor(.green)), .command(.adjustWeight(heavier: true)))
        #expect(recolored.session.selectedAnnotationValue?.style == AnnotationStyle(color: .green, weight: .heavy))
    }

    @Test("[ ] 在三档之间调节，到头保持不变")
    func bracketsAdjustWeight() {
        let base = SessionHarness.annotating(.pen)
        let lighter = base.send(.command(.adjustWeight(heavier: false)))
        #expect(lighter.session.styles.style(for: .pen).weight == .light)
        let floor = lighter.send(.command(.adjustWeight(heavier: false)))
        #expect(floor.session.styles.style(for: .pen).weight == .light)
        #expect(floor.effects.isEmpty)
        let heaviest = base.send(.command(.adjustWeight(heavier: true)), .command(.adjustWeight(heavier: true)))
        #expect(heaviest.session.styles.style(for: .pen).weight == .heavy)
    }

    @Test("指针且未选中标注时无效；马赛克没有颜色")
    func styleKeysWithoutTarget() {
        let pointer = SessionHarness.adjusting().send(.command(.selectColor(.blue)))
        #expect(pointer.session.styles == ToolStyles.default)
        let mosaic = SessionHarness.annotating(.mosaic).send(.command(.selectColor(.blue)))
        #expect(mosaic.session.styles.style(for: .mosaic) == ToolStyles.default.style(for: .mosaic))
        #expect(mosaic.effects.isEmpty)
    }
}
