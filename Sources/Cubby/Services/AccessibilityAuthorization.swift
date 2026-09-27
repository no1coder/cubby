import AppKit
import CubbyCore

/// 辅助功能授权状态，区分「从未授权」与「授权已失效」。
///
/// 系统授权条目绑定代码签名：更新到签名不同的版本（例如 ad-hoc 与 Developer ID 交替安装）后，
/// 系统设置里的开关仍显示开启，但 AXIsProcessTrusted() 返回 false。
/// 这里在每次确认授权有效时记下当时的签名身份；之后若授权无效且签名身份已变化，即判定为失效。
@MainActor
enum AccessibilityAuthorization {
    enum Status: String {
        case granted
        case notGranted
        /// 曾经授权过，但签名变化导致旧授权条目不再匹配
        case stale
    }

    private static let grantedIdentityKey = "accessibilityGrantedIdentity"
    private static let bundleID = Bundle.main.bundleIdentifier ?? "io.github.no1coder.Cubby"

    /// 重置本应用授权的终端命令（只复制给用户执行，应用不代为执行）
    static var resetCommand: String {
        "tccutil reset Accessibility \(bundleID)"
    }

    static var status: Status {
        let identity = SigningInfo.current()?.authorizationKey
        if PasteService.isTrusted {
            if let identity, UserDefaults.standard.string(forKey: grantedIdentityKey) != identity {
                UserDefaults.standard.set(identity, forKey: grantedIdentityKey)
            }
            return .granted
        }
        guard let previous = UserDefaults.standard.string(forKey: grantedIdentityKey),
            let identity, previous != identity
        else { return .notGranted }
        return .stale
    }

    /// 引导授权：授权失效时只打开系统设置（先移除旧条目才能重新授权），否则同时触发系统授权提示
    static func requestOrOpenSettings() {
        if status != .stale {
            PasteService.requestTrust()
        }
        PasteService.openAccessibilitySettings()
    }

    /// 复制到系统剪贴板，并带上自身写入标记，避免被记录进历史
    static func copyResetCommand() {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(resetCommand, forType: .string)
        pasteboard.setData(Data(), forType: PasteboardReader.markerType)
    }
}
