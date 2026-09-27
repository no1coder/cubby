#if DEBUG
import AppKit
import CubbyCore

/// 缓存与「译」角标、卡片译文行与搜索、⇄ 对调、跟随选中项（含大模型停留）、按应用记住目标语言
extension PanelE2EScenarios {
    static var cacheChip: PanelE2EScenario {
        PanelE2EScenario(
            name: "cache-chip",
            summary: "a cached item shows the translation chip and opens instantly as “Cached”"
        ) { context in
            try await context.open(selecting: "line")
            try await context.settle()
            let line = PanelE2EFixtures.id("line")
            context.check("the cached item shows the chip", context.hasAnchor("list.chip.\(line)"))
            let mail = PanelE2EFixtures.id("mail")
            context.check("an uncached item has no chip", !context.hasAnchor("list.chip.\(mail)"))
            try await context.command("t")
            context.checkEqual("the cached translation shows at once", TranslationCardPhase.done, context.card?.phase)
            context.check("… marked as cached", context.card?.plan?.isCached == true)
            context.check("… and from the cache", context.card?.content.result?.fromCache == true)
            context.check(
                "… with the cached text",
                context.card?.content.result?.plainText == PanelE2EFixtures.plainTranslation("line", "zh-Hans"))
        }
    }

    static var translationLine: PanelE2EScenario {
        PanelE2EScenario(
            name: "translation-line",
            summary: "the optional card line shows the cached translation; a search matching only it shows it too"
        ) { context in
            try await context.open(selecting: "line")
            let line = "list.line.\(PanelE2EFixtures.id("line"))"
            context.check("the line is off by default", !context.hasAnchor(line))
            context.world.settings.showsTranslationOnCards = true
            try await context.settle()
            context.check("turning the setting on shows the line", context.hasAnchor(line))
            context.world.settings.showsTranslationOnCards = false
            // 只在译文里出现的词（「资料」）：搜索能命中，卡片显示命中的译文行
            context.viewModel.searchText = PanelE2EFixtures.translationOnlyKeyword
            try await context.settle()
            context.check(
                "the search finds the item through its translation",
                context.viewModel.items.contains { $0.id == PanelE2EFixtures.id("line") })
            context.check("a match only in the translation shows the line", context.hasAnchor(line))
            context.check("the setting stays off", !context.world.settings.showsTranslationOnCards)
        }
    }

    static var swap: PanelE2EScenario {
        PanelE2EScenario(
            name: "swap",
            summary: "⇄ translates the translation back (not cached), ⇄ again returns to the cached forward result"
        ) { context in
            try await context.open(selecting: "mail")
            try await context.command("t")
            try await context.waitForCard(.done)
            context.check("swap is available", context.card?.canSwap == true)
            try await context.click("card.swap")
            try await context.waitForCard(.done)
            context.check("the card is reversed", context.card?.isReversed == true)
            context.checkEqual(
                "the service translated the translation back to English",
                TranslationLanguages(source: "zh-Hans", target: "en"), context.stub?.reverseCalls.last)
            context.check(
                "the languages are swapped",
                context.card.map { $0.displayedLanguages.source == "zh-Hans" && $0.displayedLanguages.target == "en" }
                    == true)
            try await context.click("card.swap")
            try await context.waitForCard(.done)
            context.check("⇄ again returns forward", context.card?.isReversed == false)
            context.check("… from the cache", context.card?.content.result?.fromCache == true)
        }
    }

    static var followSelection: PanelE2EScenario {
        PanelE2EScenario(
            name: "follow-selection",
            summary: "the card follows the selection; a cloud engine waits 0.6 s on an item before sending"
        ) { context in
            try await context.open(selecting: "mail")
            try await context.command("t")
            try await context.waitForCard(.done)
            try await context.press(.downArrow)
            try await context.settle()
            context.checkEqual("the card follows ↓", PanelE2EFixtures.id("notes"), context.card?.itemID)
            context.check(
                "on-device translation starts at once",
                context.card.map { $0.phase.isWorking || $0.phase == .done } == true)
            context.stub?.engine = .cloud
            let sent = context.stub?.sentCalls.count ?? 0
            try await context.press(.downArrow)
            try await context.settle()
            context.checkEqual("a cloud engine holds first", TranslationCardPhase.holding, context.card?.phase)
            try await context.press(.downArrow)
            try await context.settle()
            context.checkEqual("… skipping to the next item", PanelE2EFixtures.id("line"), context.card?.itemID)
            // 预置的缓存出自系统翻译：换成云端引擎后不算缓存，同样停留
            context.checkEqual(
                "… a cache from another engine holds too", TranslationCardPhase.holding, context.card?.phase)
            try await context.press(.upArrow)
            try await context.settle(.milliseconds(250))
            context.checkEqual("nothing sent while passing through", sent, context.stub?.sentCalls.count)
            await context.eventually("after the dwell it sends", timeout: .seconds(2)) {
                (context.stub?.sentCalls.count ?? 0) == sent + 1
            }
            context.checkEqual(
                "… for the item it stayed on", PanelE2EFixtures.id("article"), context.stub?.sentCalls.last?.itemID)
            try await pasteWhileHolding(context)
        }
    }

