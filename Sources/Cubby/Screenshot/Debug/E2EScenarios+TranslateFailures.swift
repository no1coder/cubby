#if DEBUG
import AppKit
import CubbyCore

/// 截图翻译脚本（续）：失败与「去设置」、部分失败重试、复制译文、⌘T 提取译文、选区变化、各失败原因、真实识别
extension E2EScenarios {
    static var translateResolve: E2EScenario {
        E2EScenario(
            name: "translate-resolve",
            summary: "not configured → Open Settings suspends the overlay; the shortcut is ignored; back → auto-retry",
            options: translationOptions { $0.script.setupFailure = .notConfigured },
            steps: [
                .start(at: desktop),
                .drag([textStart, textEnd]),
                .translateKey,
                .expectTranslationStatus("fails as not configured") { $0 == .failed(.notConfigured) },
                .expectEqual("nothing was sent to the engine", 0) { $0.world.translationProvider?.log.requests.count },
                .remember("overlays") { $0.numbers["overlays"] = $0.world.overlays.count },
                .clickTranslationBar(.failureAction),
                .eventually("the overlay is suspended while settings are open") { !$0.world.isOverlayPresented },
                .expectEqual("the provider was asked to resolve", [TranslationFailure.notConfigured]) {
                    $0.world.translationProvider?.resolveRequests
                },
                .hotKeyAgain,
                .expect("the shortcut neither starts a new capture nor cancels") { context in
                    context.world.isActive && context.world.overlays.count == context.numbers["overlays"]
                },
                .eventually("the overlay comes back after settings close") { $0.world.isOverlayPresented },
                .expectTranslationReady,
                .expectEqual("the retry translated without recognizing again", 1) { $0.world.stubRecognizer?.calls },
                .key(.escape),
                .key(.escape),
                .expectIdle,
            ]
        )
    }

    static var translateSaveCancel: E2EScenario {
        E2EScenario(
            name: "translate-save-cancel",
            summary:
                "cmd-S while translating: blocks keep arriving behind the save dialog; Cancel shows the finished result",
            options: translationOptions { $0.script.blockDelay = .milliseconds(350) },
            steps: [
                .start(at: desktop),
                .drag([textStart, textEnd]),
                .translateKey,
                .expectTranslationStatus("translating", timeout: .seconds(5)) { status in
                    if case .translating(_, let total) = status { return total > 0 }
                    return false
                },
                .replySave { _ in .hold },
                .command("s"),
                .eventually("the save dialog is open") { $0.world.savePrompt.isOpen },
                .expectTranslationReady,
                .action("click Cancel in the save dialog") { context in context.world.savePrompt.resolve(nil) },
                .eventually("the overlay comes back") { $0.world.isOverlayPresented },
                .expect("the translation finished while the dialog was open") { context in
                    let session = try context.requireSession()
                    return !session.isTranslating && session.canUndo
                },
                .key(.escape),
                .key(.escape),
                .expectIdle,
            ]
        )
    }

    static var translatePartial: E2EScenario {
        E2EScenario(
            name: "translate-partial",
            summary: "a stream that fails midway keeps the arrived blocks; Retry sends only the missing ones",
            options: translationOptions { $0.script.failAfter = 1 },
            steps: [
                .start(at: desktop),
                .drag([textStart, textEnd]),
                .translateKey,
                .expectTranslationStatus("partially translated") { status in
                    if case .partial(_, let failure) = status { return failure == .network }
                    return false
                },
                .expectEqual("one block kept its translation", 1) { $0.translationRun?.translatedBlocks.count },
                .clickTranslationBar(.noticeAction),
                .expectTranslationReady,
                .expect("the retry sent only the blocks that were missing") { context in
                    guard let requests = context.world.translationProvider?.log.requests, requests.count == 2 else {
                        return false
                    }
                    return requests[1].blockIDs == Array(requests[0].blockIDs.dropFirst())
                },
                .key(.escape),
                .key(.escape),
                .expectIdle,
            ]
        )
    }

