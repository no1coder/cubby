import SwiftUI
import CubbyCore

/// 第 2 步「授权」：剪贴板访问与直接粘贴（辅助功能）两张卡片，状态实时更新。
/// 只有用户点按按钮时才请求授权，进入这一步本身不会弹出系统询问
struct OnboardingPermissionsStep: View {
    private static let cardsWidth: CGFloat = 600

    let permissions: PermissionMonitor

    var body: some View {
        VStack(spacing: 26) {
            OnboardingStepHeader(
                title: String(localized: "Allow access", comment: "Onboarding: title of the permissions step"),
                subtitle: String(
                    localized:
                        "Cubby asks only when you click a button. You can change this anytime in System Settings.",
                    comment: "Onboarding: subtitle of the permissions step"
                )
            )
            VStack(spacing: 10) {
                clipboardCard
                accessibilityCard
            }
            .frame(width: Self.cardsWidth)
        }
    }

    /// 尚未询问过时按钮为「Grant Access」：点击后读取一次剪贴板，系统询问直接弹在引导页上
    private var clipboardCard: some View {
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

    private var accessibilityCard: some View {
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

    private var pasteboardMessage: LocalizedStringKey {
        if #available(macOS 15.4, *) {
            "Starting with macOS 15.4, apps need permission to read the clipboard. Your history stays on this Mac."
        } else {
            "Cubby records what you copy in the background. Your data stays on this Mac."
        }
    }
}
