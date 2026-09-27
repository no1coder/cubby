import CoreGraphics
import Testing
@testable import CubbyCore

@Suite("ScreenshotReducer · annotating")
struct ReducerAnnotatingTests {
    private typealias Fixture = TopologyFixture
    private let start = CGPoint(x: 300, y: 200)

    private func lastShape(_ harness: SessionHarness) -> AnnotationShape? {
        harness.session.document.annotations.last?.shape
    }

    @Test("选工具进入 annotating；再按同一工具 / V 回 adjusting；按另一工具切换")
    func toolSwitching() {
        let rectangle = SessionHarness.annotating(.rectangle)
        #expect(rectangle.session.phase == .annotating)
        #expect(rectangle.session.tool == .rectangle)
        #expect(rectangle.session.styleBarTool == .rectangle)

        let again = rectangle.send(.command(.selectTool(.rectangle)))
        #expect(again.session.phase == .adjusting)
        #expect(again.session.tool == .pointer)

        let pointer = rectangle.send(.command(.selectTool(.pointer)))
        #expect(pointer.session.phase == .adjusting)

        let ellipse = rectangle.send(.command(.selectTool(.ellipse)))
        #expect(ellipse.session.phase == .annotating)
        #expect(ellipse.session.tool == .ellipse)
    }

    @Test("切换工具保留选中的标注")
    func switchingKeepsSelection() {
        let selected = SessionHarness.adjusting()
            .drawingRectangle(CGRect(x: 300, y: 300, width: 100, height: 100))
            .click(CGPoint(x: 300, y: 350))
        let id = selected.session.selectedAnnotation
        #expect(id != nil)
        let switched = selected.send(.command(.selectTool(.arrow)), .command(.selectTool(.pen)))
        #expect(switched.session.selectedAnnotation == id)
    }

    @Test("矩形：拖拽对角；拖动中是实时标注，松开入文档")
    func rectangle() {
        let dragging = SessionHarness.annotating(.rectangle).press(start, dragTo: CGPoint(x: 400, y: 260))
        guard case .drawing(let live) = dragging.session.drag else {
            Issue.record("应处于绘制状态")
            return
        }
        #expect(live.shape == .rectangle(CGRect(x: 300, y: 200, width: 100, height: 60)))
        #expect(live.style == ToolStyles.default.style(for: .rectangle))
        #expect(dragging.session.document.annotations.isEmpty)

        let done = dragging.send(.mouseUp(CGPoint(x: 400, y: 260)))
        #expect(lastShape(done) == .rectangle(CGRect(x: 300, y: 200, width: 100, height: 60)))
        #expect(done.session.document.annotations.last?.id == live.id)
        #expect(done.session.drag == .none)
        #expect(done.session.tool == .rectangle)
        #expect(done.session.phase == .annotating)
    }

    @Test("矩形 ⇧ 为正方形；反向拖拽也归一化")
    func rectangleSquareAndReverse() {
        let square = SessionHarness.annotating(.rectangle).modifiers(.shift).drag(
            from: start, to: CGPoint(x: 400, y: 260))
        #expect(lastShape(square) == .rectangle(CGRect(x: 300, y: 200, width: 60, height: 60)))
        let reverse = SessionHarness.annotating(.rectangle).drag(from: start, to: CGPoint(x: 250, y: 150))
        #expect(lastShape(reverse) == .rectangle(CGRect(x: 250, y: 150, width: 50, height: 50)))
        let reverseSquare = SessionHarness.annotating(.rectangle).modifiers(.shift)
            .drag(from: start, to: CGPoint(x: 280, y: 100))
        #expect(lastShape(reverseSquare) == .rectangle(CGRect(x: 280, y: 180, width: 20, height: 20)))
    }

