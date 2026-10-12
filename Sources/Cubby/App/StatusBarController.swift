import AppKit
import CubbyCore

/// 菜单栏图标：左键打开面板，右键（或 ⌃ 点击）显示菜单
@MainActor
final class StatusBarController: NSObject, NSMenuDelegate {
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
    }

    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    private let settings: AppSettings
    private let updates: UpdateCoordinator
    private let actions: Actions
    /// 有新版本时图标右上角的蓝点（U5）
    private var updateBadge: StatusItemUpdateBadge?
    private let menu = NSMenu()
    private let openItem: ClosureMenuItem
    private let screenshotItem: ClosureMenuItem
    private let imagesItem: ClosureMenuItem
    private let clotheslineItem: ClosureMenuItem
    private let pauseItem = ClosureMenuItem(
        title: String(localized: "Pause Recording", comment: "Status menu item"),
        handler: {}
    )
    private let accessWarningItem = ClosureMenuItem(
        title: String(localized: "Allow Clipboard Access…", comment: "Status menu item")
    ) {
        PasteboardAccess.openSettings()
    }
    private let panelPositionItem: PanelPositionMenuItem
    private let appearanceItem: AppearanceMenuItem
    /// 已知有新版本时显示在菜单顶部（U5）
    private let updateAvailableItem = ClosureMenuItem(title: "", handler: {})

    init(settings: AppSettings, updates: UpdateCoordinator, actions: Actions) {
        self.settings = settings
        self.updates = updates
        self.actions = actions
        self.openItem = ClosureMenuItem(title: Self.openTitle) { actions.togglePanel(nil) }
        self.screenshotItem = ClosureMenuItem(title: Self.screenshotTitle, handler: actions.takeScreenshot)
        self.imagesItem = ClosureMenuItem(title: Self.imagesTitle, handler: actions.showOnlyImages)
        self.clotheslineItem = ClosureMenuItem(title: "", handler: actions.toggleClothesline)
        self.panelPositionItem = PanelPositionMenuItem(settings: settings)
        self.appearanceItem = AppearanceMenuItem(settings: settings)
        super.init()

        pauseItem.handler = { [weak self] in self?.settings.isPaused.toggle() }
        accessWarningItem.image = NSImage(
            systemSymbolName: "exclamationmark.triangle.fill", accessibilityDescription: nil)
        updateAvailableItem.image = NSImage(systemSymbolName: "arrow.down.circle.fill", accessibilityDescription: nil)?
            .withSymbolConfiguration(NSImage.SymbolConfiguration(hierarchicalColor: .controlAccentColor))
        updateAvailableItem.isHidden = true
        configureButton()
        buildMenu()
        refreshAppearance()
    }

    /// 图标在屏幕上的位置（用于在其下方弹出面板）
    var buttonFrame: CGRect? {
        guard let button = statusItem.button, let window = button.window else { return nil }
        return window.convertToScreen(button.convert(button.bounds, to: nil))
    }

    /// 暂停状态与更新状态变化时调用：图标、蓝点、提示文字与菜单顶部的新版本项
    func refreshAppearance() {
        let release = updates.reminder.availableRelease
        if let button = statusItem.button {
            Self.applyAppearance(to: button, badge: updateBadge, paused: settings.isPaused, release: release)
            applyClotheslineCount(to: button)
        }
        refreshUpdateItem(release)
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

    /// 已知有新版本：菜单顶部显示醒目的「新版本 x 可用…」，点击打开发布页；升级后隐藏
    private func refreshUpdateItem(_ release: KnownRelease?) {
        guard let release else {
            updateAvailableItem.isHidden = true
            return
        }
        let font = NSFontManager.shared.convert(.menuFont(ofSize: 0), toHaveTrait: .boldFontMask)
        updateAvailableItem.attributedTitle = NSAttributedString(
            string: UpdateCopy.menuItem(release.version.description), attributes: [.font: font])
        updateAvailableItem.handler = { [weak updates] in updates?.openRelease(release) }
        updateAvailableItem.isHidden = false
    }

    // MARK: - NSMenuDelegate

    func menuNeedsUpdate(_ menu: NSMenu) {
        openItem.attributedTitle = Self.titleWithDetail(Self.openTitle, detail: settings.hotKey.displayName)
        // 截图快捷键已关闭时只显示标题
        screenshotItem.attributedTitle = settings.screenshotHotKey.map {
            Self.titleWithDetail(Self.screenshotTitle, detail: $0.displayName)
        }
        panelPositionItem.refresh()
        appearanceItem.refresh()
        imagesItem.attributedTitle = settings.imagesHotKey.map {
            Self.titleWithDetail(Self.imagesTitle, detail: $0.displayName)
        }
        refreshClotheslineItem()
        pauseItem.state = settings.isPaused ? .on : .off
        accessWarningItem.isHidden = !PasteboardAccess.needsAttention
    }

    // MARK: - 私有

    private static var openTitle: String {
        String(localized: "Open Clipboard", comment: "Status menu item: open the panel")
    }

    private static var imagesTitle: String {
        String(localized: "Only Images", comment: "Status menu item: open the panel on the image grid")
    }

    /// 「显示晾衣绳 · 4 张」+ 快捷键；关闭了晾衣绳时隐藏，绳上为空时置灰
    private func refreshClotheslineItem() {
        clotheslineItem.isHidden = !settings.clotheslineEnabled
        let count = settings.clothesline.count
        let title = String(
            localized: "Show Clothesline · \(count) photos",
            comment: "Status menu item that slides the clothesline down. %lld = number of photos on it")
        clotheslineItem.attributedTitle =
            settings.clotheslineHotKey.map {
                Self.titleWithDetail(title, detail: $0.displayName)
            } ?? NSAttributedString(string: title)
        clotheslineItem.isEnabled = count > 0
    }

    private static var screenshotTitle: String {
        String(localized: "Take Screenshot", comment: "Status menu item and panel button tooltip")
    }

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
        } else {
            actions.togglePanel(buttonFrame)
        }
    }

    private func showMenu() {
        statusItem.menu = menu
        statusItem.button?.performClick(nil)
        // 用完即移除，保证左键点击仍走自定义动作
        statusItem.menu = nil
    }

    private func buildMenu() {
        menu.delegate = self
        // 菜单项的可用状态由我们在 menuNeedsUpdate 里设置（例如绳上为空时「显示晾衣绳」置灰）
        menu.autoenablesItems = false
        menu.addItem(updateAvailableItem)
        menu.addItem(accessWarningItem)
        menu.addItem(openItem)
        menu.addItem(imagesItem)
        menu.addItem(screenshotItem)
        menu.addItem(clotheslineItem)
        menu.addItem(.separator())
        menu.addItem(panelPositionItem)
        menu.addItem(appearanceItem)
        menu.addItem(.separator())
        menu.addItem(pauseItem)
        menu.addItem(
            ClosureMenuItem(
                title: String(localized: "Clear History…", comment: "Status menu item"),
                handler: actions.clearHistory
            ))
        menu.addItem(.separator())
        menu.addItem(
            ClosureMenuItem(
                title: String(localized: "Setup Guide…", comment: "Status menu item: reopen the first-launch guide"),
                handler: actions.showOnboarding
            ))
        menu.addItem(
            ClosureMenuItem(
                title: String(localized: "User Guide…", comment: "Status menu item: open the user guide window"),
                handler: actions.showUserGuide
            ))
        menu.addItem(
            ClosureMenuItem(
                title: String(localized: "Check for Updates…", comment: "Status menu item"),
                handler: actions.checkForUpdates
            ))
        menu.addItem(
            ClosureMenuItem(
                title: String(localized: "Settings…", comment: "Status menu item"),
                keyEquivalent: ",",
                handler: actions.openSettings
            ))
        menu.addItem(.separator())
        let quitTitle = String(localized: "Quit Cubby", comment: "Menu item")
        menu.addItem(
            ClosureMenuItem(title: quitTitle, keyEquivalent: "q") {
                NSApp.terminate(nil)
            })
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
