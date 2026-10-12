import AppKit
import Carbon.HIToolbox
import CoreGraphics
import Testing
@testable import CubbyCore

/// 选区锁定（晾衣绳放大编辑历史图片，docs/UI-UPGRADE-PLAN.md §5 `ClotheslineEdit`）：
/// 选区永远不变、不回 hovering；↩ = 完成并晾回、⌘C = 复制、Esc 直接放回
@Suite("ScreenshotReducer · 选区锁定（放大编辑）")
struct ReducerLockedSelectionTests {
    private static let selection = SessionHarness.selection
    private static let inside = CGPoint(x: 400, y: 300)
    private static let outside = CGPoint(x: 1000, y: 700)
    /// 右下角手柄上、仍在选区内的一点
    private static let corner = CGPoint(x: selection.maxX - 1, y: selection.maxY - 1)

    private static func locked(_ tool: ScreenshotTool = .rectangle) -> SessionHarness {
        SessionHarness(
            session: .locked(
                selection: selection, screenID: TopologyFixture.primary.id, styles: .default, cursor: inside,
                tool: tool))
    }

    /// 锁定会话 + 选区内一个矩形标注（之后回到指定工具）
    private static func annotated(_ tool: ScreenshotTool = .rectangle) -> SessionHarness {
        locked().drag(from: CGPoint(x: 300, y: 200), to: CGPoint(x: 400, y: 280))
            .send(tool == .rectangle ? [] : [.command(.selectTool(tool))])
    }

    private func expectUnchangedSelection(_ harness: SessionHarness, sourceLocation: SourceLocation = #_sourceLocation)
    {
        #expect(harness.session.selection == Self.selection, sourceLocation: sourceLocation)
        #expect(harness.session.screenID == TopologyFixture.primary.id, sourceLocation: sourceLocation)
        #expect(harness.session.isSelectionLocked, sourceLocation: sourceLocation)
        #expect(
            [ScreenshotPhase.adjusting, .annotating, .editingText].contains(harness.session.phase),
            sourceLocation: sourceLocation)
    }

    @Test("工厂：直接以工具开始标注；指针工具为 adjusting")
    func factory() {
        let session = Self.locked().session
        #expect(session.phase == .annotating)
        #expect(session.tool == .rectangle)
        #expect(session.selection == Self.selection)
        #expect(session.isSelectionLocked)
        #expect(session.isToolbarVisible)
        #expect(!session.isMagnifierVisible)
        #expect(session.hover == nil)
        let pointer = Self.locked(.pointer).session
        #expect(pointer.phase == .adjusting)
        #expect(!ScreenshotSession.initial(styles: .default, cursor: .zero).isSelectionLocked)
    }

    @Test("选区内拖拽画标注，选区不变")
    func drawsInside() {
        let drawn = Self.locked().drag(from: Self.inside, to: CGPoint(x: 500, y: 400))
        #expect(drawn.session.document.annotations.count == 1)
        expectUnchangedSelection(drawn)
    }

    @Test("选区外按下不画、不开文字编辑器、不放序号")
    func ignoresOutside() {
        for tool in [ScreenshotTool.rectangle, .pen, .text, .number, .mosaic] {
            let result = Self.locked(tool).drag(from: Self.outside, to: CGPoint(x: 1100, y: 800))
            #expect(result.session.document.annotations.isEmpty, "tool \(tool)")
            #expect(result.allEffects.isEmpty, "tool \(tool)")
            #expect(result.session.phase == .annotating, "tool \(tool)")
            expectUnchangedSelection(result)
        }
    }

    @Test("指针模式：拖选区内空白处、选区外、手柄都不改选区")
    func pointerCannotMoveOrResize() {
        let pointer = Self.locked(.pointer)
        for (start, end) in [
            (Self.inside, CGPoint(x: 600, y: 500)),
            (Self.outside, CGPoint(x: 1200, y: 850)),
            (Self.corner, CGPoint(x: 900, y: 700)),
            (CGPoint(x: Self.selection.minX, y: Self.selection.midY), CGPoint(x: 50, y: 300)),
        ] {
            let dragged = pointer.drag(from: start, to: CGPoint(x: (start.x + end.x) / 2, y: start.y), end)
            expectUnchangedSelection(dragged)
            #expect(dragged.session.phase == .adjusting)
        }
    }

    @Test("annotating 时手柄上按下是画标注，不是缩放")
    func handlesDrawInsteadOfResize() {
        let start = CGPoint(x: Self.selection.maxX - 1, y: Self.selection.maxY - 1)
        let result = Self.locked().drag(from: start, to: CGPoint(x: 500, y: 400))
        expectUnchangedSelection(result)
        #expect(result.session.document.annotations.count == 1)
    }

