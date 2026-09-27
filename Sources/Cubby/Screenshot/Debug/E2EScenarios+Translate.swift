#if DEBUG
import AppKit
import CubbyCore

/// 截图翻译脚本（docs/TRANSLATION-DESIGN.md §6）：桩 provider + 桩引擎（确定性流式、不联网），
/// 识别用桩识别器（夹具底部两行文字上的确定性块），translate-vision 用真实的 Vision 识别
extension E2EScenarios {
    /// 框住夹具底部的拉丁句子与中英混排一行（同 ocr 脚本）
    static let textStart = E2EPoint.fromBottom(12, 214)
    static let textEnd = E2EPoint.fromBottom(560, 160)

    static func translationOptions(_ configure: (inout E2EWorld.TranslationSetup) -> Void = { _ in })
        -> E2EWorld.Options
    {
        var setup = E2EWorld.TranslationSetup()
        configure(&setup)
        var options = E2EWorld.Options()
        options.translation = setup
        return options
    }

    /// 框选文字并翻译到完成
    static var selectAndTranslate: [E2EStep] {
        [
            .start(at: desktop), .drag([textStart, textEnd]), .expectPhase(.adjusting), .translateKey,
            .expectTranslationReady, .remember("block 0") { $0.rects["block0"] = $0.blockFrame(0) },
        ]
    }

    /// 第 0 块的中心
    static let firstBlock = E2EPoint.computed { context in
        guard let frame = context.blockFrame(0) else { throw E2EScriptError.missing("block 0") }
        return CGPoint(x: frame.midX, y: frame.midY)
    }

    static var translate: E2EScenario {
        E2EScenario(
            name: "translate",
            summary: "toolbar Translate recognizes, streams blocks in the engine's order with a bar below the toolbar",
            options: translationOptions {
                $0.script.reversed = true
                $0.script.blockDelay = .milliseconds(180)
            },
            steps: [
                .start(at: desktop),
                .drag([textStart, textEnd]),
                .expect("toolbar shows the Translate button") {
                    OverlayRenderModel.toolbarModel(for: try $0.requireSession()).translate == .idle
                },
                .clickToolbar(.translate),
                .expectTranslationStatus("recognizing, then translating", timeout: .seconds(3)) { status in
                    if case .translating(_, let total) = status { return total > 0 }
                    return false
                },
                .expect("the translation bar sits 6 pt below the toolbar, right-aligned (or held on screen)") {
                    context in
                    guard let view = context.selectionScreenView, let bar = view.debugTranslationBarFrame,
                        let toolbar = view.debugToolbarFrame
                    else { return false }
                    let screenLeft = context.world.screen.frame.minX + OverlayTokens.screenMargin
                    let aligned = abs(bar.maxX - toolbar.maxX) < 0.5 || abs(bar.minX - screenLeft) < 0.5
                    return abs(bar.minY - toolbar.maxY - 6) < 0.5 && aligned
                },
                .recordArrivalOrder,
                .expectEqual(
                    "blocks arrive in the engine's (reversed) order",
                    { context in
                        context.world.translationProvider?.log.requests.first.map {
                            $0.blockIDs.reversed().map(String.init)
                        }
                        .map { $0.joined(separator: ",") }
                    }
                ) { $0.strings["arrivals"] },
                .expectTranslationReady,
                .expectCanvasBlock("the first block shows the translation", block: 0, showsTranslation: true),
                .expectEqual("the translated text is the stub output", "[T] THE QUICK BROWN FOX") {
                    $0.translationRun?.translatedBlock(id: 0)?.text
                },
                .expect("Translate is highlighted and toggles the original") {
                    OverlayRenderModel.toolbarModel(for: try $0.requireSession()).translate
                        == .showing(translation: true)
                },
                .move(firstBlock),
                .eventually("hovering a block shows its original after 400 ms") { context in
                    context.selectionScreenView?.debugBubbleText == E2ETranslationFixture.latinWords[0]
                },
                .key(.escape),
                .expect("with a translation the first Esc only arms discard") {
                    try $0.requireSession().isDiscardArmed
                },
                .key(.escape),
                .expectIdle,
            ]
        )
    }

