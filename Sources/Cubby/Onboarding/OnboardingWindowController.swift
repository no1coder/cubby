import AppKit
import SwiftUI
import CubbyCore

/// 首次启动引导窗口（四步向导）。最后一步点击「开始使用」或关闭窗口都视为完成引导。
@MainActor
final class OnboardingWindowController: NSObject, NSWindowDelegate {
    /// 与设计稿 Onboarding 一致的窗口尺寸（docs/design/ui-upgrade/src/Onboarding.dc.html）
    static let contentSize = NSSize(width: 840, height: 640)

    private let settings: AppSettings
    private let initialStep: OnboardingStep
    private let onShortcutRecordingChange: (Bool) -> Void
    private let onFinish: () -> Void
    private var window: NSWindow?
    private var hasFinished = false

    init(
        settings: AppSettings,
        initialStep: OnboardingStep = .welcome,
        onShortcutRecordingChange: @escaping (Bool) -> Void,
        onFinish: @escaping () -> Void
    ) {
        self.settings = settings
        self.initialStep = initialStep
        self.onShortcutRecordingChange = onShortcutRecordingChange
        self.onFinish = onFinish
    }

    func show() {
        // 新用户第一次显示欢迎页：「有新版本时提醒我」默认勾选；从菜单重开时只反映当前设置（U3）
        settings.applyFirstRunUpdateDefault()
        let window = self.window ?? makeWindow()
        self.window = window
        if !window.isVisible {
            window.center()
        }
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
    }

    #if DEBUG
    /// 截图走查带 --backdrop 时，壁纸窗口高于普通窗口：把引导窗口抬到壁纸之上（与面板同层）
    func raiseAboveDesignBackdrop() {
        window?.level = .floating
    }
    #endif

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
        let rootView = OnboardingWizard(
            settings: settings,
            initialStep: initialStep,
            onShortcutRecordingChange: onShortcutRecordingChange,
            onStart: { [weak self] in self?.start() }
        )
        let hosting = NSHostingView(rootView: rootView)
        // 内容延伸到透明标题栏下方，不再额外计入标题栏高度
        hosting.safeAreaRegions = []

        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: Self.contentSize),
            styleMask: [.titled, .closable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.contentView = Self.makeBackground(containing: hosting)
        window.setContentSize(Self.contentSize)
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

    /// 窗口底：透出桌面的毛玻璃（设计稿为半透明深色玻璃），深浅外观随系统材质自动切换
    private static func makeBackground(containing content: NSView) -> NSView {
        let effect = NSVisualEffectView(frame: NSRect(origin: .zero, size: contentSize))
        effect.material = .underWindowBackground
        effect.blendingMode = .behindWindow
        effect.state = .active
        content.frame = effect.bounds
        content.autoresizingMask = [.width, .height]
        effect.addSubview(content)
        return effect
    }
}
