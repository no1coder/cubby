import SwiftUI
import CubbyCore

/// 各项权限的状态文案与按钮动作（设置 › 隐私、首次引导共用）
extension PermissionState {
    @MainActor
    static var accessibility: PermissionState {
        accessibility(AccessibilityAuthorization.status)
    }

    /// 由已查询到的状态生成展示（查询涉及签名信息，轮询时只查一次）。
    /// 授权失效时 requestOrOpenSettings 只会打开系统设置，按钮随之改名
    static func accessibility(_ status: AccessibilityAuthorization.Status) -> PermissionState {
        switch status {
        case .granted:
            PermissionState(level: .ok, message: allowed)
        case .notGranted:
            PermissionState(
                level: .warning,
                message: String(
                    localized: "Not allowed. Choosing an item only copies it.",
                    comment: "Accessibility permission status"
                ),
                buttonAction: .grantAccess,
                note: alreadyOnNote
            )
        case .stale:
            PermissionState(level: .warning, message: staleMessage, buttonAction: .openSystemSettings)
        }
    }

    /// 屏幕录制只有截图需要：未授权是中性状态，不用警告色；但授权失效说明用户本想使用，按警告显示。
    /// 设置页的按钮会先向系统申请（首次会弹出系统询问），因此叫「Grant Access」
    @MainActor
    static var screenRecording: PermissionState {
        screenRecording(ScreenRecordingAuthorization.status)
    }

    static func screenRecording(_ status: ScreenRecordingAuthorization.Status) -> PermissionState {
        switch status {
        case .granted:
            PermissionState(level: .ok, message: allowed)
        case .notGranted:
            PermissionState(
                level: .neutral,
                message: String(
                    localized: "Not allowed. Only needed for screenshots.",
                    comment: "Screen Recording permission status"
                ),
                buttonAction: .grantAccess,
                note: alreadyOnNote
            )
        case .stale:
            PermissionState(level: .warning, message: staleMessage, buttonAction: .openSystemSettings)
        }
    }

    @MainActor
    static var pasteboard: PermissionState {
        pasteboard(PasteboardAccess.status, clipboardWasEmpty: false)
    }

    /// - Parameter clipboardWasEmpty: 上一次点击「Grant Access」时剪贴板里没有可读的内容（系统因此没有询问）
    @MainActor
    static func pasteboard(_ status: PasteboardPermissionStatus, clipboardWasEmpty: Bool) -> PermissionState {
        guard #available(macOS 15.4, *) else {
            return PermissionState(
                level: .ok,
                message: String(
                    localized: "Not required on this version of macOS",
                    comment: "Clipboard permission status"
                )
            )
        }
        return switch status {
        case .allowed:
            PermissionState(level: .ok, message: allowed)
        case .notDetermined:
            PermissionState(
                level: .warning,
                message: String(
                    localized: "Not allowed yet. Choose “Allow Paste” when asked.",
                    comment: "Clipboard permission status. “Allow Paste” is the button title in the macOS prompt."
                ),
                buttonAction: .grantAccess,
                note: clipboardWasEmpty ? emptyClipboardNote : alwaysAllowNote
            )
        case .ask:
            PermissionState(
                level: .warning,
                message: String(
                    localized: "Set to “Ask”, so macOS will keep asking when you copy",
                    comment: """
                        Clipboard permission status. “Ask” is the option name in \
                        System Settings › Privacy & Security › Paste from Other Apps.
                        """
                ),
                buttonAction: .openSystemSettings
            )
        case .denied:
            PermissionState(
                level: .error,
                message: String(
                    localized: "Not allowed. Cubby can't record the clipboard.",
                    comment: "Clipboard permission status"
                ),
                buttonAction: .openSystemSettings
            )
        }
    }

    // MARK: - 共用文案

    /// 0.3.2 及更早版本没有记下屏幕录制的签名、辅助功能只记了团队 ID，这些用户首次升级时检测不到失效，
    /// 只能报告「未授权」：附上手动修复的说明作为兜底
    static var alreadyOnNote: String {
        String(
            localized: "Already on in System Settings? Remove Cubby with “−”, add it again, then reopen Cubby.",
            comment: "Hint below a permission that isn't allowed, for entries made stale by an update"
        )
    }

    private static var staleMessage: String {
        String(
            localized: "No longer valid (the app's signature changed after an update)",
            comment: "Accessibility / Screen Recording permission status"
        )
    }

    private static var allowed: String {
        String(localized: "Allowed", comment: "Permission status, same wording as System Settings")
    }

    /// 系统询问框只有「允许粘贴 / 不允许粘贴」，没有「始终允许」：提前告诉用户之后去哪里修改
    /// 面板名称随系统版本变化：macOS 26 为「从其他 App 粘贴」，15.4–15.x 为「粘贴」
    private static var alwaysAllowNote: String {
        if #available(macOS 26, *) {
            return String(
                localized: "You can change this later in Privacy & Security › Paste from Other Apps.",
                comment: """
                    Clipboard permission hint below the Grant Access button. “Paste from Other Apps” is the pane \
                    name in System Settings › Privacy & Security (macOS 26).
                    """
            )
        }
        return String(
            localized: "You can change this later in Privacy & Security › Paste.",
            comment: """
                Clipboard permission hint below the Grant Access button. “Paste” is the pane name in \
                System Settings › Privacy & Security (macOS 15).
                """
        )
    }

    private static var emptyClipboardNote: String {
        String(
            localized: "Copy something first, then click Grant Access again.",
            comment: "Clipboard permission hint when the clipboard was empty, so macOS didn't ask"
        )
    }
}
