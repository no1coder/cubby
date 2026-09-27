import CoreGraphics
import Testing
@testable import CubbyCore

@Suite("ScreenshotReducer · 截图翻译：开始与流水线回报")
struct ReducerTranslationFlowTests {
    private typealias Fixture = TranslationFixture

    @Test("翻译不可用：⇧⌘T 与翻译事件一律忽略")
    func unavailableIgnoresEverything() {
        let harness = SessionHarness.adjusting()
        for event in [ScreenshotEvent.command(.translate), .translation(.start), .translation(.retry)] {
            let result = harness.send(event)
            #expect(result.session == harness.session)
            #expect(result.effects.isEmpty)
        }
    }

    @Test("开始：应用译文层（一步撤销）、进入识别、发出识别副作用")
    func startRecognizes() {
        let harness = SessionHarness.translatable()
        let started = harness.send(.command(.translate))
        let run = try! #require(started.session.translation)
        #expect(run.status == .recognizing)
        #expect(run.area == SessionHarness.selection)
        #expect(started.session.document.translation == run.id)
        #expect(started.session.document.canUndo)
        #expect(started.session.showsTranslation)
        #expect(started.session.isTranslating)
        #expect(
            started.translationEffects == [
                .recognize(run.id, selection: SessionHarness.selection, screenID: 1, hidden: [])
            ])
    }

    @Test("没有选区、拖拽中：不开始")
    func startNeedsSelection() {
        let hovering = SessionHarness.hovering()
        let hover = SessionHarness(session: hovering.session.settingTranslationAvailable(true))
        #expect(hover.send(.translation(.start)).effects.isEmpty)
        let pressed = SessionHarness.translatable().send(.mouseDown(CGPoint(x: 300, y: 300), clickCount: 1))
        #expect(pressed.send(.translation(.start)).session.translation == nil)
    }

    @Test("马赛克覆盖的区域随识别副作用传给流水线（这些块不发送）")
    func hiddenRegionsAreMosaics() {
        let mosaic = SessionHarness.translatable().send(.command(.selectTool(.mosaic)))
            .drag(from: CGPoint(x: 300, y: 300), to: CGPoint(x: 400, y: 300))
            .send(.command(.selectTool(.pointer)))
        let bounds = try! #require(mosaic.session.document.annotations.first?.bounds)
        let started = mosaic.send(.translation(.start))
        guard case .recognize(_, _, _, let hidden) = started.translationEffects.first else {
            Issue.record("expected a recognize effect")
            return
        }
        #expect(hidden == [bounds])
    }

    @Test("识别完成 → 准备翻译；开始 → 已完成 0 / 2；每块到达只更新内容，不占撤销步")
    func streamingUpdatesInPlace() {
        let recognized = SessionHarness.translatable().startedAndRecognized()
        let run = recognized.runID
        #expect(recognized.session.translation?.status == .translating(done: 0, total: 0))
        #expect(recognized.session.translation?.blocks == Fixture.blocks)
        let started = recognized.send(.translation(.started(run, Fixture.plan)))
        #expect(started.session.translation?.status == .translating(done: 0, total: 2))
        #expect(started.session.translation?.engine == Fixture.engine)
        #expect(started.session.translation?.pendingBlocks == [Fixture.hello, Fixture.world])
        let arrived = started.send(.translation(.arrived(run, Fixture.placed(Fixture.world))))
        #expect(arrived.session.translation?.status == .translating(done: 1, total: 2))
        #expect(arrived.session.translation?.translatedBlocks == [Fixture.placed(Fixture.world)])
        #expect(arrived.session.translation?.pendingBlocks == [Fixture.hello])
        #expect(arrived.session.document == started.session.document)
    }

    @Test("全部到达后结束 → 完成；可以撤销整次翻译")
    func finishedIsReady() {
        let done = SessionHarness.translatable().translated()
        #expect(done.session.translation?.status == .ready)
        #expect(!done.session.isTranslating)
        #expect(done.session.translation?.hasResult == true)
        #expect(done.session.document.undone().translation == nil)
    }

    @Test("流正常结束但缺块 → 部分完成；中途失败且已有译文 → 部分完成（带原因）")
    func partialResults() {
        let recognized = SessionHarness.translatable().startedAndRecognized()
        let run = recognized.runID
        let short = recognized.send(
            .translation(.started(run, Fixture.plan)), .translation(.arrived(run, Fixture.placed(Fixture.hello))),
            .translation(.finished(run)))
        #expect(short.session.translation?.status == .partial(missing: 1, failure: nil))
        let failed = SessionHarness.translatable().partiallyTranslated()
        #expect(failed.session.translation?.status == .partial(missing: 1, failure: Fixture.failure))
        #expect(failed.session.translation?.translatedBlocks == [Fixture.placed(Fixture.hello)])
    }

    @Test("一块都没到就失败 → 失败；识别为空 / 没有要译的 / 待选语言各有状态")
    func terminalStates() {
        let recognized = SessionHarness.translatable().startedAndRecognized()
        let run = recognized.runID
        #expect(
            recognized.send(.translation(.failed(run, .notConfigured))).session.translation?.status
                == .failed(.notConfigured))
        #expect(recognized.send(.translation(.nothingToTranslate(run))).session.translation?.status == .noText)
        #expect(
            recognized.send(.translation(.needsTargetLanguage(run))).session.translation?.status
                == .needsTargetLanguage)
        let started = SessionHarness.translatable().send(.translation(.start))
        let empty = started.send(.translation(.recognized(started.runID, [])))
        #expect(empty.session.translation?.status == .noText)
        #expect(!empty.session.isTranslating)
    }

    @Test("哪些事件是流水线回报（覆盖层暂停期间照常交给会话）")
    func pipelineReports() {
        let run = TranslationRunID(rawValue: 1)
        #expect(ScreenshotEvent.translation(.finished(run)).isTranslationReport)
        #expect(ScreenshotEvent.translation(.arrived(run, Fixture.placed(Fixture.hello))).isTranslationReport)
        #expect(!ScreenshotEvent.translation(.start).isTranslationReport)
        #expect(!ScreenshotEvent.translation(.moveWipe(10)).isTranslationReport)
        #expect(!ScreenshotEvent.mouseMoved(.zero).isTranslationReport)
    }

    @Test("过期回报（别的运行、已结束的运行）被忽略")
    func staleReportsIgnored() {
        let done = SessionHarness.translatable().translated()
        let run = done.runID
        let other = TranslationRunID(rawValue: 99)
        for event in [
            TranslationEvent.recognized(run, []), .started(run, Fixture.plan),
            .arrived(run, Fixture.placed(Fixture.number)), .finished(run), .failed(run, .network),
            .nothingToTranslate(run), .needsTargetLanguage(run), .arrived(other, Fixture.placed(Fixture.hello)),
        ] {
            #expect(done.send(.translation(event)).session == done.session)
        }
    }

    @Test("识别阶段收到译文、翻译阶段收到识别结果：忽略")
    func outOfOrderReportsIgnored() {
        let started = SessionHarness.translatable().send(.translation(.start))
        let run = started.runID
        #expect(started.send(.translation(.arrived(run, Fixture.placed(Fixture.hello)))).session == started.session)
        #expect(started.send(.translation(.started(run, Fixture.plan))).session == started.session)
        let recognized = started.send(.translation(.recognized(run, Fixture.blocks)))
        #expect(recognized.send(.translation(.recognized(run, []))).session == recognized.session)
    }

    @Test("流水线回报不解除「待确认放弃」")
    func reportsDoNotDisarm() {
        // 翻译中右键清选区回 hovering（任务继续），再右键进入待确认放弃
        let started = SessionHarness.translatable().send(.translation(.start))
        let armed = started.send(
            .rightMouseDown(TopologyFixture.desktopPoint), .rightMouseDown(TopologyFixture.desktopPoint))
        #expect(armed.session.phase == .hovering)
        #expect(armed.session.isDiscardArmed)
        let recognized = armed.send(.translation(.recognized(started.runID, Fixture.blocks)))
        #expect(recognized.session.isDiscardArmed)
        #expect(recognized.session.translation?.blocks == Fixture.blocks)
    }

    @Test("编辑文字时 ⇧⌘T：先提交文字再翻译；不可用时什么都不做（文字不提交）")
    func translateWhileEditingText() {
        let editing = SessionHarness.translatable().send(.command(.selectTool(.text)))
            .click(CGPoint(x: 300, y: 400)).send(.textChanged("Note"))
        #expect(editing.session.phase == .editingText)
        let started = editing.send(.command(.translate))
        #expect(started.session.phase == .annotating)
        #expect(started.session.document.annotations.count == 1)
        #expect(started.session.translation?.status == .recognizing)
        #expect(started.effects.first == .endTextEditing)

        let plain = SessionHarness.annotating(.text).click(CGPoint(x: 300, y: 400)).send(.textChanged("Note"))
        let ignored = plain.send(.command(.translate))
        #expect(ignored.session == plain.session)
        #expect(ignored.effects.isEmpty)
    }

    @Test("编辑文字时流水线回报照常处理，不提交文字")
    func reportsWhileEditingText() {
        let started = SessionHarness.translatable().send(.translation(.start))
        let editing = started.send(.command(.selectTool(.text))).click(CGPoint(x: 300, y: 400))
        let recognized = editing.send(.translation(.recognized(started.runID, Fixture.blocks)))
        #expect(recognized.session.phase == .editingText)
        #expect(recognized.session.translation?.blocks == Fixture.blocks)
        #expect(recognized.effects.isEmpty)
    }
}
