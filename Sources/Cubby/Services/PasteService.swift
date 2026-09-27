import AppKit
import ApplicationServices
import Carbon.HIToolbox

/// 模拟 ⌘V 将内容粘贴到当前应用（需要辅助功能权限）
@MainActor
enum PasteService {
    private static let settingsURL = URL(
        string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
    )

    static var isTrusted: Bool {
        AXIsProcessTrusted()
    }

    /// 弹出系统授权提示
    static func requestTrust() {
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
    }

    static func openAccessibilitySettings() {
        guard let settingsURL else { return }
        NSWorkspace.shared.open(settingsURL)
    }

    static func sendPasteShortcut() {
        let source = CGEventSource(stateID: .combinedSessionState)
        // 粘贴期间屏蔽本地键盘事件，避免用户仍按着的修饰键干扰
        source?.setLocalEventsFilterDuringSuppressionState(
            [.permitLocalMouseEvents, .permitSystemDefinedEvents],
            state: .eventSuppressionStateSuppressionInterval
        )
        let keyCode = CGKeyCode(kVK_ANSI_V)
        let keyDown = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: true)
        let keyUp = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: false)
        keyDown?.flags = .maskCommand
        keyUp?.flags = .maskCommand
        keyDown?.post(tap: .cgAnnotatedSessionEventTap)
        keyUp?.post(tap: .cgAnnotatedSessionEventTap)
    }
}
