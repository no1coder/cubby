import AppKit

/// 菜单栏应用不显示主菜单，但 ⌘C / ⌘V / ⌘A 等编辑快捷键依赖主菜单分发，
/// 缺少时搜索框和设置中的文本框无法使用这些快捷键
@MainActor
enum MainMenu {
    static func make() -> NSMenu {
        let mainMenu = NSMenu()
        mainMenu.addItem(submenuItem(appMenu()))
        mainMenu.addItem(submenuItem(editMenu()))
        return mainMenu
    }

    private static func appMenu() -> NSMenu {
        let menu = NSMenu(title: "Cubby")
        menu.addItem(
            withTitle: String(localized: "Close Window", comment: "Menu item"),
            action: #selector(NSWindow.performClose(_:)),
            keyEquivalent: "w"
        )
        menu.addItem(
            withTitle: String(localized: "Quit Cubby", comment: "Menu item"),
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q"
        )
        return menu
    }

    private static func editMenu() -> NSMenu {
        let menu = NSMenu(title: String(localized: "Edit", comment: "Menu title"))
        menu.addItem(
            withTitle: String(localized: "Undo", comment: "Menu item"),
            action: Selector(("undo:")),
            keyEquivalent: "z"
        )
        let redo = menu.addItem(
            withTitle: String(localized: "Redo", comment: "Menu item"),
            action: Selector(("redo:")),
            keyEquivalent: "z"
        )
        redo.keyEquivalentModifierMask = [.command, .shift]
        menu.addItem(.separator())
        menu.addItem(
            withTitle: String(localized: "Cut", comment: "Menu item"),
            action: #selector(NSText.cut(_:)),
            keyEquivalent: "x"
        )
        // 编辑菜单的「拷贝」与面板里的「复制」中文用词不同，英文相同，因此用独立的键
        menu.addItem(
            withTitle: String(localized: "menu.edit.copy", defaultValue: "Copy", comment: "Edit menu item"),
            action: #selector(NSText.copy(_:)),
            keyEquivalent: "c"
        )
        menu.addItem(
            withTitle: String(localized: "Paste", comment: "Menu item"),
            action: #selector(NSText.paste(_:)),
            keyEquivalent: "v"
        )
        menu.addItem(
            withTitle: String(localized: "Select All", comment: "Menu item"),
            action: #selector(NSText.selectAll(_:)),
            keyEquivalent: "a"
        )
        return menu
    }

    private static func submenuItem(_ submenu: NSMenu) -> NSMenuItem {
        let item = NSMenuItem(title: submenu.title, action: nil, keyEquivalent: "")
        item.submenu = submenu
        return item
    }
}
