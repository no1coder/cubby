import AppKit
import Carbon.HIToolbox
import Testing
@testable import CubbyCore

@Suite("截图默认快捷键与面板截图指令")
struct HotKeyScreenshotDefaultTests {
    @Test("默认截图快捷键为 ⇧⌘2")
    func screenshotDefault() {
        let hotKey = HotKey.screenshotDefault
        #expect(hotKey.keyCode == UInt32(kVK_ANSI_2))
        #expect(hotKey.modifiers == UInt32(cmdKey | shiftKey))
        #expect(hotKey.keyLabel == "2")
        #expect(hotKey.displayName == "⇧⌘2")
        #expect(hotKey.keySymbols == ["⇧", "⌘", "2"])
    }

    @Test("与面板默认快捷键不同")
    func differsFromPanelDefault() {
        #expect(HotKey.screenshotDefault != HotKey.default)
    }

    @Test("录制器按下 ⇧⌘2 得到的快捷键与默认值相等（录制时按不带修饰键的字符取 \"2\"）")
    func recordedEventMatchesDefault() {
        let recorded = HotKey(keyCode: UInt16(kVK_ANSI_2), modifierFlags: [.command, .shift], characters: "2")
        #expect(recorded == .screenshotDefault)
    }

    @Test("JSON 往返后相等")
    func codableRoundTrip() throws {
        let data = try JSONEncoder().encode(HotKey.screenshotDefault)
        #expect(try JSONDecoder().decode(HotKey.self, from: data) == .screenshotDefault)
    }

    @Test("面板内 ⇧⌘2 不映射为任何面板指令（由全局热键处理），⌘2 仍是快速粘贴")
    func panelKeyMapping() {
        let shifted = PanelCommand.from(keyCode: UInt16(kVK_ANSI_2), modifiers: [.command, .shift], characters: "2")
        #expect(shifted == nil)
        let plain = PanelCommand.from(keyCode: UInt16(kVK_ANSI_2), modifiers: .command, characters: "2")
        #expect(plain == .pasteAt(1))
    }

    @Test("截图指令与其他指令互不相等")
    func takeScreenshotIsDistinct() {
        let others: [PanelCommand] = [.openSettings, .escape, .paste, .open, .togglePreview]
        #expect(others.allSatisfy { $0 != .takeScreenshot })
        #expect(PanelCommand.takeScreenshot == .takeScreenshot)
    }
}
