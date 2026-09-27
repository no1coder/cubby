import AppKit
import CoreGraphics
import Testing
@testable import CubbyCore

@Suite("ScreenshotSession 初始值与派生属性")
struct ScreenshotSessionTests {
    private typealias Fixture = TopologyFixture

    @Test("initial：悬停阶段、指针工具、HEX、无选区")
    func initialValues() {
        let session = ScreenshotSession.initial(styles: .default, cursor: CGPoint(x: 10, y: 20))
        #expect(session.phase == .hovering)
        #expect(session.cursor == CGPoint(x: 10, y: 20))
        #expect(session.selection == nil)
        #expect(session.screenID == nil)
        #expect(session.hover == nil)
        #expect(session.modifiers == [])
        #expect(session.tool == .pointer)
        #expect(session.styles == .default)
        #expect(session.document == .empty)
        #expect(session.selectedAnnotation == nil)
        #expect(session.drag == .none)
        #expect(session.textEditing == nil)
        #expect(session.colorFormat == .hex)
        #expect(session.isDiscardArmed == false)
        #expect(session.hoverDepth == 0)
        #expect(session.isWindowCaptureMode == false)
        #expect(session.hasAnnotations == false)
    }

    @Test("initial(topology:) 同时计算悬停目标")
    func initialWithTopology() {
        let session = ScreenshotSession.initial(
            styles: .default, cursor: Fixture.editorPoint, topology: Fixture.twoScreens)
        #expect(session.hover == .window(Fixture.editor, screen: Fixture.primary))
        #expect(session.highlightedRect == Fixture.editor.frame)
    }

    @Test("悬停阶段：放大镜可见、工具栏隐藏、高亮 = 悬停目标")
    func hoveringDerived() {
        let session = SessionHarness.hovering(at: Fixture.editorPoint).session
        #expect(session.isMagnifierVisible)
        #expect(!session.isToolbarVisible)
        #expect(session.highlightedRect == Fixture.editor.frame)
    }

    @Test("adjusting：放大镜隐藏、工具栏可见、高亮 = 选区")
    func adjustingDerived() {
        let session = SessionHarness.adjusting().session
        #expect(!session.isMagnifierVisible)
        #expect(session.isToolbarVisible)
        #expect(session.highlightedRect == SessionHarness.selection)
    }

    @Test("拖手柄时放大镜出现、工具栏隐藏；画标注时工具栏保留")
    func dragVisibility() {
        let resizing = SessionHarness.adjusting().press(CGPoint(x: 760, y: 520), dragTo: CGPoint(x: 800, y: 560))
            .session
        #expect(resizing.drag == .resizing(.bottomRight))
        #expect(resizing.isMagnifierVisible)
        #expect(!resizing.isToolbarVisible)

        let moving = SessionHarness.adjusting().press(CGPoint(x: 400, y: 300), dragTo: CGPoint(x: 420, y: 320)).session
        #expect(moving.drag == .movingSelection(last: CGPoint(x: 420, y: 320)))
        #expect(!moving.isMagnifierVisible)
        #expect(!moving.isToolbarVisible)

        let drawing = SessionHarness.annotating(.rectangle)
            .press(CGPoint(x: 300, y: 300), dragTo: CGPoint(x: 340, y: 340)).session
        #expect(!drawing.isMagnifierVisible)
        #expect(drawing.isToolbarVisible)
    }

    @Test("activeStyle / styleBarTool：选中标注优先，其次当前工具")
    func styleBarContext() {
        let styles = ToolStyles.default.setting(AnnotationStyle(color: .blue, weight: .heavy), for: .arrow)
        let hovering = SessionHarness.hovering(styles: styles)
        #expect(hovering.session.styleBarTool == nil)

        let arrow = hovering.drag(from: CGPoint(x: 200, y: 150), to: CGPoint(x: 760, y: 520))
            .send(.command(.selectTool(.arrow)))
        #expect(arrow.session.styleBarTool == .arrow)
        #expect(arrow.session.activeStyle == AnnotationStyle(color: .blue, weight: .heavy))

        let adjusting = SessionHarness.adjusting()
        #expect(adjusting.session.styleBarTool == nil)
        #expect(adjusting.session.activeStyle == ScreenshotTool.pointer.defaultStyle)

        let selected = adjusting.drawingRectangle(CGRect(x: 300, y: 300, width: 100, height: 100))
            .click(CGPoint(x: 300, y: 350))
        #expect(selected.session.selectedAnnotation != nil)
        #expect(selected.session.styleBarTool == .rectangle)
        #expect(selected.session.activeStyle == ScreenshotTool.rectangle.defaultStyle)
    }

    @Test("KeyModifiers 从 NSEvent 修饰键转换，空格单独传入")
    func keyModifiersFromFlags() {
        #expect(KeyModifiers(flags: [.shift, .command]) == [.shift, .command])
        #expect(KeyModifiers(flags: [.option, .capsLock, .function]) == [.option])
        #expect(KeyModifiers(flags: [], spaceDown: true) == [.space])
        #expect(KeyModifiers(flags: .control) == [])
    }

    @Test("TextEditingState 可由调用方构造")
    func textEditingStateInit() {
        let state = TextEditingState(origin: CGPoint(x: 1, y: 2), existing: nil, text: "a", maxWidth: 50)
        #expect(state.origin == CGPoint(x: 1, y: 2))
        #expect(state.existing == nil)
        #expect(state.text == "a")
        #expect(state.maxWidth == 50)
    }

    @Test("ScreenshotHint 提供英文 key 的本地化文案")
    func hintMessage() {
        let hints: [ScreenshotHint] = [
            .pressEscapeAgainToDiscard, .translationCancelled, .translationCancelledPressEscapeAgain,
            .translationClosed,
        ]
        #expect(hints.allSatisfy { !$0.message.isEmpty })
        #expect(Set(hints.map(\.message)).count == hints.count)
    }
}
