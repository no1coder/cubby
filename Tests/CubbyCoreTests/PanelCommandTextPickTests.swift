import AppKit
import Carbon.HIToolbox
import Testing
@testable import CubbyCore

/// 拆词的按键映射（docs/TEXT-PICK-DESIGN.md §2）：⌘B 总是拆词；卡片打开时 ⌘C 复制所选、⌘A 全选（仅搜索框为空）
@Suite("PanelCommand 拆词相关指令")
struct PanelCommandTextPickTests {
    @Test(
        "⌘B 始终映射为拆词（按字符匹配，卡片打开时同样是关闭开关）",
        arguments: [
            KeyCase("⌘B", kVK_ANSI_B, .command, "b", expect: .pickWords),
            KeyCase("⌘B（大写锁定）", kVK_ANSI_B, [.command, .capsLock], "B", expect: .pickWords),
            KeyCase("⌘B（Dvorak 按字符）", kVK_ANSI_N, .command, "b", expect: .pickWords),
            KeyCase("⌘B（拆词卡打开）", kVK_ANSI_B, .command, "b", pickOpen: true, expect: .pickWords),
            KeyCase("⌘B（翻译卡打开）", kVK_ANSI_B, .command, "b", cardOpen: true, expect: .pickWords),
            KeyCase("⌘B（搜索框有字）", kVK_ANSI_B, .command, "b", allowsSpace: false, expect: .pickWords),
        ])
    func pickWords(_ key: KeyCase) {
        #expect(key.resolve() == key.expected)
    }

    @Test(
        "⌘C / ⌘A 只在拆词卡打开时映射；⌘A 还要求搜索框为空",
        arguments: [
            KeyCase("⌘C（拆词卡打开）", kVK_ANSI_C, .command, "c", pickOpen: true, expect: .copyPickedWords),
            KeyCase(
                "⌘C（拆词卡打开、搜索框为空）", kVK_ANSI_C, .command, "c", allowsSpace: true, pickOpen: true,
                expect: .copyPickedWords),
            KeyCase(
                "⌘A（拆词卡打开、搜索框为空）", kVK_ANSI_A, .command, "a", allowsSpace: true, pickOpen: true,
                expect: .selectAllWords),
            KeyCase("⌘A（拆词卡打开、搜索框有字）", kVK_ANSI_A, .command, "a", pickOpen: true, expect: nil),
            KeyCase("⌘A（拆词卡关闭）", kVK_ANSI_A, .command, "a", allowsSpace: true, expect: nil),
            KeyCase("⌘C（拆词卡关闭）", kVK_ANSI_C, .command, "c", allowsSpace: true, expect: nil),
            KeyCase("⇧⌘C（拆词卡打开）", kVK_ANSI_C, [.command, .shift], "C", pickOpen: true, expect: nil),
            KeyCase(
                "⇧⌘A（拆词卡打开）", kVK_ANSI_A, [.command, .shift], "A", allowsSpace: true, pickOpen: true,
                expect: nil),
            KeyCase("⇧⌘B", kVK_ANSI_B, [.command, .shift], "B", expect: nil),
            KeyCase("⌥⌘B", kVK_ANSI_B, [.command, .option], "b", expect: nil),
            KeyCase("B（无修饰）", kVK_ANSI_B, [], "b", allowsSpace: true, pickOpen: true, expect: nil),
        ])
    func cardOnlyCommands(_ key: KeyCase) {
        #expect(key.resolve() == key.expected)
    }

    @Test(
        "拆词卡打开不改变其他按键：↩ / ⇧↩ / ⌘↩ / 空格 / ⌘T / ⌘Y / ← →",
        arguments: [
            KeyCase("↩", kVK_Return, pickOpen: true, expect: .paste),
            KeyCase("⇧↩", kVK_Return, .shift, pickOpen: true, expect: .pasteAlternate),
            KeyCase("⌘↩", kVK_Return, .command, pickOpen: true, expect: .copyOnly),
            KeyCase("空格", kVK_Space, [], " ", allowsSpace: true, pickOpen: true, expect: .togglePreview),
            KeyCase("⌘T", kVK_ANSI_T, .command, "t", pickOpen: true, expect: .translate),
            KeyCase("⌘Y", kVK_ANSI_Y, .command, "y", pickOpen: true, expect: .togglePreview),
            KeyCase("←（不切换译文视图）", kVK_LeftArrow, allowsSpace: true, pickOpen: true, expect: nil),
            KeyCase("⌘S（只属于翻译卡）", kVK_ANSI_S, .command, "s", pickOpen: true, expect: nil),
        ])
    func otherKeysUnchanged(_ key: KeyCase) {
        #expect(key.resolve() == key.expected)
    }

    @Test("两张卡的标志同时为真时（不会发生）⌘C 仍归翻译卡，保持原有映射")
    func translationWinsForCopy() {
        let command = PanelCommand.from(
            keyCode: UInt16(kVK_ANSI_C), modifiers: .command, characters: "c", allowsSpace: true,
            translationCardOpen: true, textPickOpen: true)
        #expect(command == .copyTranslation)
    }

    @Test("拆词指令不是选择移动")
    func pickCommandsDoNotMoveSelection() {
        for command in [PanelCommand.pickWords, .copyPickedWords, .selectAllWords] {
            #expect(command.selectionIndex(from: 2, count: 5) == nil)
        }
    }
}
