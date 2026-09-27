import AppKit
import SwiftUI

/// 快捷键录制的键盘事件捕获：录制期间成为第一响应者并截获按键
struct KeyEventCapture: NSViewRepresentable {
    let isRecording: Bool
    let onKeyDown: (NSEvent) -> Void
    let onModifiersChange: (NSEvent.ModifierFlags) -> Void
    /// 被外部因素中断：点击其他位置、窗口失去焦点、焦点被移走
    let onInterrupt: () -> Void

    func makeNSView(context: Context) -> ShortcutCaptureView {
        ShortcutCaptureView()
    }

    func updateNSView(_ view: ShortcutCaptureView, context: Context) {
        view.onKeyDown = onKeyDown
        view.onModifiersChange = onModifiersChange
        view.onInterrupt = onInterrupt
        view.setCapturing(isRecording)
    }

    static func dismantleNSView(_ view: ShortcutCaptureView, coordinator: ()) {
        view.setCapturing(false)
    }
}

/// 可成为第一响应者的透明视图。
/// 按键通过本地事件监听截获（先于菜单与 SwiftUI 快捷键处理，⌘ 组合键、⇥、esc 都能拿到），
/// 同时成为第一响应者，避免按键落到其他输入控件上。
final class ShortcutCaptureView: NSView {
    var onKeyDown: ((NSEvent) -> Void)?
    var onModifiersChange: ((NSEvent.ModifierFlags) -> Void)?
    var onInterrupt: (() -> Void)?

    private var isCapturing = false
    private var eventMonitor: Any?
    private weak var observedWindow: NSWindow?

    override var acceptsFirstResponder: Bool { isCapturing }

    /// 只负责键盘，不拦截鼠标，点击交给上层的 SwiftUI 控件
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    func setCapturing(_ capturing: Bool) {
        guard capturing != isCapturing else { return }
        if capturing {
            startCapturing()
        } else {
            stopCapturing(resignFocus: true)
        }
    }

    // MARK: 响应者

    override func keyDown(with event: NSEvent) {
        // 正常情况下按键已被事件监听截获；这里兜底，避免系统提示音
        guard isCapturing else { return super.keyDown(with: event) }
        onKeyDown?(event)
    }

    override func flagsChanged(with event: NSEvent) {
        guard isCapturing else { return super.flagsChanged(with: event) }
        onModifiersChange?(event.modifierFlags)
    }

    override func resignFirstResponder() -> Bool {
        let accepted = super.resignFirstResponder()
        if accepted && isCapturing {
            // 焦点被移走（例如点击了输入框）
            stopCapturing(resignFocus: false)
            onInterrupt?()
        }
        return accepted
    }

    override func viewWillMove(toWindow newWindow: NSWindow?) {
        super.viewWillMove(toWindow: newWindow)
        if newWindow == nil {
            interrupt()
        }
    }

    // MARK: 私有

    private func startCapturing() {
        isCapturing = true
        installEventMonitor()
        if let window {
            observedWindow = window
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(windowDidResignKey(_:)),
                name: NSWindow.didResignKeyNotification,
                object: window
            )
            window.makeFirstResponder(self)
        }
    }

    private func stopCapturing(resignFocus: Bool) {
        isCapturing = false
        if let eventMonitor {
            NSEvent.removeMonitor(eventMonitor)
        }
        eventMonitor = nil
        if let observedWindow {
            NotificationCenter.default.removeObserver(
                self,
                name: NSWindow.didResignKeyNotification,
                object: observedWindow
            )
        }
        observedWindow = nil
        if resignFocus, let window, window.firstResponder === self {
            window.makeFirstResponder(nil)
        }
    }

    private func interrupt() {
        guard isCapturing else { return }
        stopCapturing(resignFocus: true)
        onInterrupt?()
    }

    private func installEventMonitor() {
        let mask: NSEvent.EventTypeMask = [.keyDown, .flagsChanged, .leftMouseDown, .rightMouseDown, .otherMouseDown]
        eventMonitor = NSEvent.addLocalMonitorForEvents(matching: mask) { [weak self] event in
            guard let self else { return event }
            return self.handleMonitoredEvent(event)
        }
    }

    private func handleMonitoredEvent(_ event: NSEvent) -> NSEvent? {
        guard isCapturing else { return event }
        switch event.type {
        case .keyDown:
            guard event.window === window else { return event }
            onKeyDown?(event)
            return nil
        case .flagsChanged:
            onModifiersChange?(event.modifierFlags)
            return event
        default:
            // 点击录制控件以外的位置即取消，点击本身照常生效
            if event.window !== window || !bounds.contains(convert(event.locationInWindow, from: nil)) {
                interrupt()
            }
            return event
        }
    }

    @objc private func windowDidResignKey(_ notification: Notification) {
        interrupt()
    }
}
