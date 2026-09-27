import CoreGraphics
import Testing
@testable import CubbyCore

/// 拖动手柄的用例：从手柄中心拖动 (+20, +30)
struct HandleDragCase: Sendable, CustomTestStringConvertible {
    let handle: SelectionHandle
    let expected: CGRect

    var testDescription: String { "\(handle)" }
}

@Suite("ScreenshotReducer · adjusting")
struct ReducerAdjustingTests {
    private typealias Fixture = TopologyFixture
    private let selection = SessionHarness.selection
    private let rectangle = CGRect(x: 300, y: 300, width: 100, height: 100)

    @Test(
        "8 个手柄拖动缩放，对边固定",
        arguments: [
            HandleDragCase(handle: .topLeft, expected: CGRect(x: 220, y: 180, width: 540, height: 340)),
            HandleDragCase(handle: .top, expected: CGRect(x: 200, y: 180, width: 560, height: 340)),
            HandleDragCase(handle: .topRight, expected: CGRect(x: 200, y: 180, width: 580, height: 340)),
            HandleDragCase(handle: .right, expected: CGRect(x: 200, y: 150, width: 580, height: 370)),
            HandleDragCase(handle: .bottomRight, expected: CGRect(x: 200, y: 150, width: 580, height: 400)),
            HandleDragCase(handle: .bottom, expected: CGRect(x: 200, y: 150, width: 560, height: 400)),
            HandleDragCase(handle: .bottomLeft, expected: CGRect(x: 220, y: 150, width: 540, height: 400)),
            HandleDragCase(handle: .left, expected: CGRect(x: 220, y: 150, width: 540, height: 370)),
        ])
    func resizeHandles(_ item: HandleDragCase) {
        let center = item.handle.center(in: selection)
        let target = CGPoint(x: center.x + 20, y: center.y + 30)
        let dragging = SessionHarness.adjusting().press(center, dragTo: target)
        #expect(dragging.session.drag == .resizing(item.handle))
        #expect(dragging.session.selection == item.expected)
        let released = dragging.send(.mouseUp(target))
        #expect(released.session.drag == .none)
        #expect(released.session.selection == item.expected)
        #expect(released.session.phase == .adjusting)
    }

    @Test("拖手柄保持按下时的偏移，不会吸附到光标")
    func resizeKeepsGrabOffset() {
        let result = SessionHarness.adjusting().drag(from: CGPoint(x: 205, y: 153), to: CGPoint(x: 225, y: 183))
        #expect(result.session.selection == CGRect(x: 220, y: 180, width: 540, height: 340))
    }

    @Test("拖边带（手柄之间）按同侧边手柄缩放")
    func resizeByEdgeBand() {
        let result = SessionHarness.adjusting().drag(from: CGPoint(x: 350, y: 151), to: CGPoint(x: 350, y: 101))
        #expect(result.session.selection == CGRect(x: 200, y: 100, width: 560, height: 420))
    }

    @Test("⇧ 拖角手柄约束正方形")
    func resizeSquare() {
        let result = SessionHarness.adjusting().modifiers(.shift)
            .drag(from: CGPoint(x: 760, y: 520), to: CGPoint(x: 900, y: 560))
        #expect(result.session.selection == CGRect(x: 200, y: 150, width: 410, height: 410))
    }

    @Test("越过对边时停在最小尺寸")
    func resizeStopsAtMinimum() {
        let result = SessionHarness.adjusting().drag(from: CGPoint(x: 760, y: 335), to: CGPoint(x: 0, y: 335))
        #expect(result.session.selection == CGRect(x: 200, y: 150, width: 4, height: 370))
    }

    @Test("缩放夹紧在选区所在屏幕内（不会拉到外接屏）")
    func resizeClampedToScreen() {
        let result = SessionHarness.adjusting().drag(from: CGPoint(x: 760, y: 335), to: CGPoint(x: 2000, y: 335))
        #expect(result.session.selection == CGRect(x: 200, y: 150, width: 1240, height: 370))
    }

