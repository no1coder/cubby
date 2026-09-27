import AppKit
import Carbon.HIToolbox
import Testing
@testable import CubbyCore

@Suite("ScreenshotKeyboard 覆盖层按键解释")
struct ScreenshotKeyboardTests {
    private func key(
        _ code: Int,
        _ characters: String,
        _ flags: NSEvent.ModifierFlags = [],
        repeat isRepeat: Bool = false,
        ownWindow: Bool = true
    ) -> ScreenshotKeyInput {
        ScreenshotKeyInput(
            keyCode: UInt16(code),
            modifiers: flags,
            characters: characters,
            charactersIgnoringModifiers: characters.lowercased(),
            isRepeat: isRepeat,
            isOverlayWindow: ownWindow
        )
    }

    @Test("空格按下 / 松开上报为修饰键；自动重复只吞掉不上报")
    func spaceAsModifier() {
        var keyboard = ScreenshotKeyboard()
        let down = keyboard.keyDown(key(kVK_Space, " "), phase: .hovering, isComposingText: false)
        #expect(down == ScreenshotKeyDecision(consumed: true, outputs: [.event(.modifiersChanged(.space))]))
        let repeated = keyboard.keyDown(key(kVK_Space, " ", repeat: true), phase: .hovering, isComposingText: false)
        #expect(repeated == ScreenshotKeyDecision(consumed: true, outputs: []))
        let up = keyboard.keyUp(keyCode: UInt16(kVK_Space), phase: .hovering)
        #expect(up == ScreenshotKeyDecision(consumed: true, outputs: [.event(.modifiersChanged([]))]))
        #expect(!keyboard.isSpaceDown)
    }

    @Test("编辑文字时空格交给文本视图，不当修饰键")
    func spaceWhileEditing() {
        var keyboard = ScreenshotKeyboard()
        let decision = keyboard.keyDown(key(kVK_Space, " "), phase: .editingText, isComposingText: false)
        #expect(decision == ScreenshotKeyDecision(consumed: false, outputs: []))
        #expect(!keyboard.isSpaceDown)
    }

    @Test("修饰键变化随空格状态一起上报，不吞掉")
    func flagsChanged() {
        var keyboard = ScreenshotKeyboard()
        _ = keyboard.keyDown(key(kVK_Space, " "), phase: .selecting, isComposingText: false)
        let decision = keyboard.flagsChanged([.shift], phase: .selecting)
        #expect(
            decision == ScreenshotKeyDecision(consumed: false, outputs: [.event(.modifiersChanged([.shift, .space]))]))
    }

    @Test("组字中按键全部交给输入法，但 ⌘Q 之类仍被吞掉")
    func composingText() {
        var keyboard = ScreenshotKeyboard()
        let escape = keyboard.keyDown(key(kVK_Escape, "\u{1B}"), phase: .editingText, isComposingText: true)
        #expect(escape == ScreenshotKeyDecision(consumed: false, outputs: []))
        let quit = keyboard.keyDown(key(kVK_ANSI_Q, "q", .command), phase: .editingText, isComposingText: true)
        #expect(quit == ScreenshotKeyDecision(consumed: true, outputs: []))
        let copy = keyboard.keyDown(key(kVK_ANSI_C, "c", .command), phase: .editingText, isComposingText: true)
        #expect(copy == ScreenshotKeyDecision(consumed: false, outputs: []))
    }

    @Test("编辑文字：Esc 提交；普通字符交给文本视图")
    func editingKeys() {
        var keyboard = ScreenshotKeyboard()
        let escape = keyboard.keyDown(key(kVK_Escape, "\u{1B}"), phase: .editingText, isComposingText: false)
        #expect(escape == ScreenshotKeyDecision(consumed: true, outputs: [.event(.command(.escape))]))
        let letter = keyboard.keyDown(key(kVK_ANSI_R, "r"), phase: .editingText, isComposingText: false)
        #expect(letter == ScreenshotKeyDecision(consumed: false, outputs: []))
        let digit = keyboard.keyDown(key(kVK_ANSI_1, "1"), phase: .editingText, isComposingText: false)
        #expect(digit == ScreenshotKeyDecision(consumed: false, outputs: []))
    }

    @Test("非编辑阶段吞掉所有按键；映射到命令的发出命令")
    func commandKeys() {
        var keyboard = ScreenshotKeyboard()
        let tool = keyboard.keyDown(key(kVK_ANSI_R, "r"), phase: .adjusting, isComposingText: false)
        #expect(tool == ScreenshotKeyDecision(consumed: true, outputs: [.event(.command(.selectTool(.rectangle)))]))
        let unmapped = keyboard.keyDown(key(kVK_ANSI_Q, "q", .command), phase: .adjusting, isComposingText: false)
        #expect(unmapped == ScreenshotKeyDecision(consumed: true, outputs: []))
        let color = keyboard.keyDown(key(kVK_ANSI_C, "c"), phase: .hovering, isComposingText: false)
        #expect(color == ScreenshotKeyDecision(consumed: true, outputs: [.copyColor]))
    }

    @Test("⌘ 组合按 characters 匹配（非拉丁布局下系统给出拉丁字母）")
    func commandUsesCharacters() {
        var keyboard = ScreenshotKeyboard()
        let input = ScreenshotKeyInput(
            keyCode: UInt16(kVK_ANSI_Z), modifiers: .command, characters: "z",
            charactersIgnoringModifiers: "\u{044F}", isRepeat: false, isOverlayWindow: true)
        let decision = keyboard.keyDown(input, phase: .adjusting, isComposingText: false)
        #expect(decision.outputs == [.event(.command(.undo))])
    }

    @Test("其他窗口的按下不处理；空格与修饰键的松开仍同步")
    func otherWindows() {
        var keyboard = ScreenshotKeyboard()
        let foreign = keyboard.keyDown(
            key(kVK_ANSI_R, "r", ownWindow: false), phase: .adjusting, isComposingText: false)
        #expect(foreign == ScreenshotKeyDecision(consumed: false, outputs: []))
        _ = keyboard.keyDown(key(kVK_Space, " "), phase: .selecting, isComposingText: false)
        let up = keyboard.keyUp(keyCode: UInt16(kVK_Space), phase: .selecting)
        #expect(up.outputs == [.event(.modifiersChanged([]))])
    }

    @Test("重新同步：以系统修饰键为准、空格视为松开；无变化不上报")
    func resynchronize() {
        var keyboard = ScreenshotKeyboard()
        #expect(keyboard.resynchronize(flags: [], phase: .adjusting).outputs.isEmpty)
        _ = keyboard.keyDown(key(kVK_Space, " "), phase: .adjusting, isComposingText: false)
        _ = keyboard.flagsChanged([.shift], phase: .adjusting)
        let synced = keyboard.resynchronize(flags: [], phase: .adjusting)
        #expect(synced.outputs == [.event(.modifiersChanged([]))])
        #expect(!keyboard.isSpaceDown)
    }

    @Test("数字键与方括号：有选区时改颜色 / 粗细")
    func styleKeys() {
        var keyboard = ScreenshotKeyboard()
        let digit = keyboard.keyDown(key(kVK_ANSI_3, "3"), phase: .annotating, isComposingText: false)
        #expect(digit.outputs == [.event(.command(.selectColor(.yellow)))])
        let bracket = keyboard.keyDown(key(kVK_ANSI_RightBracket, "]"), phase: .annotating, isComposingText: false)
        #expect(bracket.outputs == [.event(.command(.adjustWeight(heavier: true)))])
    }
}
