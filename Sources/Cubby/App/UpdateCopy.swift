import CubbyCore
import Foundation

/// 更新提醒的文案（菜单栏、面板横幅、「关于」页、欢迎页与设置共用，docs/UPDATE-REMINDER-DESIGN.md）
enum UpdateCopy {
    static func versionAvailable(_ version: String) -> String {
        String(
            localized: "Version \(version) is available",
            comment: "Update alert title, panel banner title and About pane. %@ = new version"
        )
    }

    static func menuItem(_ version: String) -> String {
        String(
            localized: "Version \(version) Available…",
            comment: "Status menu item shown when an update is available"
        )
    }

    static func runningVersion(_ current: String) -> String {
        String(localized: "You're running \(current).", comment: "Update banner detail. %@ = installed version")
    }

    /// Homebrew 安装时的说明：命令本身不翻译
    static var homebrewHint: String {
        String(
            localized: "Run \(HomebrewInstall.upgradeCommand) in Terminal to upgrade.",
            comment: "Update banner detail for Homebrew installs. %@ = the brew command, keep it as is"
        )
    }

    static var viewAndDownload: String {
        String(localized: "View & Download", comment: "Button: open the release page of the new version")
    }

    static var copyUpgradeCommand: String {
        String(localized: "Copy Upgrade Command", comment: "Button: copy the brew upgrade command")
    }

    static var copied: String {
        String(localized: "Copied", comment: "Button title right after copying")
    }

    static var releaseNotes: String {
        String(localized: "Release Notes", comment: "Button: open the release page to read what's new")
    }

    static var askTitle: String {
        String(localized: "Remind you about new versions?", comment: "Panel banner asking to turn on update checks")
    }

    static var askDetail: String {
        String(
            localized: """
                Reads the latest version number from GitHub once a day and never uploads any data. \
                You can change this later in Settings › General.
                """,
            comment: "Panel banner asking to turn on update checks"
        )
    }

    static var remindMe: String {
        String(localized: "Remind Me", comment: "Button: turn on automatic update checks")
    }

    static var noThanks: String {
        String(localized: "No Thanks", comment: "Button: keep automatic update checks off")
    }

    static func statusItemToolTip(_ version: String) -> String {
        String(
            localized: "Cubby · Version \(version) available",
            comment: "Status item tooltip when an update is available")
    }

    /// 菜单栏图标的读屏名称：有新版本时注明（蓝点本身对读屏器隐藏）
    static func statusItemAccessibility(paused: Bool, updateAvailable: Bool) -> String {
        switch (paused, updateAvailable) {
        case (false, false):
            "Cubby"
        case (true, false):
            String(localized: "Cubby (paused)", comment: "Accessibility description of the status item icon")
        case (false, true):
            String(
                localized: "Cubby, update available",
                comment: "Accessibility description of the status item icon when an update is available")
        case (true, true):
            String(
                localized: "Cubby (paused), update available",
                comment: "Accessibility description of the status item icon when paused and an update is available")
        }
    }
}
