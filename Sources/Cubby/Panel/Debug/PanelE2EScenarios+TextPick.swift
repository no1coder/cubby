#if DEBUG
import AppKit
import CubbyCore

/// 拆词（docs/TEXT-PICK-DESIGN.md §4 的面板 E2E 清单）：⌘B 打开 / 关闭与三种详情区之间切换、点选、⌘A、⌘C 写入命名剪贴板
/// 且不入历史、↩ 粘贴、不支持的条目、跟随选中项、esc 顺序、识别出文字的图片、帮助与底栏。
/// 拖选、长按与右键菜单见 PanelE2EScenarios+TextPickMouse
extension PanelE2EScenarios {
    static var textPick: [PanelE2EScenario] {
        [
            pickToggle, pickClick, pickDrag, pickSelectAll, pickCopy, pickPaste, pickUnsupported, pickFollow,
            pickLongPress, pickContextMenu, pickEscape, pickImage, pickHelp,
        ]
    }

    static var pickToggle: PanelE2EScenario {
        PanelE2EScenario(
            name: "pick-toggle",
            summary: "⌘B opens / closes the card; preview ↔ card ↔ translation card share the detail window"
        ) { context in
            try await context.open(selecting: "pick-zh")
            try await context.command("b")
            context.check("⌘B opens the pick-words card", context.viewModel.isTextPickOpen)
            context.check("the detail window is on screen", context.detailWindow.isVisible)
            context.checkEqual(
                "the card shows the selected item", PanelE2EFixtures.id("pick-zh"), context.pick.item?.id)
            try await context.waitForPickDocument()
            context.check("the card height is within 236…620", (236...620).contains(context.detailWindow.frame.height))
            context.check("the canvas is laid out", context.hasAnchor("card.pick.canvas"))
            try await checkEntities(context)
            try await context.command("b")
            context.check("⌘B again closes the card", !context.viewModel.isTextPickOpen && !context.pick.isOpen)
            await context.eventually("the detail window hides") { !context.detailWindow.isVisible }
            try await context.press(.space)
            try await context.command("b")
            context.check("⌘B in the preview switches to the card", context.viewModel.isTextPickOpen)
            try await context.press(.escape)
            context.check("esc returns to the preview", context.viewModel.isPreviewVisible && !context.pick.isOpen)
            try await context.command("b")
            try await context.press(.space)
            context.check("space switches back to the preview", context.viewModel.isPreviewVisible)
            try await switchesWithTranslation(context)
        }
    }

    /// 网址 / 邮箱 / 电话各成一块（实体），地址按词拆开
    private static func checkEntities(_ context: PanelE2EContext) async throws {
        let entities = context.pickTokens.filter { $0.kind == .entity }.map(\.text)
        context.check(
            "the email and the phone number are single chips",
            entities.contains(PickWords.email) && entities.contains(PickWords.phone),
            detail: entities.joined(separator: ", "))
        context.check(
            "the address is split into words", context.pickTokens.contains { $0.text == PickWords.beijing })
        context.check(
            "VoiceOver sees one element per chip",
            context.pickCanvas?.accessibilityChildren()?.count == context.pickTokens.count)
    }

    /// ⌘T 从拆词卡切到翻译卡，⌘B 再切回来
    private static func switchesWithTranslation(_ context: PanelE2EContext) async throws {
        try await context.press(.escape)
        try await context.command("b")
        try await context.command("t")
        context.check(
            "⌘T in the card switches to the translation card",
            context.viewModel.isTranslationCardOpen && !context.pick.isOpen)
        try await context.command("b")
        context.check(
            "⌘B in the translation card switches back",
            context.viewModel.isTextPickOpen && context.card == nil)
    }

    // MARK: - 点选

