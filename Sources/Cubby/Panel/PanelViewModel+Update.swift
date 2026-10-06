import AppKit
import CubbyCore

/// 面板顶部的更新横幅（docs/UPDATE-REMINDER-DESIGN.md U4–U9）：状态来自 UpdateCoordinator，
/// 「稍后」按版本持久化（不同于权限提醒只在本次运行内收起）
extension PanelViewModel {
    /// 复制升级命令后按钮显示「已复制」的时长
    static let copiedFeedbackDuration: Duration = .seconds(2)

    /// 实时的更新横幅：查到新版本、点了按钮或升级后立即变化
    var updateWarning: PanelWarning? {
        PanelWarning.update(from: updates)
    }

    /// 主按钮的标题：Homebrew 变体复制成功后短暂显示「已复制」
    func actionTitle(for warning: PanelWarning) -> String {
        if case .updateAvailable(let notice) = warning, notice.viaHomebrew, upgradeCommandFeedback.isShowing {
            return UpdateCopy.copied
        }
        return warning.actionTitle
    }

    /// 更新横幅的主按钮：「查看并下载」打开发布页，Homebrew 变体复制升级命令，询问横幅的「提醒我」。返回是否处理
    func performUpdateAction(_ warning: PanelWarning) -> Bool {
        switch warning {
        case .updateAvailable(let notice) where notice.viaHomebrew:
            copyUpgradeCommand()
        case .updateAvailable(let notice):
            updates?.openRelease(notice.release)
        case .updatePermission:
            updates?.enableReminders()
        default:
            return false
        }
        return true
    }

    /// Homebrew 变体：复制命令并留在面板，按钮短暂显示「已复制」并播报给读屏器；写入失败时提示音
    private func copyUpgradeCommand() {
        guard updates?.copyUpgradeCommand() == true else {
            NSSound.beep()
            return
        }
        upgradeCommandFeedback.flash(for: Self.copiedFeedbackDuration)
        AccessibilityAnnouncement.post(UpdateCopy.copied)
    }

    /// 第二个按钮：Homebrew 变体的「更新内容」
    func performSecondaryAction(for warning: PanelWarning) {
        guard case .updateAvailable(let notice) = warning else { return }
        updates?.openRelease(notice.release)
    }

    /// 更新横幅的收起：新版本横幅记住这个版本（U6），询问横幅记为「不用了」（U4）。返回是否处理
    func dismissUpdateWarning(_ warning: PanelWarning) -> Bool {
        switch warning {
        case .updateAvailable(let notice):
            updates?.dismissBanner(for: notice.release)
        case .updatePermission:
            updates?.declineReminders()
        default:
            return false
        }
        return true
    }
}
