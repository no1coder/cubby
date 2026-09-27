import AppKit
import SwiftUI
import CubbyCore

/// 设置分页
enum SettingsPane: CaseIterable {
    case general
    case history
    /// 截图翻译（仅 macOS 26 显示）
    case translation
    case privacy
    case about

    var title: String {
        switch self {
        case .general: String(localized: "General", comment: "Settings pane")
        case .history: String(localized: "History", comment: "Settings pane")
        case .translation: String(localized: "Translation", comment: "Settings pane")
        case .privacy: String(localized: "Privacy", comment: "Settings pane")
        case .about: String(localized: "About", comment: "Settings pane")
        }
    }

    var symbolName: String {
        switch self {
        case .general: "gearshape"
        case .history: "clock.arrow.circlepath"
        case .translation: "translate"
        case .privacy: "hand.raised"
        case .about: "info.circle"
        }
    }
}

/// 设置窗口（单例复用）：系统原生工具栏分页，切换页面时窗口高度随内容变化
@MainActor
final class SettingsWindowController {
    private let settings: AppSettings
    private let store: ClipStore
    private let onShortcutRecordingChange: (Bool) -> Void
    private let updates: UpdateCoordinator
    /// 关于页的「使用说明」按钮
    private let openUserGuide: () -> Void
    /// 「设置 › 翻译」的状态；nil 表示不提供翻译（macOS 26 以前），不显示该页
    private let translation: TranslationSettingsModel?
    private var window: NSWindow?
    private var tabController: SettingsTabViewController?
    private var closeObserver: (any NSObjectProtocol)?
    /// 等待设置窗口关闭的调用方（截图翻译的「去设置」）
    private var closeWaiters: [CheckedContinuation<Void, Never>] = []

    init(
        settings: AppSettings,
        store: ClipStore,
        updates: UpdateCoordinator,
        translation: TranslationSettingsModel?,
        onShortcutRecordingChange: @escaping (Bool) -> Void,
        openUserGuide: @escaping () -> Void
    ) {
        self.updates = updates
        self.openUserGuide = openUserGuide
        self.settings = settings
        self.store = store
        self.translation = translation
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
        if let pane {
            tabController?.select(pane)
        }
        if !window.isVisible {
            window.center()
        }
        // 菜单栏应用需要主动激活，窗口才会出现在最前
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
    }

    private func makeWindow() -> NSWindow {
        let controller = SettingsTabViewController(panes: makePanes())
        let window = NSWindow(contentViewController: controller)
        window.styleMask = [.titled, .closable, .miniaturizable]
        window.toolbarStyle = .preference
        window.isReleasedWhenClosed = false
        window.tabbingMode = .disallowed
        window.collectionBehavior.insert(.fullScreenNone)
        controller.fitWindowToSelection(animated: false)
        tabController = controller
        closeObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification, object: window, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.windowWillClose() }
        }
        return window
    }

    /// 关闭时提交尚未提交的输入，再唤醒等待方
    private func windowWillClose() {
        translation?.commitPendingEdits()
        let waiters = closeWaiters
        closeWaiters = []
        waiters.forEach { $0.resume() }
    }

    private func makePanes() -> [(SettingsPane, NSViewController)] {
        SettingsPane.allCases.compactMap { pane in
            guard let view = rootView(for: pane) else { return nil }
            return (pane, SettingsHostingController(rootView: view))
        }
    }

    /// nil 表示该页不显示
    private func rootView(for pane: SettingsPane) -> AnyView? {
        switch pane {
        case .general:
            AnyView(GeneralSettingsPane(settings: settings, onShortcutRecordingChange: onShortcutRecordingChange))
        case .history:
            AnyView(HistorySettingsPane(settings: settings, store: store))
        case .translation:
            translation.map { AnyView(TranslationSettingsPane(model: $0, store: store)) }
        case .privacy:
            AnyView(PrivacySettingsPane(settings: settings))
        case .about:
            AnyView(
                AboutSettingsPane(settings: settings, store: store, updates: updates, openUserGuide: openUserGuide))
        }
    }
}

/// 设置页的 SwiftUI 容器：宽度固定，通过 preferredContentSize 上报内容的理想高度。
/// 页面默认整体不滚动：macOS 26 中工具栏窗口内可滚动的页面顶部会被一段工具栏高度的
/// 「滚动口袋」遮住。长列表放进页面内的定高列表框；内容确实放不下时见 SettingsPageLayout。
@MainActor
final class SettingsHostingController: NSHostingController<AnyView> {
    static let contentWidth: CGFloat = 520
    /// 留有余量：英文等较长语言的说明文字会多折行（隐私页最高）
    static let maxContentHeight: CGFloat = 700

    let layout: SettingsPageLayout

