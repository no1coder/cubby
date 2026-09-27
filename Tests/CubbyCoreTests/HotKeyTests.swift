import AppKit
import Carbon.HIToolbox
import Foundation
import Testing
@testable import CubbyCore

/// 从按键事件构造 HotKey 的输入与期望
struct HotKeyEventCase: Sendable, CustomTestStringConvertible {
    let label: String
    let keyCode: Int
    let flags: NSEvent.ModifierFlags
    let characters: String?
    /// 期望的 (Carbon 修饰键, 按键显示名)；nil 表示应拒绝
    let expected: (modifiers: Int, keyLabel: String)?

    init(
        _ label: String,
        _ keyCode: Int,
        _ flags: NSEvent.ModifierFlags,
        _ characters: String?,
        expect expected: (modifiers: Int, keyLabel: String)?
    ) {
        self.label = label
        self.keyCode = keyCode
        self.flags = flags
        self.characters = characters
        self.expected = expected
    }

    var testDescription: String { label }

    func make() -> HotKey? {
        HotKey(keyCode: UInt16(keyCode), modifierFlags: flags, characters: characters)
    }
}

@Suite("HotKey 全局快捷键")
struct HotKeyTests {
    @Test("默认快捷键为 ⇧⌘V")
    func defaultHotKey() {
        let hotKey = HotKey.default
        #expect(hotKey.keyCode == UInt32(kVK_ANSI_V))
        #expect(hotKey.modifiers == UInt32(cmdKey | shiftKey))
        #expect(hotKey.keyLabel == "V")
        #expect(hotKey.displayName == "⇧⌘V")
        #expect(hotKey.keySymbols == ["⇧", "⌘", "V"])
    }

    @Test(
        "从事件构造：接受的组合",
        arguments: [
            HotKeyEventCase("⇧⌘V", kVK_ANSI_V, [.command, .shift], "v", expect: (cmdKey | shiftKey, "V")),
            HotKeyEventCase("⌥K（仅 ⌥）", kVK_ANSI_K, .option, "k", expect: (optionKey, "K")),
            HotKeyEventCase("⌃J（仅 ⌃）", kVK_ANSI_J, .control, "j", expect: (controlKey, "J")),
            HotKeyEventCase("⌘ 非 ASCII 字符大写", kVK_ANSI_E, .command, "é", expect: (cmdKey, "É")),
            HotKeyEventCase("⌘ 字符前后空白被去除", kVK_ANSI_B, .command, " b ", expect: (cmdKey, "B")),
            HotKeyEventCase("⌘Space 使用专用名称", kVK_Space, .command, " ", expect: (cmdKey, "Space")),
            HotKeyEventCase("⌥↩", kVK_Return, .option, "\r", expect: (optionKey, "↩")),
            HotKeyEventCase("⌃⇥", kVK_Tab, .control, "\t", expect: (controlKey, "⇥")),
            HotKeyEventCase("⌘⌫", kVK_Delete, .command, nil, expect: (cmdKey, "⌫")),
            HotKeyEventCase(
                "⌘↑（带 numericPad/function 标志）", kVK_UpArrow, [.command, .numericPad, .function], nil,
                expect: (cmdKey, "↑")),
            HotKeyEventCase("F5 无修饰键（带 function 标志）", kVK_F5, .function, nil, expect: (0, "F5")),
            HotKeyEventCase("F1 无修饰键", kVK_F1, [], nil, expect: (0, "F1")),
            HotKeyEventCase("F12 无修饰键", kVK_F12, [], nil, expect: (0, "F12")),
            HotKeyEventCase("⇧F3（功能键只带 ⇧）", kVK_F3, .shift, nil, expect: (shiftKey, "F3")),
            HotKeyEventCase("⌘F2 忽略事件字符", kVK_F2, .command, "\u{F705}", expect: (cmdKey, "F2")),
            HotKeyEventCase("大写锁定不计入修饰键", kVK_ANSI_V, [.command, .capsLock], "V", expect: (cmdKey, "V")),
            HotKeyEventCase(
                "四个修饰键", kVK_ANSI_K, [.command, .option, .control, .shift], "k",
                expect: (cmdKey | optionKey | controlKey | shiftKey, "K")),
        ])
    func acceptedEvents(_ event: HotKeyEventCase) throws {
        let expected = try #require(event.expected)
        let hotKey = try #require(event.make())
        #expect(hotKey.keyCode == UInt32(event.keyCode))
        #expect(hotKey.modifiers == UInt32(expected.modifiers))
        #expect(hotKey.keyLabel == expected.keyLabel)
    }

