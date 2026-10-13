import CryptoKit
import CubbyCore
import Foundation
import Security
import os

/// 历史主密钥存放在登录钥匙串（E3、E3a）：通用密码，service `<bundle id>.history`，
/// account 为 `default`（默认数据目录）或 `vault-<UUID>`（CUBBY_DATA_DIR，UUID 见 Vault/vault-id），值为 32 字节原始密钥。
///
/// 只增不改：这里只有 SecItemCopyMatching 与 SecItemAdd，没有任何更新或删除主密钥的调用。
/// 访问控制靠钥匙串 ACL（只信任创建它的 Cubby 的签名）；读取可能阻塞在系统询问上，调用方须在后台线程调用。
/// 成功读到的密钥在进程内缓存；失败（锁定）不缓存，「重试」会重新读取。
final class KeychainHistoryKeyProvider: HistoryKeyProviding, Sendable {
    private let service: String
    private let account: @Sendable () throws -> String
    private let cached = OSAllocatedUnfairLock<SymmetricKey?>(initialState: nil)
    private static let logger = Logger(subsystem: "io.github.no1coder.Cubby", category: "Vault")

    /// - Parameter account: 条目的 account；自定义数据目录要读写 vault-id，在首次读取（持有 VaultLock）时才计算
    init(service: String, account: @escaping @Sendable () throws -> String) {
        self.service = service
        self.account = account
    }

    func loadKey() throws(HistoryKeyError) -> SymmetricKey? {
        if let key = cached.withLock({ $0 }) { return key }
        var query = try baseQuery()
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        do {
            let key = try HistoryKeychain.loadedKey(status: status, data: result as? Data)
            if let key { cached.withLock { $0 = key } }
            return key
        } catch {
            Self.logger.error("Reading the history key failed with status \(status, privacy: .public)")
            throw error
        }
    }

    func addKey(_ key: SymmetricKey) throws(HistoryKeyError) {
        var item = try baseQuery()
        item[kSecValueData as String] = key.withUnsafeBytes { Data($0) }
        item[kSecAttrLabel as String] = "Cubby history key"
        let status = SecItemAdd(item as CFDictionary, nil)
        do {
            try HistoryKeychain.checkAdded(status: status)
            cached.withLock { $0 = key }
        } catch {
            Self.logger.error("Adding the history key failed with status \(status, privacy: .public)")
            throw error
        }
    }

    private func baseQuery() throws(HistoryKeyError) -> [String: Any] {
        let account: String
        do {
            account = try self.account()
        } catch {
            Self.logger.error(
                "Could not determine the keychain account: \(error.localizedDescription, privacy: .public)")
            throw .locked
        }
        return [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
    }
}