    static var pickClick: PanelE2EScenario {
        PanelE2EScenario(
            name: "pick-click",
            summary: "click toggles a chip, ⇧-click extends from the last click; results follow the joining rule"
        ) { context in
            try await context.open(selecting: "pick-zh")
            try await context.command("b")
            try await context.waitForPickDocument()
            let meeting = try context.tokenIndex(PickWords.meeting)
            let thursday = try context.tokenIndex(PickWords.thursday)
            try await context.clickToken(meeting)
            context.checkEqual("clicking a chip picks it", PickWords.meeting, context.pick.result)
            context.check("the result strip appears", context.hasAnchor("card.pick.result"))
            try await context.clickToken(thursday)
            context.checkEqual(
                "Chinese runs join without a space", PickWords.meeting + PickWords.thursday, context.pick.result)
            try await context.clickToken(meeting)
            context.checkEqual("clicking again unpicks it", PickWords.thursday, context.pick.result)
            try await context.clickToken(try context.tokenIndex(PickWords.afternoon), flags: .shift)
            context.checkEqual(
                "⇧-click picks everything from the last click", PickWords.meetingToAfternoon, context.pick.result)
            context.hover(at: try await context.tokenPoint(meeting))
            context.checkEqual("hover is tracked in the non-key window", meeting, context.pickCanvas?.hovered)
            context.hover(at: nil)
            context.check("… and cleared when the pointer leaves", context.pickCanvas?.hovered == nil)
            let element = context.pickCanvas?.accessibilityChildren()?.first as? TextPickTokenElement
            let wasPicked = context.pick.selection.contains(0)
            _ = element?.accessibilityPerformPress()
            context.check(
                "a VoiceOver press toggles the chip", context.pick.selection.contains(0) != wasPicked)
        }
    }

    // MARK: - 全选

    static var pickSelectAll: PanelE2EScenario {
        PanelE2EScenario(
            name: "pick-select-all",
            summary: "⌘A selects all (again clears); Select All works too; with a search query ⌘A stays in the field"
        ) { context in
            try await context.open(selecting: "pick-en")
            try await context.command("b")
            try await context.waitForPickDocument()
            try await context.command("a")
            context.check("⌘A selects every chip", context.pick.isAllSelected)
            let original = try context.item("pick-en").text ?? ""
            context.checkEqual("… and the result is the original text", original, context.pick.result)
            try await context.command("a")
            context.check("⌘A again clears", context.pick.selection.isEmpty)
            try await context.click("card.pick.selectAll")
            context.check("clicking Select All in the non-key window works", context.pick.isAllSelected)
            try await context.click("card.pick.selectAll")
            context.viewModel.searchText = PickWords.englishQuery
            try await context.settle()
            context.check(
                "the card still shows the item", context.pick.item?.id == PanelE2EFixtures.id("pick-en"))
            try await context.command("a")
            context.check("with a search query ⌘A belongs to the search field", context.pick.selection.isEmpty)
            let editor = context.panelWindow.firstResponder as? NSTextView
            context.checkEqual(
                "… which selects the query", (PickWords.englishQuery as NSString).length,
                editor?.selectedRange().length)
        }
    }

    // MARK: - 复制与粘贴

    static var pickCopy: PanelE2EScenario {
        PanelE2EScenario(
            name: "pick-copy",
            summary: "⌘C / ⌘↩ / Copy write the result, marked so it is not recorded; nothing picked beeps"
        ) { context in
            try await context.open(selecting: "pick-zh")
            try await context.command("b")
            try await context.waitForPickDocument()
            try await context.command("c")
            context.check("⌘C with nothing picked writes nothing", context.world.pasteboardText == nil)
            try await context.clickToken(try context.tokenIndex(PickWords.email))
            try await context.command("c")
            context.checkEqual("⌘C copies the picked words", PickWords.email, context.world.pasteboardText)
            context.check(
                "… marked so the monitor ignores it", PasteboardReader.shouldIgnore(context.world.pasteboard))
            context.check("… the panel stays open", context.world.panel.debugIsShown && context.pick.isOpen)
            context.checkEqual(
                "… with a footer toast", TextPickCopy.copied(characters: PickWords.email.count),
                context.viewModel.toast?.message)
            context.check(
                "copying adds nothing to history",
                context.world.store.history.items.count == PanelE2EFixtures.entries.count)
            context.world.pasteboard.clearContents()
            try await context.press(.returnKey, .command)
            context.checkEqual("⌘↩ copies too", PickWords.email, context.world.pasteboardText)
            context.world.pasteboard.clearContents()
            try await context.click("card.pick.copy")
            context.checkEqual("the Copy button copies", PickWords.email, context.world.pasteboardText)
        }
    }