    @Test("在选区内拖动移动选区，夹紧在同一块屏幕")
    func moveSelection() {
        let moved = SessionHarness.adjusting().drag(from: CGPoint(x: 400, y: 300), to: CGPoint(x: 450, y: 350))
        #expect(moved.session.selection == CGRect(x: 250, y: 200, width: 560, height: 370))
        let clamped = SessionHarness.adjusting().drag(from: CGPoint(x: 400, y: 300), to: CGPoint(x: 2400, y: 300))
        #expect(clamped.session.selection == CGRect(x: 880, y: 150, width: 560, height: 370))
    }

    @Test("移动选区到边缘后往回拖，选区跟随光标的总位移（无漂移）")
    func moveSelectionWithoutDrift() {
        let result = SessionHarness.adjusting()
            .drag(from: CGPoint(x: 400, y: 300), to: CGPoint(x: 2400, y: 300), CGPoint(x: 410, y: 300))
        #expect(result.session.selection == CGRect(x: 210, y: 150, width: 560, height: 370))
    }

    @Test("在选区内 / 外单击不改变选区")
    func clicksKeepSelection() {
        let inside = SessionHarness.adjusting().click(CGPoint(x: 400, y: 300))
        #expect(inside.session.selection == selection)
        #expect(inside.session.phase == .adjusting)
        let outside = SessionHarness.adjusting().click(CGPoint(x: 1000, y: 800))
        #expect(outside.session.selection == selection)
        #expect(outside.allEffects.isEmpty)
    }

    @Test("单击标注选中它；单击选区外取消选中")
    func selectAndDeselectAnnotation() throws {
        let annotated = SessionHarness.adjusting().drawingRectangle(rectangle)
        let id = try #require(annotated.session.document.annotations.first?.id)
        let selected = annotated.click(CGPoint(x: 300, y: 350))
        #expect(selected.session.selectedAnnotation == id)
        let deselected = selected.click(CGPoint(x: 1000, y: 800))
        #expect(deselected.session.selectedAnnotation == nil)
        let reselected = selected.click(CGPoint(x: 600, y: 450))
        #expect(reselected.session.selectedAnnotation == nil)
    }

    @Test("选区外的标注也能单击选中")
    func selectAnnotationOutsideSelection() {
        let annotated = SessionHarness.adjusting().drawingRectangle(CGRect(x: 900, y: 600, width: 100, height: 100))
        let selected = annotated.click(CGPoint(x: 900, y: 650))
        #expect(selected.session.selectedAnnotation == annotated.session.document.annotations.first?.id)
    }

    @Test("拖动标注平移它，松开后只入一步撤销")
    func moveAnnotation() throws {
        let annotated = SessionHarness.adjusting().drawingRectangle(rectangle)
        let original = try #require(annotated.session.document.annotations.first)
        let dragging = annotated.press(
            CGPoint(x: 300, y: 350), dragTo: CGPoint(x: 320, y: 360), CGPoint(x: 340, y: 380))
        #expect(dragging.session.drag == .movingAnnotation(original.id, last: CGPoint(x: 340, y: 380)))
        let released = dragging.send(.mouseUp(CGPoint(x: 340, y: 380)))
        let moved = try #require(released.session.document.annotation(id: original.id))
        #expect(moved == original.translated(by: CGVector(dx: 40, dy: 30)))
        #expect(released.session.selection == selection)
        let undone = released.send(.command(.undo))
        #expect(undone.session.document.annotations == [original])
    }

    @Test("拖动标注但回到原位：文档不变")
    func moveAnnotationBackToStart() {
        let annotated = SessionHarness.adjusting().drawingRectangle(rectangle)
        let result = annotated.drag(from: CGPoint(x: 300, y: 350), to: CGPoint(x: 320, y: 350), CGPoint(x: 300, y: 350))
        #expect(result.session.document.annotations == annotated.session.document.annotations)
    }

    @Test("双击选区内完成（复制）；双击选区外无效")
    func doubleClick() {
        let inside = SessionHarness.adjusting().send(.mouseDown(CGPoint(x: 400, y: 300), clickCount: 2))
        #expect(inside.effects == [.finish(.copy)])
        let outside = SessionHarness.adjusting().send(.mouseDown(CGPoint(x: 1000, y: 800), clickCount: 2))
        #expect(outside.effects.isEmpty)
    }

