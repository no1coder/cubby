#if DEBUG
import AppKit
import CubbyCore

// 仅调试构建：截图走查的界面场景与面板 E2E 的访问入口

extension PanelController {
    var debugViewModel: PanelViewModel { viewModel }
    var debugPanelWindow: NSWindow { panel }
    var debugDetailWindow: NSWindow { preview.window }
    var debugIsShown: Bool { isShown }

    /// 仅调试构建：复现指定界面状态，便于截图走查（preview / help / toast / search:<关键词> / category:<分类> /
    /// preview:<分类> / contextmenu:<分类> / pin:<分类> / keys:<按键,…>；带分类的场景先切到该分类，再对第一条操作）
    func applyDebugScenario(_ scenario: String) {
        show()
        let parts = scenario.split(separator: ":", maxSplits: 1).map(String.init)
        let argument = parts.count > 1 ? parts[1] : ""
        if parts[0] != "search", let category = ClipCategory(rawValue: argument) {
            viewModel.selectCategory(category)
        }
        switch parts[0] {
        case "preview": viewModel.setPreviewVisible(true)
        case "help": viewModel.toggleHelp()
        case "toast":
            // 会真实删除条目：仅允许在 CUBBY_DATA_DIR 指定的演示数据上运行
            guard ProcessInfo.processInfo.environment["CUBBY_DATA_DIR"] != nil else { break }
            if let item = viewModel.selectedItem { viewModel.delete(item) }
        case "search": viewModel.searchText = argument
        case "contextmenu": PanelDebugInput.rightClickFirstCard(in: panel)
        case "pin": viewModel.handle(.pinToScreen)
        case "keys": PanelDebugInput.postKeys(argument, to: panel)
        default: break
        }
    }
}
#endif
