import CryptoKit
import Foundation
import Security

/// 登录钥匙串中历史主密钥条目的纯逻辑部分（E3、E3a）：OSStatus 的映射与 account 的确定。
/// 真正调用 SecItem 的是应用层的 KeychainHistoryKeyProvider；这里不接触钥匙串，便于测试。
public enum HistoryKeychain {
    /// 默认数据目录使用的 account
    public static let defaultAccount = "default"
    /// 自定义数据目录（CUBBY_DATA_DIR）的 account 前缀，其后为 Vault/vault-id 中的 UUID
    static let customAccountPrefix = "vault-"

    /// service：`<bundle id>.history`
    public static func service(bundleIdentifier: String) -> String {
        bundleIdentifier + ".history"
    }

    /// 读取结果的映射：找到且为 256 位 → 密钥；errSecItemNotFound → nil（确定不存在）；
    /// 其余一切（用户拒绝、认证失败、不允许交互、数据异常……）→ .locked，绝不当作「不存在」
    public static func loadedKey(status: OSStatus, data: Data?) throws(HistoryKeyError) -> SymmetricKey? {
        switch status {
        case errSecSuccess:
            guard let data, data.count == HistoryKeys.masterKeyByteCount else { throw .locked }
            return SymmetricKey(data: data)
        case errSecItemNotFound:
            return nil
        default:
            throw .locked
        }
    }

    /// 添加结果的映射：errSecDuplicateItem → .duplicate（调用方重读，绝不覆盖）；其余失败 → .locked
    public static func checkAdded(status: OSStatus) throws(HistoryKeyError) {
        switch status {
        case errSecSuccess: return
        case errSecDuplicateItem: throw .duplicate
        default: throw .locked
        }
    }

    /// 自定义数据目录的 account：`vault-<UUID>`，UUID 存在 Vault/vault-id（明文、不敏感），不由路径派生。
    /// 文件不存在时生成并以 link(2) 原子创建（并发的另一实例先建好时采用它的）
    public static func customAccount(vault: VaultDirectory) throws -> String {
        // E8 ② 改名中途崩溃时 vault-id 还在暂存处：先放回，account 保持不变
        try VaultRecovery.adoptStagedVaultID(into: vault)
        if let existing = try readVaultID(vault) { return customAccountPrefix + existing }
        try PrivateFiles.createDirectory(at: vault.url)
        let temporary = vault.url.appendingPathComponent(".vault-id.\(UUID().uuidString).tmp")
        defer { unlink(temporary.path) }
        try PrivateFiles.write(Data(UUID().uuidString.utf8), to: temporary)
        if link(temporary.path, vault.vaultIDURL.path) != 0, errno != EEXIST {
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }
        guard let created = try readVaultID(vault) else { throw CocoaError(.fileReadCorruptFile) }
        return customAccountPrefix + created
    }

    /// vault-id 中的 UUID（规范化为大写）；文件不存在为 nil，内容不是 UUID 时抛错（不得悄悄换成新 account）
    private static func readVaultID(_ vault: VaultDirectory) throws -> String? {
        let data: Data
        do {
            data = try Data(contentsOf: vault.vaultIDURL)
        } catch CocoaError.fileReadNoSuchFile {
            return nil
        }
        let text = String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        guard let id = UUID(uuidString: text) else { throw CocoaError(.fileReadCorruptFile) }
        return id.uuidString
    }
}