    override init(rootView: AnyView) {
        let layout = SettingsPageLayout()
        self.layout = layout
        super.init(
            rootView: AnyView(rootView.modifier(PageScrollBehavior(layout: layout)).frame(width: Self.contentWidth)))
        sizingOptions = [.preferredContentSize]
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    /// AppKit 按此尺寸生成约束调整窗口（页面内容变化时即时生效）
    override var preferredContentSize: NSSize {
        get { NSSize(width: super.preferredContentSize.width, height: contentHeight) }
        set { super.preferredContentSize = newValue }
    }

    /// 内容的完整理想高度
    var idealHeight: CGFloat {
        super.preferredContentSize.height
    }

    var contentHeight: CGFloat {
        min(idealHeight, Self.maxContentHeight)
    }
}

/// 内容超出窗口可用高度（小屏幕、大字号）时的回退：恢复页面滚动，
/// 并把内容下移一个工具栏高度避开滚动口袋，保证第一组设置可见、全部内容可达
@MainActor
@Observable
final class SettingsPageLayout {
    var overflowTopInset: CGFloat?
}

private struct PageScrollBehavior: ViewModifier {
    let layout: SettingsPageLayout

    func body(content: Content) -> some View {
        if let inset = layout.overflowTopInset {
            // 在分组 Form 自带留白之上再让出滚动口袋的高度
            content.contentMargins(.top, inset, for: .scrollContent)
        } else {
            content.scrollDisabled(true)
        }
    }
}

/// 工具栏样式的分页控制器
@MainActor
final class SettingsTabViewController: NSTabViewController {
    private static let minContentHeight: CGFloat = 160
    /// 距屏幕可见区域上下保留的边距
    private static let screenMargin: CGFloat = 30

    init(panes: [(SettingsPane, NSViewController)]) {
        super.init(nibName: nil, bundle: nil)
        tabStyle = .toolbar
        transitionOptions = [.crossfade, .allowUserInteraction]
        canPropagateSelectedChildViewControllerTitle = true
        for (pane, controller) in panes {
            controller.title = pane.title
            let item = NSTabViewItem(viewController: controller)
            item.label = pane.title
            // 工具栏项标识必须是字符串
            item.identifier = "settings.\(pane)"
            item.image = NSImage(systemSymbolName: pane.symbolName, accessibilityDescription: pane.title)
            addTabViewItem(item)
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    /// 按标识查找：不是每个分页都会显示（翻译页仅 macOS 26），不能按序号定位
    func select(_ pane: SettingsPane) {
        guard let index = tabViewItems.firstIndex(where: { $0.identifier as? String == "settings.\(pane)" }) else {
            return
        }
        selectedTabViewItemIndex = index
    }

    override func tabView(_ tabView: NSTabView, didSelect tabViewItem: NSTabViewItem?) {
        super.tabView(tabView, didSelect: tabViewItem)
        if let label = tabViewItem?.label {
            view.window?.title = label
        }
        fitWindowToSelection(animated: view.window?.isVisible == true)
    }

    /// 切换页面时以动画调整窗口高度，保持顶边与宽度不变。
    /// 动画结束后与 AppKit 按 preferredContentSize 生成的约束一致，不会再跳动。
    func fitWindowToSelection(animated: Bool) {
        guard let window = view.window,
            let controller = selectedController as? SettingsHostingController,
            controller.contentHeight > 0  // 尚未完成首次布局时等待上报
        else { return }
        let targetSize = NSSize(
            width: SettingsHostingController.contentWidth,
            height: clampedHeight(controller.contentHeight, in: window)
        )
        // 内容放不下时启用页面滚动回退（见 SettingsPageLayout）
        let overflows = controller.idealHeight > targetSize.height + 1
        let overflowInset = overflows ? window.frame.height - window.contentLayoutRect.height : nil
        if controller.layout.overflowTopInset != overflowInset {
            controller.layout.overflowTopInset = overflowInset
        }

        let currentSize = window.contentLayoutRect.size
        let deltaWidth = targetSize.width - currentSize.width
        let deltaHeight = targetSize.height - currentSize.height
        guard abs(deltaWidth) > 0.5 || abs(deltaHeight) > 0.5 else { return }

        var frame = window.frame
        frame.size.width += deltaWidth
        frame.size.height += deltaHeight
        frame.origin.y -= deltaHeight
        window.setFrame(frame, display: true, animate: animated)
    }

    private var selectedController: NSViewController? {
        guard tabViewItems.indices.contains(selectedTabViewItemIndex) else { return nil }
        return tabViewItems[selectedTabViewItemIndex].viewController
    }

    private func clampedHeight(_ height: CGFloat, in window: NSWindow) -> CGFloat {
        let chromeHeight = window.frame.height - window.contentLayoutRect.height
        let screenLimit =
            (window.screen ?? NSScreen.main).map {
                $0.visibleFrame.height - chromeHeight - Self.screenMargin * 2
            } ?? SettingsHostingController.maxContentHeight
        let maxHeight = max(min(SettingsHostingController.maxContentHeight, screenLimit), Self.minContentHeight)
        return min(max(height, Self.minContentHeight), maxHeight)
    }
}
