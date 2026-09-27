import AppKit
import Carbon.HIToolbox
import Testing
@testable import CubbyCore

/// 一次按键输入及其期望的面板指令
struct KeyCase: Sendable, CustomTestStringConvertible {
    let label: String
    let keyCode: Int
    let modifiers: NSEvent.ModifierFlags
    let characters: String?
    let allowsSpace: Bool
    let translationCardOpen: Bool
    let expected: PanelCommand?

    init(
        _ label: String,
        _ keyCode: Int,
        _ modifiers: NSEvent.ModifierFlags = [],
        _ characters: String? = nil,
        allowsSpace: Bool = false,
        cardOpen translationCardOpen: Bool = false,
        expect expected: PanelCommand?
    ) {
        self.label = label
        self.keyCode = keyCode
        self.modifiers = modifiers
        self.characters = characters
        self.allowsSpace = allowsSpace
        self.translationCardOpen = translationCardOpen
        self.expected = expected
    }

    var testDescription: String { label }

    func resolve() -> PanelCommand? {
        PanelCommand.from(
            keyCode: UInt16(keyCode),
            modifiers: modifiers,
            characters: characters,
            allowsSpace: allowsSpace,
            translationCardOpen: translationCardOpen
        )
    }
}

@Suite("PanelCommand 键盘指令映射")
struct PanelCommandTests {
    @Test(
        "无修饰键的基础按键",
        arguments: [
            KeyCase("↑", kVK_UpArrow, expect: .moveUp),
            KeyCase("↓", kVK_DownArrow, expect: .moveDown),
            KeyCase("↩", kVK_Return, expect: .paste),
            KeyCase("小键盘 Enter", kVK_ANSI_KeypadEnter, expect: .paste),
            KeyCase("Esc", kVK_Escape, expect: .escape),
            KeyCase("Tab", kVK_Tab, expect: .nextCategory),
        ])
    func basicKeys(_ key: KeyCase) {
        #expect(key.resolve() == key.expected)
    }

    @Test("方向键事件自带的 numericPad/function 标志不影响识别")
    func arrowKeysWithDeviceFlags() {
        let flags: NSEvent.ModifierFlags = [.numericPad, .function]
        #expect(PanelCommand.from(keyCode: UInt16(kVK_UpArrow), modifiers: flags, characters: nil) == .moveUp)
        #expect(PanelCommand.from(keyCode: UInt16(kVK_DownArrow), modifiers: flags, characters: nil) == .moveDown)
    }

    @Test(
        "带修饰键的组合",
        arguments: [
            KeyCase("⇧Tab", kVK_Tab, .shift, expect: .previousCategory),
            KeyCase("⌘⌫", kVK_Delete, .command, expect: .delete),
            KeyCase("⌘⌦", kVK_ForwardDelete, .command, expect: .delete),
            KeyCase("⌘P", kVK_ANSI_P, .command, "p", expect: .toggleFavorite),
            KeyCase("⌘P（大写锁定）", kVK_ANSI_P, [.command, .capsLock], "P", expect: .toggleFavorite),
            KeyCase("⌘,", kVK_ANSI_Comma, .command, ",", expect: .openSettings),
            KeyCase("⌃N", kVK_ANSI_N, .control, "n", expect: .moveDown),
            KeyCase("⌃P", kVK_ANSI_P, .control, "p", expect: .moveUp),
        ])
    func modifiedKeys(_ key: KeyCase) {
        #expect(key.resolve() == key.expected)
    }

