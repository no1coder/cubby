import SwiftUI
import CubbyCore

/// 第 4 步「快捷键」：面板快捷键录制（附呼出方式提示）、截图快捷键录制；
/// 「只看图片」与晾衣绳快捷键开着时，再列出它们的按键（在设置 › 通用里修改）
struct OnboardingShortcutStep: View {
    private static let cardsWidth: CGFloat = 680

    @Bindable var settings: AppSettings
    let onShortcutRecordingChange: (Bool) -> Void

    var body: some View {
        VStack(spacing: 26) {
            OnboardingStepHeader(
                title: String(
                    localized: "Open Cubby with a shortcut", comment: "Onboarding: title of the shortcut step"),
                subtitle: String(
                    localized: "Press it in any app, or click the Cubby icon in the menu bar.",
                    comment: "Onboarding: subtitle of the shortcut step"
                )
            )
            VStack(spacing: 10) {
                panelCard
                screenshotCard
                if !moreShortcuts.isEmpty {
                    moreShortcutsCard
                }
            }
            .frame(width: Self.cardsWidth)
        }
    }

    private var panelCard: some View {
        OnboardingStepCard(
            systemImage: "command",
            tint: .indigo,
            title: "Open from anywhere",
            message: shortcutMessage
        ) {
            ShortcutRecorder(
                hotKey: $settings.hotKey,
                reservations: HotKeyReservations.excluding(.togglePanel, settings: settings),
                onRecordingChange: onShortcutRecordingChange
            )
        }
    }

    private var screenshotCard: some View {
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

    /// 其余开着的快捷键：只展示按键，不在引导里录制
    private var moreShortcutsCard: some View {
        OnboardingStepCard(
            systemImage: "keyboard",
            tint: .orange,
            title: "More shortcuts",
            message: "Change or turn them off in Settings › General."
        ) {
            VStack(alignment: .trailing, spacing: 8) {
                ForEach(moreShortcuts, id: \.name) { shortcut in
                    HStack(spacing: 10) {
                        Text(shortcut.name)
                            .font(.system(size: FontSize.footnote))
                            .foregroundStyle(.secondary)
                        ShortcutKeyCaps(symbols: shortcut.hotKey.keySymbols)
                    }
                    .accessibilityElement(children: .combine)
                }
            }
        }
    }

    private var moreShortcuts: [(name: String, hotKey: HotKey)] {
        var shortcuts: [(name: String, hotKey: HotKey)] = []
        if let images = settings.imagesHotKey {
            shortcuts.append(
                (String(localized: "Only images", comment: "Onboarding: name of the images-only shortcut"), images))
        }
        if settings.clotheslineEnabled, let clothesline = settings.clotheslineHotKey {
            shortcuts.append(
                (
                    String(
                        localized: "Show / hide the clothesline",
                        comment: "Onboarding: name of the clothesline shortcut"),
                    clothesline
                ))
        }
        return shortcuts
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
