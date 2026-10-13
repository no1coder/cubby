import CryptoKit
import Foundation
import os

/// 读取或保存历史主密钥时的错误
public enum HistoryKeyError: Error, Equatable, Sendable {
    /// 已锁定：用户拒绝、钥匙串被锁或其他读取错误。调用方不得生成新密钥，也不得写盘（E8 ①）
    case locked
    /// 添加时发现已有密钥（另一实例刚生成）：调用方应重新读取，绝不覆盖（E3a）
    case duplicate
    /// 密钥长度不是 256 位
    case invalidKey
}

/// 历史主密钥的存放处（正式版为登录钥匙串，测试与 DEBUG 为内存）。
///
/// 只增不改：协议里没有更新、覆盖或删除密钥的接口，任何实现都不应提供。
public protocol HistoryKeyProviding: Sendable {
    /// 读取主密钥。
    /// - Returns: 存在则返回密钥；**确定**不存在（如 errSecItemNotFound）返回 nil
    /// - Throws: 其他任何情况（拒绝、锁定、未知错误）一律抛 `.locked`
    func loadKey() throws(HistoryKeyError) -> SymmetricKey?

    /// 添加主密钥（只增）。已有密钥时抛 `.duplicate` 且保持原密钥不变；其他失败抛 `.locked`
    func addKey(_ key: SymmetricKey) throws(HistoryKeyError)
}

/// 内存中的密钥来源：供单元测试与 DEBUG 构建使用，可模拟锁定与并发首次生成
public final class InMemoryHistoryKeyProvider: HistoryKeyProviding, Sendable {
    private struct State {
        var key: SymmetricKey?
        var isLocked = false
        /// 下一次 addKey 前「另一实例」抢先存入的密钥
        var rivalKey: SymmetricKey?
        var addAttempts = 0
    }

    private let state: OSAllocatedUnfairLock<State>

    public init(key: SymmetricKey? = nil) {
        state = OSAllocatedUnfairLock(initialState: State(key: key))
    }

    /// 当前存放的密钥（不受锁定状态影响，供测试断言）
    public var storedKey: SymmetricKey? {
        state.withLock { $0.key }
    }

    /// 调用 addKey 的次数（含失败）
    public var addAttempts: Int {
        state.withLock { $0.addAttempts }
    }

    /// 模拟钥匙串锁定或用户拒绝
    public func setLocked(_ isLocked: Bool) {
        state.withLock { $0.isLocked = isLocked }
    }

    /// 模拟竞态：下一次 addKey 执行前，另一实例已存入 key（于是这次添加报 duplicate）
    public func armRivalKey(_ key: SymmetricKey) {
        state.withLock { $0.rivalKey = key }
    }

    public func loadKey() throws(HistoryKeyError) -> SymmetricKey? {
        let snapshot = state.withLock { (isLocked: $0.isLocked, key: $0.key) }
        guard !snapshot.isLocked else { throw .locked }
        return snapshot.key
    }

    public func addKey(_ key: SymmetricKey) throws(HistoryKeyError) {
        let failure: HistoryKeyError? = state.withLock { current in
            current.addAttempts += 1
            guard !current.isLocked else { return .locked }
            if let rival = current.rivalKey, current.key == nil {
                current.key = rival
                current.rivalKey = nil
            }
            guard current.key == nil else { return .duplicate }
            current.key = key
            return nil
        }
        if let failure { throw failure }
    }
}
