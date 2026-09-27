import AppKit
import Carbon.HIToolbox
import Testing
@testable import CubbyCore

/// 一次按键在各阶段的期望命令
struct ScreenshotKeyCase: Sendable, CustomTestStringConvertible {
    let label: String
    let keyCode: Int
    let modifiers: NSEvent.ModifierFlags
    let characters: String?
    let expected: [ScreenshotPhase: ScreenshotCommand]

    init(
        _ label: String,
        _ keyCode: Int,
        _ modifiers: NSEvent.ModifierFlags = [],
        _ characters: String? = nil,
        _ expected: [ScreenshotPhase: ScreenshotCommand]
    ) {
        self.label = label
        self.keyCode = keyCode
        self.modifiers = modifiers
        self.characters = characters
        self.expected = expected
    }

    var testDescription: String { label }
}

@Suite("ScreenshotCommand 键盘映射（按阶段）")
struct ScreenshotCommandTests {
    private static let phases: [ScreenshotPhase] = [.hovering, .selecting, .adjusting, .annotating, .editingText]

    /// 有选区的两个阶段都映射为同一命令
    private static func withSelection(_ command: ScreenshotCommand) -> [ScreenshotPhase: ScreenshotCommand] {
        [.adjusting: command, .annotating: command]
    }

    @Test(
        "§2.11 真值表：每个按键 × 每个阶段",
        arguments: [
            ScreenshotKeyCase(
                "Esc", kVK_Escape, [], nil,
                [
                    .hovering: .escape, .selecting: .escape, .adjusting: .escape, .annotating: .escape,
                    .editingText: .escape,
                ]),
            ScreenshotKeyCase(
                "↩", kVK_Return, [], "\r", [.hovering: .confirm, .adjusting: .confirm, .annotating: .confirm]),
            ScreenshotKeyCase(
                "小键盘 Enter", kVK_ANSI_KeypadEnter, [], nil,
                [.hovering: .confirm, .adjusting: .confirm, .annotating: .confirm]),
            ScreenshotKeyCase(
                "⌘↩", kVK_Return, .command, "\r",
                [.adjusting: .confirm, .annotating: .confirm, .editingText: .commitText]),
            ScreenshotKeyCase("⇧↩", kVK_Return, .shift, "\r", [:]),
            ScreenshotKeyCase(
                "⌘C", kVK_ANSI_C, .command, "c", [.hovering: .confirm, .adjusting: .confirm, .annotating: .confirm]),
            ScreenshotKeyCase("⌘S", kVK_ANSI_S, .command, "s", withSelection(.save)),
            ScreenshotKeyCase("⌘P", kVK_ANSI_P, .command, "p", withSelection(.pin)),
            ScreenshotKeyCase("⌘T", kVK_ANSI_T, .command, "t", withSelection(.extractText)),
            ScreenshotKeyCase(
                "⌘A", kVK_ANSI_A, .command, "a",
                [.hovering: .selectAll, .adjusting: .selectAll, .annotating: .selectAll]),
            ScreenshotKeyCase("⌘Z", kVK_ANSI_Z, .command, "z", withSelection(.undo)),
            ScreenshotKeyCase("⇧⌘Z", kVK_ANSI_Z, [.command, .shift], "Z", withSelection(.redo)),
            ScreenshotKeyCase(
                "⇧⌘T 翻译（编辑文字时先提交再翻译）", kVK_ANSI_T, [.command, .shift], "T",
                [.adjusting: .translate, .annotating: .translate, .editingText: .translate]),
            ScreenshotKeyCase(
                "C 取色", kVK_ANSI_C, [], "c", [.hovering: .copyColor, .selecting: .copyColor, .adjusting: .copyColor]),
            ScreenshotKeyCase(
                "⇧C 取色（RGB）", kVK_ANSI_C, .shift, "C",
                [.hovering: .copyColor, .selecting: .copyColor, .adjusting: .copyColor]),
            ScreenshotKeyCase("1 选红", kVK_ANSI_1, [], "1", withSelection(.selectColor(.red))),
            ScreenshotKeyCase("8 选白", kVK_ANSI_8, [], "8", withSelection(.selectColor(.white))),
            ScreenshotKeyCase("小键盘 5 选蓝", kVK_ANSI_Keypad5, .numericPad, "5", withSelection(.selectColor(.blue))),
            ScreenshotKeyCase("法语键位 3（字符为 \u{22}）按键位", kVK_ANSI_3, [], "\u{22}", withSelection(.selectColor(.yellow))),
            ScreenshotKeyCase("9 无操作", kVK_ANSI_9, [], "9", [:]),
            ScreenshotKeyCase("⌘1 无操作", kVK_ANSI_1, .command, "1", [:]),
            ScreenshotKeyCase("[ 减细", kVK_ANSI_LeftBracket, [], "[", withSelection(.adjustWeight(heavier: false))),
            ScreenshotKeyCase("] 加粗", kVK_ANSI_RightBracket, [], "]", withSelection(.adjustWeight(heavier: true))),
            ScreenshotKeyCase(
                "Dvorak 的 [（键位是 ANSI -）按字符", kVK_ANSI_Minus, [], "[", withSelection(.adjustWeight(heavier: false))),
            ScreenshotKeyCase("Dvorak 的 /（键位是 ANSI [）不调粗细", kVK_ANSI_LeftBracket, [], "/", [:]),
            ScreenshotKeyCase(
                "德语键位 ü（键位是 ANSI [）退回键位", kVK_ANSI_LeftBracket, [], "\u{FC}",
                withSelection(.adjustWeight(heavier: false))),
            ScreenshotKeyCase("V", kVK_ANSI_V, [], "v", [.annotating: .selectTool(.pointer)]),
            ScreenshotKeyCase("R", kVK_ANSI_R, [], "r", withSelection(.selectTool(.rectangle))),
            ScreenshotKeyCase("O", kVK_ANSI_O, [], "o", withSelection(.selectTool(.ellipse))),
            ScreenshotKeyCase("A", kVK_ANSI_A, [], "a", withSelection(.selectTool(.arrow))),
            ScreenshotKeyCase("P", kVK_ANSI_P, [], "p", withSelection(.selectTool(.pen))),
            ScreenshotKeyCase("H", kVK_ANSI_H, [], "h", withSelection(.selectTool(.highlighter))),
            ScreenshotKeyCase("M", kVK_ANSI_M, [], "m", withSelection(.selectTool(.mosaic))),
            ScreenshotKeyCase("T", kVK_ANSI_T, [], "t", withSelection(.selectTool(.text))),
            ScreenshotKeyCase("N", kVK_ANSI_N, [], "n", withSelection(.selectTool(.number))),
            ScreenshotKeyCase("↑", kVK_UpArrow, [], nil, withSelection(.nudge(.up, large: false))),
            ScreenshotKeyCase("↓", kVK_DownArrow, [], nil, withSelection(.nudge(.down, large: false))),
            ScreenshotKeyCase("←", kVK_LeftArrow, [], nil, withSelection(.nudge(.left, large: false))),
            ScreenshotKeyCase("→", kVK_RightArrow, [], nil, withSelection(.nudge(.right, large: false))),
            ScreenshotKeyCase("⇧↑", kVK_UpArrow, .shift, nil, withSelection(.nudge(.up, large: true))),
            ScreenshotKeyCase("⇧→", kVK_RightArrow, .shift, nil, withSelection(.nudge(.right, large: true))),
            ScreenshotKeyCase("⌫", kVK_Delete, [], nil, withSelection(.deleteAnnotation)),
            ScreenshotKeyCase("⌦", kVK_ForwardDelete, [], nil, withSelection(.deleteAnnotation)),
            ScreenshotKeyCase("Tab", kVK_Tab, [], "\t", [.hovering: .cycleHover(forward: true)]),
            ScreenshotKeyCase("⇧Tab", kVK_Tab, .shift, "\t", [.hovering: .cycleHover(forward: false)]),
            ScreenshotKeyCase("空格不是命令", kVK_Space, [], " ", [:]),
            ScreenshotKeyCase("⌥R 无命令", kVK_ANSI_R, .option, "®", [:]),
            ScreenshotKeyCase("⌃C 无命令", kVK_ANSI_C, .control, "c", [:]),
            ScreenshotKeyCase("⌘X 无命令", kVK_ANSI_X, .command, "x", [:]),
            ScreenshotKeyCase("无字符的普通键", kVK_ANSI_Q, [], nil, [:]),
        ])
    func truthTable(_ key: ScreenshotKeyCase) {
        for phase in Self.phases {
            let command = ScreenshotCommand.from(
                keyCode: UInt16(key.keyCode), modifiers: key.modifiers, characters: key.characters, phase: phase)
            #expect(command == key.expected[phase], "\(key.label) @ \(phase)")
        }
    }