    @Test("椭圆：外接矩形；⇧ 为圆")
    func ellipse() {
        let oval = SessionHarness.annotating(.ellipse).drag(from: start, to: CGPoint(x: 400, y: 260))
        #expect(lastShape(oval) == .ellipse(CGRect(x: 300, y: 200, width: 100, height: 60)))
        let circle = SessionHarness.annotating(.ellipse).modifiers(.shift).drag(
            from: start, to: CGPoint(x: 400, y: 260))
        #expect(lastShape(circle) == .ellipse(CGRect(x: 300, y: 200, width: 60, height: 60)))
    }

    @Test("箭头：起点为尾、终点为头；⇧ 吸附 45°")
    func arrow() {
        let free = SessionHarness.annotating(.arrow).drag(from: start, to: CGPoint(x: 400, y: 210))
        #expect(lastShape(free) == .arrow(from: start, to: CGPoint(x: 400, y: 210)))
        let snapped = SessionHarness.annotating(.arrow).modifiers(.shift).drag(from: start, to: CGPoint(x: 400, y: 210))
        let expected = ArrowGeometry.snapped45(from: start, to: CGPoint(x: 400, y: 210))
        #expect(lastShape(snapped) == .arrow(from: start, to: expected))
        #expect(expected.y == start.y)
        let diagonal = SessionHarness.annotating(.arrow).modifiers(.shift).drag(
            from: start, to: CGPoint(x: 400, y: 290))
        guard case .arrow(_, let head) = lastShape(diagonal) else {
            Issue.record("应为箭头")
            return
        }
        #expect(abs((head.x - start.x) - (head.y - start.y)) < 0.001)
    }

    @Test("画笔 / 荧光笔 / 马赛克：记录抽稀后的原始点（相邻 < 1.5 pt 丢弃）")
    func freehand() {
        let points = [
            CGPoint(x: 305, y: 200), CGPoint(x: 305.5, y: 200), CGPoint(x: 310, y: 200), CGPoint(x: 310, y: 210),
        ]
        let expected = [start, CGPoint(x: 305, y: 200), CGPoint(x: 310, y: 200), CGPoint(x: 310, y: 210)]
        let pen = SessionHarness.annotating(.pen).send(
            [.mouseDown(start, clickCount: 1)] + points.map { .mouseDragged($0) } + [.mouseUp(points[3])])
        #expect(lastShape(pen) == .pen(expected))
        let highlighter = SessionHarness.annotating(.highlighter).send(
            [.mouseDown(start, clickCount: 1)] + points.map { .mouseDragged($0) } + [.mouseUp(points[3])])
        #expect(lastShape(highlighter) == .highlighter(expected))
        #expect(highlighter.session.document.annotations.last?.style.color == .yellow)
        let mosaic = SessionHarness.annotating(.mosaic).send(
            [.mouseDown(start, clickCount: 1)] + points.map { .mouseDragged($0) } + [.mouseUp(points[3])])
        #expect(lastShape(mosaic) == .mosaic(expected))
    }

    @Test("⇧ 对自由笔迹无约束")
    func freehandIgnoresShift() {
        let pen = SessionHarness.annotating(.pen).modifiers(.shift).drag(from: start, to: CGPoint(x: 350, y: 230))
        #expect(lastShape(pen) == .pen([start, CGPoint(x: 350, y: 230)]))
    }

    @Test("形状类工具单击（无拖动）不产生标注")
    func clickWithShapeToolDoesNothing() {
        for tool in [ScreenshotTool.rectangle, .ellipse, .arrow, .pen, .highlighter, .mosaic] {
            let result = SessionHarness.annotating(tool).click(start)
            #expect(result.session.document.annotations.isEmpty)
            #expect(result.effects.isEmpty)
        }
    }

