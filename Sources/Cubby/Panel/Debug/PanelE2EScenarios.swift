#if DEBUG
import AppKit
import CubbyCore

/// 全部面板脚本（按运行顺序；docs/CLIP-TRANSLATION-DESIGN.md §9 的面板 E2E 清单 + 按住 ⌥、⇄、跟随选中项、按应用记住语言；
/// 然后是拆词，docs/TEXT-PICK-DESIGN.md §4；最后是更新提醒，docs/UPDATE-REMINDER-DESIGN.md §2）
@MainActor
enum PanelE2EScenarios {
    static var all: [PanelE2EScenario] {
        [
            cardToggle, cardStreaming, cardActions, richPaste, altReturn, altReturnCancel, altReturnFailure,
            escapeCancelsCard, hideCancels, notConfigured, secretGate, cacheChip, translationLine, image, holdOption,
            holdOptionEscape, imageWithoutText, swap, followSelection, rememberForApp, unsupported, unavailable, help,
            refusals, swapRefused, partialFailure, cacheWholeSegment, imageCached, holdOptionCloud,
            cardRoutesTranslateAndPaste, copyCachedAfterEngineChange, holdOptionNoteAfterRelease,
        ] + textPick + updates
    }

    // MARK: - 翻译卡的打开与关闭

    static var cardToggle: PanelE2EScenario {
        PanelE2EScenario(
            name: "card-toggle",
            summary: "⌘T opens / closes the card, ⇧⌘T alias, space ↔ card, esc returns to the preview"
        ) { context in
            try await context.open(selecting: "mail")
            try await context.command("t")
            context.check("⌘T opens the translation card", context.viewModel.isTranslationCardOpen)
            context.check("the detail window is on screen", context.detailWindow.isVisible)
            context.checkEqual("the card shows the selected item", PanelE2EFixtures.id("mail"), context.card?.itemID)
            try await context.waitForCard(.done)
            context.check("the card height is within 236…620", (236...620).contains(context.detailWindow.frame.height))
            try await context.command("t")
            context.check("⌘T again closes the card", !context.viewModel.isTranslationCardOpen && context.card == nil)
            await context.eventually("the detail window hides") { !context.detailWindow.isVisible }
            try await context.command("t", shift: true)
            context.check("⇧⌘T also opens the card", context.viewModel.isTranslationCardOpen)
            try await context.press(.space)
            context.check("space switches to the preview", context.viewModel.isPreviewVisible && context.card == nil)
            try await context.command("t")
            context.check("⌘T in the preview switches to the card", context.viewModel.isTranslationCardOpen)
            try await context.waitForCard(.done)
            try await context.press(.escape)
            context.check("esc closes the card and returns to the preview", context.viewModel.isPreviewVisible)
            try await context.press(.escape)
            context.check("esc again closes the preview", context.viewModel.detailPane == nil)
            await context.eventually("the detail window hides again") { !context.detailWindow.isVisible }
        }
    }

    // MARK: - 流式与三种视图

    static var cardStreaming: PanelE2EScenario {
        var options = PanelE2EWorld.Options()
        options.startDelay = .milliseconds(250)
        options.segmentDelay = .milliseconds(400)
        return PanelE2EScenario(
            name: "card-streaming",
            summary: "segments arrive one by one without resizing the card; ← / → switch the three views",
            options: options
        ) { context in
            try await context.open(selecting: "mail")
            try await context.command("t")
            context.checkEqual("the card starts waiting", TranslationCardPhase.waiting, context.card?.phase)
            let startHeight = context.detailWindow.frame.height
            try await context.wait("the first segment") { context.card?.phase == .streaming }
            context.checkEqual("one of two segments has arrived", 1, context.card?.content.arrivedCount)
            try await context.waitForCard(.done)
            context.checkEqual("both segments arrived", 2, context.card?.content.arrivedCount)
            context.checkEqual(
                "the card did not resize while streaming", startHeight, context.detailWindow.frame.height)
            try await context.press(.rightArrow)
            context.checkEqual("→ shows side by side", TranslationViewMode.sideBySide, context.card?.mode)
            try await context.settle()
            let pairs = context.hasAnchor("card.pair.0") && context.hasAnchor("card.pair.1")
            context.check("both pairs are laid out", pairs)
            try await context.press(.rightArrow)
            context.checkEqual("→ shows the original", TranslationViewMode.original, context.card?.mode)
            try await context.press(.rightArrow)
            context.checkEqual("→ stops at the original", TranslationViewMode.original, context.card?.mode)
            try await context.press(.leftArrow)
            try await context.press(.leftArrow)
            context.checkEqual("← ← back to the translation", TranslationViewMode.translation, context.card?.mode)
            try await context.click("card.mode.1")
            context.checkEqual(
                "clicking Side by Side in the non-key window works", TranslationViewMode.sideBySide, context.card?.mode)
            try await context.holdOption(true)
            context.check("holding ⌥ shows the original", context.card?.isPeeking == true)
            try await context.holdOption(false)
            context.check("releasing ⌥ returns to the translation", context.card?.isPeeking == false)
        }
    }