    @Test("悬停时双击窗口：第一次单击选中，第二次落在选区内完成")
    func doubleClickWindowFromHovering() {
        let result = SessionHarness.hovering()
            .click(Fixture.editorPoint)
            .send(.mouseDown(Fixture.editorPoint, clickCount: 2))
        #expect(result.effects == [.finish(.copy)])
        #expect(result.session.selection == Fixture.editor.frame)
    }

    @Test(
        "方向键移动选区 1 / 10 pt",
        arguments: [
            (NudgeDirection.up, false, CGRect(x: 200, y: 149, width: 560, height: 370)),
            (NudgeDirection.down, true, CGRect(x: 200, y: 160, width: 560, height: 370)),
            (NudgeDirection.left, true, CGRect(x: 190, y: 150, width: 560, height: 370)),
            (NudgeDirection.right, false, CGRect(x: 201, y: 150, width: 560, height: 370)),
        ])
    func nudgeSelection(_ direction: NudgeDirection, _ large: Bool, _ expected: CGRect) {
        let result = SessionHarness.adjusting().send(.command(.nudge(direction, large: large)))
        #expect(result.session.selection == expected)
    }

    @Test("方向键微调夹紧在屏幕内")
    func nudgeClamped() {
        let full = SessionHarness.hovering().send(.command(.selectAll), .command(.nudge(.left, large: true)))
        #expect(full.session.selection == Fixture.primary.frame)
    }

    @Test("选中标注时方向键移动标注而不是选区")
    func nudgeAnnotation() throws {
        let selected = SessionHarness.adjusting().drawingRectangle(rectangle).click(CGPoint(x: 300, y: 350))
        let original = try #require(selected.session.document.annotations.first)
        let result = selected.send(.command(.nudge(.right, large: true)))
        #expect(result.session.selection == selection)
        #expect(result.session.document.annotation(id: original.id) == original.translated(by: CGVector(dx: 10, dy: 0)))
    }

    @Test("⌫ 删除选中标注；未选中时无效")
    func deleteAnnotation() {
        let annotated = SessionHarness.adjusting().drawingRectangle(rectangle)
        let untouched = annotated.send(.command(.deleteAnnotation))
        #expect(untouched.session.document.annotations.count == 1)
        let deleted = annotated.click(CGPoint(x: 300, y: 350)).send(.command(.deleteAnnotation))
        #expect(deleted.session.document.annotations.isEmpty)
        #expect(deleted.session.selectedAnnotation == nil)
        #expect(deleted.send(.command(.undo)).session.document.annotations.count == 1)
    }

    @Test("⌘A：选区扩为所在整屏")
    func selectAllExpands() {
        let result = SessionHarness.adjusting().send(.command(.selectAll))
        #expect(result.session.selection == Fixture.primary.frame)
        #expect(result.session.phase == .adjusting)
    }

    @Test("右键清除选区回 hovering，标注保留、工具复位")
    func rightClickClearsSelection() {
        let annotated = SessionHarness.adjusting().drawingRectangle(rectangle).send(.command(.selectTool(.arrow)))
        let result = annotated.send(.rightMouseDown(Fixture.editorPoint))
        #expect(result.effects.isEmpty)
        #expect(result.session.phase == .hovering)
        #expect(result.session.selection == nil)
        #expect(result.session.screenID == nil)
        #expect(result.session.tool == .pointer)
        #expect(result.session.document == annotated.session.document)
        #expect(result.session.hover == .window(Fixture.editor, screen: Fixture.primary))
        #expect(result.session.highlightedRect == Fixture.editor.frame)
    }

    @Test(
        "出口命令与工具栏按钮",
        arguments: [
            (ScreenshotEvent.command(.confirm), ScreenshotOutcome.copy),
            (.command(.save), .save),
            (.command(.pin), .pin),
            (.command(.extractText), .extractText),
            (.toolbarAction(.copy), .copy),
            (.toolbarAction(.save), .save),
            (.toolbarAction(.pin), .pin),
            (.toolbarAction(.extractText), .extractText),
            (.toolbarAction(.cancel), .cancel),
        ])
    func outcomes(_ event: ScreenshotEvent, _ outcome: ScreenshotOutcome) {
        #expect(SessionHarness.adjusting().send(event).effects == [.finish(outcome)])
        #expect(SessionHarness.annotating(.arrow).send(event).effects == [.finish(outcome)])
    }

