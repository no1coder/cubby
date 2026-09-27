import AppKit
import CoreGraphics

/// 屏幕录制权限：截图前检查、首次需要时申请、引导用户打开系统设置。
///
/// 只读取状态、调用系统公开的申请接口、打开系统设置对应面板；
/// 从不修改系统设置或 TCC 数据库（授权与否始终由用户在系统设置中决定）。
@MainActor
enum ScreenRecordingAuthorization {
    enum Status: String {
        case granted
        case denied
    }

    /// 系统设置 › 隐私与安全性 › 录屏与系统录音（macOS 26，英文 Screen & System Audio Recording；
    /// macOS 14 上叫「屏幕录制」/ Screen Recording）
    private static let settingsURL = URL(
        string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture"
    )
    /// 本次启动是否已调用过系统申请（系统只在首次显示弹窗，重复调用没有意义）
    private static var hasRequestedThisLaunch = false

    /// 不触发任何弹窗的状态检查。注意：授权后 macOS 常要求重启应用，本进程才会读到 granted
    static var status: Status {
        CGPreflightScreenCaptureAccess() ? .granted : .denied
    }

    /// 申请权限：每次启动最多调用一次 CGRequestScreenCaptureAccess
    /// （首次会显示系统弹窗，并把 Cubby 加入系统设置的列表）；返回当前是否已授权
    @discardableResult
    static func request() -> Bool {
        guard !hasRequestedThisLaunch else { return status == .granted }
        hasRequestedThisLaunch = true
        return CGRequestScreenCaptureAccess()
    }

    /// 打开系统设置中的屏幕录制面板（只打开页面，不做任何修改）
    static func openSettings() {
        guard let settingsURL else { return }
        NSWorkspace.shared.open(settingsURL)
    }

    /// 设置页「打开系统设置」按钮：先申请一次（让 Cubby 出现在列表中），再打开对应面板
    static func requestOrOpenSettings() {
        request()
        openSettings()
    }
}