    // MARK: - 不支持与不可用

    static var unsupported: PanelE2EScenario {
        PanelE2EScenario(
            name: "unsupported",
            summary: "⌘T / ⌥↩ on a link beeps with a footer hint; a card following onto code shows why"
        ) { context in
            try await context.open(selecting: "link")
            try await context.command("t")
            context.check("⌘T on a link does not open a card", !context.viewModel.isTranslationCardOpen)
            context.checkEqual(
                "the footer explains", TranslationCopy.unsupportedTitle(.link), context.viewModel.toast?.message)
            try await context.press(.returnKey, .option)
            context.check("⌥↩ on a link starts nothing", context.translation?.inline.job == nil)
            context.check("nothing was written to the pasteboard", context.world.pasteboardText == nil)
            try context.select("line")
            try await context.command("t")
            try await context.waitForCard(.done)
            try await context.press(.upArrow)
            try await context.settle()
            try context.select("code")
            try await context.settle()
            context.checkEqual(
                "following onto code shows the unsupported state", TranslationCardPhase.unsupported(.code),
                context.card?.phase)
        }
    }

    static var unavailable: PanelE2EScenario {
        var options = PanelE2EWorld.Options()
        options.translationAvailable = false
        return PanelE2EScenario(
            name: "unavailable",
            summary: "without a translation service every entry point is hidden and ⌘T / ⌥↩ do nothing",
            options: options
        ) { context in
            try await context.open(selecting: "mail")
            context.check("translation is unavailable", context.translation == nil)
            try await context.command("t")
            context.check("⌘T opens nothing", context.viewModel.detailPane == nil)
            try await context.press(.returnKey, .option)
            context.check("⌥↩ pastes nothing", context.world.pasteboardText == nil)
            context.check("the panel stays open", context.world.panel.debugIsShown)
            context.viewModel.toggleHelp()
            try await context.settle()
            context.check("help has no translation rows", !context.hasAnchor("help.⌘T"))
            context.check("help still lists the preview", context.hasAnchor("help.⌘P"))
        }
    }

    static var help: PanelE2EScenario {
        PanelE2EScenario(
            name: "help",
            summary: "help lists ⌘T, ⌥↩ and hold ⌥; with the card open also ⌘C and ⌘S"
        ) { context in
            try await context.open(selecting: "mail")
            context.viewModel.toggleHelp()
            try await context.settle()
            context.check("help lists ⌘T", context.hasAnchor("help.⌘T"))
            context.check("help lists ⌥↩", context.hasAnchor("help.⌥↩"))
            context.check("help lists ⌘C only with the card open", !context.hasAnchor("help.⌘C"))
            try await context.command("t")
            context.check("⌘T closes help first, then opens the card", !context.viewModel.isShowingHelp)
            context.check("… and the card is open", context.viewModel.isTranslationCardOpen)
            context.viewModel.toggleHelp()
            try await context.settle()
            context.check("with the card open help lists ⌘C", context.hasAnchor("help.⌘C"))
            context.check("… and ⌘S", context.hasAnchor("help.⌘S"))
            // 最后一行（鼠标 · 右键）完整落在 620pt 面板内（R5）
            let panel = ScreenTopologyProvider.toGlobal(context.panelWindow.frame)
            let rightClick = String(
                localized: "Right-click", comment: "Shortcut help: mouse gesture, shown in a key cap")
            let lastRow = try? context.frame(of: "help.\(rightClick)", in: context.panelWindow)
            context.check(
                "the help overlay fits in the panel",
                lastRow.map { $0.minY >= panel.minY && $0.maxY <= panel.maxY - 8 } == true,
                detail: "last row \(lastRow.map { "\($0)" } ?? "missing"), panel \(panel)")
        }
    }
}
#endif