    @Test("放大镜隐藏时取色无效；拖手柄时有效")
    func copyColorVisibility() {
        #expect(SessionHarness.adjusting().send(.toolbarAction(.copyColor("#000000"))).effects.isEmpty)
        let resizing = SessionHarness.adjusting().press(CGPoint(x: 760, y: 520), dragTo: CGPoint(x: 800, y: 560))
        #expect(resizing.send(.toolbarAction(.copyColor("#000000"))).effects == [.finish(.copyColor("#000000"))])
    }

    @Test("撤销 / 重做只作用于标注，不影响选区")
    func undoOnlyAffectsAnnotations() {
        let annotated = SessionHarness.adjusting().drawingRectangle(rectangle)
        let moved = annotated.drag(from: CGPoint(x: 600, y: 450), to: CGPoint(x: 650, y: 480))
        let movedSelection = CGRect(x: 250, y: 180, width: 560, height: 370)
        #expect(moved.session.selection == movedSelection)
        let undone = moved.send(.command(.undo))
        #expect(undone.session.document.annotations.isEmpty)
        #expect(undone.session.selection == movedSelection)
        let redone = undone.send(.command(.redo))
        #expect(redone.session.document.annotations.count == 1)
        #expect(redone.session.selection == movedSelection)
    }

    @Test("撤销掉选中的标注后清除选中")
    func undoClearsDanglingSelection() {
        let selected = SessionHarness.adjusting().drawingRectangle(rectangle).click(CGPoint(x: 300, y: 350))
        let result = selected.send(.command(.undo))
        #expect(result.session.selectedAnnotation == nil)
    }

    @Test("调整选区不改变已有标注的屏幕坐标")
    func selectionChangesKeepAnnotations() {
        let annotated = SessionHarness.adjusting().drawingRectangle(rectangle)
        let result =
            annotated
            .drag(from: CGPoint(x: 760, y: 520), to: CGPoint(x: 900, y: 700))
            .drag(from: CGPoint(x: 600, y: 450), to: CGPoint(x: 500, y: 350))
            .send(.command(.nudge(.down, large: true)), .command(.selectAll))
        #expect(result.session.document.annotations == annotated.session.document.annotations)
    }

    @Test("adjusting 下 V 无效，工具键进入 annotating")
    func toolKeys() {
        let pointer = SessionHarness.adjusting().send(.command(.selectTool(.pointer)))
        #expect(pointer.session.phase == .adjusting)
        let rectangle = SessionHarness.adjusting().send(.command(.selectTool(.rectangle)))
        #expect(rectangle.session.phase == .annotating)
        #expect(rectangle.session.tool == .rectangle)
    }

    @Test("滚轮与 Tab 在 adjusting 下无效")
    func cyclingIgnored() {
        let start = SessionHarness.adjusting()
        #expect(start.send(.scrolled(deltaY: -200)).session == start.session)
        #expect(start.send(.command(.cycleHover(forward: true))).session == start.session)
    }

    @Test("拖动过程中方向键 / 撤销 / ⌘A 被忽略")
    func commandsIgnoredWhileDragging() {
        let dragging = SessionHarness.adjusting().press(CGPoint(x: 400, y: 300), dragTo: CGPoint(x: 450, y: 350))
        for command in [ScreenshotCommand.nudge(.up, large: false), .undo, .redo, .selectAll] {
            #expect(dragging.send(.command(command)).session.selection == dragging.session.selection)
        }
    }

    @Test("选区所在屏的 id 不在拓扑中时，按选区中心所在屏夹紧")
    func boundsFallbackToSelectionCenter() {
        let orphan = SessionHarness.hovering().send(.command(.selectAll)).session.updating { $0.screenID = 99 }
        let result = SessionHarness(session: orphan).send(.command(.nudge(.left, large: true)))
        #expect(result.session.selection == Fixture.primary.frame)
        let lost = orphan.updating { $0.selection = CGRect(x: 1000, y: -150, width: 10, height: 10) }
        let untouched = SessionHarness(session: lost).send(.command(.nudge(.left, large: true)))
        #expect(untouched.session.selection == lost.selection)
    }

