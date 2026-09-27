#if DEBUG
import AppKit
import Carbon.HIToolbox

/// 仅调试构建：截图走查时向面板投递真实输入事件（与用户操作走同一条事件路径）
@MainActor
enum PanelDebugInput {
    /// 等待面板布局完成后再投递
    private static let settleDelay: Duration = .milliseconds(600)
    /// 第一张卡片中部距面板顶边的距离（搜索栏 + 分类栏 + 卡片上半部）
    private static let firstCardOffset: CGFloat = 130

    private struct Key {
        let code: Int
        let characters: String
        var flags: NSEvent.ModifierFlags = []
    }

    private static let namedKeys: [String: Key] = [
        "space": Key(code: kVK_Space, characters: " "),
        "home": Key(code: kVK_Home, characters: ""),
        "end": Key(code: kVK_End, characters: ""),
        "pageup": Key(code: kVK_PageUp, characters: ""),
        "pagedown": Key(code: kVK_PageDown, characters: ""),
        "optdown": Key(code: kVK_DownArrow, characters: "", flags: .option),
        "return": Key(code: kVK_Return, characters: "\r"),
    ]

    /// 逗号分隔的按键：单个字符或 space / home / end / pageup / pagedown / optdown / return
    static func postKeys(_ spec: String, to panel: NSPanel) {
        Task { @MainActor [weak panel] in
            try? await Task.sleep(for: settleDelay)
            guard let panel else { return }
            panel.makeKey()
            for token in spec.split(separator: ",").map(String.init) {
                let key = namedKeys[token] ?? Key(code: kVK_ANSI_A, characters: token)
                for type in [NSEvent.EventType.keyDown, .keyUp] {
                    guard
                        let event = NSEvent.keyEvent(
                            with: type, location: .zero, modifierFlags: key.flags,
                            timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: panel.windowNumber,
                            context: nil, characters: key.characters, charactersIgnoringModifiers: key.characters,
                            isARepeat: false, keyCode: UInt16(key.code))
                    else { continue }
                    NSApp.postEvent(event, atStart: false)
                }
            }
        }
    }

    /// 在第一张卡片上模拟右键，弹出卡片菜单
    static func rightClickFirstCard(in panel: NSPanel) {
        Task { @MainActor [weak panel] in
            try? await Task.sleep(for: settleDelay)
            guard let panel, let contentView = panel.contentView else { return }
            let location = NSPoint(x: contentView.bounds.midX, y: contentView.bounds.maxY - firstCardOffset)
            guard
                let event = NSEvent.mouseEvent(
                    with: .rightMouseDown, location: location, modifierFlags: [],
                    timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: panel.windowNumber,
                    context: nil, eventNumber: 0, clickCount: 1, pressure: 1)
            else { return }
            // 应用不在前台时右键菜单可能不弹出：先激活
            NSApp.activate()
            panel.makeKey()
            panel.sendEvent(event)
        }
    }
}
#endif
