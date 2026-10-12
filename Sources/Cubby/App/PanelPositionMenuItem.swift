import AppKit
import CubbyCore

/// 菜单栏菜单的「面板位置 ›」：子菜单先列三个浮动位置，分隔线后是两个停靠位置（当前项打勾），
/// 父项右侧以次要颜色显示当前值（docs/UI-UPGRADE-PLAN.md 第 3 节）
@MainActor
final class PanelPositionMenuItem: NSMenuItem {
    private let settings: AppSettings
    private var options: [(position: PanelPosition, item: NSMenuItem)] = []

    init(settings: AppSettings) {
        self.settings = settings
        super.init(title: Self.title, action: nil, keyEquivalent: "")
        let menu = NSMenu()
        let floating = PanelPosition.allCases.filter { $0.layout == .floating }
        let docked = PanelPosition.allCases.filter { $0.layout != .floating }
        for position in floating {
            menu.addItem(makeItem(for: position))
        }
        // 浮动与停靠两组之间用分隔线隔开
        menu.addItem(.separator())
        for position in docked {
            menu.addItem(makeItem(for: position))
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
        let current = settings.panelPosition
        attributedTitle = StatusBarController.titleWithDetail(Self.title, detail: current.displayName)
        for option in options {
            option.item.state = option.position == current ? .on : .off
        }
    }

    private func makeItem(for position: PanelPosition) -> NSMenuItem {
        let item = ClosureMenuItem(title: position.displayName) { [weak settings] in
            settings?.panelPosition = position
        }
        options.append((position, item))
        return item
    }

    private static var title: String {
        String(
            localized: "Panel Position",
            comment: "Status menu item: submenu to choose where the panel appears (floating or docked)"
        )
    }
}
