#if DEBUG
import CryptoKit
import CubbyCore
import Foundation
import os

/// 面板 E2E 的历史密钥来源：内存密钥（可模拟锁定 / 拒绝）+ 一道闸门。
/// 闸门关着时读取密钥会一直等（模拟停在钥匙串询问上），Vault 保持「准备中」，面板显示迁移占位
final class PanelE2EKeyGate: HistoryKeyProviding, Sendable {
    /// 闸门最长等待：脚本中止忘了开闸时，后台线程也不会永远卡住
    private static let maximumWait: DispatchTimeInterval = .seconds(30)

    private let keys = InMemoryHistoryKeyProvider()
    private let gate: DispatchSemaphore
    private let isOpen: OSAllocatedUnfairLock<Bool>

    init(startsOpen: Bool) {
        gate = DispatchSemaphore(value: 0)
        isOpen = OSAllocatedUnfairLock(initialState: startsOpen)
    }

    /// 模拟用户在钥匙串询问中拒绝（或允许）
    func setLocked(_ locked: Bool) {
        keys.setLocked(locked)
    }

    /// 开闸：等待中的读取继续，之后的读取不再等待
    func open() {
        let wasOpen = isOpen.withLock { open in
            defer { open = true }
            return open
        }
        if !wasOpen { gate.signal() }
    }

    func loadKey() throws(HistoryKeyError) -> SymmetricKey? {
        if !isOpen.withLock({ $0 }) {
            _ = gate.wait(timeout: .now() + Self.maximumWait)
        }
        return try keys.loadKey()
    }

    func addKey(_ key: SymmetricKey) throws(HistoryKeyError) {
        try keys.addKey(key)
    }
}
#endif
