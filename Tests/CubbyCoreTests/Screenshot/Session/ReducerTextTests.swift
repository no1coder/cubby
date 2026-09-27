import CoreGraphics
import Testing
@testable import CubbyCore

@Suite("ScreenshotReducer · 文字编辑")
struct ReducerTextTests {
    private typealias Fixture = TopologyFixture
    private let point = CGPoint(x: 300, y: 200)

    private var editing: SessionHarness {
        SessionHarness.annotating(.text).send(.mouseDown(point, clickCount: 1))
    }

    private func textShapes(_ harness: SessionHarness) -> [AnnotationShape] {
        harness.session.document.annotations.map { $0.shape }
    }

    @Test("文字工具单击：打开编辑器，宽度到选区右缘")
    func beginEditing() {
        let result = editing
        let state = TextEditingState(origin: point, existing: nil, text: "", maxWidth: 460)
        #expect(result.session.phase == .editingText)
        #expect(result.session.textEditing == state)
        #expect(result.effects == [.beginTextEditing(state, initialText: "")])
        #expect(result.session.isToolbarVisible)
        #expect(!result.session.isMagnifierVisible)
    }

    @Test("编辑器最小宽 40 pt；在选区外单击时宽度到屏幕右缘")
    func maxWidthRules() {
        let nearEdge = SessionHarness.annotating(.text).send(.mouseDown(CGPoint(x: 740, y: 200), clickCount: 1))
        #expect(nearEdge.session.textEditing?.maxWidth == 40)
        let outside = SessionHarness.annotating(.text).send(.mouseDown(CGPoint(x: 900, y: 600), clickCount: 1))
        #expect(outside.session.textEditing?.maxWidth == 540)
    }

    @Test("拖拽 = 单击：按下即打开编辑器，随后的拖动与松开被忽略")
    func dragIsClick() {
        let result = editing.send(.mouseDragged(CGPoint(x: 400, y: 300)), .mouseUp(CGPoint(x: 400, y: 300)))
        #expect(result.session.phase == .editingText)
        #expect(result.session.textEditing?.origin == point)
        #expect(result.session.cursor == CGPoint(x: 400, y: 300))
    }

    @Test("Esc 提交已输入的文字（不退出会话）")
    func escapeCommits() {
        let result = editing.send(.textChanged("Hello"), .command(.escape))
        #expect(result.effects == [.endTextEditing])
        #expect(result.session.phase == .annotating)
        #expect(result.session.textEditing == nil)
        #expect(textShapes(result) == [.text("Hello", origin: point, maxWidth: 460)])
        #expect(result.session.document.annotations.first?.style == ToolStyles.default.style(for: .text))
    }

    @Test("⌘↩ 提交")
    func commandReturnCommits() {
        let result = editing.send(.textChanged("Line 1\nLine 2"), .command(.commitText))
        #expect(textShapes(result) == [.text("Line 1\nLine 2", origin: point, maxWidth: 460)])
    }

    @Test("textCommitted 以给定文本提交；末尾空白与换行被去掉")
    func explicitCommit() {
        let result = editing.send(.textChanged("ignored"), .textCommitted("  Hi\n\n"))
        #expect(textShapes(result) == [.text("  Hi", origin: point, maxWidth: 460)])
        #expect(result.effects == [.endTextEditing])
    }

    @Test("空文本或纯空白：丢弃，不产生标注")
    func blankDiscards() {
        #expect(editing.send(.command(.escape)).session.document.annotations.isEmpty)
        #expect(editing.send(.textChanged(" \n "), .command(.escape)).session.document.annotations.isEmpty)
        let discarded = editing.send(.textChanged("abc"), .textCommitted(nil))
        #expect(discarded.session.document.annotations.isEmpty)
        #expect(discarded.session.phase == .annotating)
        #expect(!discarded.session.document.canUndo)
    }

    @Test("点击文本框外：提交，且该点击不再产生其他效果")
    func clickOutsideCommitsOnly() {
        let result = editing.send(.textChanged("A"))
            .send(.mouseDown(CGPoint(x: 500, y: 400), clickCount: 1), .mouseUp(CGPoint(x: 500, y: 400)))
        #expect(result.session.phase == .annotating)
        #expect(result.session.textEditing == nil)
        #expect(result.session.document.annotations.count == 1)
        #expect(result.allEffects.filter { $0 == .endTextEditing }.count == 1)
        #expect(result.effects.isEmpty)
    }

    @Test("编辑中双击外部只提交，不完成会话")
    func doubleClickWhileEditing() {
        let result = editing.send(.textChanged("A"), .mouseDown(CGPoint(x: 500, y: 400), clickCount: 2))
        #expect(result.effects == [.endTextEditing])
    }

    @Test("单击已有文字：重新打开编辑器，提交后原位替换并可撤销")
    func reeditExistingText() throws {
        let committed = editing.send(.textChanged("Hello"), .command(.escape))
        let original = try #require(committed.session.document.annotations.first)
        let reopened = committed.send(.mouseDown(CGPoint(x: 305, y: 210), clickCount: 1))
        let state = TextEditingState(origin: point, existing: original.id, text: "Hello", maxWidth: 460)
        #expect(reopened.session.phase == .editingText)
        #expect(reopened.session.textEditing == state)
        #expect(reopened.session.selectedAnnotation == original.id)
        #expect(reopened.effects == [.beginTextEditing(state, initialText: "Hello")])

        let edited = reopened.send(.textChanged("Hello world"), .command(.escape))
        #expect(edited.session.document.annotations.count == 1)
        #expect(edited.session.document.annotations.first == original.withText("Hello world"))
        #expect(edited.session.selectedAnnotation == nil)
        #expect(edited.send(.command(.undo)).session.document.annotations.first == original)
    }