    @Test(
        "从事件构造：拒绝的组合",
        arguments: [
            HotKeyEventCase("Esc", kVK_Escape, [], nil, expect: nil),
            HotKeyEventCase("⌘Esc（Esc 保留用于取消录制）", kVK_Escape, .command, "\u{1B}", expect: nil),
            HotKeyEventCase("无修饰键字母", kVK_ANSI_V, [], "v", expect: nil),
            HotKeyEventCase("仅 ⇧ 的字母", kVK_ANSI_V, .shift, "V", expect: nil),
            HotKeyEventCase("仅大写锁定", kVK_ANSI_V, .capsLock, "V", expect: nil),
            HotKeyEventCase("仅 function 标志的方向键", kVK_UpArrow, [.function, .numericPad], nil, expect: nil),
            HotKeyEventCase("F13 不属于允许无修饰的功能键", kVK_F13, [], nil, expect: nil),
            HotKeyEventCase("⌘ 普通键但字符为 nil", kVK_ANSI_V, .command, nil, expect: nil),
            HotKeyEventCase("⌘ 普通键但字符为空", kVK_ANSI_V, .command, "", expect: nil),
            HotKeyEventCase("⌘ 普通键但字符全为空白", kVK_ANSI_V, .command, " \n", expect: nil),
        ])
    func rejectedEvents(_ event: HotKeyEventCase) {
        #expect(event.make() == nil)
    }

    @Test(
        "carbonModifiers 逐个映射修饰键",
        arguments: [
            (NSEvent.ModifierFlags.command, cmdKey),
            (.shift, shiftKey),
            (.option, optionKey),
            (.control, controlKey),
        ])
    func carbonModifierMapping(_ flag: NSEvent.ModifierFlags, _ carbon: Int) {
        #expect(HotKey.carbonModifiers(from: flag) == UInt32(carbon))
    }

    @Test("carbonModifiers 组合与无关标志")
    func carbonModifierCombinations() {
        #expect(HotKey.carbonModifiers(from: []) == 0)
        #expect(HotKey.carbonModifiers(from: [.capsLock, .function, .numericPad, .help]) == 0)
        #expect(HotKey.carbonModifiers(from: [.command, .shift, .capsLock]) == UInt32(cmdKey | shiftKey))
    }

    @Test("显示顺序固定为 ⌃⌥⇧⌘，与构造顺序无关")
    func displayOrder() {
        let all = HotKey(
            keyCode: UInt32(kVK_ANSI_K), modifiers: UInt32(shiftKey | cmdKey | controlKey | optionKey), keyLabel: "K")
        #expect(all.keySymbols == ["⌃", "⌥", "⇧", "⌘", "K"])
        #expect(all.displayName == "⌃⌥⇧⌘K")

        let bare = HotKey(keyCode: UInt32(kVK_F6), modifiers: 0, keyLabel: "F6")
        #expect(bare.keySymbols == ["F6"])
        #expect(bare.displayName == "F6")
    }

    @Test("JSON 往返后相等")
    func codableRoundTrip() throws {
        let original = HotKey(keyCode: UInt32(kVK_Space), modifiers: UInt32(optionKey), keyLabel: "Space")
        let decoded = try JSONDecoder().decode(HotKey.self, from: JSONEncoder().encode(original))
        #expect(decoded == original)
    }

    @Test("字段不同即不相等")
    func equality() {
        let base = HotKey.default
        #expect(base != HotKey(keyCode: base.keyCode, modifiers: UInt32(cmdKey), keyLabel: base.keyLabel))
        #expect(base != HotKey(keyCode: UInt32(kVK_ANSI_C), modifiers: base.modifiers, keyLabel: base.keyLabel))
        #expect(base == HotKey(keyCode: base.keyCode, modifiers: base.modifiers, keyLabel: base.keyLabel))
    }
}

@Suite("PanelPosition / PasteFormat 设置选项")
struct SettingsOptionTests {
    @Test("PanelPosition 选项与显示名")
    func panelPositions() {
        #expect(PanelPosition.allCases == [.mouse, .statusItem, .center])
        #expect(Set(PanelPosition.allCases.map(\.displayName)).count == 3)
        #expect(PanelPosition(rawValue: "statusItem") == .statusItem)
    }

    @Test("PasteFormat 的 alternate 互为对方，两次后复原", arguments: PasteFormat.allCases)
    func pasteFormatAlternate(_ format: PasteFormat) {
        #expect(format.alternate != format)
        #expect(format.alternate.alternate == format)
    }

    @Test("PasteFormat 显示名")
    func pasteFormatNames() {
        #expect(PasteFormat.original.alternate == .plainText)
        // 测试环境没有编译后的 String Catalog，本地化回落到英文键
        #expect(PasteFormat.original.displayName == "Original formatting")
        #expect(PasteFormat.plainText.displayName == "Plain text")
    }
}
