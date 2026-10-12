import SwiftUI
import CubbyCore

/// 第 1 步「欢迎」：应用图标、标题与一句话介绍，下面一张卡片放两个开关（登录时启动、有新版本时提醒我）
struct OnboardingWelcomeStep: View {
    private static let iconSize: CGFloat = 96
    private static let optionsWidth: CGFloat = 460
    /// 两个勾选项之间的间距；勾选项标题与说明之间的间距
    private static let toggleSpacing: CGFloat = 12
    private static let toggleDetailSpacing: CGFloat = 2

    @Bindable var settings: AppSettings

    var body: some View {
        VStack(spacing: 0) {
            AppIconImage(size: Self.iconSize)
            OnboardingStepHeader(
                title: String(localized: "Welcome to Cubby", comment: "Onboarding window title"),
                subtitle: AppCopy.tagline
            )
            .padding(.top, 16)
            options
                .padding(.top, 32)
        }
        // 欢迎页内容少：在步骤区域里垂直居中（略偏上，留出底部按钮的视觉重量）
        .frame(maxHeight: .infinity)
        .padding(.bottom, 40)
    }

    private var options: some View {
        VStack(alignment: .leading, spacing: Self.toggleSpacing) {
            LaunchAtLoginToggle()
            updateReminderToggle
        }
        .frame(width: Self.optionsWidth, alignment: .leading)
        .padding(.horizontal, 18)
        .padding(.vertical, 16)
        .background(OnboardingCardBackground())
    }

    /// 新用户第一次显示欢迎页时默认勾选；之后只反映当前设置（docs/UPDATE-REMINDER-DESIGN.md U3）
    private var updateReminderToggle: some View {
        Toggle(isOn: $settings.checksForUpdatesAutomatically) {
            VStack(alignment: .leading, spacing: Self.toggleDetailSpacing) {
                Text("Remind me about new versions")
                Text("Reads the latest version number from GitHub once a day")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

/// 引导里各种卡片共用的底：半透明白底 + 0.5pt 描边 + 轻投影（与步骤卡一致）
struct OnboardingCardBackground: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
        shape
            .fill(Self.fill(colorScheme))
            .overlay(shape.strokeBorder(Color.primary.opacity(0.06), lineWidth: 0.5))
            .shadow(color: .black.opacity(0.08), radius: 2, y: 1)
    }

    static func fill(_ colorScheme: ColorScheme) -> Color {
        colorScheme == .dark ? Color.white.opacity(0.08) : Color.white.opacity(0.92)
    }
}
