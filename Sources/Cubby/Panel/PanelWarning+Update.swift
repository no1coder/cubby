import CubbyCore
import Foundation

/// 新版本横幅要显示的内容（docs/UPDATE-REMINDER-DESIGN.md U5、U8）
struct UpdateNotice: Hashable {
    let release: KnownRelease
    let currentVersion: String
    /// 用 Homebrew 安装：主按钮改为复制升级命令，另有「更新内容」
    let viaHomebrew: Bool
}

/// 横幅的外观与按钮组合：权限等问题为橙色，更新提醒为强调色（U9）
extension PanelWarning {
    enum Style {
        /// 需要处理的问题（橙色）
        case attention
        /// 信息提示（强调色）
        case informational
    }

    var style: Style {
        switch self {
        case .updateAvailable, .updatePermission: .informational
        default: .attention
        }
    }

    var symbolName: String {
        switch self {
        case .updateAvailable: "arrow.down.circle.fill"
        case .updatePermission: "questionmark.circle.fill"
        case .paused: "pause.circle.fill"
        default: "exclamationmark.triangle.fill"
        }
    }

    /// 第二个按钮（Homebrew 变体的「更新内容」）；nil 表示没有
    var secondaryActionTitle: String? {
        guard case .updateAvailable(let notice) = self, notice.viaHomebrew else { return nil }
        return UpdateCopy.releaseNotes
    }

    /// 收起按钮：询问横幅是「不用了」，其余是「稍后」
    var dismissTitle: String {
        self == .updatePermission
            ? UpdateCopy.noThanks
            : String(localized: "Not Now", comment: "Button")
    }

    /// 面板 E2E 定位按钮用的名称
    var anchorKey: String {
        switch self {
        case .updateAvailable: "update"
        case .updatePermission: "update-permission"
        case .paused: "paused"
        default: "warning"
        }
    }

    /// 当前要显示的更新横幅（随设置实时变化）；没有接线或不需要提醒时为 nil
    @MainActor
    static func update(from updates: UpdateCoordinator?) -> PanelWarning? {
        guard let updates else { return nil }
        switch updates.reminder.banner {
        case .available(let release):
            return .updateAvailable(
                UpdateNotice(
                    release: release, currentVersion: updates.currentVersion, viaHomebrew: updates.isHomebrewInstall))
        case .askPermission:
            return .updatePermission
        case nil:
            return nil
        }
    }

    /// 更新横幅排在权限类提醒之后、「已暂停记录」之前（U9）
    static func inserting(_ update: PanelWarning?, into warnings: [PanelWarning]) -> [PanelWarning] {
        guard let update else { return warnings }
        let paused = warnings.filter { $0 == .paused }
        return warnings.filter { $0 != .paused } + [update] + paused
    }
}
