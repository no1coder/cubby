import SwiftUI
import CubbyCore

extension OnboardingStep {
    /// 步骤指示器上的名称
    var title: String {
        switch self {
        case .welcome: String(localized: "Welcome", comment: "Onboarding step name in the step indicator")
        case .permissions: String(localized: "Permissions", comment: "Onboarding step name in the step indicator")
        case .style: String(localized: "Choose a Style", comment: "Onboarding step name in the step indicator")
        case .shortcut: String(localized: "Shortcut", comment: "Onboarding step name in the step indicator")
        }
    }
}

/// 向导顶部的步骤指示器：已完成的步骤为绿色对勾，当前步骤为蓝色序号（名称加粗），之后的步骤为灰色序号，步骤之间连线。
/// 读屏把整行读作一句「第 3 步，共 4 步：选择样子」
struct OnboardingStepIndicator: View {
    let current: OnboardingStep

    /// 设计稿：圆点 18、序号 11pt、名称 12pt、连线 28 × 1、间距 10 / 6
    private static let dotSize: CGFloat = 18
    private static let lineWidth: CGFloat = 28
    private static let itemSpacing: CGFloat = 10
    private static let labelSpacing: CGFloat = 6

    var body: some View {
        HStack(spacing: Self.itemSpacing) {
            ForEach(OnboardingStep.allCases, id: \.self) { step in
                if !step.isFirst {
                    Rectangle()
                        .fill(Color.primary.opacity(0.2))
                        .frame(width: Self.lineWidth, height: 1)
                }
                item(step, progress: step.progress(current: current))
            }
        }
        .font(.system(size: FontSize.footnote))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
    }

    private func item(_ step: OnboardingStep, progress: OnboardingStep.Progress) -> some View {
        HStack(spacing: Self.labelSpacing) {
            dot(step, progress: progress)
            Text(step.title)
                .fontWeight(progress == .current ? .semibold : .regular)
                .foregroundStyle(progress == .current ? Color.primary : Color.secondary)
        }
    }

    @ViewBuilder
    private func dot(_ step: OnboardingStep, progress: OnboardingStep.Progress) -> some View {
        switch progress {
        case .done:
            Image(systemName: "checkmark")
                .font(.system(size: FontSize.caption2, weight: .bold))
                .foregroundStyle(Color.green)
                .frame(width: Self.dotSize, height: Self.dotSize)
                .background(Circle().fill(Color.green.opacity(0.25)))
        case .current:
            number(step)
                .foregroundStyle(.white)
                .background(Circle().fill(Color.accentColor))
        case .upcoming:
            number(step)
                .foregroundStyle(.secondary)
                .background(Circle().fill(Color.primary.opacity(0.1)))
        }
    }

    private func number(_ step: OnboardingStep) -> some View {
        Text(step.number, format: .number)
            .font(.system(size: FontSize.caption, weight: .semibold))
            .frame(width: Self.dotSize, height: Self.dotSize)
    }

    private var accessibilityText: String {
        String(
            localized: "Step \(current.number) of \(OnboardingStep.allCases.count): \(current.title)",
            comment: "VoiceOver label of the onboarding step indicator. %1$lld = step, %2$lld = total, %3$@ = step name"
        )
    }
}