    @Test("重新编辑但未修改：不产生撤销步")
    func reeditUnchanged() {
        let committed = editing.send(.textChanged("Hello"), .command(.escape))
        let result = committed.send(.mouseDown(CGPoint(x: 305, y: 210), clickCount: 1), .command(.escape))
        #expect(result.session.document == committed.session.document)
    }

    @Test("重新编辑并清空：删除该文字标注")
    func reeditToEmptyRemoves() {
        let committed = editing.send(.textChanged("Hello"), .command(.escape))
        let result = committed.send(
            .mouseDown(CGPoint(x: 305, y: 210), clickCount: 1), .textChanged(""), .command(.escape))
        #expect(result.session.document.annotations.isEmpty)
    }

    @Test("文字工具单击其他类型标注：新建文字而不是重新编辑")
    func clickOnNonTextAnnotation() {
        let result = SessionHarness.annotating(.number)
            .click(point)
            .send(.command(.selectTool(.text)), .mouseDown(point, clickCount: 1))
        #expect(result.session.textEditing?.existing == nil)
    }

    @Test("右键：先提交文字，再清除选区回 hovering")
    func rightClickCommitsThenClears() {
        let result = editing.send(.textChanged("Keep"), .rightMouseDown(Fixture.desktopPoint))
        #expect(result.effects == [.endTextEditing])
        #expect(result.session.phase == .hovering)
        #expect(result.session.selection == nil)
        #expect(textShapes(result) == [.text("Keep", origin: point, maxWidth: 460)])
    }

    @Test("编辑中点工具栏 ✓：先提交再完成")
    func toolbarDoneCommitsFirst() {
        let result = editing.send(.textChanged("Done"), .toolbarAction(.copy))
        #expect(result.effects == [.endTextEditing, .finish(.copy)])
        #expect(result.session.document.annotations.count == 1)
    }

    @Test("编辑中切换工具：先提交再切换")
    func toolSwitchCommitsFirst() {
        let result = editing.send(.textChanged("T"), .command(.selectTool(.arrow)))
        #expect(result.effects == [.endTextEditing])
        #expect(result.session.tool == .arrow)
        #expect(result.session.phase == .annotating)
        #expect(result.session.document.annotations.count == 1)
    }

    @Test("编辑中改样式：不提交；提交时使用新样式")
    func styleWhileEditing() {
        let large = AnnotationStyle(color: .white, weight: .heavy)
        let styled = editing.send(.textChanged("Big"), .styleChanged(large))
        #expect(styled.session.phase == .editingText)
        #expect(styled.effects == [.stylesChanged(ToolStyles.default.setting(large, for: .text))])
        #expect(styled.session.activeStyle == large)
        let committed = styled.send(.command(.escape))
        #expect(committed.session.document.annotations.first?.style == large)
    }

    @Test("编辑中其他事件：移动、修饰键、滚动、无关命令")
    func otherEventsWhileEditing() {
        let base = editing.send(.textChanged("x"))
        let moved = base.send(.mouseMoved(CGPoint(x: 10, y: 10)))
        #expect(moved.session.cursor == CGPoint(x: 10, y: 10))
        #expect(moved.session.phase == .editingText)
        let shifted = base.modifiers(.shift)
        #expect(shifted.session.modifiers == .shift)
        #expect(shifted.session.phase == .editingText)
        let scrolled = base.send(.scrolled(deltaY: -100))
        #expect(scrolled.session == base.session)
    }

    @Test("非编辑阶段的文字事件被忽略")
    func textEventsOutsideEditing() {
        let start = SessionHarness.annotating(.text)
        #expect(start.send(.textChanged("x")).session == start.session)
        #expect(start.send(.textCommitted("x")).session == start.session)
        #expect(start.send(.command(.commitText)).session == start.session)
    }

    @Test("editingText 下 Esc 不会触发放弃确认")
    func escapeDoesNotArmDiscard() {
        let annotated = SessionHarness.annotating(.number).click(CGPoint(x: 400, y: 400))
            .send(.command(.selectTool(.text)), .mouseDown(point, clickCount: 1), .command(.escape))
        #expect(!annotated.session.isDiscardArmed)
        #expect(annotated.effects == [.endTextEditing])
    }

    @Test("5 万个空白后跟一个字符：提交在线性时间内完成（不能用回溯正则）", .timeLimit(.minutes(1)))
    func longWhitespaceCommitIsLinear() throws {
        let spaces = String(repeating: " ", count: 50_000)
        let clock = ContinuousClock()
        var result: SessionHarness?
        let elapsed = clock.measure {
            result = editing.send(.textChanged(spaces + "x"), .command(.escape))
        }
        #expect(elapsed < .seconds(1))
        let shape = try #require(result?.session.document.annotations.first?.shape)
        #expect(shape == .text(spaces + "x", origin: point, maxWidth: 460))

        let trailing = editing.send(.textChanged("x" + spaces + "\n\n"), .command(.escape))
        #expect(textShapes(trailing) == [.text("x", origin: point, maxWidth: 460)])
        let blank = editing.send(.textChanged(spaces), .command(.escape))
        #expect(blank.session.document.annotations.isEmpty)
    }
}