    /// 停留期间按 ↩：立即发送（不等停留结束），完成后粘贴
    private static func pasteWhileHolding(_ context: PanelE2EContext) async throws {
        try await context.waitForCard(.done)
        for _ in 0..<4 { try await context.press(.downArrow) }
        try await context.settle()
        context.checkEqual("the image item holds first", TranslationCardPhase.holding, context.card?.phase)
        let sent = context.stub?.sentCalls.count ?? 0
        try await context.press(.returnKey)
        context.checkEqual("↩ while holding sends at once", sent + 1, context.stub?.sentCalls.count)
        await context.eventually("… and pastes when done") {
            context.world.pasteboard.data(forType: .png) != nil
        }
    }

    static var holdOptionEscape: PanelE2EScenario {
        var options = PanelE2EWorld.Options()
        options.segmentDelay = .milliseconds(600)
        return PanelE2EScenario(
            name: "hold-option-escape",
            summary: "⌥↩ before the hold starts sends once; esc cancels a preview waiting to paste",
            options: options
        ) { context in
            try await context.open(selecting: "mail")
            try await context.holdOption(true)
            try await context.press(.returnKey)
            try await context.holdOption(false)
            try await context.settle(.milliseconds(500))
            context.check("⌥↩ right away starts only the inline job", context.translation?.peek.peek == nil)
            context.checkEqual("… sending once", 1, context.stub?.sentCalls.count)
            try await context.press(.escape)
            context.stub?.clearCache()
            try await context.holdOption(true)
            await context.eventually("the preview starts") { context.translation?.peek.peek?.isStreaming == true }
            try await context.press(.returnKey)
            try await context.holdOption(false)
            context.check("↩ keeps the preview to paste when done", context.translation?.peek.peek?.pasteOnDone == true)
            try await context.press(.escape)
            context.check("esc cancels it", context.translation?.peek.peek == nil)
            context.checkEqual(
                "… with a footer toast", TranslationCopy.cancelledTitle, context.viewModel.toast?.message)
            context.check("… and the panel stays open", context.world.panel.debugIsShown)
            try await Task.sleep(for: .seconds(1.5))
            context.check("nothing was pasted", context.world.pasteboardText == nil)
        }
    }

    static var imageWithoutText: PanelE2EScenario {
        PanelE2EScenario(
            name: "image-no-text",
            summary: "an image without text shows “No text to translate”; ⌥↩ pastes nothing"
        ) { context in
            context.stub?.imageHasText = false
            try await context.open(selecting: "image")
            try await context.command("t")
            try await context.waitForCard(.unsupported(.noText))
            context.check("the card explains there is nothing to translate", true)
            try await context.press(.escape)
            try await context.press(.returnKey, .option)
            await context.eventually("⌥↩ says so inline") {
                context.translation?.inline.job?.phase == .failed(.nothingToTranslate)
            }
            context.check("nothing was pasted", context.world.pasteboard.types?.isEmpty ?? true)
        }
    }

    static var rememberForApp: PanelE2EScenario {
        PanelE2EScenario(
            name: "remember-for-app",
            summary: "the language menu picks a target and remembers it for the paste target app"
        ) { context in
            try await context.open(selecting: "mail")
            try await context.command("t")
            try await context.waitForCard(.done)
            guard let card = context.card, let controller = context.translation?.card else { return }
            let menu = TranslationMenus.languageMenu(for: card, controller: controller)
            let japaneseName = TranslationCopy.nativeLanguageName("ja")
            let titles = menu.items.map(\.title)
            context.check(
                "the menu lists the languages",
                titles.contains(japaneseName) && titles.contains { $0.hasPrefix("English") },
                detail: titles.joined(separator: ", "))
            let english = menu.items.first { $0.title.hasPrefix("English") }
            context.check("the source language is disabled", english?.isEnabled == false)
            let japanese = menu.items.firstIndex { $0.title == japaneseName }
            menu.performActionForItem(at: japanese ?? 0)
            try await context.waitForCard(.done)
            context.checkEqual("choosing Japanese retranslates", "ja", context.card?.plan?.languages.target)
            context.check(
                "… with the Japanese translation",
                context.card?.content.result?.plainText == PanelE2EFixtures.plainTranslation("mail", "ja"))
            guard let chosen = context.card else { return }
            let rememberMenu = TranslationMenus.languageMenu(for: chosen, controller: controller)
            let remember = rememberMenu.items.firstIndex { $0.title.contains(PanelE2EWorld.pasteTarget.name) }
            rememberMenu.performActionForItem(at: remember ?? 0)
            context.checkEqual(
                "the target is remembered for Slack", "ja",
                context.stub?.rememberedTarget(for: PanelE2EWorld.pasteTarget.bundleID ?? ""))
            let checked = TranslationMenus.languageMenu(for: chosen, controller: controller).items
                .first { $0.title.contains(PanelE2EWorld.pasteTarget.name) }
            context.check("the menu shows it checked", checked?.state == .on)
            try await context.press(.escape)
            try await context.press(.returnKey, .option)
            await context.eventually("⌥↩ now pastes Japanese") {
                context.world.pasteboardText == PanelE2EFixtures.plainTranslation("mail", "ja")
            }
        }
    }
}
#endif
