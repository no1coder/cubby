import AppKit

/// 面板显示期间的本地键盘监听：keyDown 映射为面板指令；flagsChanged 只转发 ⌥ 的按下 / 松开，
/// 鼠标按下只通知一声（取消按住 ⌥ 的预览：⌥ 点按不是要预览），都不消费事件
/// （按住 ⌥ 预览译文、翻译卡里按住 ⌥ 看原文，docs/CLIP-TRANSLATION-DESIGN.md §1.2）
@MainActor
final class PanelKeyboard {
    /// keyDown：返回 true 表示事件已处理、不再传递
    var handler: ((NSEvent) -> Bool)?
    /// ⌥ 单独按下（true）或松开（false）；同时按着其他修饰键时视为松开
    var onOptionChange: ((Bool) -> Void)?
    /// 本应用的任一窗口里按下了鼠标
    var onPointerDown: (() -> Void)?
    private var monitor: Any?
    private static let pointerDowns: NSEvent.EventTypeMask = [.leftMouseDown, .rightMouseDown, .otherMouseDown]
    private var isOptionDown = false

    func install(for panel: NSPanel) {
        guard monitor == nil else { return }
        isOptionDown = false
        let mask = Self.pointerDowns.union([.keyDown, .flagsChanged])
        monitor = NSEvent.addLocalMonitorForEvents(matching: mask) { [weak self] event in
            guard let self else { return event }
            if event.type == .flagsChanged {
                self.flagsChanged(event, panel: panel)
                return event
            }
            if event.type != .keyDown {
                self.onPointerDown?()
                return event
            }
            guard let handler = self.handler else { return event }
            return handler(event) ? nil : event
        }
    }

    func remove() {
        if let monitor {
            NSEvent.removeMonitor(monitor)
        }
        monitor = nil
        isOptionDown = false
    }

    private func flagsChanged(_ event: NSEvent, panel: NSPanel) {
        guard event.window === panel || event.window == nil else { return }
        let flags = event.modifierFlags.intersection([.command, .option, .control, .shift])
        let optionAlone = flags == .option
        guard optionAlone != isOptionDown else { return }
        isOptionDown = optionAlone
        onOptionChange?(optionAlone)
    }
}
