import CubbyCore
import Foundation

/// 面板顶部展示的问题提醒
enum PanelWarning: Hashable, Identifiable {
    /// 未允许读取剪贴板，无法静默记录
    case pasteboardAccess
    /// 未授权辅助功能，无法直接粘贴
    case accessibility
    /// 曾授权但签名变化导致授权失效
    case accessibilityStale
    /// 历史文件读取失败，本次运行不会保存
    case persistenceDisabled
    /// 历史由更新版本的 Cubby 写入，本次只读
    case historyFromNewerVersion
    /// 历史文件曾损坏，已备份后重新开始
    case historyRestored(backupURL: URL)
    /// 从磁盘映像或系统隔离位置运行，权限与开机启动可能无法保留
    case runningFromTemporaryLocation
    /// 用户暂停了记录：复制的内容不会进入历史（优先级低于权限类提醒，排在最后）
    case paused

    /// 打开设置窗口的隐私页（由 AppDelegate 注入）
    @MainActor static var openPrivacySettings: (() -> Void)?
    /// 检查更新（由 AppDelegate 注入）
    @MainActor static var checkForUpdates: (() -> Void)?

    var id: Self { self }

    var title: String {
        switch self {
        case .pasteboardAccess:
            String(localized: "Clipboard access isn't allowed", comment: "Panel warning title")
        case .accessibility:
            String(localized: "Cubby can only copy for now", comment: "Panel warning title")
        case .accessibilityStale:
            String(localized: "Direct paste stopped working", comment: "Panel warning title")
        case .persistenceDisabled:
            String(localized: "History can't be saved", comment: "Panel warning title")
        case .runningFromTemporaryLocation:
            String(localized: "Move Cubby to the Applications folder", comment: "Panel warning title")
        case .historyFromNewerVersion:
            String(localized: "History was created by a newer version of Cubby", comment: "Panel warning title")
        case .historyRestored:
            String(localized: "History file was damaged, starting over", comment: "Panel warning title")
        case .paused:
            String(localized: "Recording paused", comment: "Panel warning title when clipboard recording is paused")
        }
    }

