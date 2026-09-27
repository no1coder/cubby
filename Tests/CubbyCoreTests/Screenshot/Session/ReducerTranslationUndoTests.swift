import CoreGraphics
import Testing
@testable import CubbyCore

@Suite("ScreenshotReducer · 截图翻译：撤销、Esc、重试与换语言")
struct ReducerTranslationUndoTests {
    private typealias Fixture = TranslationFixture
    private let rectangle = CGRect(x: 300, y: 400, width: 80, height: 60)

    @Test("翻译进行中：撤销 / 重做不生效（Esc 才是取消）")
    func undoBlockedWhileBusy() {
        let started = SessionHarness.translatable().drawingRectangle(rectangle).send(.translation(.start))
        #expect(!started.session.canUndo)
        #expect(started.send(.command(.undo)).session.document == started.session.document)
    }

    @Test("完成后：⌘Z 一步撤销整次翻译，⇧⌘Z 带着全部译文重做")
    func undoRedoWholeTranslation() {
        let done = SessionHarness.translatable().translated()
        let undone = done.send(.command(.undo))
        #expect(undone.session.translation == nil)
        #expect(undone.session.translationDisplay == .hidden)
        let redone = undone.send(.command(.redo))
        #expect(redone.session.translation?.translatedBlocks.count == 2)
        #expect(redone.session.translation?.status == .ready)
    }

    @Test("翻译进行中按 Esc：只取消翻译（回到翻译前，那一步撤销也消失），期间画的标注保留")
    func escapeCancelsTranslationOnly() {
        let started = SessionHarness.translatable().send(.translation(.start))
        let drawn = started.drawingRectangle(rectangle)
        let recognized = drawn.send(.translation(.recognized(started.runID, Fixture.blocks)))
        let cancelled = recognized.send(.command(.escape))
        #expect(cancelled.session.translation == nil)
        #expect(!cancelled.session.isTranslating)
        #expect(cancelled.session.document.annotations.count == 1)
        #expect(cancelled.session.document.undone().annotations.isEmpty)
        #expect(!cancelled.session.document.undone().canUndo)
        #expect(cancelled.effects == [.translation(.cancel), .showHint(.translationCancelled)])
        #expect(!cancelled.session.isDiscardArmed)
    }

    @Test("没有标注时取消翻译后的提示是「再按一次 Esc 关闭」；再按一次 Esc 结束会话")
    func escapeAgainCloses() {
        let started = SessionHarness.translatable().send(.translation(.start))
        let cancelled = started.send(.command(.escape))
        #expect(cancelled.effects == [.translation(.cancel), .showHint(.translationCancelledPressEscapeAgain)])
        #expect(cancelled.send(.command(.escape)).effects == [.finish(.cancel)])
    }

    @Test("失败状态按 Esc：关闭这次翻译；完成后按 Esc：按有内容处理（二次确认）")
    func escapeInTerminalStates() {
        let recognized = SessionHarness.translatable().startedAndRecognized()
        let failed = recognized.send(.translation(.failed(recognized.runID, .notConfigured)))
        let closed = failed.send(.command(.escape))
        #expect(closed.session.translation == nil)
        #expect(closed.effects == [.showHint(.translationClosed)])
        let done = SessionHarness.translatable().translated().send(.command(.escape))
        #expect(done.session.isDiscardArmed)
        #expect(done.effects == [.showHint(.pressEscapeAgainToDiscard)])
        #expect(done.session.translation?.status == .ready)
    }

