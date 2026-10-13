import Foundation
import os

/// 启动时准备加密 Vault 的完整流程（E3a、E6、E7、E8），在后台线程调用（读取钥匙串可能阻塞在系统询问上）：
/// ① 持锁解析密钥；密钥找不到但 Vault 已有数据（或历史文件的密钥 ID 与当前密钥不符）→ Vault 改名保留（E8 ②）；
/// ② 改名后重新持锁解析（此时生成新密钥）；锁定 → 返回 .locked（E8 ①）；
/// ③ 还原密钥 ID 相符的保留目录；删除迁移残留；有明文则迁移（E6 / E7）。
/// Vault 不存在而密钥存在（E8 ③）不需要特殊处理：解析器直接返回已有密钥，Vault 随第一次写入建立。
public struct VaultLaunch: Sendable {
    /// 准备好的 Vault
    public struct Session: Equatable, Sendable {
        public let keys: HistoryKeys
        public let vault: VaultDirectory
        /// 本次启动因密钥丢失而改名保留的旧 Vault（E8 ②）
        public let quarantinedFolder: URL?
        /// 迁移失败（明文原样保留，下次启动重试）
        public let migrationFailed: Bool
    }

    public enum Outcome: Equatable, Sendable {
        case ready(Session)
        /// 无法取得密钥：本次运行只在内存中记录（E8 ①）
        case locked
    }

    public let dataDirectory: URL
    private let provider: any HistoryKeyProviding
    private let historyLimit: Int
    /// false：密钥只存在于本进程（DEBUG 的临时密钥），不得改名保留旧 Vault、不得迁移（会让明文落进用完即弃的密钥下）
    private let allowsDestructiveSteps: Bool
    private let logger = Logger(subsystem: "io.github.no1coder.Cubby", category: "Vault")

    public init(
        dataDirectory: URL,
        provider: any HistoryKeyProviding,
        historyLimit: Int,
        allowsDestructiveSteps: Bool = true
    ) {
        self.dataDirectory = dataDirectory
        self.provider = provider
        self.historyLimit = historyLimit
        self.allowsDestructiveSteps = allowsDestructiveSteps
    }

    private var recovery: VaultRecovery { VaultRecovery(dataDirectory: dataDirectory) }

    /// 执行全部步骤。progress(已处理, 总数) 只在迁移时回调（在调用线程上）
    public func run(progress: (_ done: Int, _ total: Int) -> Void = { _, _ in }) throws -> Outcome {
        let vault = recovery.vault
        let first = try VaultLock(vaultDirectory: vault.url).withLock { try resolveOrQuarantine(vault) }
        // 改名后旧锁文件随目录一起移走，重新在新的 Vault 目录上持锁
        return try VaultLock(vaultDirectory: vault.url).withLock {
            let resolution = first.quarantined == nil ? first.resolution : resolver(vault).resolve()
            guard case .ready(let keys) = resolution else { return .locked }
            recovery.restoreFolders(matching: keys, historyLimit: historyLimit)
            let migrationFailed = migrate(vault: vault, keys: keys, progress: progress)
            return .ready(
                Session(
                    keys: keys, vault: vault, quarantinedFolder: first.quarantined, migrationFailed: migrationFailed))
        }
    }

    private func resolver(_ vault: VaultDirectory) -> VaultKeyResolver {
        VaultKeyResolver(provider: provider, vaultHasData: { vault.containsEncryptedData() })
    }

    private func resolveOrQuarantine(_ vault: VaultDirectory) throws -> (
        resolution: VaultKeyResolution, quarantined: URL?
    ) {
        let resolution = resolver(vault).resolve()
        let needsQuarantine: Bool
        switch resolution {
        case .missingKeyForExistingVault:
            needsQuarantine = true
        case .ready(let keys):
            // 历史文件属于另一把密钥：按「密钥找不到」处理，绝不当作损坏
            needsQuarantine = VaultRecovery.keyID(ofVaultAt: vault.url).map { $0 != keys.keyID } ?? false
        case .locked:
            needsQuarantine = false
        }
        guard needsQuarantine else { return (resolution, nil) }
        guard allowsDestructiveSteps else {
            logger.error("The vault belongs to another key; staying in memory with a temporary key")
            return (.locked, nil)
        }
        return (resolution, try recovery.quarantine())
    }

    /// 删除迁移残留；有明文则迁移。迁移失败只记日志（明文原样保留，下次启动重试），返回是否失败
    private func migrate(vault: VaultDirectory, keys: HistoryKeys, progress: (Int, Int) -> Void) -> Bool {
        let migration = PlaintextMigration(
            dataDirectory: dataDirectory, vault: vault, keys: keys, historyLimit: historyLimit)
        do {
            try migration.files.removeLeftovers()
            guard allowsDestructiveSteps, migration.isNeeded else { return false }
            try migration.run(progress: progress)
            return false
        } catch {
            logger.error("Failed to encrypt the plaintext history: \(error.localizedDescription, privacy: .public)")
            return true
        }
    }
}
