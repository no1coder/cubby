import SwiftUI
import CubbyCore

/// 权限状态展示（各权限的具体文案见 PermissionState+Permissions.swift）。
/// 用词规则（设置、引导、屏幕录制引导统一）：状态为「Allowed / Not allowed」（与系统设置一致）；
/// 按钮能让系统弹出询问的叫「Grant Access」，只能跳转系统设置的叫「Open System Settings」
struct PermissionState: Equatable {
    enum Level {
        case ok
        case neutral
        case warning
        case error

        var color: Color {
            switch self {
            case .ok: .green
            case .neutral: .secondary
            case .warning: .orange
            case .error: .red
            }
        }

        var symbolName: String {
            switch self {
            case .ok: "checkmark.circle.fill"
            case .neutral: "circle.dashed"
            case .warning: "exclamationmark.triangle.fill"
            case .error: "xmark.octagon.fill"
            }
        }
    }

    let level: Level
    let message: String
    /// 按钮动作；nil 表示不显示按钮（已允许）
    var buttonAction: PermissionButtonAction?
    /// 状态下方的补充说明（例如系统询问框没有「始终允许」，告诉用户之后去哪里修改）
    var note: String?

    var isGranted: Bool { level == .ok }
}

extension PermissionButtonAction {
    var title: LocalizedStringKey {
        switch self {
        case .grantAccess: "Grant Access"
        case .openSystemSettings: "Open System Settings"
        }
    }
}

/// 设置 › 隐私中的权限行：图标、名称、状态（可带补充说明），未允许时右侧显示按钮。
/// 状态由调用方的 PermissionMonitor 轮询提供（用户在系统设置中授权后自动更新）
struct PermissionRow: View {
    let title: LocalizedStringKey
    let systemImage: String
    let state: PermissionState
    /// 正在等待系统询问的结果时禁用按钮，避免重复触发
    var isBusy = false
    let action: @MainActor () -> Void

    private static let iconSpacing: CGFloat = 10

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: Self.iconSpacing) {
                PermissionIcon(systemImage: systemImage, isGranted: state.isGranted)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                    Label(state.message, systemImage: state.level.symbolName)
                        .font(.caption)
                        .foregroundStyle(state.level.color)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 8)
                if let buttonAction = state.buttonAction {
                    Button(buttonAction.title, action: action)
                        .disabled(isBusy)
                }
            }
            // 补充说明放在整行下方（按钮之下），占满宽度、与名称左对齐，避免被按钮挤成多行
            if let note = state.note {
                Text(note)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.leading, PermissionIcon.defaultSize + Self.iconSpacing)
            }
        }
        .animation(.easeOut(duration: 0.2), value: state)
    }
}

/// 权限图标：圆角底板 + SF Symbol，已授权时为绿色
struct PermissionIcon: View {
    static let defaultSize: CGFloat = 28

    let systemImage: String
    let isGranted: Bool
    var size: CGFloat = defaultSize

    /// 底板圆角占边长的比例，与 App 图标（macOS 图标模板）一致
    private static let cornerRatio: CGFloat = Radius.iconRatio
    /// 符号占底板边长的比例（默认 28pt 底板对应 FontSize.callout）
    private static let glyphRatio: CGFloat = 0.5

    var body: some View {
        Image(systemName: systemImage)
            .font(.system(size: size * Self.glyphRatio, weight: .medium))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(
                RoundedRectangle(cornerRadius: size * Self.cornerRatio, style: .continuous)
                    .fill(isGranted ? Color.green.gradient : Color.accentColor.gradient)
            )
            .accessibilityHidden(true)
    }
}
