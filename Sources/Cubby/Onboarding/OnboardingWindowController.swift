import AppKit
import SwiftUI
import CubbyCore

/// 首次启动引导窗口。点击「开始使用」或关闭窗口都视为完成引导。
@MainActor
final class OnboardingWindowController: NSObject, NSWindowDelegate {
    private let settings: AppSettings
    private let onShortcutRecordingChange: (Bool) -> Void
    private let onFinish: () -> Void
    private var window: NSWindow?
    private var hasFinished = false

    init(
        settings: AppSettings,
        onShortcutRecordingChange: @escaping (Bool) -> Void,
        onFinish: @escaping () -> Void
    ) {
        self.settings = settings
        self.onShortcutRecordingChange = onShortcutRecordingChange
        self.onFinish = onFinish
    }

    func show() {
        let window = self.window ?? makeWindow()
        self.window = window
        if !window.isVisible {
            window.center()
        }
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
    }

    // MARK: - NSWindowDelegate

    func windowWillClose(_ notification: Notification) {
        // 推迟到关闭流程结束后再回调：回调方可能会释放本控制器（及其持有的窗口）
        Task { @MainActor in self.finish() }
    }

    // MARK: - 私有

    /// 标记完成并回调（只执行一次）
    private func finish() {
        guard !hasFinished else { return }
        hasFinished = true
        settings.hasCompletedOnboarding = true
        onFinish()
    }

    private func start() {
        // 关闭窗口会触发 windowWillClose → finish()
        guard let window else { return finish() }
        window.close()
    }

    private func makeWindow() -> NSWindow {
        let rootView = OnboardingView(
            settings: settings,
            onShortcutRecordingChange: onShortcutRecordingChange,
            onStart: { [weak self] in self?.start() }
        )
        // 默认 sizingOptions：窗口随内容高度自动调整（例如出现错误提示时）
        let controller = NSHostingController(rootView: rootView)
        // 内容延伸到透明标题栏下方，不再额外计入标题栏高度
        controller.safeAreaRegions = []
        let size = controller.sizeThatFits(in: NSSize(width: OnboardingView.width, height: .greatestFiniteMagnitude))

        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.titled, .closable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.contentViewController = controller
        window.setContentSize(size)
        window.title = String(localized: "Welcome to Cubby", comment: "Onboarding window title")
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.isMovableByWindowBackground = true
        window.isReleasedWhenClosed = false
        window.tabbingMode = .disallowed
        window.collectionBehavior.insert(.fullScreenNone)
        window.standardWindowButton(.miniaturizeButton)?.isHidden = true
        window.standardWindowButton(.zoomButton)?.isHidden = true
        window.delegate = self
        return window
    }
}
