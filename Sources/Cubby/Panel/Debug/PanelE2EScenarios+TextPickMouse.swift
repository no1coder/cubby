#if DEBUG
import AppKit
import CubbyCore

/// 拆词的鼠标操作（docs/TEXT-PICK-DESIGN.md P2、P7）：拖选（加选 / 取消 / 往回拖收缩）、卡片长按（不影响单击选中、
/// 双击粘贴）、卡片右键菜单「拆词 ⌘B」（不支持的条目置灰）
extension PanelE2EScenarios {
    static var pickDrag: PanelE2EScenario {
        PanelE2EScenario(
            name: "pick-drag",
            summary: "dragging picks a run; dragging back shrinks it; a drag starting on a picked chip unpicks"
        ) { context in
            try await context.open(selecting: "pick-en")
            try await context.command("b")
            try await context.waitForPickDocument()
            let please = try context.tokenIndex("Please")
            let pr = try context.tokenIndex("PR")
            try await context.dragTokens(from: please, through: [pr])
            context.checkEqual("dragging picks the run", "Please review PR", context.pick.result)
            let review = try context.tokenIndex("review")
            try await context.dragTokens(from: review, through: [pr])
            context.checkEqual("a drag from a picked chip unpicks", "Please", context.pick.result)
            let at = try context.tokenIndex("at")
            let before = try context.tokenIndex("before")
            let link = try context.tokenIndex(PickWords.link)
            try await context.dragTokens(from: at, through: [before, link])
            context.checkEqual(
                "dragging back shrinks the run (runs join with a space)", "Please at \(PickWords.link)",
                context.pick.result)
            context.check("the drag anchors ⇧-click", context.pick.selection.anchor == at)
        }
    }

    // MARK: - 长按

    static var pickLongPress: PanelE2EScenario {
        PanelE2EScenario(
            name: "pick-long-press",
            summary: "a 0.45 s press on a card opens the card; a short press only selects; double-click still pastes"
        ) { context in
            try await context.open(selecting: "mail")
            // 选中最后一条让列表滚到底，两张拆词演示卡都在可见区域
            let en = try await context.cardPoint("pick-en")
            let zh = try context.point(of: "list.card.\(PanelE2EFixtures.id("pick-zh"))")
            try await context.driver.mouseDown(at: zh)
            try await Task.sleep(for: .milliseconds(80))
            try await context.driver.mouseUp(at: zh)
            try await context.settle(.milliseconds(500))
            context.check("a short press does not open the card", !context.viewModel.isTextPickOpen)
            context.checkEqual(
                "… it selects the pressed card", PanelE2EFixtures.id("pick-zh"), context.viewModel.selectedItem?.id)
            try await context.driver.mouseDown(at: en)
            await context.eventually("holding 0.45 s opens the card") { context.viewModel.isTextPickOpen }
            context.checkEqual("… on the pressed item", PanelE2EFixtures.id("pick-en"), context.pick.item?.id)
            try await context.driver.mouseUp(at: en)
            try await context.settle()
            try await context.driver.click(at: zh)
            try await context.waitForPickDocument()
            context.checkEqual(
                "with the card open a click selects and the card follows", PanelE2EFixtures.id("pick-zh"),
                context.pick.item?.id)
            // 隔开一个双击间隔：否则上一次单击与这次双击的第一下就已构成双击，粘贴后面板关闭，第二下落空
            try await Task.sleep(for: .seconds(NSEvent.doubleClickInterval + 0.1))
            try await context.driver.click(at: zh, count: 2)
            await context.eventually("double-click still pastes the item") {
                context.world.pasteboardText == (try? context.item("pick-zh").text)
            }
        }
    }

    // MARK: - 右键菜单

    static var pickContextMenu: PanelE2EScenario {
        PanelE2EScenario(
            name: "pick-context-menu",
            summary: "the card menu has “Pick Words ⌘B”, disabled for a link; choosing it opens the card"
        ) { context in
            try await context.open(selecting: "mail")
            // 选中另一张卡（列表滚到底，两张拆词演示卡都可见），再右键 pick-zh：菜单必须作用于右键的那张卡
            _ = try await context.cardPoint("pick-en")
            let item = try await context.contextMenu(
                on: "pick-zh", item: TextPickCopy.title, choose: true, selectingFirst: false)
            context.check(
                "the menu lists Pick Words", item?.isEnabled != nil,
                detail: item.map { $0.titles.joined(separator: ", ") } ?? "no menu opened")
            context.check("… enabled for text", item?.isEnabled == true)
            context.check("… showing ⌘B", item?.keyEquivalent == "b" && item?.modifiers == .command)
            try await context.settle()
            context.check("choosing it opens the card", context.viewModel.isTextPickOpen)
            context.checkEqual("… on that item", PanelE2EFixtures.id("pick-zh"), context.pick.item?.id)
            context.checkEqual(
                "… which becomes the selection", PanelE2EFixtures.id("pick-zh"), context.viewModel.selectedItem?.id)
            try await context.press(.escape)
            let link = try await context.contextMenu(on: "link", item: TextPickCopy.title, choose: true)
            context.check("for a link it is disabled", link?.isEnabled == false)
            context.check("… so nothing opens", !context.viewModel.isTextPickOpen)
        }
    }
}
#endif