    @Test("序号：单击放置，编号自动递增；删除中间一个后续补位")
    func numbers() throws {
        let placed = SessionHarness.annotating(.number)
            .click(CGPoint(x: 300, y: 200))
            .click(CGPoint(x: 400, y: 200))
            .click(CGPoint(x: 500, y: 200))
        let document = placed.session.document
        let shapes = document.annotations.map { $0.shape }
        let labels = document.annotations.map { document.numberLabel(for: $0.id) }
        #expect(
            shapes == [
                .number(center: CGPoint(x: 300, y: 200)),
                .number(center: CGPoint(x: 400, y: 200)),
                .number(center: CGPoint(x: 500, y: 200)),
            ])
        #expect(labels == [1, 2, 3])
        #expect(document.nextNumber == 4)

        let middle = try #require(document.annotations.dropFirst().first)
        let removed = placed.send(.command(.selectTool(.pointer)))
            .click(CGPoint(x: 400, y: 200))
            .send(.command(.deleteAnnotation))
        #expect(removed.session.document.annotation(id: middle.id) == nil)
        let last = try #require(removed.session.document.annotations.last)
        #expect(removed.session.document.numberLabel(for: last.id) == 2)
    }

    @Test("序号放置后拖动不产生额外效果")
    func numberDragIsInert() {
        let result = SessionHarness.annotating(.number).drag(from: start, to: CGPoint(x: 400, y: 300))
        #expect(result.session.document.annotations.count == 1)
        #expect(result.session.drag == .none)
    }

    @Test("可以画到选区外，选区不变")
    func drawOutsideSelection() {
        let result = SessionHarness.annotating(.rectangle).drag(
            from: CGPoint(x: 900, y: 600), to: CGPoint(x: 1000, y: 700))
        #expect(lastShape(result) == .rectangle(CGRect(x: 900, y: 600, width: 100, height: 100)))
        #expect(result.session.selection == SessionHarness.selection)
    }

    @Test("手柄优先于绘制：在手柄上按下拖动是缩放选区")
    func handleBeatsDrawing() {
        let resized = SessionHarness.annotating(.rectangle).drag(
            from: CGPoint(x: 760, y: 520), to: CGPoint(x: 800, y: 560))
        #expect(resized.session.document.annotations.isEmpty)
        #expect(resized.session.selection == CGRect(x: 200, y: 150, width: 600, height: 410))
        #expect(resized.session.phase == .annotating)
        let numbered = SessionHarness.annotating(.number).click(CGPoint(x: 760, y: 520))
        #expect(numbered.session.document.annotations.isEmpty)
    }

    @Test("annotating 下双击选区内完成")
    func doubleClickFinishes() {
        let result = SessionHarness.annotating(.arrow).send(.mouseDown(CGPoint(x: 400, y: 300), clickCount: 2))
        #expect(result.effects == [.finish(.copy)])
    }

    @Test("新画的标注不被选中，并清除之前的选中")
    func drawingClearsSelection() {
        let selected = SessionHarness.adjusting()
            .drawingRectangle(CGRect(x: 300, y: 300, width: 100, height: 100))
            .click(CGPoint(x: 300, y: 350))
            .send(.command(.selectTool(.arrow)))
            .drag(from: CGPoint(x: 500, y: 200), to: CGPoint(x: 600, y: 250))
        #expect(selected.session.selectedAnnotation == nil)
        #expect(selected.session.document.annotations.count == 2)
    }

    @Test("撤销 / 重做标注")
    func undoRedo() {
        let drawn = SessionHarness.annotating(.arrow)
            .drag(from: start, to: CGPoint(x: 400, y: 260))
            .drag(from: CGPoint(x: 300, y: 400), to: CGPoint(x: 400, y: 460))
        #expect(drawn.session.document.annotations.count == 2)
        let undone = drawn.send(.command(.undo))
        #expect(undone.session.document.annotations.count == 1)
        #expect(undone.session.document.canRedo)
        let redone = undone.send(.command(.redo))
        #expect(redone.session.document.annotations == drawn.session.document.annotations)
    }

    @Test("样式条：无选中标注时改当前工具的默认样式，并通知持久化")
    func styleChangeUpdatesToolDefault() {
        let heavyBlue = AnnotationStyle(color: .blue, weight: .heavy)
        let result = SessionHarness.annotating(.arrow).send(.styleChanged(heavyBlue))
        let expected = ToolStyles.default.setting(heavyBlue, for: .arrow)
        #expect(result.session.styles == expected)
        #expect(result.effects == [.stylesChanged(expected)])
        let drawn = result.drag(from: start, to: CGPoint(x: 400, y: 260))
        #expect(drawn.session.document.annotations.last?.style == heavyBlue)
    }

    @Test("样式条：有选中标注时改它的样式，并更新该标注工具的默认样式")
    func styleChangeUpdatesSelectedAnnotation() throws {
        let green = AnnotationStyle(color: .green, weight: .light)
        let selected = SessionHarness.adjusting()
            .drawingRectangle(CGRect(x: 300, y: 300, width: 100, height: 100))
            .click(CGPoint(x: 300, y: 350))
            .send(.command(.selectTool(.arrow)))
        let result = selected.send(.styleChanged(green))
        let annotation = try #require(result.session.document.annotations.first)
        #expect(annotation.style == green)
        let expected = ToolStyles.default.setting(green, for: .rectangle)
        #expect(result.session.styles == expected)
        #expect(result.effects == [.stylesChanged(expected)])
        #expect(result.session.activeStyle == green)
        #expect(
            result.send(.command(.undo)).session.document.annotations.first?.style
                == ToolStyles.default.style(for: .rectangle))
    }

    @Test("样式未变化时不产生效果；指针模式且无选中时忽略")
    func styleChangeNoOp() {
        let same = SessionHarness.annotating(.arrow).send(.styleChanged(ToolStyles.default.style(for: .arrow)))
        #expect(same.effects.isEmpty)
        let pointer = SessionHarness.adjusting().send(.styleChanged(AnnotationStyle(color: .blue, weight: .heavy)))
        #expect(pointer.effects.isEmpty)
        #expect(pointer.session.styles == .default)
    }

    @Test("选中标注的样式与工具默认一致但标注本身不同：只改标注，不通知")
    func styleChangeOnlyAnnotation() throws {
        let blue = AnnotationStyle(color: .blue, weight: .regular)
        let selected = SessionHarness.adjusting()
            .drawingRectangle(CGRect(x: 300, y: 300, width: 100, height: 100))
            .send(.command(.selectTool(.rectangle)), .styleChanged(blue), .command(.selectTool(.rectangle)))
            .click(CGPoint(x: 300, y: 350))
        #expect(selected.session.styles == ToolStyles.default.setting(blue, for: .rectangle))
        #expect(
            try #require(selected.session.document.annotations.first).style == ToolStyles.default.style(for: .rectangle)
        )
        let result = selected.send(.styleChanged(blue))
        #expect(result.effects.isEmpty)
        #expect(try #require(result.session.document.annotations.first).style == blue)
    }

    @Test("同样的事件序列产生完全相同的会话（reducer 为纯函数、id 确定）")
    func deterministic() {
        let events: [ScreenshotEvent] = [
            .mouseDown(start, clickCount: 1), .mouseDragged(CGPoint(x: 400, y: 260)), .mouseUp(CGPoint(x: 400, y: 260)),
        ]
        let first = SessionHarness.annotating(.rectangle).send(events)
        let second = SessionHarness.annotating(.rectangle).send(events)
        #expect(first.session == second.session)
        let two = first.send(events)
        let ids = two.session.document.annotations.map(\.id)
        #expect(Set(ids).count == 2)
    }

    @Test("按下后在拖动前切到指针：拖动不产生标注")
    func toolChangedBeforeDrag() {
        let result = SessionHarness.annotating(.rectangle)
            .send(.mouseDown(start, clickCount: 1), .command(.selectTool(.rectangle)))
            .send(.mouseDragged(CGPoint(x: 400, y: 300)), .mouseUp(CGPoint(x: 400, y: 300)))
        #expect(result.session.document.annotations.isEmpty)
    }
}
