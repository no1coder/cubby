import Foundation

/// 全局快捷键对应的动作；原始值即 Carbon EventHotKeyID.id
public enum HotKeyAction: UInt32, CaseIterable, Sendable {
    case togglePanel = 1
    case screenshot = 2
}

/// 全局快捷键登记表（纯值，不调用 Carbon）：哪些动作登记了哪个快捷键、暂停了几层，
/// 以及 Carbon 热键 id ↔ 动作的映射。App 层的 HotKeyManager 比较前后两个登记表的
/// activeActions，决定向系统注册或注销哪些热键
public struct HotKeyRegistry: Equatable, Sendable {
    /// 'CUBY'：区分 Cubby 自己注册的热键与其他组件的热键
    public static let signature: UInt32 = 0x4355_4259

    private let hotKeys: [HotKeyAction: HotKey]
    /// 暂停层数（录制新快捷键时暂停，按次数计数，需与恢复成对）
    public let suspendCount: Int

    public init() {
        self.init(hotKeys: [:], suspendCount: 0)
    }

    private init(hotKeys: [HotKeyAction: HotKey], suspendCount: Int) {
        self.hotKeys = hotKeys
        self.suspendCount = suspendCount
    }

    public var isSuspended: Bool {
        suspendCount > 0
    }

    /// 此刻应当向系统注册的动作（暂停时为空），按原始值排序
    public var activeActions: [HotKeyAction] {
        guard !isSuspended else { return [] }
        return HotKeyAction.allCases.filter { hotKeys[$0] != nil }
    }

    public func hotKey(for action: HotKeyAction) -> HotKey? {
        hotKeys[action]
    }

    /// 登记（或替换）某个动作的快捷键
    public func registering(_ hotKey: HotKey, for action: HotKeyAction) -> HotKeyRegistry {
        HotKeyRegistry(hotKeys: hotKeys.merging([action: hotKey]) { _, new in new }, suspendCount: suspendCount)
    }

    public func removing(_ action: HotKeyAction) -> HotKeyRegistry {
        HotKeyRegistry(hotKeys: hotKeys.filter { $0.key != action }, suspendCount: suspendCount)
    }

    public func suspended() -> HotKeyRegistry {
        HotKeyRegistry(hotKeys: hotKeys, suspendCount: suspendCount + 1)
    }

    /// 未暂停时恢复不会变成负数
    public func resumed() -> HotKeyRegistry {
        HotKeyRegistry(hotKeys: hotKeys, suspendCount: max(suspendCount - 1, 0))
    }

    // MARK: - Carbon 热键 id

    public static func hotKeyID(for action: HotKeyAction) -> UInt32 {
        action.rawValue
    }

    /// 热键事件 → 动作；签名不符（其他组件注册的热键）或未知 id 时为 nil
    public static func action(signature: UInt32, id: UInt32) -> HotKeyAction? {
        guard signature == Self.signature else { return nil }
        return HotKeyAction(rawValue: id)
    }
}
