#if DEBUG
import AppKit
import CubbyCore

/// 翻译卡上的 ⌘C / ⌘S / ↩、富文本粘贴、esc 与面板关闭时取消（§4、§1.5）
extension PanelE2EScenarios {
    static var cardActions: PanelE2EScenario {
        PanelE2EScenario(
            name: "card-actions",
            summary: "⌘C copies and stays, ⌘S saves via the service, ↩ pastes the translation and promotes the original"
        ) { context in
            try await context.open(selecting: "notes")
            try await context.command("t")
            try await context.waitForCard(.done)
            let expected = context.card?.content.result?.plainText
            try await context.command("c")
            context.checkEqual("⌘C writes the translation", expected, context.world.pasteboardText)
            context.check(
                "… marked so the monitor ignores it", PasteboardReader.shouldIgnore(context.world.pasteboard))
            context.check("… and the panel stays open", context.world.panel.debugIsShown)
            context.checkEqual(
                "… with a footer flash", TranslationCopy.copiedFlash(isImage: false),
                context.translation?.card.flash?.message)
            context.check(
                "copying adds nothing to history",
                context.world.store.history.items.count == PanelE2EFixtures.entries.count)
            try await context.command("s")
            context.checkEqual("⌘S hands the result to the service", 1, context.stub?.saved.count)
            context.checkEqual(
                "… with a footer flash", TranslationCopy.savedFlash, context.translation?.card.flash?.message)
            context.world.pasteboard.clearContents()
            try await context.click("card.paste")
            await context.eventually("clicking Paste Translation writes it") {
                context.world.pasteboardText == expected
            }
            context.check("the panel hides after pasting", !context.world.panel.debugIsShown)
            context.checkEqual(
                "the original is promoted", PanelE2EFixtures.id("notes"), context.world.store.history.items.first?.id)
            await context.expectHUD(containing: PanelE2EStubTranslator.systemEngineName)
        }
    }

    static var richPaste: PanelE2EScenario {
        PanelE2EScenario(
            name: "rich-paste",
            summary: "↩ on a rich-text translation writes RTF + HTML + plain text; ⇧↩ writes plain text only"
        ) { context in
            try await context.open(selecting: "article")
            try await context.command("t")
            try await context.waitForCard(.done)
            context.check("the result keeps the structure", context.card?.content.result?.richText != nil)
            try await context.press(.returnKey)
            await context.eventually("↩ writes RTF") { context.world.pasteboardTypes.contains(.rtf) }
            context.check("… and HTML", context.world.pasteboardTypes.contains(.html))
            context.check(
                "… and the plain text of the whole translation",
                context.world.pasteboardText == PanelE2EFixtures.plainTranslation("article", "zh-Hans"),
                detail: context.world.pasteboardText ?? "nil")
            let rtf = context.world.pasteboard.data(forType: .rtf).flatMap {
                NSAttributedString(rtf: $0, documentAttributes: nil)
            }
            context.check("the RTF keeps the bullet list", rtf?.string.contains("• ") == true)
            try await context.open(selecting: "article")
            try await context.command("t")
            try await context.waitForCard(.done)
            try await context.press(.returnKey, .shift)
            await context.eventually("⇧↩ writes plain text") { context.world.pasteboardText != nil }
            context.check("… without RTF", !context.world.pasteboardTypes.contains(.rtf))
            await context.expectHUD(containing: "plain text")
        }
    }

    static var escapeCancelsCard: PanelE2EScenario {
        var options = PanelE2EWorld.Options()
        options.segmentDelay = .milliseconds(700)
        return PanelE2EScenario(
            name: "esc-cancels-card",
            summary: "esc while translating cancels and discards; the next esc closes the card",
            options: options
        ) { context in
            try await context.open(selecting: "mail")
            try await context.command("t")
            try await context.wait("streaming") { context.card?.phase == .streaming }
            try await context.press(.escape)
            context.checkEqual("esc cancels the translation", TranslationCardPhase.cancelled, context.card?.phase)
            context.check("arrived segments are discarded", context.card?.content.arrivedCount == 0)
            context.check("the card stays open", context.viewModel.isTranslationCardOpen)
            await context.eventually("the stream was cancelled") { (context.stub?.terminatedEarly ?? 0) >= 1 }
            try await context.click("card.action.0")
            try await context.wait("retry streams again") { context.card?.phase == .streaming }
            context.check("Retry in the non-key window restarts", true)
            try await context.press(.escape)
            try await context.press(.escape)
            context.check("the second esc closes the card", !context.viewModel.isTranslationCardOpen)
        }
    }

    static var hideCancels: PanelE2EScenario {
        var options = PanelE2EWorld.Options()
        options.segmentDelay = .milliseconds(700)
        return PanelE2EScenario(
            name: "hide-cancels",
            summary: "hiding the panel cancels the card and ⌥↩ jobs; nothing is pasted",
            options: options
        ) { context in
            try await context.open(selecting: "mail")
            try await context.command("t")
            try await context.wait("streaming") { context.card?.phase == .streaming }
            context.world.panel.hide(animated: false)
            try await context.settle()
            context.check("the card is gone", context.card == nil)
            await context.eventually("the card stream was cancelled") { (context.stub?.terminatedEarly ?? 0) >= 1 }
            try await context.open(selecting: "notes")
            try await context.press(.returnKey, .option)
            context.check("⌥↩ is running", context.translation?.inline.job?.isRunning == true)
            context.world.panel.hide(animated: false)
            try await context.settle()
            context.check("the ⌥↩ job is gone", context.translation?.inline.job == nil)
            await context.eventually("the ⌥↩ stream was cancelled") { (context.stub?.terminatedEarly ?? 0) >= 2 }
            try await Task.sleep(for: .seconds(1))
            context.check("nothing was pasted", context.world.pasteboardText == nil)
        }
    }
}
#endif