    static var pickPaste: PanelE2EScenario {
        PanelE2EScenario(
            name: "pick-paste",
            summary: "↩ pastes the result through the item delivery (promote, hide); the Paste button does the same"
        ) { context in
            try await context.open(selecting: "pick-zh")
            try await context.command("b")
            try await context.waitForPickDocument()
            try await context.clickToken(try context.tokenIndex(PickWords.beijing))
            try await context.clickToken(try context.tokenIndex(PickWords.chaoyang))
            try await context.press(.returnKey)
            let expected = PickWords.beijing + PickWords.chaoyang
            await context.eventually("↩ writes the picked words") { context.world.pasteboardText == expected }
            context.check("the panel hides after pasting", !context.world.panel.debugIsShown)
            context.checkEqual(
                "the source item is promoted", PanelE2EFixtures.id("pick-zh"),
                context.world.store.history.items.first?.id)
            context.check(
                "no new history item", context.world.store.history.items.count == PanelE2EFixtures.entries.count)
            context.check("the card closed with the panel", !context.pick.isOpen)
            context.world.pasteboard.clearContents()
            try await context.open(selecting: "pick-en")
            try await context.command("b")
            try await context.waitForPickDocument()
            try await context.clickToken(try context.tokenIndex(PickWords.link))
            try await context.click("card.pick.paste")
            await context.eventually("the Paste button pastes") { context.world.pasteboardText == PickWords.link }
        }
    }

    // MARK: - 不支持的条目与跟随

    static var pickUnsupported: PanelE2EScenario {
        PanelE2EScenario(
            name: "pick-unsupported",
            summary: "⌘B on a link, color or text-less image beeps with a footer hint; following onto one shows why"
        ) { context in
            for key in ["link", "color", "image"] {
                try await context.open(selecting: key)
                try await context.command("b")
                context.check("⌘B on \(key) opens nothing", !context.viewModel.isTextPickOpen)
                context.checkEqual("… the footer explains", TextPickCopy.noText, context.viewModel.toast?.message)
            }
            try await context.open(selecting: "pick-en")
            try await context.command("b")
            try await context.waitForPickDocument()
            try context.select("link")
            try await context.settle()
            context.check("following onto a link shows the state page", context.pick.isUnsupported)
            context.check(
                "… inside the open card", context.viewModel.isTextPickOpen && context.hasAnchor("card.pick.state"))
            try await context.press(.returnKey)
            context.check("↩ there pastes nothing", context.world.pasteboardText == nil)
            try context.select("pick-en")
            try await context.waitForPickDocument()
            context.check(
                "moving back shows the chips again", !context.pick.isUnsupported && !context.pickTokens.isEmpty)
        }
    }

    static var pickFollow: PanelE2EScenario {
        PanelE2EScenario(
            name: "pick-follow",
            summary: "the card follows the selection and clears the picked words"
        ) { context in
            try await context.open(selecting: "pick-zh")
            try await context.command("b")
            try await context.waitForPickDocument()
            try await context.clickToken(try context.tokenIndex(PickWords.meeting))
            try await context.press(.downArrow)
            try await context.waitForPickDocument()
            context.checkEqual("the card follows ↓", PanelE2EFixtures.id("pick-en"), context.pick.item?.id)
            context.check("… with that item's text", context.pick.document?.text == (try? context.item("pick-en").text))
            context.check("… and nothing picked", context.pick.selection.isEmpty)
            try await context.press(.upArrow)
            try await context.waitForPickDocument()
            context.checkEqual("↑ follows back", PanelE2EFixtures.id("pick-zh"), context.pick.item?.id)
        }
    }

    // MARK: - esc、图片、帮助

