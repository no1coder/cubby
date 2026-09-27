#if DEBUG
import AppKit
import CubbyCore

/// 图片翻译（逐块叠画、卷帘、悬停原文、按住 ⌥）与列表中按住 ⌥ 预览译文（A4）
extension PanelE2EScenarios {
    static var image: PanelE2EScenario {
        var options = PanelE2EWorld.Options()
        options.startDelay = .milliseconds(300)
        options.segmentDelay = .milliseconds(150)
        return PanelE2EScenario(
            name: "image",
            summary: "image blocks arrive over the picture; wipe drag and ←/→; hover bubble; hold ⌥; ↩ pastes the PNG",
            options: options
        ) { context in
            try await context.open(selecting: "image")
            try await context.command("t")
            context.checkEqual("the image card starts recognizing", TranslationCardPhase.waiting, context.card?.phase)
            try await context.wait("the first block") { (context.card?.content.imageBlocks.count ?? 0) >= 1 }
            context.check("blocks arrive one by one", (context.card?.content.imageBlocks.count ?? 0) < 5)
            try await context.waitForCard(.done)
            context.checkEqual("all five blocks arrived", 5, context.card?.content.imageBlocks.count)
            try await context.press(.rightArrow)
            try await context.settle()
            context.check("side by side shows the wipe divider", context.hasAnchor("card.divider"))
            try await dragDivider(context)
            try await hoverBubble(context)
            try await context.holdOption(true)
            context.check("holding ⌥ shows the original image", context.card?.isPeeking == true)
            try await context.holdOption(false)
            context.check("releasing ⌥ shows the translation", context.card?.isPeeking == false)
            let expected = context.card?.content.result?.imageURL.flatMap { try? Data(contentsOf: $0) }
            try await context.press(.returnKey)
            await context.eventually("↩ pastes the translated PNG") {
                expected != nil && context.world.pasteboard.data(forType: .png) == expected
            }
        }
    }

    /// 拖动分隔线到 25%，再用 → 微调（点过分隔线后 ← / → 改为微调）
    private static func dragDivider(_ context: PanelE2EContext) async throws {
        let stage = try context.frame(of: "card.stage", in: context.detailWindow)
        let start = CGPoint(x: stage.midX, y: stage.midY)
        let end = CGPoint(x: stage.minX + stage.width * 0.25, y: stage.midY)
        try await context.driver.drag(through: [start, end])
        let wipe = context.card?.wipe ?? 0
        context.check("dragging the divider moves the wipe", abs(wipe - 0.25) < 0.03, detail: "wipe \(wipe)")
        context.check("… and focuses it", context.card?.isDividerFocused == true)
        try await context.press(.rightArrow)
        let nudged = context.card?.wipe ?? 0
        context.check("→ nudges the divider", abs(nudged - (wipe + 0.02)) < 0.001, detail: "wipe \(nudged)")
        context.checkEqual("… instead of switching views", TranslationViewMode.sideBySide, context.card?.mode)
    }

    /// 悬停在「立即更新」按钮的译文上 400 ms：气泡显示原文
    private static func hoverBubble(_ context: PanelE2EContext) async throws {
        let stage = try context.frame(of: "card.stage", in: context.detailWindow)
        let point = PanelE2EFixtures.stagePoint(of: 4, in: stage)
        context.hover(at: point)
        try await context.settle(.milliseconds(150))
        context.check("the bubble waits 400 ms", !context.hasAnchor("card.bubble"))
        await context.eventually("hovering a block shows its original", timeout: .seconds(2)) {
            context.hasAnchor("card.bubble")
        }
        context.hover(at: nil)
        await context.eventually("moving away hides the bubble") { !context.hasAnchor("card.bubble") }
    }

    static var holdOptionCloud: PanelE2EScenario {
        var options = PanelE2EWorld.Options()
        options.engine = .cloud
        return PanelE2EScenario(
            name: "hold-option-cloud",
            summary: "with a cloud engine the preview shows at 300 ms but sends only after 0.6 s; a click cancels",
            options: options
        ) { context in
            try await context.open(selecting: "mail")
            try await context.holdOption(true)
            await context.eventually("the preview shows after the hold") {
                context.translation?.peek.peek?.phase == .holding
            }
            context.check("… without sending yet", context.stub?.sentCalls.isEmpty == true)
            await context.eventually("it sends once the 0.6 s dwell is over", timeout: .seconds(2)) {
                context.stub?.sentCalls.count == 1
            }
            try await context.holdOption(false)
            try context.select("notes")
            try await context.holdOption(true)
            await context.eventually("the next preview holds") { context.translation?.peek.peek?.phase == .holding }
            let panel = ScreenTopologyProvider.toGlobal(context.panelWindow.frame)
            try await context.driver.click(at: CGPoint(x: panel.minX + 30, y: panel.maxY - 18))
            context.check("a click cancels the preview", context.translation?.peek.peek == nil)
            try await Task.sleep(for: .milliseconds(700))
            context.checkEqual("… and nothing is sent", 1, context.stub?.sentCalls.count)
            try await context.holdOption(false)
            try await context.holdOption(true)
            await context.eventually("holding again") { context.translation?.peek.peek?.phase == .holding }
            try await context.press(.returnKey)
            context.checkEqual("↩ while holding sends at once", 2, context.stub?.sentCalls.count)
            await context.eventually("… and pastes when done") {
                context.world.pasteboardText == PanelE2EFixtures.plainTranslation("notes", "en")
            }
            try await context.holdOption(false)
        }
    }

    static var holdOption: PanelE2EScenario {
        var options = PanelE2EWorld.Options()
        options.segmentDelay = .milliseconds(200)
        return PanelE2EScenario(
            name: "hold-option",
            summary: "holding ⌥ ~300 ms previews the translation in the card; ↩ pastes it; other keys cancel",
            options: options
        ) { context in
            try await context.open(selecting: "mail")
            let mail = PanelE2EFixtures.id("mail")
            try await context.holdOption(true)
            try await context.settle(.milliseconds(150))
            context.check("no preview before 300 ms", context.translation?.peek.peek == nil)
            await context.eventually("the preview starts after the hold") { context.translation?.peek.peek != nil }
            try await context.settle()
            context.check("the card shows the preview", context.hasAnchor("list.peek.\(mail)"))
            await context.eventually("the preview finishes") { context.translation?.peek.peek?.phase == .done }
            try await context.holdOption(false)
            context.check("releasing ⌥ restores the card", context.translation?.peek.peek == nil)
            try await context.settle()
            context.check("the card content is back", !context.hasAnchor("list.peek.\(mail)"))
            try await context.holdOption(true)
            try await context.settle(.milliseconds(100))
            try await context.press(.downArrow)
            try await context.settle(.milliseconds(400))
            context.check("⌥↓ keeps its meaning and cancels the hold", context.translation?.peek.peek == nil)
            context.checkEqual(
                "… jumping to the last item", PanelE2EFixtures.id("terminal"), context.viewModel.selectedItem?.id)
            try await context.holdOption(false)
            try context.select("mail")
            try await context.holdOption(true)
            await context.eventually("the preview starts again") { context.translation?.peek.peek != nil }
            try await context.press(.returnKey)
            await context.eventually("↩ while holding pastes the shown translation") {
                context.world.pasteboardText == PanelE2EFixtures.plainTranslation("mail", "zh-Hans")
            }
            try await context.holdOption(false)
        }
    }
}
#endif
