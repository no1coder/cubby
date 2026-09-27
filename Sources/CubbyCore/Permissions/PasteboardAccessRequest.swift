import AppKit

/// 「读取一次剪贴板以触发系统询问」的抽象，测试时注入假实现
public protocol PasteboardPromptTrigger: Sendable {
    /// 读取剪贴板中的一项内容并立即丢弃（不记录、不保存）。
    /// 返回是否真的读取了内容：剪贴板为空（或只有不应读取的内容）时系统无从询问
    func readOnceAndDiscard() async -> Bool
}

/// 剪贴板权限按钮的逻辑（引导第 2 步与设置 › 隐私共用）：
/// - 尚未询问过：读取一次剪贴板，让系统询问直接在当前窗口上弹出；
/// - 询问过但未设为「允许」：只能打开系统设置；
/// - 执行后重新读取状态，由调用方立即刷新界面。
@MainActor
public struct PasteboardAccessRequest {
    public enum Outcome: Equatable, Sendable {
        /// 已允许，什么也不做
        case alreadyAllowed
        /// 已打开系统设置
        case openedSettings
        /// 系统询问后状态变为新值
        case changed(to: PasteboardPermissionStatus)
        /// 读取了内容但状态没变（系统没有询问，或用户尚未作答）
        case unchanged
        /// 剪贴板里没有可读的内容，系统没有询问
        case nothingToRead
    }

    private let status: @MainActor () -> PasteboardPermissionStatus
    private let trigger: any PasteboardPromptTrigger
    private let openSettings: @MainActor () -> Void

    public init(
        status: @escaping @MainActor () -> PasteboardPermissionStatus,
        trigger: any PasteboardPromptTrigger,
        openSettings: @escaping @MainActor () -> Void
    ) {
        self.status = status
        self.trigger = trigger
        self.openSettings = openSettings
    }

    public func perform() async -> Outcome {
        let before = status()
        switch before.buttonAction {
        case nil:
            return .alreadyAllowed
        case .openSystemSettings:
            openSettings()
            return .openedSettings
        case .grantAccess:
            let didRead = await trigger.readOnceAndDiscard()
            let after = status()
            // 状态没变时不自动打开系统设置：系统询问框可能仍在屏幕上，设置窗口会把它盖住
            if after != before { return .changed(to: after) }
            return didRead ? .unchanged : .nothingToRead
        }
    }
}

/// 读取真实剪贴板的实现。
/// 在后台线程读取：系统询问期间读取会一直等到用户作答，不能卡住主线程
public struct SystemPasteboardPromptTrigger: PasteboardPromptTrigger {
    /// 优先读取的轻量类型：只为触发询问，不必读出整张图片
    private static let preferredTypes: [NSPasteboard.PasteboardType] = [.string, .URL, .fileURL, .rtf, .html]

    private let pasteboardName: NSPasteboard.Name

    public init(pasteboardName: NSPasteboard.Name = .general) {
        self.pasteboardName = pasteboardName
    }

    public func readOnceAndDiscard() async -> Bool {
        let name = pasteboardName
        return await Task.detached(priority: .userInitiated) {
            Self.readOnce(from: NSPasteboard(name: name))
        }.value
    }

    /// 读取一项内容后立即丢弃；遵循 nspasteboard.org 约定，机密 / 临时内容与 Cubby 自身写入的内容不读取
    static func readOnce(from pasteboard: NSPasteboard) -> Bool {
        guard !PasteboardReader.shouldIgnore(pasteboard),
            let type = probeType(in: pasteboard.types ?? [])
        else { return false }
        return pasteboard.data(forType: type) != nil
    }

    static func probeType(in types: [NSPasteboard.PasteboardType]) -> NSPasteboard.PasteboardType? {
        preferredTypes.first(where: types.contains) ?? types.first
    }
}
