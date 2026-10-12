import AppKit
import Carbon.HIToolbox
import Testing
@testable import CubbyCore

/// 晾衣绳的按键映射（docs/UI-UPGRADE-PLAN.md 第 5 节）：⌘L 挂上 / 取下选中的图片，按字符匹配
@Suite("PanelCommand 晾衣绳指令")
struct PanelCommandClotheslineTests {
    @Test(
        "⌘L 映射为挂上 / 取下（大写锁定、Dvorak 与卡片打开时同样映射）",
        arguments: [
            KeyCase("⌘L", kVK_ANSI_L, .command, "l", expect: .toggleClothesline),
            KeyCase("⌘L（大写锁定）", kVK_ANSI_L, [.command, .capsLock], "L", expect: .toggleClothesline),
            KeyCase("⌘L（Dvorak 按字符）", kVK_ANSI_P, .command, "l", expect: .toggleClothesline),
            KeyCase("⌘L（搜索框为空）", kVK_ANSI_L, .command, "l", allowsSpace: true, expect: .toggleClothesline),
            KeyCase("⌘L（翻译卡打开）", kVK_ANSI_L, .command, "l", cardOpen: true, expect: .toggleClothesline),
            KeyCase("⌘L（拆词卡打开）", kVK_ANSI_L, .command, "l", pickOpen: true, expect: .toggleClothesline),
            KeyCase("⌘L（图片网格）", kVK_ANSI_L, .command, "l", horizontal: true, expect: .toggleClothesline),
        ])
    func toggleClothesline(_ key: KeyCase) {
        #expect(key.resolve() == key.expected)
    }

    @Test(
        "加了 ⇧ / ⌥ / ⌃ 或没有 ⌘ 时不映射",
        arguments: [
            KeyCase("⇧⌘L", kVK_ANSI_L, [.command, .shift], "L", expect: nil),
            KeyCase("⌥⌘L", kVK_ANSI_L, [.command, .option], "¬", expect: nil),
            KeyCase("⌥⌘L（字符仍为 l）", kVK_ANSI_L, [.command, .option], "l", expect: nil),
            KeyCase("⌃⌘L", kVK_ANSI_L, [.command, .control], "l", expect: nil),
            KeyCase("L（无修饰）", kVK_ANSI_L, [], "l", expect: nil),
            KeyCase("⌃L", kVK_ANSI_L, .control, "l", expect: nil),
            KeyCase("⌘ + QWERTY 的 L 键位在 Dvorak 下是 n", kVK_ANSI_L, .command, "n", expect: nil),
        ])
    func otherModifiers(_ key: KeyCase) {
        #expect(key.resolve() == key.expected)
    }
}
