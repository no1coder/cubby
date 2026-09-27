import AppKit
import SwiftUI

/// 面板关闭后仍需告知结果时使用的悬浮提示（如「已复制」）
@MainActor
enum HUDToast {
    /// 默认显示时长：操作结果类的短提示（「已复制」等）
    static let defaultDuration: Duration = .seconds(1.4)
    /// 需要读完一句说明的提示（如引导结束后的快捷键提示）
    static let tipDuration: Duration = .seconds(4)
    /// 全局提示的纵向位置：可见区域自下而上的比例
    private static let defaultAnchorHeightRatio: CGFloat = 0.25
    private static var panel: NSPanel?
    private static var generation = 0

    /// 与界面无关的全局提示（快捷键冲突、权限、截图结果等）的默认位置：
    /// 光标所在屏幕可见区域的下四分之一处；没有屏幕时为 nil
    static func defaultAnchor() -> CGPoint? {
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) } ?? NSScreen.main
        guard let frame = screen?.visibleFrame else { return nil }
        return CGPoint(x: frame.midX, y: frame.minY + frame.height * defaultAnchorHeightRatio)
    }

    /// - Parameters:
    ///   - duration: 完全显示的时长（不含淡入淡出），默认 `defaultDuration`
    ///   - anchor: 提示中心点（屏幕坐标），通常为刚关闭的面板中心
    static func show(
        _ message: String,
        symbolName: String = "checkmark.circle.fill",
        tint: Color = .green,
        duration: Duration = defaultDuration,
        at anchor: CGPoint
    ) {
        let hosting = NSHostingView(rootView: HUDToastView(message: message, symbolName: symbolName, tint: tint))
        // 视图尚未进入窗口时按整点测量，实际需要的宽度可能多出半个点，文字会被截成省略号：向上取整并留 1 pt 余量
        let fitting = hosting.fittingSize
        let size = NSSize(width: ceil(fitting.width) + 1, height: ceil(fitting.height) + 1)
        hosting.frame = NSRect(origin: .zero, size: size)

        let window = panel ?? makePanel()
        panel = window
        window.contentView = hosting
        window.setFrame(
            NSRect(x: anchor.x - size.width / 2, y: anchor.y - size.height / 2, width: size.width, height: size.height),
            display: true
        )
        window.alphaValue = 0
        window.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.12
            window.animator().alphaValue = 1
        }

        generation += 1
        let current = generation
        Task { @MainActor in
            try? await Task.sleep(for: duration)
            guard current == generation else { return }
            NSAnimationContext.runAnimationGroup(
                { context in
                    context.duration = 0.25
                    window.animator().alphaValue = 0
                },
                completionHandler: {
                    Task { @MainActor in
                        if current == generation { panel?.orderOut(nil) }
                    }
                })
        }
    }

    private static func makePanel() -> NSPanel {
        let panel = NSPanel(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: true
        )
        panel.level = .statusBar
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.ignoresMouseEvents = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient, .ignoresCycle]
        panel.isReleasedWhenClosed = false
        return panel
    }
}

private struct HUDToastView: View {
    let message: String
    let symbolName: String
    let tint: Color

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: symbolName)
                .font(.system(size: FontSize.title, weight: .semibold))
                .foregroundStyle(tint)
            Text(message)
                .font(.system(size: FontSize.body, weight: .medium))
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 11)
        .background(.regularMaterial, in: Capsule())
        .overlay(Capsule().strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.5))
        .padding(12)
        .shadow(color: .black.opacity(0.18), radius: 10, y: 4)
    }
}