    static var translatePeek: E2EScenario {
        E2EScenario(
            name: "translate-peek",
            summary: "holding Space shows the original pixels; releasing restores; the export keeps the translation",
            options: translationOptions(),
            steps: [.markOutputs] + selectAndTranslate + [
                .expectCanvasBlock("translation visible", block: 0, showsTranslation: true),
                .spaceDown,
                .expect("peeking") { try $0.requireSession().isPeekingOriginal },
                .expectCanvasBlock(
                    "while Space is held the block shows the original", block: 0, showsTranslation: false),
                .expect("the peek chip is visible") { $0.selectionScreenView?.debugPeekChipVisible == true },
                .spaceUp,
                .expectCanvasBlock("releasing Space brings the translation back", block: 0, showsTranslation: true),
                .spaceDown,
                .key(.returnKey),
                .spaceUp,
                .expectIdle,
                .expectExportedBlock("the copied PNG has the translation", block: 0, translated: true),
            ]
        )
    }

    static var translateWipe: E2EScenario {
        let knob = E2EPoint.computed { context in
            guard let center = context.selectionScreenView?.debugWipeKnobCenter else {
                throw E2EScriptError.unavailable("wipe divider")
            }
            return center
        }
        return E2EScenario(
            name: "translate-wipe",
            summary:
                "Compare shows a divider at the middle; dragging the knob moves it; arrows nudge; export unaffected",
            options: translationOptions(),
            steps: [.markOutputs] + selectAndTranslate + [
                .clickTranslationBar(.compare),
                .expectEqual("the divider starts at the selection's middle", { try $0.requireSelection().midX }) {
                    context in
                    if case .split(let x) = try context.requireSession().translationDisplay { return x }
                    return nil
                },
                .remember("knob") { context in
                    context.rects["knob"] = CGRect(origin: try knob.resolve(context), size: .zero)
                },
                .drag([
                    knob,
                    .computed { context in
                        guard let start = context.rects["knob"]?.origin else { throw E2EScriptError.missing("knob") }
                        return CGPoint(x: start.x + 120, y: start.y)
                    },
                ]),
                .expect("dragging moved the divider right by about 120 pt") { context in
                    guard case .split(let x) = try context.requireSession().translationDisplay,
                        let start = context.rects["knob"]?.origin
                    else { return false }
                    return abs(x - start.x - 120) <= 1
                },
                .expect("the divider has keyboard focus") { try $0.requireSession().isWipeFocused },
                .rememberSelection,
                .key(.leftArrow),
                .expect("Left nudges the divider, not the selection") { context in
                    guard case .split(let x) = try context.requireSession().translationDisplay,
                        let start = context.rects["knob"]?.origin
                    else { return false }
                    let selection = try context.requireSelection()
                    return abs(x - (start.x + 120 - selection.width / 50)) <= 1
                        && selection == context.rects["selection"]
                },
                .key(.returnKey),
                .expectIdle,
                .expectExportedBlock(
                    "the export ignores the divider (translation everywhere)", block: 0, translated: true),
            ]
        )
    }

    static var translateExport: E2EScenario {
        E2EScenario(
            name: "translate-export",
            summary: "the Original | Translation switch decides what Done exports",
            options: translationOptions(),
            steps: [.markOutputs] + selectAndTranslate + [
                .clickTranslationBar(.original),
                .expect("switched to the original") { !(try $0.requireSession().showsTranslation) },
                .expectCanvasBlock("the canvas shows the original", block: 0, showsTranslation: false),
                .key(.returnKey),
                .expectIdle,
                .expectExportedBlock("the copied PNG is the original", block: 0, translated: false),
            ] + selectAndTranslate + [
                .translateKey,
                .translateKey,
                .expect("cmd-shift-T twice keeps the translation") { try $0.requireSession().showsTranslation },
                .clickToolbar(.done),
                .expectIdle,
                .expectExportedBlock("the copied PNG is the translation", block: 0, translated: true),
            ]
        )
    }

