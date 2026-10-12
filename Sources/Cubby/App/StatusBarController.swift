import AppKit
import CubbyCore

/// 菜单栏图标：左键打开面板，右键（或 ⌃ 点击）显示菜单
@MainActor
final class StatusBarController: NSObject {
    struct Actions {
        let togglePanel: (CGRect?) -> Void
        let showOnlyImages: () -> Void
        let takeScreenshot: () -> Void
        let toggleClothesline: () -> Void
        let openSettings: () -> Void
        let showOnboarding: () -> Void
        let showUserGuide: () -> Void
        let clearHistory: () -> Void
        let checkForUpdates: () -> Void
        /// 菜单栏是红色「地址被替换」胶囊时左键点击：重新打开警示卡
        var showTamperAlert: () -> Void = {}
        /// 历史条数（菜单头部的状态行）
        var itemCount: () -> Int = { 0 }
    }

    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    private let settings: AppSettings
    private let updates: UpdateCoordinator
    private let actions: Actions
    /// 有新版本时图标右上角的蓝点（U5）
    private var updateBadge: StatusItemUpdateBadge?
    /// 右键菜单（StatusBarMenu）
    private let statusMenu: StatusBarMenu
    /// 有还没处理的地址替换：图标换成红色「地址被替换」胶囊
    private var showsTamperPill = false

    init(settings: AppSettings, updates: UpdateCoordinator, actions: Actions) {
        self.settings = settings
        self.updates = updates
        self.actions = actions
        statusMenu = StatusBarMenu(settings: settings, actions: actions)
        super.init()
        statusMenu.tamperPending = { [weak self] in self?.showsTamperPill ?? false }
        configureButton()
        refreshAppearance()
    }

    #if DEBUG
    var debugStatusMenu: StatusBarMenu { statusMenu }
    #endif

    /// 图标在屏幕上的位置（用于在其下方弹出面板）
    var buttonFrame: CGRect? {
        guard let button = statusItem.button, let window = button.window else { return nil }
        return window.convertToScreen(button.convert(button.bounds, to: nil))
    }

    /// 暂停状态与更新状态变化时调用：图标、蓝点、提示文字与菜单顶部的新版本项
    func refreshAppearance() {
        let release = updates.reminder.availableRelease
        if showsTamperPill, let button = statusItem.button {
            applyTamperPill(to: button)
        } else if let button = statusItem.button {
            Self.applyAppearance(to: button, badge: updateBadge, paused: settings.isPaused, release: release)
            applyClotheslineCount(to: button)
        }
        statusMenu.refreshUpdateItem(release, updates: updates)
    }

    /// 发现替换后到用户处理之前显示红色胶囊（AddressGuardController.pending）
    func setTamperPill(_ visible: Bool) {
        guard visible != showsTamperPill else { return }
        showsTamperPill = visible
        refreshAppearance()
    }

    private func applyTamperPill(to button: NSStatusBarButton) {
        statusItem.length = NSStatusItem.variableLength
        button.image = StatusItemTamperPill.image()
        button.imagePosition = .imageOnly
        button.attributedTitle = NSAttributedString()
        button.toolTip = SecurityCopy.statusPill
        button.setAccessibilityValue(SecurityCopy.statusPill)
        updateBadge?.isVisible = false
    }

    /// 绳上挂着照片时，图标右侧显示张数（「⌗ 4」）；绳上为空或关闭了晾衣绳时只有图标
    private func applyClotheslineCount(to button: NSStatusBarButton) {
        let count = settings.clotheslineEnabled ? settings.clothesline.count : 0
        statusItem.length = count > 0 ? NSStatusItem.variableLength : NSStatusItem.squareLength
        button.imagePosition = count > 0 ? .imageLeading : .imageOnly
        button.attributedTitle =
            count > 0
            ? NSAttributedString(
                string: " \(count)",
                attributes: [.font: NSFont.monospacedDigitSystemFont(ofSize: NSFont.systemFontSize, weight: .medium)])
            : NSAttributedString()
        button.setAccessibilityValue(
            count > 0
                ? String(localized: "\(count) photos on the clothesline", comment: "Status item accessibility value")
                : nil)
    }

    /// 按暂停与更新状态设置图标（有新版本时带缺口与读屏说明）、蓝点与提示文字；面板 E2E 用同一函数检查蓝点
    static func applyAppearance(
        to button: NSButton, badge: StatusItemUpdateBadge?, paused: Bool, release: KnownRelease?
    ) {
        button.image = StatusBarIcon.image(paused: paused, badged: release != nil)
        badge?.isVisible = release != nil
        button.toolTip = toolTip(paused: paused, release: release)
    }

    private static func toolTip(paused: Bool, release: KnownRelease?) -> String {
        if paused { return String(localized: "Cubby · Recording paused", comment: "Status item tooltip") }
        return release.map { UpdateCopy.statusItemToolTip($0.version.description) } ?? "Cubby"
    }

    // MARK: - 私有

    private func configureButton() {
        guard let button = statusItem.button else { return }
        button.target = self
        button.action = #selector(handleClick(_:))
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        updateBadge = StatusItemUpdateBadge(button: button)
    }

    @objc private func handleClick(_ sender: NSStatusBarButton) {
        let event = NSApp.currentEvent
        let wantsMenu = event?.type == .rightMouseUp || event?.modifierFlags.contains(.control) == true
        if wantsMenu {
            showMenu()
        } else if showsTamperPill {
            actions.showTamperAlert()
        } else {
            actions.togglePanel(buttonFrame)
        }
    }

    private func showMenu() {
        statusItem.menu = statusMenu.menu
        statusItem.button?.performClick(nil)
        // 用完即移除，保证左键点击仍走自定义动作
        statusItem.menu = nil
    }

    /// 标题右侧以次要颜色显示补充信息：全局快捷键（无法用 keyEquivalent 表达）或子菜单的当前值
    static func titleWithDetail(_ title: String, detail: String) -> NSAttributedString {
        let result = NSMutableAttributedString(string: title + "    ")
        result.append(
            NSAttributedString(
                string: detail,
                attributes: [.foregroundColor: NSColor.secondaryLabelColor]
            ))
        return result
    }
}

/// 以闭包作为动作的菜单项
final class ClosureMenuItem: NSMenuItem {
    var handler: () -> Void

    init(title: String, keyEquivalent: String = "", handler: @escaping () -> Void) {
        self.handler = handler
        super.init(title: title, action: #selector(invoke), keyEquivalent: keyEquivalent)
        target = self
    }

    @available(*, unavailable)
    required init(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    @objc private func invoke() {
        handler()
    }
}
