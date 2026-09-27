import AppKit
import SwiftUI

/// 屏幕录制权限引导窗口：说明为什么需要、去哪里开启；授权后自动关闭并回调。
/// 视觉沿用首次引导窗口（透明标题栏、强调色渐变背景、胶囊按钮）
@MainActor
final class ScreenRecordingGuideWindowController: NSObject, NSWindowDelegate {
    /// 轮询发现已授权时调用（窗口已关闭）
    var onGranted: (() -> Void)?
    private var window: NSWindow?

    var isVisible: Bool {
        window?.isVisible == true
    }

    func show() {
        let window = self.window ?? makeWindow()
        self.window = window
        if !window.isVisible {
            window.center()
        }
        // 截图由全局快捷键触发时 Cubby 不在前台，需要主动激活窗口才会出现在最前
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
    }

    func close() {
        window?.close()
    }

    // MARK: - NSWindowDelegate

    func windowWillClose(_ notification: Notification) {
        // 关闭流程结束后丢弃窗口：视图随之销毁，权限轮询任务也随 .task 取消而停止。
        // 期间若已再次 show()（窗口重新可见），保留引用
        let closing = notification.object as? NSWindow
        Task { @MainActor in
            guard let window = self.window, window === closing, !window.isVisible else { return }
            self.window = nil
        }
    }

    // MARK: - 私有

    private func granted() {
        close()
        onGranted?()
    }

    private func makeWindow() -> NSWindow {
        let rootView = ScreenRecordingGuideView(
            onOpenSettings: ScreenRecordingAuthorization.openSettings,
            onQuitAndReopen: { AppRelauncher.relaunch() },
            onDismiss: { [weak self] in self?.close() },
            onGranted: { [weak self] in self?.granted() }
        )
        let controller = NSHostingController(rootView: rootView)
        // 内容延伸到透明标题栏下方，不再额外计入标题栏高度
        controller.safeAreaRegions = []
        let size = controller.sizeThatFits(
            in: NSSize(width: ScreenRecordingGuideView.width, height: .greatestFiniteMagnitude))

        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.titled, .closable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.contentViewController = controller
        window.setContentSize(size)
        window.title = String(localized: "Screen Recording", comment: "Screen Recording guide window title")
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.isMovableByWindowBackground = true
        window.isReleasedWhenClosed = false
        window.tabbingMode = .disallowed
        window.collectionBehavior.insert(.fullScreenNone)
        window.standardWindowButton(.miniaturizeButton)?.isHidden = true
        window.standardWindowButton(.zoomButton)?.isHidden = true
        window.delegate = self
        return window
    }
}

/// 引导窗口内容：图标、标题、原因、重启提示（附次要的「退出并重新打开」），一个主按钮
private struct ScreenRecordingGuideView: View {
    static let width: CGFloat = 460
    private static let iconSide: CGFloat = 56

    let onOpenSettings: () -> Void
    let onQuitAndReopen: () -> Void
    let onDismiss: () -> Void
    let onGranted: () -> Void

    /// 浅色下系统 .secondary 在白底上约 3.9:1，达不到 WCAG AA（4.5:1），重启提示改用略深的次要色
    private static let lightHintOpacity: Double = 0.7

    @State private var permissions = PermissionMonitor()
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(spacing: 0) {
            PermissionIcon(systemImage: "rectangle.dashed.badge.record", isGranted: false, size: Self.iconSide)
            Text("Allow Screen Recording to take screenshots")
                .font(.title2.weight(.bold))
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 16)
            Text(
                """
                Cubby needs Screen Recording to capture your screen. It only captures when you take a \
                screenshot, and frames stay in memory until you copy, save or pin them.
                """
            )
            .font(.system(size: FontSize.body))
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.top, 8)
            relaunchHint
                .padding(.top, 12)
            buttons
                .padding(.top, 24)
        }
        .padding(.horizontal, 32)
        // 内容延伸到透明标题栏下方，顶部留出关闭按钮的空间
        .padding(.top, 40)
        .padding(.bottom, 24)
        .frame(width: Self.width)
        .background(background)
        .task { await permissions.run() }
        .onChange(of: permissions.screenRecording.isGranted) { _, isGranted in
            if isGranted { onGranted() }
        }
    }

    /// 授权后常需重启才生效：提示用 footnote + 次要色（深浅色下对比度均满足 WCAG AA），
    /// 下方附一个链接样式的次要按钮，不与主按钮争夺注意力
    private var relaunchHint: some View {
        VStack(spacing: 4) {
            // 纯文本而非 Label：折成两行时仍整体居中
            Text("macOS may ask you to quit and reopen Cubby after granting access.")
                .foregroundStyle(hintStyle)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            Button("Quit & Reopen Cubby", action: onQuitAndReopen)
                .buttonStyle(.link)
        }
        .font(.system(size: FontSize.footnote))
    }

    private var hintStyle: AnyShapeStyle {
        colorScheme == .dark
            ? AnyShapeStyle(.secondary)
            : AnyShapeStyle(Color.primary.opacity(Self.lightHintOpacity))
    }

    private var buttons: some View {
        HStack(spacing: 12) {
            Button("Not Now", action: onDismiss)
                .buttonStyle(CapsuleButtonStyle(isPrimary: false, size: .large))
                .keyboardShortcut(.cancelAction)
            // 自定义样式：窗口失去 key 状态时（用户切到系统设置）仍保持强调色
            Button("Open System Settings", action: onOpenSettings)
                .buttonStyle(CapsuleButtonStyle(size: .large))
                .keyboardShortcut(.defaultAction)
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
}
