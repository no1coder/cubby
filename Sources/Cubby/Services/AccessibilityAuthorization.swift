import AppKit
import CubbyCore

/// 辅助功能授权状态，区分「从未授权」与「授权已失效」。
///
/// 系统授权条目绑定代码签名：更新到签名不同的版本（例如 ad-hoc、Apple Development 与 Developer ID 交替安装）后，
/// 系统设置里的开关仍显示开启，但 AXIsProcessTrusted() 返回 false（判断逻辑见 SignedGrant）。
@MainActor
enum AccessibilityAuthorization {
    typealias Status = SignedGrantStatus

    static let record = SignedGrantRecord(defaultsKey: "accessibilityGrantedIdentity", tccService: "Accessibility")

    static var status: Status {
        record.status(isGranted: PasteService.isTrusted)
    }

    /// 引导授权：授权失效时只打开系统设置（先移除旧条目才能重新授权），否则同时触发系统授权提示
    static func requestOrOpenSettings() {
        if status != .stale {
            PasteService.requestTrust()
        }
        PasteService.openAccessibilitySettings()
    }
}