    static var pickEscape: PanelE2EScenario {
        PanelE2EScenario(
            name: "pick-escape",
            summary: "esc order: help → card → preview → search → panel"
        ) { context in
            try await context.open(selecting: "pick-en")
            try await context.press(.space)
            try await context.command("b")
            context.viewModel.toggleHelp()
            try await context.settle()
            try await context.press(.escape)
            context.check("esc closes help first", !context.viewModel.isShowingHelp && context.viewModel.isTextPickOpen)
            try await context.press(.escape)
            context.check("then the card (back to the preview)", context.viewModel.isPreviewVisible)
            try await context.press(.escape)
            context.check("then the preview", context.viewModel.detailPane == nil)
            context.viewModel.searchText = PickWords.englishQuery
            try await context.settle()
            try await context.press(.escape)
            context.check("then the search", context.viewModel.searchText.isEmpty)
            try await context.press(.escape)
            context.check("then the panel", !context.world.panel.debugIsShown)
        }
    }

    static var pickImage: PanelE2EScenario {
        PanelE2EScenario(
            name: "pick-image",
            summary: "an image shows the state page until its text is recognized, then its OCR words; ⌘B opens it"
        ) { context in
            let recognized = PanelE2EFixtures.imageTexts.joined(separator: "\n")
            try await context.open(selecting: "pick-en")
            try await context.command("b")
            try await context.waitForPickDocument()
            try context.select("image")
            try await context.settle()
            context.check("an image without recognized text shows the state page", context.pick.isUnsupported)
            context.world.store.setRecognizedText(recognized, for: PanelE2EFixtures.id("image"))
            await context.eventually("when recognition finishes the card shows its words") {
                context.pick.document?.text == recognized
            }
            context.check("… into words", context.pickTokens.contains { $0.text == "Update" })
            try await context.press(.escape)
            try await context.command("b")
            context.check("⌘B opens the card on the image", context.viewModel.isTextPickOpen)
            try await context.waitForPickDocument()
            context.checkEqual("the card splits the recognized text", recognized, context.pick.document?.text)
        }
    }

    static var pickHelp: PanelE2EScenario {
        PanelE2EScenario(
            name: "pick-help",
            summary: "help lists ⌘B; with the card open also ⌘A and ⌘C; the footer shows the card's keys"
        ) { context in
            try await context.open(selecting: "pick-zh")
            context.viewModel.toggleHelp()
            try await context.settle()
            context.check("help lists ⌘B", context.hasAnchor("help.⌘B"))
            context.check("help lists ⌘A only with the card open", !context.hasAnchor("help.⌘A"))
            try await context.command("b")
            context.check("⌘B closes help first, then opens the card", !context.viewModel.isShowingHelp)
            context.check("… and the card is open", context.viewModel.isTextPickOpen)
            context.check("the footer shows the card's keys", context.hasAnchor("footer.pick"))
            context.viewModel.toggleHelp()
            try await context.settle()
            context.check("with the card open help lists ⌘A", context.hasAnchor("help.⌘A"))
            context.check("… and ⌘C", context.hasAnchor("help.⌘C"))
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

/// 脚本里用到的词（中文用 Unicode 转义，源码字面量不得含汉字）
enum PickWords {
    /// 会议、周四、下午、「会议改到周四下午」、北京市、朝阳区
    static let meeting = "\u{4F1A}\u{8BAE}"
    static let thursday = "\u{5468}\u{56DB}"
    static let afternoon = "\u{4E0B}\u{5348}"
    static let meetingToAfternoon = "\u{4F1A}\u{8BAE}\u{6539}\u{5230}\u{5468}\u{56DB}\u{4E0B}\u{5348}"
    static let beijing = "\u{5317}\u{4EAC}\u{5E02}"
    static let chaoyang = "\u{671D}\u{9633}\u{533A}"
    static let email = "wang.xm@example.com"
    static let phone = "13812345678"
    static let link = "https://github.com/no1coder/cubby/pull/1234"
    /// 只有 pick-en 命中的搜索词
    static let englishQuery = "30pm"
}
#endif
