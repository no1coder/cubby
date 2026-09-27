import CoreGraphics
import Testing
@testable import CubbyCore

@Suite("ScreenshotReducer · 截图翻译：原文 / 译文、卷帘、按住空格、悬停与复制")
struct ReducerTranslationViewTests {
    private typealias Fixture = TranslationFixture
    private var done: SessionHarness { SessionHarness.translatable().translated() }
    private var selection: CGRect { SessionHarness.selection }

    @Test("完成后默认显示译文并导出译文；⇧⌘T 与开关切到原文后两者都是原文")
    func toggleDecidesExport() {
        #expect(done.session.translationDisplay == .full)
        #expect(done.session.exportedTranslation.count == 2)
        for event in [ScreenshotEvent.command(.translate), .translation(.showTranslation(false))] {
            let original = done.send(event)
            #expect(!original.session.showsTranslation)
            #expect(original.session.translationDisplay == .hidden)
            #expect(original.session.exportedTranslation.isEmpty)
            #expect(original.send(.command(.translate)).session.showsTranslation)
        }
    }

    @Test("翻译进行中：译文层始终显示已到达的块；开关与卷帘不可用；已到达的块照常导出")
    func busyShowsArrivedBlocks() {
        let recognized = SessionHarness.translatable().startedAndRecognized()
        let run = recognized.runID
        let arrived = recognized.send(
            .translation(.started(run, Fixture.plan)), .translation(.arrived(run, Fixture.placed(Fixture.hello))))
        #expect(arrived.session.translationDisplay == .full)
        #expect(arrived.send(.translation(.showTranslation(false))).session == arrived.session)
        #expect(arrived.send(.translation(.setWipe(true))).session == arrived.session)
        #expect(arrived.send(.command(.translate)).session == arrived.session)
        #expect(arrived.session.exportedTranslation == [Fixture.placed(Fixture.hello)])
    }

    @Test("按住空格：只看原文，松开恢复；导出不受影响；编辑文字与 hovering 时无效")
    func peekIsViewOnly() {
        let peeking = done.modifiers(.space)
        #expect(peeking.session.isPeekingOriginal)
        #expect(peeking.session.translationDisplay == .hidden)
        #expect(peeking.session.exportedTranslation.count == 2)
        #expect(peeking.modifiers([]).session.translationDisplay == .full)
        let annotating = done.send(.command(.selectTool(.arrow))).modifiers(.space)
        #expect(annotating.session.isPeekingOriginal)
        let hovering = done.send(.rightMouseDown(TopologyFixture.desktopPoint)).modifiers(.space)
        #expect(!hovering.session.isPeekingOriginal)
    }

    @Test("卷帘：打开时分隔线在选区中点；拖动夹在选区内；不影响导出；关闭复位")
    func wipeDivider() {
        let wiped = done.send(.translation(.setWipe(true)))
        #expect(wiped.session.translationDisplay == .split(x: selection.midX))
        let moved = wiped.send(.translation(.moveWipe(300)))
        #expect(moved.session.translationDisplay == .split(x: 300))
        #expect(moved.session.isWipeFocused)
        #expect(moved.send(.translation(.moveWipe(-50))).session.translationDisplay == .split(x: selection.minX))
        #expect(moved.send(.translation(.moveWipe(5000))).session.translationDisplay == .split(x: selection.maxX))
        #expect(moved.session.exportedTranslation.count == 2)
        let reopened = moved.send(.translation(.setWipe(false)), .translation(.setWipe(true)))
        #expect(reopened.session.translationDisplay == .split(x: selection.midX))
        // 开关在原文时卷帘仍然对比两者
        let original = wiped.send(.translation(.showTranslation(false)))
        #expect(original.session.translationDisplay == .split(x: selection.midX))
        // 按住空格时整层原文
        #expect(wiped.modifiers(.space).session.translationDisplay == .hidden)
    }

    @Test("卷帘获得焦点后 ← / → 微调分隔线（⇧ 大步）；点其他地方失去焦点，方向键回到移动选区")
    func wipeNudge() {
        let focused = done.send(.translation(.setWipe(true)), .translation(.moveWipe(400)))
        let small = focused.send(.command(.nudge(.right, large: false)))
        #expect(small.session.translationDisplay == .split(x: 400 + selection.width / 50))
        #expect(small.session.selection == selection)
        let large = focused.send(.command(.nudge(.left, large: true)))
        #expect(large.session.translationDisplay == .split(x: 400 - selection.width / 10))
        let clicked = focused.click(CGPoint(x: 900, y: 700))
        #expect(!clicked.session.isWipeFocused)
        let nudged = focused.send(.command(.nudge(.down, large: false)))
        #expect(nudged.session.selection == selection.offsetBy(dx: 0, dy: 1))
    }

