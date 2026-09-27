import AppKit
import SwiftUI

/// 使用说明窗口（单例复用）：标准的可调整大小窗口，再次打开时把已有窗口带到最前
@MainActor
final class UserGuideWindowController {
    private static let defaultSize = NSSize(width: 820, height: 640)
    private static let minimumSize = NSSize(width: 640, height: 480)

    private let model = UserGuideModel()
    private var window: NSWindow?

    /// - Parameter query: 预先填入搜索框（调试走查 --scenario guide:<query>）
    func show(query: String? = nil) {
        let isNew = window == nil
        let window = self.window ?? makeWindow()
        self.window = window
        model.loadIfNeeded()
        if let query {
            model.query = query
        }
        if !window.isVisible {
            window.center()
        }
        // 菜单栏应用需要主动激活，窗口才会出现在最前
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
        if isNew {
            window.makeFirstResponder(model.document.focusView)
        }
    }

    private func makeWindow() -> NSWindow {
        let controller = NSHostingController(rootView: UserGuideView(model: model))
        // 窗口大小由用户决定，不让 SwiftUI 按内容调整
        controller.sizingOptions = []
        let window = UserGuideWindow(
            contentRect: NSRect(origin: .zero, size: Self.defaultSize),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.contentViewController = controller
        window.setContentSize(Self.defaultSize)
        window.contentMinSize = Self.minimumSize
        window.title = String(localized: "User Guide", comment: "User guide window title")
        window.isReleasedWhenClosed = false
        window.tabbingMode = .disallowed
        window.onFind = { [weak model] in model?.focusSearch() }
        return window
    }
}

/// ⌘F 聚焦搜索框：菜单栏应用没有「查找」菜单，按键在窗口层面处理
private final class UserGuideWindow: NSWindow {
    private static let ignoredModifiers: NSEvent.ModifierFlags = [.capsLock, .numericPad, .function]

    var onFind: (() -> Void)?

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask).subtracting(Self.ignoredModifiers)
        if modifiers == .command, event.charactersIgnoringModifiers?.lowercased() == "f" {
            onFind?()
            return true
        }
        return super.performKeyEquivalent(with: event)
    }
}