    /// 系统设置中的面板名称随版本变化：macOS 26 为「从其他 App 粘贴」，15.4–15.x 为「粘贴」
    private static var pasteboardAccessDetail: String {
        if #available(macOS 26, *) {
            return String(
                localized: """
                    Set Cubby to “Allow” in Privacy & Security › Paste from Other Apps so macOS stops asking \
                    every time you copy.
                    """,
                comment: "Panel warning detail on macOS 26. Use the name of the pane in System Settings."
            )
        }
        return String(
            localized: """
                Set Cubby to “Allow” in Privacy & Security › Paste so macOS stops asking every time you copy.
                """,
            comment: "Panel warning detail on macOS 15. Use the name of the pane in System Settings."
        )
    }

    var detail: String {
        switch self {
        case .pasteboardAccess:
            Self.pasteboardAccessDetail
        case .accessibility:
            String(
                localized: "Allow Cubby in Privacy & Security › Accessibility.",
                comment: "Panel warning detail. Use the name of the pane in System Settings."
            )
        case .accessibilityStale:
            String(
                localized: """
                    The app's signature changed after an update, so the old Accessibility entry no longer applies.
                    """,
                comment: "Panel warning detail"
            )
        case .persistenceDisabled:
            String(
                localized: "Couldn't read the history file. Items copied during this session won't be saved to disk.",
                comment: "Panel warning detail"
            )
        case .runningFromTemporaryLocation:
            String(
                localized: """
                    Cubby is running from a disk image or a quarantined location, \
                    so permissions and launch at login may not be kept.
                    """,
                comment: "Panel warning detail"
            )
        case .historyFromNewerVersion:
            String(
                localized: """
                    To avoid data loss, history is read-only for now and new copies won't be saved. \
                    Please update to the latest version.
                    """,
                comment: "Panel warning detail"
            )
        case .historyRestored:
            String(
                localized: "The original file was backed up. You can find it in Finder.",
                comment: "Panel warning detail"
            )
        case .paused:
            String(
                localized: "Items you copy while paused aren't saved.",
                comment: "Panel warning detail when clipboard recording is paused"
            )
        }
    }

    /// 权限类按钮的用词与设置页、引导页一致：能弹出系统授权对话框的用「Grant Access」，
    /// 只能跳转到系统设置的用「Open System Settings」
    var actionTitle: String {
        switch self {
        case .pasteboardAccess:
            String(localized: "Open System Settings", comment: "Button: open the pane in System Settings")
        case .accessibility:
            String(localized: "Grant Access", comment: "Button: ask macOS for the permission")
        case .accessibilityStale:
            String(localized: "Fix…", comment: "Panel warning button: show how to renew Accessibility access")
        case .persistenceDisabled:
            String(localized: "Show File", comment: "Panel warning button: reveal the history file in Finder")
        case .runningFromTemporaryLocation:
            String(localized: "Show in Finder", comment: "Button")
        case .historyFromNewerVersion:
            String(localized: "Check for Updates", comment: "Button")
        case .historyRestored:
            String(localized: "Show Backup", comment: "Panel warning button: reveal the backup file in Finder")
        case .paused:
            String(localized: "Resume", comment: "Panel warning button: resume clipboard recording")
        }
    }

    /// 「稍后」只用于可以暂时忽略的提醒；暂停记录是用户的主动选择，唯一的出口是恢复
    var isDismissible: Bool {
        self != .paused
    }

    /// 提醒的具体状态；用户点「稍后」后状态发生变化（例如由询问变为拒绝）时会再次显示
    @MainActor
    var stateSignature: String {
        switch self {
        case .pasteboardAccess: PasteboardAccess.status.rawValue
        default: "active"
        }
    }

    @MainActor
    func performAction(settings: AppSettings) {
        switch self {
        case .pasteboardAccess: PasteboardAccess.openSettings()
        case .accessibility: AccessibilityAuthorization.requestOrOpenSettings()
        case .accessibilityStale:
            if let open = Self.openPrivacySettings { open() } else { PasteService.openAccessibilitySettings() }
        case .persistenceDisabled: ItemOpener.revealInFinder([AppPaths.historyFile.path])
        case .runningFromTemporaryLocation: ItemOpener.revealInFinder([Bundle.main.bundlePath])
        case .historyFromNewerVersion: Self.checkForUpdates?()
        case .historyRestored(let backupURL): ItemOpener.revealInFinder([backupURL.path])
        case .paused: settings.isPaused = false
        }
    }

    /// 根据当前状态计算需要展示的提醒
    @MainActor
    static func current(pasteDirectly: Bool, isPaused: Bool, loadIssue: ClipStore.LoadIssue?) -> [PanelWarning] {
        var warnings: [PanelWarning] = []
        if InstallLocation.isTemporary { warnings.append(.runningFromTemporaryLocation) }
        switch loadIssue {
        case nil: break
        case .newerVersion: warnings.append(.historyFromNewerVersion)
        case .unreadable: warnings.append(.persistenceDisabled)
        case .restoredFromCorruption(let backupURL): warnings.append(.historyRestored(backupURL: backupURL))
        }
        if PasteboardAccess.needsAttention { warnings.append(.pasteboardAccess) }
        if pasteDirectly {
            switch AccessibilityAuthorization.status {
            case .granted: break
            case .notGranted: warnings.append(.accessibility)
            case .stale: warnings.append(.accessibilityStale)
            }
        }
        if isPaused { warnings.append(.paused) }
        return warnings
    }
}

/// 应用的安装位置
enum InstallLocation {
    /// 从挂载的磁盘映像（/Volumes）或 Gatekeeper 隔离路径（AppTranslocation）运行
    static var isTemporary: Bool {
        let path = Bundle.main.bundlePath
        return path.hasPrefix("/Volumes/") || path.contains("/AppTranslocation/")
    }

    static var description: String {
        let path = Bundle.main.bundlePath
        if path.contains("/AppTranslocation/") {
            return String(
                localized: "\(path) (App Translocation)",
                comment: "Diagnostics: install location under App Translocation"
            )
        }
        if path.hasPrefix("/Volumes/") {
            return String(localized: "\(path) (disk image)", comment: "Diagnostics: install location on a disk image")
        }
        return path
    }
}
