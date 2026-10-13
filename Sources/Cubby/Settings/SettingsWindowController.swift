import AppKit
import CubbyCore
import SwiftUI

/// 设置窗口（单例复用）：左侧侧边栏切换分页（docs/design/ui-upgrade/Settings.png），右侧页面内容可滚动。
/// 标题栏透明、内容铺满，红绿灯压在侧边栏上；宽度固定，高度可调
@MainActor
final class SettingsWindowController {
    /// 默认内容尺寸与最小高度（宽度固定：侧边栏 220 + 页面 600）
    private static let contentSize = NSSize(width: 820, height: 700)
    private static let minContentHeight: CGFloat = 460
    /// 距屏幕可见区域上下保留的边距
    private static let screenMargin: CGFloat = 30

    private let settings: AppSettings
    private let store: ClipStore
    /// 加密 Vault 的状态（设置 › 历史的「加密」一行、诊断信息）
    private let vault: VaultCoordinator?
    private let onShortcutRecordingChange: (Bool) -> Void
    private let updates: UpdateCoordinator
    /// 关于页的「使用说明」按钮
    private let openUserGuide: () -> Void
    /// 「设置 › 翻译」的状态；nil 表示不提供翻译（macOS 26 以前），不显示该页
    private let translation: TranslationSettingsModel?
    private let addressGuard: AddressGuardController
    private let navigation = SettingsNavigation()
    private var window: NSWindow?
    private var closeObserver: (any NSObjectProtocol)?
    /// 等待设置窗口关闭的调用方（截图翻译的「去设置」）
    private var closeWaiters: [CheckedContinuation<Void, Never>] = []

    init(
        settings: AppSettings,
        store: ClipStore,
        vault: VaultCoordinator?,
        updates: UpdateCoordinator,
        translation: TranslationSettingsModel?,
        addressGuard: AddressGuardController,
        onShortcutRecordingChange: @escaping (Bool) -> Void,
        openUserGuide: @escaping () -> Void
    ) {
        self.updates = updates
        self.openUserGuide = openUserGuide
        self.settings = settings
        self.store = store
        self.vault = vault
        self.translation = translation
        self.addressGuard = addressGuard
        self.onShortcutRecordingChange = onShortcutRecordingChange
    }

    func show() {
        present(pane: nil)
    }

    /// 打开设置并切换到指定分页（例如从权限提醒直接跳到「隐私」）
    func show(pane: SettingsPane) {
        present(pane: pane)
    }

    /// 打开指定分页，在设置窗口关闭后返回（窗口已打开时同样等到它关闭）
    func showUntilClosed(pane: SettingsPane) async {
        present(pane: pane)
        await withCheckedContinuation { closeWaiters.append($0) }
    }

    private func present(pane: SettingsPane?) {
        let window = self.window ?? makeWindow()
        self.window = window
        if let pane, availablePanes.contains(pane) {
            navigation.selection = pane
        }
        if !window.isVisible {
            window.setContentSize(fittedContentSize(on: NSScreen.main))
            window.center()
        }
        // 菜单栏应用需要主动激活，窗口才会出现在最前
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
    }

    private func makeWindow() -> NSWindow {
        let root = SettingsRootView(panes: availablePanes, navigation: navigation) { [unowned self] pane in
            self.rootView(for: pane) ?? AnyView(EmptyView())
        }
        let controller = NSHostingController(rootView: root)
        controller.sizingOptions = []
        let window = NSWindow(contentViewController: controller)
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView]
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.isReleasedWhenClosed = false
        window.tabbingMode = .disallowed
        window.collectionBehavior.insert(.fullScreenNone)
        window.contentMinSize = NSSize(width: Self.contentSize.width, height: Self.minContentHeight)
        window.contentMaxSize = NSSize(width: Self.contentSize.width, height: .greatestFiniteMagnitude)
        window.setContentSize(Self.contentSize)
        // 标题栏不显示文字，但窗口标题仍随分页变化（窗口菜单与辅助功能使用）
        window.title = navigation.selection.title
        navigation.onChange = { [weak self, weak window] pane in
            // 切页会销毁页面视图：先提交翻译页里输入了一半的内容（幂等）
            self?.translation?.commitPendingEdits()
            window?.title = pane.title
        }
        closeObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification, object: window, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.windowWillClose() }
        }
        return window
    }

    /// 默认高度不超过屏幕可见区域
    private func fittedContentSize(on screen: NSScreen?) -> NSSize {
        guard let screen else { return Self.contentSize }
        // 内容铺满整个窗口（含标题栏），内容高度即窗口高度
        let limit = screen.visibleFrame.height - Self.screenMargin * 2
        return NSSize(
            width: Self.contentSize.width, height: max(min(Self.contentSize.height, limit), Self.minContentHeight))
    }

    /// 关闭时提交尚未提交的输入，再唤醒等待方
    private func windowWillClose() {
        translation?.commitPendingEdits()
        let waiters = closeWaiters
        closeWaiters = []
        waiters.forEach { $0.resume() }
    }

    /// 侧边栏显示的分页：翻译页仅在提供翻译时出现
    private var availablePanes: [SettingsPane] {
        SettingsPane.allCases.filter { $0 != .translation || translation != nil }
    }

    /// nil 表示该页不显示
    private func rootView(for pane: SettingsPane) -> AnyView? {
        switch pane {
        case .general:
            AnyView(GeneralSettingsPane(settings: settings, onShortcutRecordingChange: onShortcutRecordingChange))
        case .history:
            AnyView(HistorySettingsPane(settings: settings, store: store, vault: vault))
        case .screenshots:
            AnyView(ScreenshotSettingsPane(settings: settings, onShortcutRecordingChange: onShortcutRecordingChange))
        case .translation:
            translation.map { AnyView(TranslationSettingsPane(model: $0, store: store)) }
        case .security:
            AnyView(SecuritySettingsPane(settings: settings, addressGuard: addressGuard))
        case .privacy:
            AnyView(PrivacySettingsPane(settings: settings))
        case .about:
            AnyView(
                AboutSettingsPane(
                    settings: settings, store: store, vault: vault, updates: updates, openUserGuide: openUserGuide))
        }
    }
}
