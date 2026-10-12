import AppKit
import SwiftUI

/// 警示卡窗口：指针所在屏幕中上部的非激活浮窗，不能成为 key（不抢走钱包等应用的焦点），按钮首次点击即响应
@MainActor
final class TamperAlertController {
    struct Actions {
        /// 「恢复我复制的地址」（写入失败时警示卡留着；剪贴板已经变了时收起并说明）
        let restore: (TamperIncident) -> AddressGuardController.RestoreResult
        let changedMyself: (TamperIncident) -> Void
        /// 「查看安全记录」：打开设置 › 剪贴板安全
        let viewLog: () -> Void
    }

    /// 卡片顶边距屏幕可见区域顶边的比例（设计稿：900 高的屏幕上距顶 150）
    private static let topRatio: CGFloat = 0.14

    private let actions: Actions
    private var panel: ClipPanel?
    private(set) var incident: TamperIncident?

    init(actions: Actions) {
        self.actions = actions
    }

    var isVisible: Bool { panel?.isVisible == true }

    func show(_ incident: TamperIncident) {
        self.incident = incident
        let view = TamperAlertView(
            incident: incident,
            onViewLog: { [weak self] in
                self?.hide()
                self?.actions.viewLog()
            },
            onChangedMyself: { [weak self] in
                self?.actions.changedMyself(incident)
                self?.hide()
            },
            onRestore: { [weak self] in
                guard let self else { return }
                switch self.actions.restore(incident) {
                case .restored:
                    self.hide()
                case .alreadyChanged:
                    self.hide()
                    Self.showAlreadyChanged()
                case .failed:
                    NSSound.beep()
                }
            })
        let hosting = FirstMouseHostingView(rootView: view)
        let fitting = hosting.fittingSize
        let size = NSSize(width: ceil(fitting.width), height: ceil(fitting.height))
        hosting.frame = NSRect(origin: .zero, size: size)

        let window = panel ?? makePanel()
        panel = window
        window.contentView = hosting
        window.setFrame(frame(for: size), display: true)
        let wasVisible = window.isVisible
        window.orderFrontRegardless()
        guard !wasVisible else { return }
        window.alphaValue = 0
        NSAnimationContext.runAnimationGroup { context in
            context.duration = Motion.overlayFade
            window.animator().alphaValue = 1
        }
        NSAccessibility.post(
            element: hosting, notification: .announcementRequested,
            userInfo: [.announcement: TamperAlertCopy.title, .priority: NSAccessibilityPriorityLevel.high.rawValue])
    }

    private static func showAlreadyChanged() {
        guard let anchor = HUDToast.defaultAnchor() else { return }
        HUDToast.show(
            String(
                localized: "Your clipboard has already changed, so nothing was restored",
                comment: "HUD after Restore when the clipboard no longer holds the replacing value"),
            symbolName: "info.circle.fill", tint: .orange, duration: HUDToast.tipDuration, at: anchor)
    }

    func hide() {
        incident = nil
        guard let panel, panel.isVisible else { return }
        NSAnimationContext.runAnimationGroup(
            { context in
                context.duration = Motion.fade
                panel.animator().alphaValue = 0
            },
            completionHandler: { [weak self] in
                Task { @MainActor in
                    guard self?.incident == nil else { return }
                    panel.orderOut(nil)
                }
            })
    }

    private func makePanel() -> ClipPanel {
        let panel = ClipPanel(size: .zero, isKeyable: false)
        // 浮窗自己画阴影与光晕
        panel.hasShadow = false
        panel.level = .statusBar
        panel.setAccessibilityRole(.window)
        panel.setAccessibilitySubrole(.dialog)
        return panel
    }

    /// 指针所在屏幕，水平居中、靠上
    private func frame(for size: NSSize) -> NSRect {
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) } ?? NSScreen.main
        guard let visible = screen?.visibleFrame else { return NSRect(origin: .zero, size: size) }
        let top = visible.maxY - visible.height * Self.topRatio + TamperAlertView.outerMargin
        let y = max(visible.minY, min(top - size.height, visible.maxY - size.height))
        return NSRect(x: visible.midX - size.width / 2, y: y, width: size.width, height: size.height)
    }
}
