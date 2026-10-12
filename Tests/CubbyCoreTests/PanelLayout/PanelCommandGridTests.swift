import AppKit
import Carbon.HIToolbox
import Testing
@testable import CubbyCore

/// 横条与图片网格的键盘（docs/UI-UPGRADE-PLAN.md 第 3、4 节）：← / → 移动一格，网格里 ↑ / ↓ 移动一整行
@Suite("PanelCommand 横条与网格")
struct PanelCommandGridTests {
    @Test(
        "← / → 的映射：只在横向排列且搜索框为空时移动选中项",
        arguments: [
            KeyCase("←（横向、搜索框为空）", kVK_LeftArrow, allowsSpace: true, horizontal: true, expect: .moveLeft),
            KeyCase("→（横向、搜索框为空）", kVK_RightArrow, allowsSpace: true, horizontal: true, expect: .moveRight),
            KeyCase(
                "→（带方向键设备标志）", kVK_RightArrow, [.numericPad, .function], allowsSpace: true, horizontal: true,
                expect: .moveRight),
            KeyCase("←（横向、搜索框有字：留给光标）", kVK_LeftArrow, horizontal: true, expect: nil),
            KeyCase("←（竖向列表）", kVK_LeftArrow, allowsSpace: true, expect: nil),
            KeyCase("⇧←（横向：留给搜索框选取）", kVK_LeftArrow, .shift, allowsSpace: true, horizontal: true, expect: nil),
            KeyCase("⌘→（横向）", kVK_RightArrow, .command, allowsSpace: true, horizontal: true, expect: nil),
            KeyCase(
                "←（横向、拆词卡打开）", kVK_LeftArrow, allowsSpace: true, pickOpen: true, horizontal: true,
                expect: .moveLeft),
        ])
    func horizontalArrows(_ key: KeyCase) {
        #expect(key.resolve() == key.expected)
    }

    @Test(
        "翻译卡打开时 ← / → 仍归翻译卡",
        arguments: [
            KeyCase(
                "←", kVK_LeftArrow, allowsSpace: true, cardOpen: true, horizontal: true,
                expect: .stepTranslationView(-1)),
            KeyCase(
                "⇧→", kVK_RightArrow, .shift, allowsSpace: true, cardOpen: true, horizontal: true,
                expect: .stepTranslationView(PanelCommand.largeTranslationStep)),
        ])
    func translationCardKeepsArrows(_ key: KeyCase) {
        #expect(key.resolve() == key.expected)
    }

    @Test(
        "横向排列时 ↑ / ↓ 照常可用",
        arguments: [
            KeyCase("↑", kVK_UpArrow, allowsSpace: true, horizontal: true, expect: .moveUp),
            KeyCase("↓", kVK_DownArrow, horizontal: true, expect: .moveDown),
        ])
    func verticalArrowsStillWork(_ key: KeyCase) {
        #expect(key.resolve() == key.expected)
    }

    @Test(
        "两列网格中的目标序号（7 张图：最后一行只有一格）",
        arguments: [
            MoveCase("↓ 移动一整行", .moveDown, from: 1, count: 7, expect: 3),
            MoveCase("↑ 移动一整行", .moveUp, from: 4, count: 7, expect: 2),
            MoveCase("→ 移动一格（跨行）", .moveRight, from: 1, count: 7, expect: 2),
            MoveCase("← 移动一格（跨行）", .moveLeft, from: 2, count: 7, expect: 1),
            MoveCase("↓ 最后一行不满时落到最后一格", .moveDown, from: 5, count: 7, expect: 6),
            MoveCase("↓ 已在最后一格时不动", .moveDown, from: 6, count: 7, expect: 6),
            MoveCase("↑ 在首行时不动（与访达一致）", .moveUp, from: 1, count: 7, expect: 1),
            MoveCase("↑ 在首格不动", .moveUp, from: 0, count: 7, expect: 0),
            MoveCase("↓ 在最后一行（满行）时不动", .moveDown, from: 6, count: 8, expect: 6),
            MoveCase("↓ 从倒数第二行的右格落到不满的最后一行", .moveDown, from: 5, count: 7, expect: 6),
            MoveCase("← 在首格不越界", .moveLeft, from: 0, count: 7, expect: 0),
            MoveCase("→ 在末格不越界", .moveRight, from: 6, count: 7, expect: 6),
            MoveCase("PageDown 移动 5 行", .pageDown, from: 1, count: 30, expect: 11),
            MoveCase("PageUp 移动 5 行", .pageUp, from: 21, count: 30, expect: 11),
            MoveCase("首格", .moveToFirst, from: 5, count: 7, expect: 0),
            MoveCase("末格", .moveToLast, from: 0, count: 7, expect: 6),
        ])
    func gridDestination(_ move: MoveCase) {
        #expect(move.command.selectionIndex(from: move.current, count: move.count, columns: 2) == move.expected)
    }

    @Test("单列（列表与横条）时 ← / → 与 ↑ / ↓ 都移动一格")
    func singleColumn() {
        #expect(PanelCommand.moveRight.selectionIndex(from: 3, count: 10) == 4)
        #expect(PanelCommand.moveLeft.selectionIndex(from: 3, count: 10) == 2)
        #expect(PanelCommand.moveDown.selectionIndex(from: 3, count: 10, columns: 1) == 4)
    }

    @Test("列数为 0 或负数时按单列处理", arguments: [0, -2])
    func invalidColumns(_ columns: Int) {
        #expect(PanelCommand.moveDown.selectionIndex(from: 3, count: 10, columns: columns) == 4)
        #expect(PanelCommand.pageDown.selectionIndex(from: 0, count: 10, columns: columns) == 5)
    }

    @Test("空网格没有目标", arguments: [PanelCommand.moveLeft, .moveRight])
    func emptyGrid(_ command: PanelCommand) {
        #expect(command.selectionIndex(from: 0, count: 0, columns: 2) == nil)
    }
}
