import Foundation
import os

/// 密钥找不到但 Vault 已有数据（E8 ②）：把 Vault 改名保留、之后若钥匙串恢复了对应密钥则自动还原。
/// 调用方须持有 VaultLock。任何路径都不删除无法解密的数据。
public struct VaultRecovery: Sendable {
    /// restoreFolders 的结果
    public struct RestoreResult: Equatable, Sendable {
        /// 已合并回当前 Vault 并删除的保留目录
        public let restored: [URL]
        /// 还原时发现当前 Vault 的历史损坏、已被移入 Backups 的位置：本次启动不得清理图片（E8 ④）
        public let corruptedHistoryBackup: URL?
    }

    /// 保留目录名前缀：`Vault-unreadable-<yyyy-MM-dd>[-n]`
    public static let unreadablePrefix = VaultDirectory.defaultName + "-unreadable-"

    public let dataDirectory: URL
    private let logger = Logger(subsystem: "io.github.no1coder.Cubby", category: "Vault")

    public init(dataDirectory: URL) {
        self.dataDirectory = dataDirectory
    }

    public var vault: VaultDirectory {
        VaultDirectory(url: dataDirectory.appendingPathComponent(VaultDirectory.defaultName, isDirectory: true))
    }

    /// 把 Vault/ 改名为 `Vault-unreadable-<日期>`（同一天已有则加 -2、-3……），返回新位置
    public func quarantine(now: Date = Date()) throws -> URL {
        let base = Self.unreadablePrefix + Self.dayFormatter.string(from: now)
        var candidate = dataDirectory.appendingPathComponent(base, isDirectory: true)
        var suffix = 2
        while FileManager.default.fileExists(atPath: candidate.path) {
            candidate = dataDirectory.appendingPathComponent("\(base)-\(suffix)", isDirectory: true)
            suffix += 1
        }
        // 先在 Vault 之外留一份 vault-id，再改名，再放回新 Vault：任何一步之后崩溃，account 都找得回来
        try Self.stageVaultID(of: vault)
        try FileManager.default.moveItem(at: vault.url, to: candidate)
        try Self.adoptStagedVaultID(into: vault)
        logger.error("History key is missing; kept the old vault as \(candidate.lastPathComponent, privacy: .public)")
        return candidate
    }

    /// 自定义数据目录的 vault-id 决定钥匙串 account：改名前先复制到 Vault 之外（`.vault-id.pending`），
    /// account 不随改名而变，否则下次启动会换成新 account、又一次判定「密钥找不到」
    public static func stageVaultID(of vault: VaultDirectory) throws {
        guard FileManager.default.fileExists(atPath: vault.vaultIDURL.path) else { return }
        try PrivateFiles.write(try Data(contentsOf: vault.vaultIDURL), to: vault.stagedVaultIDURL)
    }

    /// 把暂存的 vault-id 放回 Vault（已有则保留现有的），然后删除暂存文件；没有暂存时什么也不做
    static func adoptStagedVaultID(into vault: VaultDirectory) throws {
        let staged = vault.stagedVaultIDURL
        guard FileManager.default.fileExists(atPath: staged.path) else { return }
        if !FileManager.default.fileExists(atPath: vault.vaultIDURL.path) {
            try PrivateFiles.createDirectory(at: vault.url)
            try FileManager.default.copyItem(at: staged, to: vault.vaultIDURL)
        }
        try FileManager.default.removeItem(at: staged)
    }