    static var translateUndo: E2EScenario {
        E2EScenario(
            name: "translate-undo",
            summary: "applying a translation is one undo step; streamed blocks add none; redo brings it back",
            options: translationOptions(),
            steps: selectAndTranslate + [
                .letter("r"),
                .drag([.fromBottom(300, 176), .fromBottom(420, 168)]),
                .letter("v"),
                .expectEqual("one rectangle on top of the translation", 1) {
                    try $0.requireSession().document.annotations.count
                },
                .command("z"),
                .expect("the first undo removes only the rectangle") { context in
                    let session = try context.requireSession()
                    return session.document.annotations.isEmpty && session.translation?.status == .ready
                },
                .command("z"),
                .expect("the second undo removes the whole translation") { try $0.requireSession().translation == nil },
                .expect("the translation bar is gone") { $0.selectionScreenView?.debugTranslationBarFrame == nil },
                .expectCanvasBlock("the canvas is back to the original", block: 0, showsTranslation: false),
                .command("z", shift: true),
                .expect("redo restores every block") { context in
                    let run = try context.requireSession().translation
                    return run?.status == .ready && run?.translatedBlocks.count == run?.candidateIDs.count
                },
                .expectCanvasBlock("and the canvas shows it again", block: 0, showsTranslation: true),
                .command("z", shift: true),
                .expectEqual("redo again restores the rectangle", 1) {
                    try $0.requireSession().document.annotations.count
                },
                .key(.escape),
                .key(.escape),
                .expectIdle,
            ]
        )
    }

    static var translateEscape: E2EScenario {
        E2EScenario(
            name: "translate-esc",
            summary: "Esc while translating cancels only the translation; the next Esc closes the screenshot",
            options: translationOptions { $0.script.blockDelay = .milliseconds(600) },
            steps: [
                .start(at: desktop),
                .drag([textStart, textEnd]),
                .translateKey,
                .expectTranslationStatus("the first block arrived", timeout: .seconds(5)) { status in
                    if case .translating(let done, _) = status { return done >= 1 }
                    return false
                },
                .expect("undo is disabled while translating") { !(try $0.requireSession().canUndo) },
                .key(.escape),
                .expect("the translation is gone") { try $0.requireSession().translation == nil },
                .expectPresented,
                .eventually("a hint explains the next Esc") { context in
                    context.world.overlay?.debugScreenViews.compactMap(\.debugHintText).first
                        == ScreenshotHint.translationCancelledPressEscapeAgain.message
                },
                .wait(900),
                .expect("no late block comes back") { try $0.requireSession().translation == nil },
                .key(.escape),
                .expectIdle,
                .expectEqual("the session was cancelled", "cancel") { $0.world.results.last },
            ]
        )
    }

    static var translateLanguage: E2EScenario {
        E2EScenario(
            name: "translate-language",
            summary:
                "choosing another language re-translates the same blocks without recognizing again; undo goes back",
            options: translationOptions(),
            steps: selectAndTranslate + [
                .translationBarAction(.chooseLanguage("ja")),
                .expectEqual("the choice is saved to the provider", "ja") {
                    $0.world.translationProvider?.targetLanguage
                },
                .expectTranslationStatus("re-translated", timeout: .seconds(10)) { $0 == .ready },
                .expectEqual("blocks are now Japanese stub output", "[JA] THE QUICK BROWN FOX") {
                    $0.translationRun?.translatedBlock(id: 0)?.text
                },
                .expectEqual("the text was recognized only once", 1) { $0.world.stubRecognizer?.calls },
                .expectEqual("the engine was asked twice, the second time for ja", "ja") {
                    $0.world.translationProvider?.log.requests.dropFirst().first?.target
                },
                .command("z"),
                .expectEqual("undo goes back to the previous language", "[T] THE QUICK BROWN FOX") {
                    $0.translationRun?.translatedBlock(id: 0)?.text
                },
                .key(.escape),
                .key(.escape),
                .expectIdle,
            ]
        )
    }
}

extension E2EStep {
    /// 翻译进行中轮询，记下各块第一次出现的顺序（逗号分隔的 id）到 strings["arrivals"]
    static var recordArrivalOrder: E2EStep {
        action("record the arrival order") { context in
            var order: [Int] = []
            let finished = await context.poll(timeout: .seconds(10)) {
                for block in context.translationRun?.translatedBlocks ?? [] where !order.contains(block.blockID) {
                    order.append(block.blockID)
                }
                return context.translationRun?.status == .ready
            }
            guard finished else { throw E2EScriptError.timedOut("the translation") }
            context.strings["arrivals"] = order.map(String.init).joined(separator: ",")
        }
    }
}
#endif