    @Test("选区变化时分隔线复位到新中点；撤销翻译时卷帘关闭")
    func wipeResets() {
        let moved = done.send(.translation(.setWipe(true)), .translation(.moveWipe(300)))
        let nudged = moved.send(.command(.selectTool(.pointer)))
            .click(CGPoint(x: 900, y: 700)).send(.command(.nudge(.right, large: true)))
        let shifted = selection.offsetBy(dx: 10, dy: 0)
        #expect(nudged.session.selection == shifted)
        #expect(nudged.session.translationDisplay == .split(x: shifted.midX))
        let undone = moved.send(.command(.undo))
        #expect(!undone.session.isWipeEnabled)
        #expect(!undone.send(.command(.redo)).session.isWipeEnabled)
    }

    @Test("悬停看原文：指针工具停在某块译文上；工具、按住空格、卷帘左侧、标注上、拖拽中都不算")
    func hoveredBlock() {
        let onHello = CGPoint(x: 300, y: 180)
        let hovering = done.send(.mouseMoved(onHello))
        #expect(hovering.session.hoveredTranslationBlockID == 0)
        #expect(hovering.send(.mouseMoved(CGPoint(x: 600, y: 450))).session.hoveredTranslationBlockID == nil)
        #expect(hovering.send(.command(.selectTool(.arrow))).session.hoveredTranslationBlockID == nil)
        #expect(hovering.modifiers(.space).session.hoveredTranslationBlockID == nil)
        #expect(hovering.send(.mouseDown(onHello, clickCount: 1)).session.hoveredTranslationBlockID == nil)
        let split = hovering.send(.translation(.setWipe(true)), .translation(.moveWipe(400)))
        #expect(split.send(.mouseMoved(onHello)).session.hoveredTranslationBlockID == nil)
        #expect(split.send(.mouseMoved(CGPoint(x: 410, y: 180))).session.hoveredTranslationBlockID == 0)
        // 矩形的左边线紧挨着光标：命中标注，标注优先
        let covered = done.drawingRectangle(CGRect(x: 297, y: 160, width: 60, height: 40)).send(.mouseMoved(onHello))
        #expect(covered.session.hoveredTranslationBlockID == nil)
    }

    @Test("复制译文：按块 id 顺序、换行分隔、未翻译的块用原文；马赛克下与选区外的块不复制")
    func translatedText() {
        #expect(done.session.translatedText == "[T] HELLO\n[T] WORLD WIDE\n42")
        #expect(SessionHarness.translatable().session.translatedText == nil)
        let mosaic = done.send(.command(.selectTool(.mosaic)))
            .drag(from: CGPoint(x: 225, y: 220), to: CGPoint(x: 515, y: 220))
        #expect(mosaic.session.translatedText == "[T] HELLO\n42")
        let shrunk = done.drag(
            from: SelectionHandle.bottom.center(in: selection), to: CGPoint(x: selection.midX, y: 240))
        #expect(shrunk.session.translatedText == "[T] HELLO\n[T] WORLD WIDE")
        // 两块各不足 20% 的马赛克合计盖住 20% 以上：与「不发送」同一口径，同样不复制
        #expect(done.drawingSmallMosaics().session.translatedText == "[T] HELLO\n42")
    }

    @Test("选区超出识别区域时提示「选区已变化」；缩小不算")
    func staleSelection() {
        #expect(!done.session.isTranslationStale)
        let shrunk = done.drag(
            from: SelectionHandle.bottom.center(in: selection), to: CGPoint(x: selection.midX, y: 400))
        #expect(!shrunk.session.isTranslationStale)
        #expect(done.send(.command(.nudge(.left, large: false))).session.isTranslationStale)
    }

    @Test("有译文时 Esc / 快捷键视为有内容（hasDiscardableContent）")
    func translationCountsAsContent() {
        #expect(!SessionHarness.translatable().session.hasDiscardableContent)
        #expect(SessionHarness.translatable().send(.translation(.start)).session.hasDiscardableContent)
    }
}
