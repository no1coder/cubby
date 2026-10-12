import AppKit
import CubbyCore

/// 菜单栏菜单（docs/design/ui-upgrade MenuBar 画板）：
/// 新版本 / 剪贴板权限提醒 → 头部（图标、Cubby、状态）→ 打开 / 只看图片 / 截图 / 晾衣绳
/// → 面板位置 ›、外观 › → 暂停记录、清空历史 → 使用说明、设置引导、检查更新、设置、退出
@MainActor
final class StatusBarMenu: NSObject, NSMenuDelegate {
    let menu = NSMenu()
    private let settings: AppSettings
    /// 历史条数（头部状态行）
    private let itemCount: () -> Int
    /// 有还没处理的地址替换（头部状态行变成红色「地址被替换」）
    var tamperPending: () -> Bool = { false }
    private let header = StatusMenuHeaderView()
    private let headerItem = NSMenuItem()
    private let openItem: ClosureMenuItem
    private let imagesItem: ClosureMenuItem
    private let screenshotItem: ClosureMenuItem
    private let clotheslineItem: ClosureMenuItem
    private let pauseItem = ClosureMenuItem(title: "", handler: {})
    private let accessWarningItem = ClosureMenuItem(
        title: String(localized: "Allow Clipboard Access…", comment: "Status menu item")
    ) {
        PasteboardAccess.openSettings()
    }
    private let panelPositionItem: PanelPositionMenuItem
    private let appearanceItem: AppearanceMenuItem
    /// 已知有新版本时显示在菜单顶部（U5）
    private let updateAvailableItem = ClosureMenuItem(title: "", handler: {})

    init(settings: AppSettings, actions: StatusBarController.Actions) {
        self.settings = settings
        itemCount = actions.itemCount
        openItem = ClosureMenuItem(title: Self.openTitle) { actions.togglePanel(nil) }
        imagesItem = ClosureMenuItem(title: Self.imagesTitle, handler: actions.showOnlyImages)
        screenshotItem = ClosureMenuItem(title: Self.screenshotTitle, handler: actions.takeScreenshot)
        clotheslineItem = ClosureMenuItem(title: "", handler: actions.toggleClothesline)
        panelPositionItem = PanelPositionMenuItem(settings: settings)
        appearanceItem = AppearanceMenuItem(settings: settings)
        super.init()
        pauseItem.handler = { [weak settings] in settings?.isPaused.toggle() }
        accessWarningItem.image = NSImage(
            systemSymbolName: "exclamationmark.triangle.fill", accessibilityDescription: nil)
        updateAvailableItem.image = NSImage(systemSymbolName: "arrow.down.circle.fill", accessibilityDescription: nil)?
            .withSymbolConfiguration(NSImage.SymbolConfiguration(hierarchicalColor: .controlAccentColor))
        updateAvailableItem.isHidden = true
        headerItem.view = header
        // 只是展示：键盘 ↑↓ 不停在这一行
        headerItem.isEnabled = false
        build(actions)
        refresh()
    }

    // MARK: - NSMenuDelegate

    func menuNeedsUpdate(_ menu: NSMenu) {
        refresh()
    }

    /// 打开菜单前刷新：头部状态、全局快捷键、晾衣绳张数、子菜单当前值、暂停 / 继续
    func refresh() {
        header.statusLine = StatusMenuHeaderView.statusLine(
            paused: settings.isPaused, itemCount: itemCount(), tamperPending: tamperPending())
        openItem.attributedTitle = Self.titleWithShortcut(Self.openTitle, settings.hotKey)
        imagesItem.attributedTitle = Self.titleWithShortcut(Self.imagesTitle, settings.imagesHotKey)
        // 截图快捷键已关闭时只显示标题
        screenshotItem.attributedTitle = Self.titleWithShortcut(Self.screenshotTitle, settings.screenshotHotKey)
        refreshClotheslineItem()
        panelPositionItem.refresh()
        appearanceItem.refresh()
        pauseItem.title =
            settings.isPaused
            ? String(localized: "Resume Recording", comment: "Status menu item while recording is paused")
            : String(localized: "Pause Recording", comment: "Status menu item")
        accessWarningItem.isHidden = !PasteboardAccess.needsAttention
    }

    /// 已知有新版本：菜单顶部显示醒目的「新版本 x 可用…」，点击打开发布页；升级后隐藏
    func refreshUpdateItem(_ release: KnownRelease?, updates: UpdateCoordinator) {
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

    // MARK: - 私有

    private func build(_ actions: StatusBarController.Actions) {
        menu.delegate = self
        // 菜单项的可用状态由我们在 refresh 里设置（例如绳上为空时「显示晾衣绳」置灰）
        menu.autoenablesItems = false
        let groups: [[NSMenuItem]] = [
            [updateAvailableItem, accessWarningItem, headerItem],
            [openItem, imagesItem, screenshotItem, clotheslineItem],
            [panelPositionItem, appearanceItem],
            [pauseItem, item(String(localized: "Clear History…", comment: "Status menu item"), actions.clearHistory)],
            [
                item(
                    String(localized: "User Guide", comment: "Status menu item: open the user guide window"),
                    actions.showUserGuide),
                item(
                    String(localized: "Setup Guide…", comment: "Status menu item: reopen the first-launch guide"),
                    actions.showOnboarding),
                item(String(localized: "Check for Updates…", comment: "Status menu item"), actions.checkForUpdates),
                item(String(localized: "Settings…", comment: "Status menu item"), key: ",", actions.openSettings),
                item(String(localized: "Quit Cubby", comment: "Menu item"), key: "q") { NSApp.terminate(nil) },
            ],
        ]
        for (index, group) in groups.enumerated() {
            if index > 0 { menu.addItem(.separator()) }
            group.forEach(menu.addItem)
        }
    }

    private func item(_ title: String, key: String = "", _ handler: @escaping () -> Void) -> ClosureMenuItem {
        ClosureMenuItem(title: title, keyEquivalent: key, handler: handler)
    }

    /// 「显示晾衣绳 · 4 张」+ 快捷键；关闭了晾衣绳时隐藏，绳上为空时置灰
    private func refreshClotheslineItem() {
        clotheslineItem.isHidden = !settings.clotheslineEnabled
        let count = settings.clothesline.count
        let title = String(
            localized: "Show Clothesline · \(count) photos",
            comment: "Status menu item that slides the clothesline down. %lld = number of photos on it")
        clotheslineItem.attributedTitle = Self.titleWithShortcut(title, settings.clotheslineHotKey)
        clotheslineItem.isEnabled = count > 0
    }

    /// 全局快捷键无法用 keyEquivalent 表达：以次要颜色写在标题右侧；快捷键关闭时只有标题
    private static func titleWithShortcut(_ title: String, _ hotKey: HotKey?) -> NSAttributedString {
        hotKey.map { StatusBarController.titleWithDetail(title, detail: $0.displayName) }
            ?? NSAttributedString(string: title)
    }

    private static var openTitle: String {
        String(localized: "Open Clipboard", comment: "Status menu item: open the panel")
    }

    private static var imagesTitle: String {
        String(localized: "Only Images", comment: "Status menu item: open the panel on the image grid")
    }

    private static var screenshotTitle: String {
        String(localized: "Take Screenshot", comment: "Status menu item and panel button tooltip")
    }
}