    @Test("按住鼠标时 Esc 取消翻译：随后的拖动从按下时的快照重建文档，不会把被取消的译文带回来（模糊测试回归）")
    func escapeWhilePressed() {
        let drawn = SessionHarness.translatable().drawingRectangle(CGRect(x: 300, y: 300, width: 80, height: 60))
        let started = drawn.send(.translation(.start))
        let pressed = started.send(.mouseDown(CGPoint(x: 300, y: 330), clickCount: 1))
        let dragged = pressed.send(.command(.escape), .mouseDragged(CGPoint(x: 340, y: 360)))
        #expect(dragged.session.document.translation == nil)
        #expect(dragged.session.translation == nil)
        #expect(dragged.session.document.annotations.count == 1)
        #expect(
            started.send(.mouseDown(CGPoint(x: 300, y: 330), clickCount: 1), .translation(.changeTarget("ja")))
                .session.translation?.id == started.runID)
    }

    @Test("selecting 时 Esc 仍是放弃拖拽（翻译继续）")
    func escapeWhileSelecting() {
        let started = SessionHarness.translatable().send(.translation(.start))
        let selecting = started.press(CGPoint(x: 900, y: 700), dragTo: CGPoint(x: 1000, y: 800))
        #expect(selecting.session.phase == .selecting)
        let abandoned = selecting.send(.command(.escape))
        #expect(abandoned.session.isTranslating)
        #expect(abandoned.session.selection == SessionHarness.selection)
    }

    @Test("部分失败后重试：只重发缺失的块，沿用语言；不入撤销栈")
    func retryMissingOnly() {
        let partial = SessionHarness.translatable().partiallyTranslated()
        let retried = partial.send(.translation(.retry))
        #expect(
            retried.translationEffects == [
                .retry(
                    partial.runID, blocks: [Fixture.world], screenID: 1, languages: Fixture.languages, hidden: [])
            ])
        #expect(retried.session.translation?.status == .translating(done: 1, total: 2))
        #expect(retried.session.document == partial.session.document)
        let plan = TranslationPlan(blockIDs: [1], languages: Fixture.languages, engine: Fixture.engine)
        let finished = retried.send(
            .translation(.started(partial.runID, plan)),
            .translation(.arrived(partial.runID, Fixture.placed(Fixture.world))), .translation(.finished(partial.runID))
        )
        #expect(finished.session.translation?.status == .ready)
        #expect(finished.session.translation?.candidateIDs == [0, 1])
    }

    @Test("部分失败后在缺失的块上画马赛克再重试：被遮住的块不再发送，也不再算缺失（设计文档 D6）")
    func retrySkipsHiddenBlocks() {
        let partial = SessionHarness.translatable().partiallyTranslated()
        let covered = partial.send(.command(.selectTool(.mosaic)))
            .drag(from: CGPoint(x: 225, y: 220), to: CGPoint(x: 515, y: 220))
            .send(.command(.selectTool(.mosaic)))
        let retried = covered.send(.translation(.retry))
        #expect(retried.translationEffects.isEmpty)
        #expect(retried.session.translation?.status == .ready)
        #expect(retried.session.translation?.candidateIDs == [0])
        #expect(!retried.session.isTranslating)
    }

    @Test("部分失败后用两块各不足 20% 的马赛克合计盖住缺失的块再重试：与发送过滤同一口径，不再卡在部分完成")
    func retryWithTwoSmallMosaics() {
        let partial = SessionHarness.translatable().partiallyTranslated()
        let covered = partial.drawingSmallMosaics()
        // 前提：每块单独都不到 20%，合计达到 20%
        let fractions = covered.mosaicCoverage(of: Fixture.world)
        #expect(fractions.count == 2 && fractions.allSatisfy { $0 < 0.2 } && fractions.reduce(0, +) >= 0.2)
        let retried = covered.send(.translation(.retry))
        #expect(retried.translationEffects.isEmpty)
        #expect(retried.session.translation?.status == .ready)
        #expect(!retried.session.isTranslating)
        // 被遮住的块不复制（它的文字在马赛克下面）
        #expect(retried.session.translatedText == "[T] HELLO\n42")
    }

    @Test("重试进行中按 Esc：只停掉这次重试，回到部分完成（已到达的译文与撤销步都保留）")
    func escapeDuringRetryKeepsResult() {
        let partial = SessionHarness.translatable().partiallyTranslated()
        let retried = partial.send(.translation(.retry))
        let stopped = retried.send(.command(.escape))
        #expect(stopped.session.translation?.status == .partial(missing: 1, failure: nil))
        #expect(stopped.session.translation?.translatedBlocks == [Fixture.placed(Fixture.hello)])
        #expect(stopped.session.document == partial.session.document)
        #expect(!stopped.session.isTranslating)
        #expect(stopped.effects == [.translation(.cancel), .showHint(.translationCancelled)])
        // 重试中已到达的块同样保留
        let arrived = retried.send(.translation(.arrived(partial.runID, Fixture.placed(Fixture.world))))
        #expect(arrived.send(.command(.escape)).session.translation?.status == .ready)
    }

    @Test("失败后重试 / ⇧⌘T：有块则重新过滤翻译，没有块则重新识别；都在原地（不新增撤销步）")
    func retryAfterFailure() {
        let recognized = SessionHarness.translatable().startedAndRecognized()
        let failed = recognized.send(.translation(.failed(recognized.runID, .notConfigured)))
        let retried = failed.send(.command(.translate))
        #expect(
            retried.translationEffects == [
                .translate(failed.runID, blocks: Fixture.blocks, screenID: 1, hidden: [])
            ])
        #expect(retried.session.translation?.status == .translating(done: 0, total: 0))
        #expect(retried.session.document == failed.session.document)

        let started = SessionHarness.translatable().send(.translation(.start))
        let empty = started.send(.translation(.recognized(started.runID, [])))
        let again = empty.send(.translation(.retry))
        #expect(again.session.translation?.status == .recognizing)
        #expect(
            again.translationEffects == [
                .recognize(started.runID, selection: SessionHarness.selection, screenID: 1, hidden: [])
            ])
    }

    @Test("换语言：沿用已识别的块重译，旧译文先留着；一步撤销；撤销回到上一种语言")
    func changeTargetRetranslates() {
        let done = SessionHarness.translatable().translated()
        let changed = done.send(.translation(.changeTarget("ja")))
        let run = try! #require(changed.session.translation)
        #expect(run.id != done.runID)
        #expect(run.parent == done.runID)
        #expect(run.languages?.target == "ja")
        #expect(run.translatedBlocks.count == 2)
        #expect(run.status == .translating(done: 0, total: 0))
        #expect(changed.translationEffects == [.translate(run.id, blocks: Fixture.blocks, screenID: 1, hidden: [])])
        // 完成前不能撤销；Esc 回到上一种语言（译文完整）
        let restored = changed.send(.command(.escape))
        #expect(restored.session.translation?.id == done.runID)
        #expect(restored.session.translation?.translatedBlocks.count == 2)
        #expect(restored.session.document == done.session.document)
        // 走完后：撤销一次回到上一种语言
        let plan = TranslationPlan(
            blockIDs: [0, 1], languages: TranslationLanguages(source: "en", target: "ja"), engine: Fixture.engine)
        let finished = changed.send(
            .translation(.started(run.id, plan)),
            .translation(.arrived(run.id, Fixture.placed(Fixture.hello, prefix: "[J] "))),
            .translation(.arrived(run.id, Fixture.placed(Fixture.world, prefix: "[J] "))),
            .translation(.finished(run.id)))
        #expect(finished.session.translation?.translatedBlocks.first?.text == "[J] HELLO")
        #expect(finished.send(.command(.undo)).session.translation?.id == done.runID)
    }

    @Test("换语言后失败：继承的旧译文不再显示（那些块回到原文）")
    func failedRetranslationDropsInherited() {
        let changed = SessionHarness.translatable().translated().send(.translation(.changeTarget("ja")))
        let failed = changed.send(.translation(.failed(changed.runID, .network)))
        #expect(failed.session.translation?.status == .failed(.network))
        #expect(failed.session.translation?.translatedBlocks.isEmpty == true)
    }

    @Test("换成当前语言：无操作；失败状态换语言：原地重来（不新增撤销步）")
    func changeTargetEdgeCases() {
        let done = SessionHarness.translatable().translated()
        #expect(done.send(.translation(.changeTarget("zh-Hans"))).session == done.session)
        let recognized = SessionHarness.translatable().startedAndRecognized()
        let waiting = recognized.send(.translation(.needsTargetLanguage(recognized.runID)))
        let picked = waiting.send(.translation(.changeTarget("fr")))
        #expect(picked.session.translation?.id == waiting.runID)
        #expect(picked.session.translation?.languages?.target == "fr")
        #expect(picked.session.document == waiting.session.document)
        #expect(
            picked.translationEffects == [.translate(waiting.runID, blocks: Fixture.blocks, screenID: 1, hidden: [])])
    }

    @Test("识别中换语言：取消后重新识别（同一次运行）")
    func changeTargetWhileRecognizing() {
        let started = SessionHarness.translatable().send(.translation(.start))
        let changed = started.send(.translation(.changeTarget("de")))
        #expect(changed.session.translation?.id == started.runID)
        #expect(changed.session.translation?.status == .recognizing)
        #expect(
            changed.translationEffects == [
                .recognize(started.runID, selection: SessionHarness.selection, screenID: 1, hidden: [])
            ])
    }

    @Test("选区变化后重新翻译：新的一次运行（一步撤销），按新选区识别")
    func retranslateSelection() {
        let done = SessionHarness.translatable().translated()
        let grown = done.send(.command(.selectAll))
        #expect(grown.session.isTranslationStale)
        let again = grown.send(.translation(.retranslateSelection))
        let run = try! #require(again.session.translation)
        #expect(run.parent == done.runID)
        #expect(run.area == grown.session.selection)
        #expect(run.status == .recognizing)
        #expect(again.session.document.undone().translation == done.runID)
        #expect(!again.session.isTranslationStale)
        #expect(done.send(.translation(.retranslateSelection)).session == done.session)
    }
}
