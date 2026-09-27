import Carbon.HIToolbox
import os
import CubbyCore

/// 注册一个动作的结果
enum HotKeyRegistrationResult: Equatable {
    /// 已向系统注册成功
    case registered
    /// 暂停期间只登记，恢复时才真正注册（结果由 resume() 报告）
    case deferred
    /// 系统拒绝（通常是被其他应用占用）
    case failed
}

/// 基于 Carbon 的全局快捷键（无需辅助功能权限），可同时注册多个动作。
/// 登记、暂停计数与热键 id ↔ 动作的映射在 Core 的 HotKeyRegistry（纯值、可测）；这里只做 Carbon 调用
@MainActor
final class HotKeyManager {
    private let logger = Logger(subsystem: "io.github.no1coder.Cubby", category: "HotKey")

    private var registry = HotKeyRegistry()
    private var handlers: [HotKeyAction: () -> Void] = [:]
    /// 已向系统注册成功的热键
    private var refs: [HotKeyAction: EventHotKeyRef] = [:]
    private var handlerRef: EventHandlerRef?

    /// 注册（或替换）某个动作的快捷键
    @discardableResult
    func register(_ hotKey: HotKey, for action: HotKeyAction, handler: @escaping () -> Void) -> HotKeyRegistrationResult
    {
        unregisterRef(for: action)
        handlers[action] = handler
        registry = registry.registering(hotKey, for: action)
        guard !registry.isSuspended else { return .deferred }
        return activate(action) ? .registered : .failed
    }

    /// 注销并忘记某个动作的快捷键（例如用户清空了截图快捷键）
    func unregister(_ action: HotKeyAction) {
        unregisterRef(for: action)
        handlers[action] = nil
        registry = registry.removing(action)
    }

    /// 当前已向系统注册成功的快捷键（暂停中或注册失败时为 nil）
    func registeredHotKey(for action: HotKeyAction) -> HotKey? {
        refs[action] == nil ? nil : registry.hotKey(for: action)
    }

    /// 暂停全部快捷键（例如录制新快捷键时，避免按下旧快捷键直接触发动作）。按次数计数，需与 resume 成对调用
    func suspend() {
        registry = registry.suspended()
        for action in HotKeyAction.allCases where !registry.activeActions.contains(action) {
            unregisterRef(for: action)
        }
    }

    /// 恢复；最后一层恢复时逐个重新注册（不因一个失败而跳过其余），返回注册失败的动作
    @discardableResult
    func resume() -> [HotKeyAction] {
        registry = registry.resumed()
        return registry.activeActions.filter { refs[$0] == nil && !activate($0) }
    }

    // MARK: - 注册

    private func activate(_ action: HotKeyAction) -> Bool {
        unregisterRef(for: action)
        guard let hotKey = registry.hotKey(for: action), installHandlerIfNeeded() else { return false }

        var ref: EventHotKeyRef?
        let hotKeyID = EventHotKeyID(
            signature: OSType(HotKeyRegistry.signature), id: HotKeyRegistry.hotKeyID(for: action))
        let status = RegisterEventHotKey(
            hotKey.keyCode,
            hotKey.modifiers,
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &ref
        )
        guard status == noErr, let ref else {
            logger.error(
                """
                Failed to register hot key \(hotKey.displayName, privacy: .public) \
                for action \(action.rawValue): \(status)
                """
            )
            return false
        }
        refs[action] = ref
        return true
    }

    private func unregisterRef(for action: HotKeyAction) {
        guard let ref = refs.removeValue(forKey: action) else { return }
        UnregisterEventHotKey(ref)
    }

    private func dispatch(_ action: HotKeyAction) {
        // 以已注册的热键为准：已注销的动作即使有迟到的事件也直接忽略
        guard refs[action] != nil else { return }
        handlers[action]?()
    }

    // MARK: - Carbon 事件处理

    private func installHandlerIfNeeded() -> Bool {
        guard handlerRef == nil else { return true }
        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        let userData = Unmanaged.passUnretained(self).toOpaque()
        let status = InstallEventHandler(
            GetApplicationEventTarget(),
            { _, event, userData in
                guard let event, let userData, let action = HotKeyManager.action(of: event) else {
                    return OSStatus(eventNotHandledErr)
                }
                let manager = Unmanaged<HotKeyManager>.fromOpaque(userData).takeUnretainedValue()
                // Carbon 事件在主线程分发
                MainActor.assumeIsolated { manager.dispatch(action) }
                return noErr
            },
            1,
            &eventType,
            userData,
            &handlerRef
        )
        guard status == noErr else {
            logger.error("Failed to install the hot key event handler: \(status)")
            return false
        }
        return true
    }

    /// 从热键事件中取出 EventHotKeyID 并映射为动作（签名不符或未知 id 为 nil）
    nonisolated private static func action(of event: EventRef) -> HotKeyAction? {
        var hotKeyID = EventHotKeyID()
        let status = GetEventParameter(
            event,
            EventParamName(kEventParamDirectObject),
            EventParamType(typeEventHotKeyID),
            nil,
            MemoryLayout<EventHotKeyID>.size,
            nil,
            &hotKeyID
        )
        guard status == noErr else { return nil }
        return HotKeyRegistry.action(signature: UInt32(hotKeyID.signature), id: hotKeyID.id)
    }
}
