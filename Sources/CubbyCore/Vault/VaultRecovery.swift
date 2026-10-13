import Foundation
import os

/// 密钥找不到但 Vault 已有数据（E8 ②）：把 Vault 改名保留、之后若钥匙串恢复了对应密钥则自动还原。
/// 调用方须持有 VaultLock。任何路径都不删除无法解密的数据。
public struct VaultRecovery: Sendable {
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
        try FileManager.default.moveItem(at: vault.url, to: candidate)
        try keepVaultID(from: VaultDirectory(url: candidate))
        logger.error("History key is missing; kept the old vault as \(candidate.lastPathComponent, privacy: .public)")
        return candidate
    }

    /// 自定义数据目录的 vault-id 决定钥匙串 account：留一份在新 Vault 里，account 不随改名而变，
    /// 否则下次启动会换成新 account、又一次判定「密钥找不到」
    private func keepVaultID(from old: VaultDirectory) throws {
        guard FileManager.default.fileExists(atPath: old.vaultIDURL.path) else { return }
        try PrivateFiles.createDirectory(at: vault.url)
        try FileManager.default.copyItem(at: old.vaultIDURL, to: vault.vaultIDURL)
    }

    /// 数据目录中所有保留的旧 Vault（按名称排序）
    public func unreadableFolders() -> [URL] {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: dataDirectory.path)) ?? []
        return names.filter { $0.hasPrefix(Self.unreadablePrefix) }.sorted()
            .map { dataDirectory.appendingPathComponent($0, isDirectory: true) }
    }

    /// 历史文件头部中的密钥 ID 与 keys 相同的保留目录：合并回当前 Vault（规则同 HistoryMerge），
    /// 读回校验通过后才删除该目录。返回已还原的目录；单个目录失败只记日志、原样保留
    @discardableResult
    public func restoreFolders(matching keys: HistoryKeys, historyLimit: Int) -> [URL] {
        unreadableFolders().filter { folder in
            guard Self.keyID(ofVaultAt: folder) == keys.keyID else { return false }
            do {
                try restore(folder, keys: keys, historyLimit: historyLimit)
                return true
            } catch {
                logger.error(
                    "Failed to restore \(folder.lastPathComponent, privacy: .public): \(error.localizedDescription, privacy: .public)"
                )
                return false
            }
        }
    }

    /// Vault 的历史文件头部中的密钥 ID；没有历史文件或头部无法识别时为 nil
    public static func keyID(ofVaultAt url: URL) -> Data? {
        let history = VaultDirectory(url: url).historyURL
        guard let file = try? Data(contentsOf: history, options: .mappedIfSafe) else { return nil }
        return try? EncryptedFileFormat.keyID(ofFile: file)
    }

    private func restore(_ folder: URL, keys: HistoryKeys, historyLimit: Int) throws {
        let old = VaultDirectory(url: folder)
        let restored = try EncryptedHistoryStorage(vaultDirectory: folder, keys: keys).load()
        // 同一把密钥：文件名与加密角色都相同，密文可以原样复制
        try copyMissingFiles(from: old.blobsDirectory, to: vault.blobsDirectory)
        try copyMissingFiles(from: old.backupsDirectory, to: vault.backupsDirectory)
        try mergeSecurityLog(from: old, keys: keys)

        let storage = EncryptedHistoryStorage(vaultDirectory: vault.url, keys: keys)
        let merged = HistoryMerge.merging(base: try storage.load(), incoming: restored.items, limit: historyLimit)
        try storage.save(merged)
        guard try storage.load() == merged else { throw PlaintextMigration.MigrationError.verificationFailed }
        try FileManager.default.removeItem(at: folder)
        logger.info("Restored \(restored.items.count) items from \(folder.lastPathComponent, privacy: .public)")
    }

    private func mergeSecurityLog(from old: VaultDirectory, keys: HistoryKeys) throws {
        guard FileManager.default.fileExists(atPath: old.securityLogURL.path) else { return }
        let previous = SecurityLogStore(dataDirectory: old.url, vault: old, keys: keys).load()
        let current = SecurityLogStore(dataDirectory: dataDirectory, vault: vault, keys: keys)
        let loaded = current.load()
        guard previous.allowsSaving, loaded.allowsSaving else { return }
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