    @Test("字母按字符匹配（Dvorak：物理 J 键产生 c）")
    func matchesCharactersNotKeyCodes() {
        let dvorakC = ScreenshotCommand.from(
            keyCode: UInt16(kVK_ANSI_J), modifiers: [], characters: "c", phase: .hovering)
        #expect(dvorakC == .copyColor)
        let dvorakSave = ScreenshotCommand.from(
            keyCode: UInt16(kVK_ANSI_Semicolon), modifiers: .command, characters: "s", phase: .adjusting)
        #expect(dvorakSave == .save)
    }

    @Test("大写锁定下字母键仍识别")
    func capsLock() {
        let command = ScreenshotCommand.from(
            keyCode: UInt16(kVK_ANSI_R), modifiers: .capsLock, characters: "R", phase: .adjusting)
        #expect(command == .selectTool(.rectangle))
    }

    @Test("方向键自带的 numericPad / function 标志不影响识别")
    func arrowDeviceFlags() {
        let command = ScreenshotCommand.from(
            keyCode: UInt16(kVK_UpArrow), modifiers: [.numericPad, .function], characters: nil, phase: .annotating)
        #expect(command == .nudge(.up, large: false))
    }

    @Test("editingText 只识别 Esc、⌘↩ 与 ⇧⌘T，其余全部交给文本框")
    func editingTextOnlyTwoKeys() {
        let keys: [(Int, NSEvent.ModifierFlags, String?)] = [
            (kVK_Return, [], "\r"), (kVK_ANSI_C, .command, "c"), (kVK_ANSI_Z, .command, "z"),
            (kVK_ANSI_R, [], "r"), (kVK_Delete, [], nil), (kVK_LeftArrow, [], nil), (kVK_Tab, [], "\t"),
        ]
        for (code, flags, characters) in keys {
            let command = ScreenshotCommand.from(
                keyCode: UInt16(code), modifiers: flags, characters: characters, phase: .editingText)
            #expect(command == nil)
        }
    }
}
