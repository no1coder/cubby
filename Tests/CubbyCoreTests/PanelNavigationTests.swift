import AppKit
import Carbon.HIToolbox
import Testing
@testable import CubbyCore

/// 选择移动：从 current 出发，指令移动到的目标序号
struct MoveCase: Sendable, CustomTestStringConvertible {
    let label: String
    let command: PanelCommand
    let current: Int
    let count: Int
    let expected: Int?

    init(_ label: String, _ command: PanelCommand, from current: Int, count: Int, expect expected: Int?) {
        self.label = label
        self.command = command
        self.current = current
        self.count = count
        self.expected = expected
    }

    var testDescription: String { label }
}

@Suite("PanelCommand 快速跳转")
struct PanelNavigationTests {
    @Test(
        "跳转按键映射：Home/End、⌥↑/⌥↓、PageUp/PageDown",
        arguments: [
            KeyCase("Home", kVK_Home, expect: .moveToFirst),
            KeyCase("End", kVK_End, expect: .moveToLast),
            KeyCase("⌥↑", kVK_UpArrow, .option, expect: .moveToFirst),
            KeyCase("⌥↓", kVK_DownArrow, .option, expect: .moveToLast),
            KeyCase("PageUp", kVK_PageUp, expect: .pageUp),
            KeyCase("PageDown", kVK_PageDown, expect: .pageDown),
            KeyCase("Home（带 fn 标志）", kVK_Home, .function, expect: .moveToFirst),
            KeyCase("PageDown（带 fn 标志）", kVK_PageDown, .function, expect: .pageDown),
            KeyCase("⌥↑（带方向键设备标志）", kVK_UpArrow, [.option, .numericPad, .function], expect: .moveToFirst),
            KeyCase("End 在允许空格时同样有效", kVK_End, allowsSpace: true, expect: .moveToLast),
        ])
    func jumpKeys(_ key: KeyCase) {
        #expect(key.resolve() == key.expected)
    }

    @Test(
        "⇧⌘P 贴到屏幕（按字符匹配，兼容大写锁定）",
        arguments: [
            KeyCase("⇧⌘P", kVK_ANSI_P, [.command, .shift], "P", expect: .pinToScreen),
            KeyCase("⇧⌘P（字符为小写）", kVK_ANSI_P, [.command, .shift], "p", expect: .pinToScreen),
            KeyCase("⇧⌘P（大写锁定）", kVK_ANSI_P, [.command, .shift, .capsLock], "P", expect: .pinToScreen),
            KeyCase("⌘P 仍为收藏", kVK_ANSI_P, .command, "p", expect: .toggleFavorite),
        ])
    func pinShortcut(_ key: KeyCase) {
        #expect(key.resolve() == key.expected)
    }

    @Test("翻页步长为 5 条")
    func pageSize() {
        #expect(PanelCommand.pageSize == 5)
    }

    @Test(
        "移动类指令的目标序号（结果夹在列表范围内）",
        arguments: [
            MoveCase("↓ 下移一条", .moveDown, from: 3, count: 10, expect: 4),
            MoveCase("↑ 上移一条", .moveUp, from: 3, count: 10, expect: 2),
            MoveCase("↑ 在首条不越界", .moveUp, from: 0, count: 10, expect: 0),
            MoveCase("↓ 在末条不越界", .moveDown, from: 9, count: 10, expect: 9),
            MoveCase("PageDown 下移一页", .pageDown, from: 2, count: 20, expect: 7),
            MoveCase("PageUp 上移一页", .pageUp, from: 12, count: 20, expect: 7),
            MoveCase("PageDown 不足一页时停在末条", .pageDown, from: 17, count: 20, expect: 19),
            MoveCase("PageUp 不足一页时停在首条", .pageUp, from: 3, count: 20, expect: 0),
            MoveCase("首条", .moveToFirst, from: 432, count: 600, expect: 0),
            MoveCase("末条", .moveToLast, from: 0, count: 600, expect: 599),
            MoveCase("只有一条时各指令都停在 0", .pageDown, from: 0, count: 1, expect: 0),
            MoveCase("当前序号越界时先夹回范围", .moveDown, from: 50, count: 10, expect: 9),
            MoveCase("当前序号为负时先夹回范围", .moveUp, from: -3, count: 10, expect: 0),
        ])
    func destination(_ move: MoveCase) {
        #expect(move.command.selectionIndex(from: move.current, count: move.count) == move.expected)
    }

    @Test(
        "空列表没有目标",
        arguments: [PanelCommand.moveUp, .moveDown, .pageUp, .pageDown, .moveToFirst, .moveToLast])
    func emptyList(_ command: PanelCommand) {
        #expect(command.selectionIndex(from: 0, count: 0) == nil)
    }

    @Test(
        "非移动类指令没有目标",
        arguments: [PanelCommand.paste, .escape, .togglePreview, .pinToScreen, .pasteAt(2), .delete])
    func nonMovingCommands(_ command: PanelCommand) {
        #expect(command.selectionIndex(from: 1, count: 10) == nil)
    }
}
