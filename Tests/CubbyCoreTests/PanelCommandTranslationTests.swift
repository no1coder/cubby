import AppKit
import Carbon.HIToolbox
import Testing
@testable import CubbyCore

@Suite("PanelCommand 翻译相关指令")
struct PanelCommandTranslationTests {
    @Test(
        "⌘T 与别名 ⇧⌘T 始终映射为翻译",
        arguments: [
            KeyCase("⌘T", kVK_ANSI_T, .command, "t", expect: .translate),
            KeyCase("⇧⌘T", kVK_ANSI_T, [.command, .shift], "T", expect: .translate),
            KeyCase("⌘T（大写锁定）", kVK_ANSI_T, [.command, .capsLock], "T", expect: .translate),
            KeyCase("⌘T（翻译卡打开）", kVK_ANSI_T, .command, "t", cardOpen: true, expect: .translate),
            KeyCase("⌘T（Dvorak 按字符）", kVK_ANSI_K, .command, "t", expect: .translate),
        ])
    func translate(_ key: KeyCase) {
        #expect(key.resolve() == key.expected)
    }

    @Test(
        "⌥↩ 与 ⌥ + 小键盘 Enter 映射为翻译并粘贴",
        arguments: [
            KeyCase("⌥↩", kVK_Return, .option, expect: .translateAndPaste),
            KeyCase("⌥ 小键盘 Enter", kVK_ANSI_KeypadEnter, .option, expect: .translateAndPaste),
            KeyCase("⌥↩（翻译卡打开）", kVK_Return, .option, cardOpen: true, expect: .translateAndPaste),
            KeyCase("⌥↩（大写锁定）", kVK_Return, [.option, .capsLock], expect: .translateAndPaste),
        ])
    func translateAndPaste(_ key: KeyCase) {
        #expect(key.resolve() == key.expected)
    }

    @Test(
        "⌘C / ⌘S 只在翻译卡打开时映射，否则放行给搜索框",
        arguments: [
            KeyCase("⌘C（卡片打开）", kVK_ANSI_C, .command, "c", cardOpen: true, expect: .copyTranslation),
            KeyCase("⌘S（卡片打开）", kVK_ANSI_S, .command, "s", cardOpen: true, expect: .saveTranslation),
            KeyCase("⌘C（卡片关闭）", kVK_ANSI_C, .command, "c", expect: nil),
            KeyCase("⌘S（卡片关闭）", kVK_ANSI_S, .command, "s", expect: nil),
            KeyCase("⇧⌘C（卡片打开）", kVK_ANSI_C, [.command, .shift], "C", cardOpen: true, expect: nil),
            KeyCase("⌥⌘S（卡片打开）", kVK_ANSI_S, [.command, .option], "s", cardOpen: true, expect: nil),
        ])
    func cardOnlyCommands(_ key: KeyCase) {
        #expect(key.resolve() == key.expected)
    }

    @Test(
        "翻译卡打开且搜索框为空时 ← / → 切换视图（⇧ 为大步，卷帘微调用）",
        arguments: [
            KeyCase(
                "←", kVK_LeftArrow, [.numericPad, .function], allowsSpace: true, cardOpen: true,
                expect: .stepTranslationView(-1)),
            KeyCase(
                "→", kVK_RightArrow, [.numericPad, .function], allowsSpace: true, cardOpen: true,
                expect: .stepTranslationView(1)),
            KeyCase(
                "⇧←", kVK_LeftArrow, .shift, allowsSpace: true, cardOpen: true,
                expect: .stepTranslationView(-PanelCommand.largeTranslationStep)),
            KeyCase(
                "⇧→", kVK_RightArrow, .shift, allowsSpace: true, cardOpen: true,
                expect: .stepTranslationView(PanelCommand.largeTranslationStep)),
        ])
    func arrowsSwitchViews(_ key: KeyCase) {
        #expect(key.resolve() == key.expected)
    }

    @Test(
        "← / → 在卡片关闭、搜索框有字或带其他修饰键时放行",
        arguments: [
            KeyCase("←（卡片关闭）", kVK_LeftArrow, allowsSpace: true, expect: nil),
            KeyCase("→（搜索框有字）", kVK_RightArrow, cardOpen: true, expect: nil),
            KeyCase("⌘←（卡片打开）", kVK_LeftArrow, .command, allowsSpace: true, cardOpen: true, expect: nil),
            KeyCase("⌥→（卡片打开）", kVK_RightArrow, .option, allowsSpace: true, cardOpen: true, expect: nil),
        ])
    func arrowsPassThrough(_ key: KeyCase) {
        #expect(key.resolve() == nil)
    }

    @Test(
        "翻译卡打开不改变其他按键：↩ / ⇧↩ / ⌘↩ / 空格 / ⌥↑",
        arguments: [
            KeyCase("↩", kVK_Return, cardOpen: true, expect: .paste),
            KeyCase("⇧↩", kVK_Return, .shift, cardOpen: true, expect: .pasteAlternate),
            KeyCase("⌘↩", kVK_Return, .command, cardOpen: true, expect: .copyOnly),
            KeyCase("空格", kVK_Space, [], " ", allowsSpace: true, cardOpen: true, expect: .togglePreview),
            KeyCase("⌥↑", kVK_UpArrow, .option, cardOpen: true, expect: .moveToFirst),
            KeyCase("⌥↓", kVK_DownArrow, .option, cardOpen: true, expect: .moveToLast),
            KeyCase("⌘P", kVK_ANSI_P, .command, "p", cardOpen: true, expect: .toggleFavorite),
        ])
    func otherKeysUnchanged(_ key: KeyCase) {
        #expect(key.resolve() == key.expected)
    }

    @Test("⌥⇧↩ 与 ⌃⌘T 仍不映射")
    func unmappedCombinations() {
        #expect(PanelCommand.from(keyCode: UInt16(kVK_Return), modifiers: [.option, .shift], characters: nil) == nil)
        #expect(
            PanelCommand.from(keyCode: UInt16(kVK_ANSI_T), modifiers: [.command, .control], characters: "t") == nil)
        #expect(PanelCommand.from(keyCode: UInt16(kVK_ANSI_T), modifiers: .option, characters: "t") == nil)
    }

    @Test("翻译指令不是选择移动")
    func translationCommandsDoNotMoveSelection() {
        let commands: [PanelCommand] = [
            .translate, .translateAndPaste, .copyTranslation, .saveTranslation, .stepTranslationView(1),
        ]
        for command in commands {
            #expect(command.selectionIndex(from: 2, count: 5) == nil)
        }
    }
}