    @Test("指针模式仍可选中并拖动标注")
    func pointerMovesAnnotations() {
        let annotated = Self.annotated(.pointer)
        let moved = annotated.drag(from: CGPoint(x: 300, y: 240), to: CGPoint(x: 340, y: 260))
        expectUnchangedSelection(moved)
        guard case .rectangle(let rect) = moved.session.document.annotations.first?.shape else {
            Issue.record("expected a rectangle")
            return
        }
        #expect(rect.origin == CGPoint(x: 340, y: 220))
    }

    @Test("双击选区内不完成会话")
    func doubleClickDoesNotFinish() {
        let result = Self.locked(.pointer).click(Self.inside).click(Self.inside, count: 2)
        #expect(result.allEffects.isEmpty)
        expectUnchangedSelection(result)
    }

    @Test("右键不清选区、不回 hovering；拖动中右键放弃这次拖动")
    func rightClickKeepsSelection() {
        let annotated = Self.annotated()
        let clicked = annotated.send(.rightMouseDown(Self.inside))
        expectUnchangedSelection(clicked)
        #expect(clicked.session.document == annotated.session.document)
        let drawing = Self.locked().press(Self.inside, dragTo: CGPoint(x: 500, y: 450))
        let abandoned = drawing.send(.rightMouseDown(CGPoint(x: 500, y: 450)), .mouseUp(CGPoint(x: 500, y: 450)))
        #expect(abandoned.session.document.annotations.isEmpty)
        #expect(abandoned.session.drag == .none)
        expectUnchangedSelection(abandoned)
    }

    @Test("编辑文字时右键：提交文字，选区不变")
    func rightClickWhileEditingText() {
        let editing = Self.locked(.text).click(Self.inside).send(.textChanged("Hi"))
        #expect(editing.session.phase == .editingText)
        let result = editing.send(.rightMouseDown(Self.outside))
        #expect(result.session.document.annotations.count == 1)
        #expect(result.session.phase == .annotating)
        expectUnchangedSelection(result)
    }

    @Test("⌘A 与方向键不改选区；选中标注时方向键移动标注")
    func selectAllAndNudge() {
        let pointer = Self.locked(.pointer)
        let commands: [ScreenshotEvent] = [
            .command(.selectAll), .command(.nudge(.left, large: true)), .command(.nudge(.down, large: false)),
        ]
        expectUnchangedSelection(pointer.send(commands))
        let selected = Self.annotated(.pointer).click(CGPoint(x: 300, y: 240))
        #expect(selected.session.selectedAnnotation != nil)
        let nudged = selected.send(.command(.nudge(.right, large: true)))
        expectUnchangedSelection(nudged)
        guard case .rectangle(let rect) = nudged.session.document.annotations.first?.shape else {
            Issue.record("expected a rectangle")
            return
        }
        #expect(rect.origin == CGPoint(x: 310, y: 200))
    }

    @Test("Esc 有标注时也直接取消（不要求按两次）")
    func escapeCancelsImmediately() {
        let result = Self.annotated().send(.command(.escape))
        #expect(result.effects == [.finish(.cancel)])
        #expect(!result.session.isDiscardArmed)
        #expect(Self.locked().send(.command(.escape)).effects == [.finish(.cancel)])
    }

    @Test("↩ = 完成并晾回，⌘C（.copy）= 复制；工具栏同理")
    func confirmAndCopy() {
        for tool in [ScreenshotTool.pointer, .arrow] {
            let harness = Self.annotated(tool)
            #expect(harness.send(.command(.confirm)).effects == [.finish(.hangBack)])
            #expect(harness.send(.command(.copy)).effects == [.finish(.copy)])
            #expect(harness.send(.toolbarAction(.hangBack)).effects == [.finish(.hangBack)])
            #expect(harness.send(.toolbarAction(.copy)).effects == [.finish(.copy)])
            #expect(harness.send(.toolbarAction(.cancel)).effects == [.finish(.cancel)])
        }
    }

    @Test("编辑文字时 ↩ 工具栏晾回：先提交文字再完成")
    func hangBackCommitsText() {
        let editing = Self.locked(.text).click(Self.inside).send(.textChanged("Note"))
        let result = editing.send(.toolbarAction(.hangBack))
        #expect(result.effects == [.endTextEditing, .finish(.hangBack)])
        #expect(result.session.document.annotations.count == 1)
    }

    @Test("未锁定时：晾回无效，.copy 等同 ↩")
    func unlockedSemantics() {
        let adjusting = SessionHarness.adjusting()
        #expect(adjusting.send(.toolbarAction(.hangBack)).effects.isEmpty)
        #expect(adjusting.send(.command(.copy)).effects == [.finish(.copy)])
        let hovering = SessionHarness.hovering(at: TopologyFixture.editorPoint)
        #expect(hovering.send(.command(.copy)).effects == hovering.send(.command(.confirm)).effects)
    }