    /// 数据目录中所有保留的旧 Vault（按名称排序）
    public func unreadableFolders() -> [URL] {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: dataDirectory.path)) ?? []
        return names.filter { $0.hasPrefix(Self.unreadablePrefix) }.sorted()
            .map { dataDirectory.appendingPathComponent($0, isDirectory: true) }
    }

    /// 历史文件头部中的密钥 ID 与 keys 相同的保留目录：合并回当前 Vault（规则同 HistoryMerge，不按上限裁剪），
    /// 读回校验通过后才删除该目录。单个目录失败只记日志、原样保留
    @discardableResult
    public func restoreFolders(matching keys: HistoryKeys) -> RestoreResult {
        var restored: [URL] = []
        var corruptedBackup: URL?
        for folder in unreadableFolders() where Self.keyID(ofVaultAt: folder) == keys.keyID {
            do {
                let corruption = try restore(folder, keys: keys)
                corruptedBackup = corruptedBackup ?? corruption
                restored.append(folder)
            } catch {
                logger.error(
                    "Failed to restore \(folder.lastPathComponent, privacy: .public): \(error.localizedDescription, privacy: .public)"
                )
            }
        }
        return RestoreResult(restored: restored, corruptedHistoryBackup: corruptedBackup)
    }

    /// Vault 的历史文件头部中的密钥 ID；没有历史文件或头部无法识别时为 nil
    public static func keyID(ofVaultAt url: URL) -> Data? {
        let history = VaultDirectory(url: url).historyURL
        guard let file = try? Data(contentsOf: history, options: .mappedIfSafe) else { return nil }
        return try? EncryptedFileFormat.keyID(ofFile: file)
    }

    /// 返回当前 Vault 历史损坏时的备份位置（损坏的文件已被移入 Backups，按空历史合并）
    private func restore(_ folder: URL, keys: HistoryKeys) throws -> URL? {
        let old = VaultDirectory(url: folder)
        let restored = try EncryptedHistoryStorage(vaultDirectory: folder, keys: keys).load()
        // 同一把密钥：文件名与加密角色都相同，密文可以原样复制
        try copyMissingFiles(from: old.blobsDirectory, to: vault.blobsDirectory)
        try copyMissingFiles(from: old.backupsDirectory, to: vault.backupsDirectory)
        try mergeSecurityLog(from: old, keys: keys)

        let storage = EncryptedHistoryStorage(vaultDirectory: vault.url, keys: keys)
        let (current, corruptedBackup) = try loadCurrentHistory(storage)
        let merged = HistoryMerge.merging(base: current, incoming: restored.items)
        try storage.save(merged)
        guard try storage.load() == merged else { throw PlaintextMigration.MigrationError.verificationFailed }
        try FileManager.default.removeItem(at: folder)
        logger.info("Restored \(restored.items.count) items from \(folder.lastPathComponent, privacy: .public)")
        return corruptedBackup
    }

    private func loadCurrentHistory(_ storage: EncryptedHistoryStorage) throws -> (ClipHistory, URL?) {
        do {
            return (try storage.load(), nil)
        } catch HistoryStorageError.corrupted(let backupURL) {
            logger.error("The current history is corrupted, moved to \(backupURL.lastPathComponent, privacy: .public)")
            return (.empty, backupURL)
        }
    }

    /// 两份安全记录都读得出来时合并；任何一份读不出来时不合并，把旧目录的密文原样移进当前 Vault 的 Backups
    /// （同一把密钥，日后仍可解密），绝不随目录一起删除
    private func mergeSecurityLog(from old: VaultDirectory, keys: HistoryKeys) throws {
        guard FileManager.default.fileExists(atPath: old.securityLogURL.path) else { return }
        let previous = SecurityLogStore(dataDirectory: old.url, vault: old, keys: keys).load()
        let current = SecurityLogStore(dataDirectory: dataDirectory, vault: vault, keys: keys)
        let loaded = current.load()
        guard previous.allowsSaving, loaded.allowsSaving else {
            let name = "security-log.\(old.url.lastPathComponent).cubby"
            try PrivateFiles.createDirectory(at: vault.backupsDirectory)
            let destination = vault.backupsDirectory.appendingPathComponent(name, isDirectory: false)
            if !FileManager.default.fileExists(atPath: destination.path) {
                try FileManager.default.copyItem(at: old.securityLogURL, to: destination)
            }
            logger.error("A security log could not be read; kept the old one in Backups")
            return
        }
        try current.save(loaded.log.merging(previous.log))
    }

    private func copyMissingFiles(from source: URL, to destination: URL) throws {
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: source.path) else { return }
        try PrivateFiles.createDirectory(at: destination)
        for name in try fileManager.contentsOfDirectory(atPath: source.path) where !name.hasPrefix(".") {
            let target = destination.appendingPathComponent(name, isDirectory: false)
            guard !fileManager.fileExists(atPath: target.path) else { continue }
            try fileManager.copyItem(at: source.appendingPathComponent(name, isDirectory: false), to: target)
        }
    }

    /// 保留目录名中的日期：本地时区、公历、固定格式
    private static var dayFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }
}
