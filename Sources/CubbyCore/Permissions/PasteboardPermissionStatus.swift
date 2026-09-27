import AppKit

/// 权限按钮的两种动作，决定按钮文案（设置、引导、屏幕录制引导共用同一规则）：
/// 能让系统弹出授权询问的叫「Grant Access」，只能跳转到系统设置的叫「Open System Settings」
public enum PermissionButtonAction: String, Sendable, CaseIterable {
    case grantAccess
    case openSystemSettings
}

/// macOS 15.4+ 读取剪贴板的隐私权限状态（对应 `NSPasteboard.AccessBehavior`；更早的系统不需要授权，由调用方视为已允许）。
///
/// 系统设置 › 隐私与安全性 ›「从其他 App 粘贴」只列出**请求过**权限的应用：
/// 全新安装、从未以编程方式读取过剪贴板时状态为 `notDetermined`，列表里还没有 Cubby，
/// 此时只能由 App 主动读取一次剪贴板让系统弹出询问。
public enum PasteboardPermissionStatus: String, Sendable, CaseIterable {
    /// 「允许」：可以静默读取
    case allowed
    /// 从未询问过
    case notDetermined
    /// 「询问」：每次读取都会弹出系统询问（系统询问框里选过「允许粘贴」或「不允许粘贴」后即为此状态）
    case ask
    /// 「拒绝」
    case denied

    @available(macOS 15.4, *)
    public init(_ behavior: NSPasteboard.AccessBehavior) {
        switch behavior {
        case .alwaysAllow: self = .allowed
        case .default: self = .notDetermined
        case .ask: self = .ask
        case .alwaysDeny: self = .denied
        @unknown default: self = .ask
        }
    }

    /// 已询问过但没有设为「允许」：需要提醒用户去系统设置修改
    public var needsAttention: Bool {
        self == .ask || self == .denied
    }

    /// 权限按钮的动作；已允许时不显示按钮
    public var buttonAction: PermissionButtonAction? {
        switch self {
        case .allowed: nil
        case .notDetermined: .grantAccess
        case .ask, .denied: .openSystemSettings
        }
    }
}
