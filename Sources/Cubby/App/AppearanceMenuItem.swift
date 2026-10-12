import AppKit
import CubbyCore

/// 菜单栏菜单的「外观 ›」：子菜单列出三个选项（当前项打勾），父项右侧以次要颜色显示当前值
@MainActor
final class AppearanceMenuItem: NSMenuItem {
    private let settings: AppSettings
    private var options: [(appearance: AppAppearance, item: NSMenuItem)] = []

    init(settings: AppSettings) {
        self.settings = settings
        super.init(title: Self.title, action: nil, keyEquivalent: "")
        let menu = NSMenu()
        for appearance in AppAppearance.allCases {
            let item = ClosureMenuItem(title: appearance.displayName) { [weak settings] in
                settings?.appearance = appearance
            }
            menu.addItem(item)
            options.append((appearance, item))
        }
        submenu = menu
        refresh()
    }

    @available(*, unavailable)
    required init(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    /// 菜单打开前调用：当前值与勾选状态
    func refresh() {
        let current = settings.appearance
        attributedTitle = StatusBarController.titleWithDetail(Self.title, detail: current.displayName)
        for option in options {
            option.item.state = option.appearance == current ? .on : .off
        }
    }

    private static var title: String {
        String(localized: "Appearance", comment: "Status menu item: submenu to choose light, dark or system appearance")
    }
}