    static var translateCopy: E2EScenario {
        E2EScenario(
            name: "translate-copy",
            summary:
                "Copy Translation copies the blocks in reading order (originals for skipped ones) and keeps the overlay",
            options: translationOptions(),
            steps: [.markOutputs] + selectAndTranslate + [
                .clickTranslationBar(.copy),
                .expectCopiedTranslation,
                .expectHUD(containing: TranslationBarText.copiedTranslation),
                .expectHistoryDelta(1),
                .expect("history item is text") { $0.world.history.first?.kind == .text },
                .expectPresented,
                .key(.escape),
                .key(.escape),
                .expectIdle,
            ]
        )
    }

    static var translateExtract: E2EScenario {
        E2EScenario(
            name: "translate-extract",
            summary: "cmd-T with the switch on Translation copies the translation instead of running OCR",
            options: translationOptions(),
            steps: [.markOutputs] + selectAndTranslate + [
                .remember("expected text") { $0.strings["expected"] = $0.expectedTranslatedText },
                .command("t"),
                .expectIdle,
                .expectEqual("the overlay delivered the translated text", "translatedText") { $0.world.results.last },
                .eventually("pasteboard has the translation") { context in
                    context.world.pasteboardText != nil && context.world.pasteboardText == context.strings["expected"]
                },
                .expectHUD(containing: E2EText.localized("Text copied")),
                .expectHistoryDelta(1),
            ]
        )
    }

    static var translateSelection: E2EScenario {
        E2EScenario(
            name: "translate-selection",
            summary: "growing the selection past the translated area offers Translate Again (a new undo step)",
            options: translationOptions(),
            steps: selectAndTranslate + [
                .remember("area") { $0.rects["area"] = $0.translationRun?.area },
                .command("a"),
                .expect("the bar says the selection changed") { try $0.requireSession().isTranslationStale },
                .expect("the translation stays anchored on screen") { $0.translationRun?.status == .ready },
                .clickTranslationBar(.noticeAction),
                .expectTranslationReady,
                .expect("the new translation covers the new selection") { context in
                    context.translationRun?.area == (try context.requireSelection())
                },
                .expectEqual("the text was recognized again", 2) { $0.world.stubRecognizer?.calls },
                .command("z"),
                .expectEqual("undo returns to the first translation", { $0.rects["area"] }) {
                    $0.translationRun?.area
                },
                .key(.escape),
                .key(.escape),
                .expectIdle,
            ]
        )
    }

    /// 每种失败：翻译条给出原因；能去某处解决的给「去设置 / 下载语言」，语言组合不支持不给按钮，其余给「重试」
    static var translateFailures: E2EScenario {
        let failures: [TranslationFailure] = [
            .notConfigured, .unauthorized, .rateLimited, .network, .server(status: 503), .unsupportedLanguages,
            .languageNotInstalled, .invalidResponse,
        ]
        let steps = failures.flatMap { failure -> [E2EStep] in
            [
                .remember("failure \(failure)") { $0.world.translationProvider?.script.setupFailure = failure },
                .start(at: desktop),
                .drag([textStart, textEnd]),
                .translateKey,
                .expectTranslationStatus("\(failure) is reported") { $0 == .failed(failure) },
                .eventually("\(failure) has the expected action button", timeout: .seconds(2)) { context in
                    guard case .failure(_, _, let action) = context.selectionScreenView?.translationBarModel?.content
                    else { return false }
                    return (action != nil) == (failure != .unsupportedLanguages)
                },
                .key(.escape),
                .expect("Esc closes the failed translation") { try $0.requireSession().translation == nil },
                .key(.escape),
                .expectIdle,
            ]
        }
        return E2EScenario(
            name: "translate-failures",
            summary: "every TranslationFailure shows a reason and the right action; Esc closes the bar",
            options: translationOptions(),
            steps: steps
        )
    }

    static var translateVision: E2EScenario {
        E2EScenario(
            name: "translate-vision",
            summary: "the real Vision recognizer finds the fixture's sentence and the stub engine translates it",
            options: translationOptions { $0.recognizer = .vision },
            steps: [
                .start(at: desktop),
                .drag([textStart, textEnd]),
                .translateKey,
                .expectTranslationStatus("translated", timeout: .seconds(20)) { status in
                    switch status {
                    case .ready, .partial: true
                    default: false
                    }
                },
                .expect("the recognized sentence came back translated") { context in
                    let text = try context.requireSession().translatedText ?? ""
                    return text.contains("[T]") && text.contains("QUICK")
                },
                .key(.escape),
                .key(.escape),
                .expectIdle,
            ]
        )
    }
}
#endif
