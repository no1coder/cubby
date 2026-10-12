import AppKit
import SwiftUI
import CubbyCore

/// 首次启动引导向导：欢迎 → 授权 → 选择样子 → 快捷键（docs/design/ui-upgrade/src/Onboarding.dc.html）。
/// 顶部步骤指示器，中间是当前步骤，底部左侧「上一步」、右侧「继续」（最后一步为「开始使用」，↩ 触发）。
/// 屏幕录制权限不在这里申请：首次截图时才请求（只介绍，不打扰）
struct OnboardingWizard: View {
    /// 设计稿：窗口内边距上 36、左右 48、下 28；指示器与标题之间 26
    private static let topInset: CGFloat = 36
    private static let horizontalInset: CGFloat = 48
    private static let bottomInset: CGFloat = 28
    private static let indicatorSpacing: CGFloat = 26
    /// 非减弱动态效果时，步骤切换的横向滑入距离
    private static let slideDistance: CGFloat = 24
    private static let stepAnimation: TimeInterval = 0.22

    @Bindable var settings: AppSettings
    let onShortcutRecordingChange: (Bool) -> Void
    let onStart: () -> Void

    @State private var step: OnboardingStep
    /// 最近一次切换的方向：前进时新步骤从右侧滑入，后退时从左侧
    @State private var isMovingForward = true
    /// 权限状态在向导存在期间一直轮询，回到授权步骤时不必重新读取
    @State private var permissions = PermissionMonitor()
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(
        settings: AppSettings,
        initialStep: OnboardingStep,
        onShortcutRecordingChange: @escaping (Bool) -> Void,
        onStart: @escaping () -> Void
    ) {
        self.settings = settings
        self.onShortcutRecordingChange = onShortcutRecordingChange
        self.onStart = onStart
        _step = State(initialValue: initialStep)
    }

    var body: some View {
        VStack(spacing: 0) {
            OnboardingStepIndicator(current: step)
                .padding(.bottom, Self.indicatorSpacing)
            ZStack(alignment: .top) {
                stepContent
                    .id(step)
                    .transition(transition)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            navigation
        }
        .padding(.top, Self.topInset)
        .padding(.horizontal, Self.horizontalInset)
        .padding(.bottom, Self.bottomInset)
        .frame(
            width: OnboardingWindowController.contentSize.width,
            height: OnboardingWindowController.contentSize.height
        )
        .background(OnboardingBackground())
        .task { await permissions.run() }
    }

    @ViewBuilder
    private var stepContent: some View {
        switch step {
        case .welcome:
            OnboardingWelcomeStep(settings: settings)
        case .permissions:
            OnboardingPermissionsStep(permissions: permissions)
        case .style:
            OnboardingStyleStep(settings: settings)
        case .shortcut:
            OnboardingShortcutStep(settings: settings, onShortcutRecordingChange: onShortcutRecordingChange)
        }
    }

    private var navigation: some View {
        HStack {
            if let previous = step.previous {
                Button("Back") { go(to: previous) }
                    .buttonStyle(OnboardingBackButtonStyle())
            }
            Spacer(minLength: 16)
            // 自定义样式：窗口失去 key 状态时仍保持强调色；回车触发
            Button(action: advance) {
                if step.isLast {
                    Text("Get Started")
                } else {
                    Text("Continue", comment: "Onboarding: go to the next step")
                }
            }
            .buttonStyle(OnboardingPrimaryButtonStyle())
            .keyboardShortcut(.defaultAction)
        }
    }

    // MARK: - 切换

    /// 减弱动态效果时只做 0.1s 淡入淡出，否则滑入 + 淡入
    private var transition: AnyTransition {
        guard !reduceMotion else { return .opacity }
        let offset = isMovingForward ? Self.slideDistance : -Self.slideDistance
        return .asymmetric(
            insertion: .offset(x: offset).combined(with: .opacity),
            removal: .offset(x: -offset).combined(with: .opacity)
        )
    }

    private func advance() {
        guard let next = step.next else { return onStart() }
        go(to: next)
    }

    private func go(to target: OnboardingStep) {
        isMovingForward = target.rawValue > step.rawValue
        let animation: Animation =
            reduceMotion ? .easeOut(duration: Motion.fade) : .easeOut(duration: Self.stepAnimation)
        withAnimation(animation) { step = target }
        // 读屏：换步后朗读新步骤的名称
        AccessibilityNotification.Announcement(target.title).post()
    }
}

/// 每一步的标题与说明（居中，设计稿 24 / 13pt；字号阶梯里最大的标题为 .title）
struct OnboardingStepHeader: View {
    let title: String
    let subtitle: String

    var body: some View {
        VStack(spacing: 8) {
            Text(title)
                .font(.title.weight(.bold))
                .accessibilityAddTraits(.isHeader)
            Text(subtitle)
                .font(.system(size: FontSize.body))
                .foregroundStyle(.secondary)
        }
        .multilineTextAlignment(.center)
        .fixedSize(horizontal: false, vertical: true)
    }
}

/// 毛玻璃（在窗口控制器里）上的着色：深色接近设计稿 rgba(26,27,35,0.78) 的观感，浅色提亮一层
private struct OnboardingBackground: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        colorScheme == .dark
            ? Color(red: 0.102, green: 0.106, blue: 0.137).opacity(0.55)
            : Color.white.opacity(0.35)
    }
}

/// 「继续」：32 高的强调色圆角按钮（设计稿圆角 9、左右 22、13pt semibold）
private struct OnboardingPrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: FontSize.body, weight: .semibold))
            .foregroundStyle(.white)
            .lineLimit(1)
            .padding(.horizontal, 22)
            .frame(minWidth: 88, minHeight: 32)
            .background(RoundedRectangle(cornerRadius: Radius.segment, style: .continuous).fill(Color.accentColor))
            .contentShape(RoundedRectangle(cornerRadius: Radius.segment, style: .continuous))
            .opacity(configuration.isPressed ? 0.8 : 1)
            .animation(.easeOut(duration: Motion.fade), value: configuration.isPressed)
    }
}

/// 「上一步」：无底色的文字按钮，按下时出现淡底
private struct OnboardingBackButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: FontSize.body))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 16)
            .frame(minHeight: 32)
            .background(
                RoundedRectangle(cornerRadius: Radius.segment, style: .continuous)
                    .fill(Color.primary.opacity(configuration.isPressed ? 0.08 : 0))
            )
            .contentShape(RoundedRectangle(cornerRadius: Radius.segment, style: .continuous))
    }
}
