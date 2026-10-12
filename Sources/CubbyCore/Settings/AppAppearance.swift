import AppKit

/// 界面外观：跟随系统（默认），或固定为浅色 / 深色。作用于应用的全部窗口（面板、预览、晾衣绳、设置、引导等）
public enum AppAppearance: String, CaseIterable, Sendable {
    case system
    case light
    case dark

    public var displayName: String {
        switch self {
        case .system: String(localized: "Match System", comment: "Appearance option: follow the macOS appearance")
        case .light: String(localized: "Light", comment: "Appearance option")
        case .dark: String(localized: "Dark", comment: "Appearance option")
        }
    }

    /// 赋给 NSApp.appearance 的外观名；跟随系统时为 nil（不覆盖，随 macOS 外观自动切换）
    public var appearanceName: NSAppearance.Name? {
        switch self {
        case .system: nil
        case .light: .aqua
        case .dark: .darkAqua
        }
    }
}
