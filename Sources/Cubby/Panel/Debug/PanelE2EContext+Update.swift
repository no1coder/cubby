#if DEBUG
import AppKit
import CubbyCore

/// 更新提醒脚本的辅助（docs/UPDATE-REMINDER-DESIGN.md §2）：写好设置再启动协调器、读当前的更新横幅、
/// 用一个独立按钮检查菜单栏蓝点（与 StatusBarController 同一个函数，不在真实菜单栏里加图标）
@MainActor
extension PanelE2EContext {
    var updates: UpdateCoordinator {
        world.updates
    }

    var updateStub: PanelE2EUpdateStub {
        world.updateStub
    }

    var settings: AppSettings {
        world.settings
    }

    /// 当前显示的更新横幅（强调色那一条）
    var updateBanner: PanelWarning? {
        viewModel.visibleWarnings.first { $0.style == .informational }
    }

    /// 完成过欢迎页的用户：自动检查的开关、是否回答过询问；最近刚检查过时 start() 不会联网
    func seedUser(checksAutomatically: Bool, answered: Bool = true, checkedRecently: Bool = false) {
        settings.hasCompletedOnboarding = true
        if checksAutomatically || answered {
            settings.answerUpdatePrompt(remindMe: checksAutomatically)
        }
        if checkedRecently { settings.lastUpdateCheck = Date() }
    }

    /// 直接记住一个已知的新版本（不经过检查）
    func seedKnownRelease(_ version: String) throws {
        guard let release = KnownRelease(version: version, releaseURL: PanelE2EUpdateStub.releaseURL) else {
            throw PanelE2EError.missingItem("release \(version)")
        }
        settings.rememberAvailableRelease(release)
    }

    /// 收起再打开面板
    func reopen() async throws {
        world.panel.hide(animated: false)
        try await settle()
        try await open()
    }

    /// 模拟重启（可同时模拟升级到 version）后重新打开面板
    func relaunch(currentVersion: String? = nil) async throws {
        world.relaunch(currentVersion: currentVersion)
        try await settle()
        try await open()
    }

    /// 按协调器当前的状态给一个独立按钮套上菜单栏图标的外观，检查蓝点是否可见、读屏名称，以及蓝点是否在图标右上角
    func checkStatusItemDot(expectVisible: Bool) {
        // 与菜单栏里的方形图标按钮同样大小、只显示图标
        let side = NSStatusBar.system.thickness
        let button = NSButton(frame: CGRect(x: 0, y: 0, width: side, height: side))
        button.isBordered = false
        button.title = ""
        button.imagePosition = .imageOnly
        let badge = StatusItemUpdateBadge(button: button)
        let release = updates.reminder.availableRelease
        StatusBarController.applyAppearance(to: button, badge: badge, paused: false, release: release)
        check(expectVisible ? "the menu bar dot shows" : "the menu bar dot is gone", badge.isVisible == expectVisible)
        checkEqual(
            "VoiceOver reads the status item accordingly",
            UpdateCopy.statusItemAccessibility(paused: false, updateAvailable: expectVisible),
            button.image?.accessibilityDescription)
        guard expectVisible else { return }
        let dot = badge.frame
        let isTop = button.isFlipped ? dot.midY < button.bounds.midY : dot.midY > button.bounds.midY
        check(
            "the dot sits at the top right of the icon",
            button.bounds.contains(dot) && dot.midX > button.bounds.midX && isTop,
            detail: "dot \(dot) in \(button.bounds)")
    }
}
#endif
