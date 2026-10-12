#if DEBUG
import AppKit

/// 调试构建：--dump-status-menu [tamper] 把菜单栏菜单的结构打印到标准输出后退出（菜单无法截图，用它自检）
extension StatusBarMenu {
    static let dumpArgument = "--dump-status-menu"

    /// nil：没有请求；true：同时模拟一条未处理的地址替换
    static var dumpRequest: Bool? {
        let arguments = CommandLine.arguments
        guard let index = arguments.firstIndex(of: dumpArgument) else { return nil }
        return arguments.indices.contains(index + 1) && arguments[index + 1] == "tamper"
    }

    /// 每行一项：分隔线、标题（含右侧补充信息）、keyEquivalent、隐藏 / 置灰 / 勾选；子菜单缩进
    func dump() -> String {
        menuNeedsUpdate(menu)
        return Self.lines(of: menu, depth: 0).joined(separator: "\n")
    }

    private static func lines(of menu: NSMenu, depth: Int) -> [String] {
        let indent = String(repeating: "    ", count: depth)
        return menu.items.flatMap { item -> [String] in
            var line = indent + describe(item)
            var flags: [String] = []
            if item.isHidden { flags.append("hidden") }
            if !item.isEnabled { flags.append("disabled") }
            if item.state == .on { flags.append("checked") }
            if !flags.isEmpty { line += "  [" + flags.joined(separator: ", ") + "]" }
            let children = item.submenu.map { lines(of: $0, depth: depth + 1) } ?? []
            return [line] + children
        }
    }

    private static func describe(_ item: NSMenuItem) -> String {
        if item.isSeparatorItem { return "----" }
        if let header = item.view as? StatusMenuHeaderView {
            let line = header.statusLine
            return "[header] Cubby | \(line.text)" + (line.isAlert ? " (red)" : "")
        }
        var text = item.attributedTitle?.string ?? item.title
        text = text.replacingOccurrences(of: "    ", with: " | ")
        if !item.keyEquivalent.isEmpty {
            text += "  ⌘" + item.keyEquivalent.uppercased()
        }
        return text
    }
}

extension StatusBarController {
    func debugDumpMenu(tamper: Bool) -> String {
        if tamper { setTamperPill(true) }
        return debugStatusMenu.dump()
    }
}
#endif
