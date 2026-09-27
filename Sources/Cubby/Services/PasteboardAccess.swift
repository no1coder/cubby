import AppKit
import CubbyCore

/// macOS 15.4+ 的剪贴板隐私权限。
/// 首次以编程方式读取剪贴板时系统会弹窗询问（只有「允许粘贴 / 不允许粘贴」，没有「始终允许」），
/// 之后状态变为「询问」，Cubby 才会出现在系统设置 › 隐私与安全性 ›「从其他 App 粘贴」列表里；
/// 剪贴板管理器需要用户在那里改为「允许」才能静默记录。状态与按钮逻辑见 CubbyCore 的 PasteboardAccessRequest
@MainActor
enum PasteboardAccess {
    typealias Status = PasteboardPermissionStatus

    private static let settingsURL = URL(
        string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Pasteboard"
    )

    static var status: Status {
        guard #available(macOS 15.4, *) else { return .allowed }
        return Status(NSPasteboard.general.accessBehavior)
    }

    /// 已触发过系统询问但未设为「允许」时需要提醒用户
    static var needsAttention: Bool {
        status.needsAttention
    }

    /// 只打开系统设置对应页面，不做任何修改
    static func openSettings() {
        guard let settingsURL else { return }
        NSWorkspace.shared.open(settingsURL)
    }

    /// 权限按钮：尚未询问过时读取一次剪贴板（内容立即丢弃），让系统询问在当前窗口上弹出；否则打开系统设置
    static func performButtonAction() async -> PasteboardAccessRequest.Outcome {
        await PasteboardAccessRequest(
            status: { status },
            trigger: SystemPasteboardPromptTrigger(),
            openSettings: openSettings
        ).perform()
    }
}
