import AppKit
import SwiftUI
import CubbyCore

/// 首次启动引导：设置快捷键、授予两项权限、介绍截图。
/// 屏幕录制权限不在这里申请：首次截图时才请求（只介绍，不打扰）
struct OnboardingView: View {
    /// 四张步骤卡要放进设置窗口同样的高度上限（SettingsHostingController.maxContentHeight）：
    /// 加宽窗口让说明少折行，头部改为图标在左的横排
    static let width: CGFloat = 600
    /// 图标 + 间距 = 步骤卡内边距 + 步骤图标 + 间距，标题与卡片正文左对齐
    private static let iconSize: CGFloat = 52
    private static let headerSpacing: CGFloat = 12
    private static let sectionSpacing: CGFloat = 20
    /// 底部两个勾选项之间的间距；勾选项标题与说明之间的间距
    private static let footerToggleSpacing: CGFloat = 8
    private static let toggleDetailSpacing: CGFloat = 2

    @Bindable var settings: AppSettings
    let onShortcutRecordingChange: (Bool) -> Void
    let onStart: () -> Void

    @State private var permissions = PermissionMonitor()

    var body: some View {
        VStack(spacing: 0) {
            header
            steps
                .padding(.top, Self.sectionSpacing)
            footer
                .padding(.top, Self.sectionSpacing)
        }
        .padding(.horizontal, 32)
        // 内容延伸到透明标题栏下方，顶部留出关闭按钮的空间
        .padding(.top, 40)
        .padding(.bottom, Self.sectionSpacing)
        .frame(width: Self.width)
        .background(background)
        .task { await permissions.run() }
    }

    // MARK: - 区块

    private var header: some View {
        HStack(spacing: Self.headerSpacing) {
            AppIconImage(size: Self.iconSize)
            VStack(alignment: .leading, spacing: 2) {
                Text("Welcome to Cubby")
                    .font(.title.weight(.bold))
                Text(AppCopy.tagline)
                    .font(.system(size: FontSize.body))
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
    }

    private var steps: some View {
        VStack(spacing: 10) {
            shortcutStep
            clipboardStep
            accessibilityStep
            screenshotStep
        }
    }

    private var shortcutStep: some View {
        OnboardingStepCard(
            systemImage: "command",
            tint: .indigo,
            title: "Open from anywhere",
            message: shortcutMessage
        ) {
            ShortcutRecorder(
                hotKey: $settings.hotKey,
                reservations: settings.screenshotHotKey.map {
                    [.init(hotKey: $0, message: ShortcutReservationCopy.screenshots)]
                } ?? [],
                onRecordingChange: onShortcutRecordingChange
            )
        }
    }

    /// 尚未询问过时按钮为「Grant Access」：点击后读取一次剪贴板，系统询问直接弹在引导页上
    private var clipboardStep: some View {
        OnboardingStepCard(
            systemImage: "doc.on.clipboard",
            tint: .blue,
            title: "Allow clipboard access",
            message: pasteboardMessage,
            status: permissions.pasteboard
        ) {
            if let action = permissions.pasteboard.buttonAction {
                Button(action.title) {
                    Task { await permissions.requestPasteboardAccess() }
                }
                .disabled(permissions.isRequestingPasteboard)
            }
        }
    }

    private var accessibilityStep: some View {
        OnboardingStepCard(
            systemImage: "cursorarrow.click.2",
            tint: .purple,
            title: "Allow direct paste",
            message: """
                With Accessibility access, choosing an item pastes it into the current app. \
                Otherwise it's only copied to the clipboard.
                """,
            status: permissions.accessibility
        ) {
            // 授权失效时只能去系统设置，按钮随状态改名
            Button(
                (permissions.accessibility.buttonAction ?? .grantAccess).title,
                action: AccessibilityAuthorization.requestOrOpenSettings
            )
        }
    }

    private var screenshotStep: some View {
        OnboardingStepCard(
            systemImage: "camera.viewfinder",
            tint: .teal,
            title: "Take and pin screenshots",
            message: screenshotMessage
        ) {
            ScreenshotShortcutRecorder(
                settings: settings,
                allowsTurningOff: false,
                onRecordingChange: onShortcutRecordingChange
            )
        }
    }

    private var footer: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: Self.footerToggleSpacing) {
                LaunchAtLoginToggle()
                updateReminderToggle
            }
            Spacer(minLength: 16)
            // 自定义样式：窗口失去 key 状态时仍保持强调色；回车仍可触发
            Button("Get Started", action: onStart)
                .buttonStyle(CapsuleButtonStyle(size: .large))
                .keyboardShortcut(.defaultAction)
        }
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

    private var background: some View {
        LinearGradient(
            colors: [Color.accentColor.opacity(0.10), Color.accentColor.opacity(0)],
            startPoint: .top,
            endPoint: .center
        )
        .background(Color(nsColor: .windowBackgroundColor))
    }

    // MARK: - 文案

    /// 默认快捷键 ⇧⌘V 会代替部分应用的「粘贴并匹配样式」：使用默认值时提前说明
    private var shortcutMessage: LocalizedStringKey {
        guard settings.hotKey == .default else { return "Press it in any app to open Cubby." }
        return """
            Press it in any app to open Cubby. By default, \(HotKey.default.displayName) replaces \
            “Paste and Match Style” in some apps. You can change it anytime.
            """
    }

    private var pasteboardMessage: LocalizedStringKey {
        if #available(macOS 15.4, *) {
            "Starting with macOS 15.4, apps need permission to read the clipboard. Your history stays on this Mac."
        } else {
            "Cubby records what you copy in the background. Your data stays on this Mac."
        }
    }

    private var screenshotMessage: LocalizedStringKey {
        guard let hotKey = settings.screenshotHotKey else {
            return """
                Capture, mark up and pin screenshots on screen. \
                Cubby asks for Screen Recording only when you take your first one.
                """
        }
        return """
            Press \(hotKey.displayName) to capture, mark up and pin screenshots on screen. \
            Cubby asks for Screen Recording only when you take your first one.
            """
    }
}
