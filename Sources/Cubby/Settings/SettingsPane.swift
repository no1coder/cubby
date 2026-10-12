import Foundation

/// 设置分页（侧边栏从上到下的顺序）
enum SettingsPane: CaseIterable, Hashable {
    case general
    case history
    case screenshots
    /// 截图翻译（仅 macOS 26 显示）
    case translation
    /// 剪贴板安全：地址守护（docs/UI-UPGRADE-PLAN.md §6）
    case security
    case privacy
    case about

    var title: String {
        switch self {
        case .general: String(localized: "General", comment: "Settings pane")
        case .history: String(localized: "History", comment: "Settings pane")
        case .screenshots: String(localized: "Screenshots", comment: "Settings pane")
        case .translation: String(localized: "Translation", comment: "Settings pane")
        case .security: String(localized: "Security", comment: "Settings pane: clipboard security (address guard)")
        case .privacy: String(localized: "Privacy", comment: "Settings pane")
        case .about: String(localized: "About", comment: "Settings pane")
        }
    }

    var symbolName: String {
        switch self {
        case .general: "gearshape"
        case .history: "clock.arrow.circlepath"
        case .screenshots: "camera.viewfinder"
        case .translation: "translate"
        case .security: "checkmark.shield"
        case .privacy: "hand.raised"
        case .about: "info.circle"
        }
    }
}