    @Test("锁定的选区不吸附像素网格（调用方负责对齐）")
    func noPixelSnapping() {
        let offGrid = CGRect(x: 200.3, y: 150.2, width: 560.1, height: 370.4)
        let session = ScreenshotSession.locked(
            selection: offGrid, screenID: TopologyFixture.primary.id, styles: .default, cursor: Self.inside)
        let result = SessionHarness(session: session).send(.mouseMoved(CGPoint(x: 410, y: 310)))
        #expect(result.session.selection == offGrid)
    }

    @Test("光标：没有手柄；选区外为箭头；指针模式空白处为箭头、标注上为移动")
    func cursorKinds() {
        let rectangle = Self.locked()
        #expect(rectangle.send(.mouseMoved(Self.inside)).session.cursorKind == .crosshair)
        #expect(rectangle.send(.mouseMoved(Self.outside)).session.cursorKind == .arrow)
        #expect(rectangle.send(.mouseMoved(Self.corner)).session.cursorKind == .crosshair)
        #expect(rectangle.send(.mouseMoved(Self.corner)).session.activeHandle == nil)
        let text = Self.locked(.text)
        #expect(text.send(.mouseMoved(Self.inside)).session.cursorKind == .iBeam)
        let pointer = Self.annotated(.pointer)
        #expect(pointer.send(.mouseMoved(Self.inside)).session.cursorKind == .arrow)
        #expect(pointer.send(.mouseMoved(CGPoint(x: 300, y: 240))).session.cursorKind == .move)
        #expect(pointer.send(.mouseMoved(Self.corner)).session.cursorKind == .arrow)
        #expect(pointer.send(.mouseMoved(Self.corner)).session.activeHandle == nil)
    }

    @Test("任意事件序列之后选区都不变（确定性的混合序列）")
    func mixedSequence() {
        var harness = Self.locked()
        let events: [ScreenshotEvent] = [
            .command(.selectTool(.pointer)), .mouseDown(Self.corner, clickCount: 1),
            .mouseDragged(CGPoint(x: 1300, y: 890)), .mouseUp(CGPoint(x: 1300, y: 890)),
            .command(.selectAll), .modifiersChanged(.space), .modifiersChanged([]),
            .scrolled(deltaY: -120), .command(.cycleHover(forward: true)), .command(.selectTool(.arrow)),
            .mouseDown(Self.inside, clickCount: 2), .mouseUp(Self.inside),
            .rightMouseDown(Self.outside), .command(.undo), .command(.redo), .command(.translate),
        ]
        for event in events {
            harness = harness.send(event)
            expectUnchangedSelection(harness)
        }
    }

    // MARK: - 键盘映射

    @Test("键盘：锁定时 ⌘C → .copy；↩ / ⌘↩ 仍为 .confirm；未锁定时 ⌘C → .confirm")
    func keyMapping() {
        for phase in [ScreenshotPhase.adjusting, .annotating] {
            #expect(
                ScreenshotCommand.from(
                    keyCode: UInt16(kVK_ANSI_C), modifiers: .command, characters: "c", phase: phase,
                    isSelectionLocked: true) == .copy)
            #expect(
                ScreenshotCommand.from(
                    keyCode: UInt16(kVK_ANSI_C), modifiers: .command, characters: "c", phase: phase) == .confirm)
            #expect(
                ScreenshotCommand.from(
                    keyCode: UInt16(kVK_Return), modifiers: [], characters: "\r", phase: phase,
                    isSelectionLocked: true) == .confirm)
        }
        // 编辑文字时 ⌘C 交给文本视图
        #expect(
            ScreenshotCommand.from(
                keyCode: UInt16(kVK_ANSI_C), modifiers: .command, characters: "c", phase: .editingText,
                isSelectionLocked: true) == nil)
    }

    @Test("ScreenshotKeyboard 把锁定标志传给命令映射")
    func keyboardPassesLock() {
        var keyboard = ScreenshotKeyboard()
        let key = ScreenshotKeyInput(
            keyCode: UInt16(kVK_ANSI_C), modifiers: .command, characters: "c", charactersIgnoringModifiers: "c",
            isRepeat: false, isOverlayWindow: true)
        let locked = keyboard.keyDown(key, phase: .annotating, isComposingText: false, isSelectionLocked: true)
        #expect(locked.outputs == [.event(.command(.copy))])
        let normal = keyboard.keyDown(key, phase: .annotating, isComposingText: false)
        #expect(normal.outputs == [.event(.command(.confirm))])
    }
}