    @Test(
        "⌘1…⌘9 映射为 pasteAt(0…8)",
        arguments: zip(
            [
                kVK_ANSI_1, kVK_ANSI_2, kVK_ANSI_3, kVK_ANSI_4, kVK_ANSI_5, kVK_ANSI_6, kVK_ANSI_7, kVK_ANSI_8,
                kVK_ANSI_9,
            ],
            0...8
        ))
    func commandDigits(_ keyCode: Int, _ index: Int) {
        #expect(
            PanelCommand.from(keyCode: UInt16(keyCode), modifiers: .command, characters: "\(index + 1)")
                == .pasteAt(index))
    }

    @Test("数字快捷键按键位匹配，兼容 AZERTY 等布局")
    func digitsMatchByKeyCode() {
        #expect(PanelCommand.from(keyCode: UInt16(kVK_ANSI_1), modifiers: .command, characters: "&") == .pasteAt(0))
    }

    @Test("字母快捷键按字符匹配，兼容 Dvorak 等布局")
    func lettersMatchByCharacter() {
        // Dvorak 下 P 字符位于 QWERTY 的 R 键位
        #expect(PanelCommand.from(keyCode: UInt16(kVK_ANSI_R), modifiers: .command, characters: "p") == .toggleFavorite)
    }

    @Test(
        "带多余修饰键或无法识别时返回 nil",
        arguments: [
            KeyCase("⌘↓", kVK_DownArrow, .command, expect: nil),
            KeyCase("⌘↑", kVK_UpArrow, .command, expect: nil),
            KeyCase("⌥⇧↓", kVK_DownArrow, [.option, .shift], expect: nil),
            KeyCase("⇧Home", kVK_Home, .shift, expect: nil),
            KeyCase("⌘End", kVK_End, .command, expect: nil),
            KeyCase("⌥PageDown", kVK_PageDown, .option, expect: nil),
            KeyCase("⌥⇧⌘P", kVK_ANSI_P, [.command, .shift, .option], "P", expect: nil),
            KeyCase("⌃↩", kVK_Return, .control, expect: nil),
            KeyCase("⇧⌘↩", kVK_Return, [.command, .shift], expect: nil),
            KeyCase("⌥⇧↩", kVK_Return, [.option, .shift], expect: nil),
            KeyCase("⇧⌘Z（重做未支持）", kVK_ANSI_Z, [.command, .shift], "Z", expect: nil),
            KeyCase("Z（无修饰）", kVK_ANSI_Z, [], "z", expect: nil),
            KeyCase("⌥⌘O", kVK_ANSI_O, [.command, .option], "o", expect: nil),
            KeyCase("⌃Y", kVK_ANSI_Y, .control, "y", expect: nil),
            KeyCase("空格（默认不作为预览）", kVK_Space, [], " ", expect: nil),
            KeyCase("⌃Tab", kVK_Tab, .control, expect: nil),
            KeyCase("⌘⇧Tab", kVK_Tab, [.command, .shift], expect: nil),
            KeyCase("⌫（无修饰）", kVK_Delete, expect: nil),
            KeyCase("⌥⌘⌫", kVK_Delete, [.command, .option], expect: nil),
            KeyCase("⌥⌘1", kVK_ANSI_1, [.command, .option], "1", expect: nil),
            KeyCase("⇧⌘1", kVK_ANSI_1, [.command, .shift], "!", expect: nil),
            KeyCase("1（无修饰）", kVK_ANSI_1, [], "1", expect: nil),
            KeyCase("⌘0", kVK_ANSI_0, .command, "0", expect: nil),
            KeyCase("⌃⌘P", kVK_ANSI_P, [.command, .control], "p", expect: nil),
            KeyCase("P（无修饰）", kVK_ANSI_P, [], "p", expect: nil),
            KeyCase("⌘N", kVK_ANSI_N, .command, "n", expect: nil),
            KeyCase("⌃⇧N", kVK_ANSI_N, [.control, .shift], "N", expect: nil),
            KeyCase("⌘A", kVK_ANSI_A, .command, "a", expect: nil),
            KeyCase("⌘ 无字符", kVK_ANSI_P, .command, nil, expect: nil),
        ])
    func unrecognized(_ key: KeyCase) {
        #expect(key.resolve() == nil)
    }

    // MARK: - 新指令

    @Test(
        "回车组合：↩ 粘贴、⇧↩ 另一种格式、⌘↩ 仅复制",
        arguments: [
            KeyCase("↩", kVK_Return, expect: .paste),
            KeyCase("⇧↩", kVK_Return, .shift, expect: .pasteAlternate),
            KeyCase("⌘↩", kVK_Return, .command, expect: .copyOnly),
            KeyCase("⇧ 小键盘 Enter", kVK_ANSI_KeypadEnter, .shift, expect: .pasteAlternate),
            KeyCase("⌘ 小键盘 Enter", kVK_ANSI_KeypadEnter, .command, expect: .copyOnly),
            KeyCase("⇧↩（大写锁定）", kVK_Return, [.shift, .capsLock], expect: .pasteAlternate),
        ])
    func returnVariants(_ key: KeyCase) {
        #expect(key.resolve() == key.expected)
    }

    @Test(
        "字母指令：⌘Z 撤销、⌘O 打开、⌘Y 预览",
        arguments: [
            KeyCase("⌘Z", kVK_ANSI_Z, .command, "z", expect: .undo),
            KeyCase("⌘Z（大写锁定）", kVK_ANSI_Z, [.command, .capsLock], "Z", expect: .undo),
            KeyCase("⌘O", kVK_ANSI_O, .command, "o", expect: .open),
            KeyCase("⌘Y", kVK_ANSI_Y, .command, "y", expect: .togglePreview),
            KeyCase("⌘Y 在允许空格时同样有效", kVK_ANSI_Y, .command, "y", allowsSpace: true, expect: .togglePreview),
        ])
    func letterCommands(_ key: KeyCase) {
        #expect(key.resolve() == key.expected)
    }

    @Test(
        "空格仅在 allowsSpace 且无修饰键时切换预览",
        arguments: [
            KeyCase("空格 + allowsSpace", kVK_Space, [], " ", allowsSpace: true, expect: .togglePreview),
            KeyCase("空格 + allowsSpace（字符为 nil）", kVK_Space, [], nil, allowsSpace: true, expect: .togglePreview),
            KeyCase("空格 + allowsSpace（大写锁定）", kVK_Space, .capsLock, " ", allowsSpace: true, expect: .togglePreview),
            KeyCase("⇧空格 + allowsSpace", kVK_Space, .shift, " ", allowsSpace: true, expect: nil),
            KeyCase("⌘空格 + allowsSpace", kVK_Space, .command, " ", allowsSpace: true, expect: nil),
            KeyCase("⌃空格 + allowsSpace", kVK_Space, .control, " ", allowsSpace: true, expect: nil),
            KeyCase("空格（allowsSpace 为 false）", kVK_Space, [], " ", allowsSpace: false, expect: nil),
        ])
    func spaceTogglesPreview(_ key: KeyCase) {
        #expect(key.resolve() == key.expected)
    }

    @Test(
        "allowsSpace 不影响其他按键",
        arguments: [
            KeyCase("↩", kVK_Return, allowsSpace: true, expect: .paste),
            KeyCase("↓", kVK_DownArrow, allowsSpace: true, expect: .moveDown),
            KeyCase("Esc", kVK_Escape, allowsSpace: true, expect: .escape),
            KeyCase("⌘1", kVK_ANSI_1, .command, "1", allowsSpace: true, expect: .pasteAt(0)),
            KeyCase("字母 a", kVK_ANSI_A, [], "a", allowsSpace: true, expect: nil),
        ])
    func allowsSpaceDoesNotAffectOthers(_ key: KeyCase) {
        #expect(key.resolve() == key.expected)
    }

    @Test(
        "Esc 带任意修饰键仍为 escape",
        arguments: [
            NSEvent.ModifierFlags.command, .shift, .option, .control, [.command, .shift],
        ])
    func escapeIgnoresModifiers(_ flags: NSEvent.ModifierFlags) {
        #expect(PanelCommand.from(keyCode: UInt16(kVK_Escape), modifiers: flags, characters: nil) == .escape)
    }
}
