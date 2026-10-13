import CryptoKit
import Foundation

/// 启动时解析历史密钥的结果
public enum VaultKeyResolution: Equatable, Sendable {
    /// 密钥可用（已有或刚生成）
    case ready(HistoryKeys)
    /// 已锁定：本次运行只在内存中记录，不写盘（E8 ①）
    case locked
    /// 钥匙串里确定没有密钥，但 Vault 中已有加密数据：不得生成新密钥（E8 ②）
    case missingKeyForExistingVault
}

/// 历史密钥的解析规则（E3a），纯逻辑：只依赖密钥来源与「Vault 是否已有数据」。
///
/// - 只有「确定不存在」且「Vault 没有数据」时才生成新密钥，且只走 addKey；
/// - addKey 报 duplicate（另一实例刚生成）就重新读取，采用对方的密钥，绝不覆盖；
/// - 任何不确定的情况都按锁定处理。
///
/// 调用方应在 VaultLock 内调用 resolve()，使同一数据目录同时只有一个实例生成密钥。
public struct VaultKeyResolver: Sendable {
    private let provider: any HistoryKeyProviding
    private let vaultHasData: @Sendable () -> Bool
    private let generateMasterKey: @Sendable () -> SymmetricKey

    /// - Parameters:
    ///   - vaultHasData: Vault 中是否已有加密数据（见 VaultDirectory.containsEncryptedData），只在需要时调用
    ///   - generateMasterKey: 新主密钥的来源，测试可注入固定值
    public init(
        provider: any HistoryKeyProviding,
        vaultHasData: @escaping @Sendable () -> Bool,
        generateMasterKey: @escaping @Sendable () -> SymmetricKey = HistoryKeys.generateMasterKey
    ) {
        self.provider = provider
        self.vaultHasData = vaultHasData
        self.generateMasterKey = generateMasterKey
    }

    public func resolve() -> VaultKeyResolution {
        let existing: SymmetricKey?
        do {
            existing = try provider.loadKey()
        } catch {
            return .locked
        }
        if let existing {
            return Self.resolution(for: existing)
        }
        guard !vaultHasData() else { return .missingKeyForExistingVault }

        let generated = generateMasterKey()
        do {
            try provider.addKey(generated)
            return Self.resolution(for: generated)
        } catch .duplicate {
            return rereadAfterDuplicate()
        } catch {
            return .locked
        }
    }

    /// 另一实例抢先添加了密钥：重读一次；仍读不到则按锁定处理，绝不再次生成
    private func rereadAfterDuplicate() -> VaultKeyResolution {
        guard let key = try? provider.loadKey() else { return .locked }
        return Self.resolution(for: key)
    }

    /// 钥匙串中的密钥长度不对：无法使用又不能覆盖，按锁定处理
    private static func resolution(for masterKey: SymmetricKey) -> VaultKeyResolution {
        guard let keys = try? HistoryKeys(masterKey: masterKey) else { return .locked }
        return .ready(keys)
    }
}