    @Test(
        "按下鼠标期间（拖拽前 / 拖拽中）忽略会改动文档或选区的命令",
        arguments: [
            ScreenshotEvent.command(.deleteAnnotation), .command(.undo), .command(.redo), .command(.selectAll),
            .command(.nudge(.right, large: true)), .styleChanged(AnnotationStyle(color: .blue, weight: .heavy)),
        ])
    func mutatingCommandsIgnoredWhilePressed(_ event: ScreenshotEvent) {
        let grab = CGPoint(x: 300, y: 350)
        let selected = SessionHarness.adjusting().drawingRectangle(rectangle).click(grab)
        let pressed = selected.send(.mouseDown(grab, clickCount: 1))
        let pending = pressed.send(event)
        #expect(pending.session.document == pressed.session.document)
        #expect(pending.session.selection == pressed.session.selection)
        #expect(pending.session.styles == pressed.session.styles)

        let dragging = pressed.send(.mouseDragged(CGPoint(x: 340, y: 380)))
        let during = dragging.send(event)
        #expect(during.session.document == dragging.session.document)
        #expect(during.session.selection == dragging.session.selection)

        let end: [ScreenshotEvent] = [.mouseDragged(CGPoint(x: 350, y: 390)), .mouseUp(CGPoint(x: 350, y: 390))]
        #expect(during.send(end).session.document == dragging.send(end).session.document)
        #expect(pending.send(end).session.document == pressed.send(end).session.document)
    }

    @Test("拖动标注途中按 ⌫：标注不消失也不复活，撤销一步回到拖动前")
    func deleteWhileMovingAnnotation() throws {
        let annotated = SessionHarness.adjusting().drawingRectangle(rectangle)
        let original = try #require(annotated.session.document.annotations.first)
        let dragging =
            annotated
            .send(.mouseDown(CGPoint(x: 300, y: 350), clickCount: 1), .mouseDragged(CGPoint(x: 320, y: 370)))
        let deleted = dragging.send(.command(.deleteAnnotation))
        #expect(deleted.session.document == dragging.session.document)
        let result = deleted.send(.mouseDragged(CGPoint(x: 340, y: 380)), .mouseUp(CGPoint(x: 340, y: 380)))
        #expect(result.session.document.annotations == [original.translated(by: CGVector(dx: 40, dy: 30))])
        #expect(result.send(.command(.undo)).session.document.annotations == [original])
    }

    @Test("选区内按下后未拖满 4 pt 时 ⌘Z / ⌘A / 方向键被忽略，随后的拖动照常移动选区")
    func pendingPressIgnoresSelectionCommands() {
        let pressed = SessionHarness.adjusting().drawingRectangle(rectangle)
            .send(.mouseDown(CGPoint(x: 600, y: 450), clickCount: 1))
        let ignored = pressed.send(.command(.undo), .command(.selectAll), .command(.nudge(.left, large: true)))
        #expect(ignored.session.selection == selection)
        #expect(ignored.session.document == pressed.session.document)
        let moved = ignored.send(.mouseDragged(CGPoint(x: 650, y: 450)), .mouseUp(CGPoint(x: 650, y: 450)))
        #expect(moved.session.selection == CGRect(x: 250, y: 150, width: 560, height: 370))
        #expect(moved.session.document.annotations.count == 1)
    }

    @Test("hovering 按下鼠标期间 ⌘A 被忽略")
    func hoveringPressIgnoresSelectAll() {
        let result = SessionHarness.hovering().send(
            .mouseDown(Fixture.desktopPoint, clickCount: 1), .command(.selectAll))
        #expect(result.session.phase == .hovering)
        #expect(result.session.selection == nil)
    }

    @Test("按住鼠标时执行不改变选区 / 文档的命令：按下仍然有效")
    func harmlessCommandKeepsPress() {
        let result = SessionHarness.adjusting()
            .send(.mouseDown(CGPoint(x: 400, y: 300), clickCount: 1), .command(.redo))
            .send(.mouseDragged(CGPoint(x: 450, y: 300)), .mouseUp(CGPoint(x: 450, y: 300)))
        #expect(result.session.selection == CGRect(x: 250, y: 150, width: 560, height: 370))
    }
}
