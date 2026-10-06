import CubbyCore
import SwiftUI

/// 设置 › 关于的更新状态（docs/UPDATE-REMINDER-DESIGN.md U5）：已知有新版本时直接显示版本与按钮
/// （Homebrew 安装为「复制升级命令」+「更新内容」，其余为「查看并下载」）；否则显示最近一次手动检查的结果
struct AboutUpdateStatus: View {
    private static let copiedFeedbackDuration: Duration = .seconds(2)
    /// 版本行与按钮行的间距、按钮之间的间距
    private static let rowSpacing: CGFloat = 6
    private static let buttonSpacing: CGFloat = 8

    let updates: UpdateCoordinator
    /// 在本页点「检查更新」得到的结果；nil 表示还没在本页检查过
    let manualResult: UpdateChecker.Result?

    @State private var copyFeedback = TransientFeedback()

    var body: some View {
        if let release = updates.reminder.availableRelease {
            available(release)
        } else {
            switch manualResult {
            case .upToDate(let current):
                Label("You're up to date (\(current))", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                    .font(.callout)
            case .failed(let reason):
                Label("Couldn't check for updates: \(reason)", systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                    .font(.callout)
            case .available, nil:
                // 查到的新版本已记进设置，由上面的分支显示
                EmptyView()
            }
        }
    }

    /// 复制 Homebrew 升级命令：按钮短暂显示「已复制」并播报给读屏器
    private func copy() {
        guard updates.copyUpgradeCommand() else {
            NSSound.beep()
            return
        }
        copyFeedback.flash(for: Self.copiedFeedbackDuration)
        AccessibilityAnnouncement.post(UpdateCopy.copied)
    }

    private func available(_ release: KnownRelease) -> some View {
        VStack(spacing: Self.rowSpacing) {
            Label(UpdateCopy.versionAvailable(release.version.description), systemImage: "arrow.down.circle.fill")
                .foregroundStyle(Color.accentColor)
                .font(.callout.weight(.medium))
            HStack(spacing: Self.buttonSpacing) {
                if updates.isHomebrewInstall {
                    Button(copyFeedback.isShowing ? UpdateCopy.copied : UpdateCopy.copyUpgradeCommand, action: copy)
                        .buttonStyle(CapsuleButtonStyle())
                    Button(UpdateCopy.releaseNotes) { updates.openRelease(release) }
                        .buttonStyle(CapsuleButtonStyle(isPrimary: false))
                } else {
                    Button(UpdateCopy.viewAndDownload) { updates.openRelease(release) }
                        .buttonStyle(CapsuleButtonStyle())
                }
            }
        }
    }
}
