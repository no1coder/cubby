import Foundation

/// 加密的历史文件 `<Vault>/history.cubby`，语义与 JSONHistoryStorage 一致（E4–E8、E12）：
/// - 保存：流式编码 → 分段加密 → StreamingFileWriter（0600 临时文件、fsync、原子替换），全程不落明文；
/// - 读取：密文按 mappedIfSafe 映射，解密到匿名映射内存，解码后立即归还；
/// - 更高版本（格式或 schema）：抛 unsupportedVersion，不移动、不改写；
/// - 密钥 ID 不符：抛 keyMismatch，不移动任何文件；
/// - 密钥正确但认证或解码失败：把加密文件原样移入 `Backups/` 并抛 corrupted。
public struct EncryptedHistoryStorage: HistoryPersisting {
    /// 历史文件的加密角色（参与认证，防止与其他加密文件互换）
    public static let role = "history"
    private static let corruptBackupPrefix = "corrupt"
    private static let backupExtension = "cubby"
    /// 损坏备份名中随机后缀的长度：同一秒内再次损坏时备份名不冲突
    private static let backupSuffixLength = 8

    public let vault: VaultDirectory
    private let keys: HistoryKeys

    public init(vaultDirectory: URL, keys: HistoryKeys) {
        vault = VaultDirectory(url: vaultDirectory)
        self.keys = keys
    }

    public var fileURL: URL { vault.historyURL }
    public var backupsDirectory: URL { vault.backupsDirectory }

    public func load() throws -> ClipHistory {
        try loadReportingMigration().history
    }

    public func loadReportingMigration() throws -> HistoryMigrator.Outcome {
        StreamingFileWriter.removeStaleTemporaryFiles(for: fileURL)
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            return HistoryMigrator.Outcome(history: .empty)
        }

        // 密文映射读取的安全前提同 JSONHistoryStorage：本文件只会被原子替换或整体移走，从不就地改写
        let file = try Data(contentsOf: fileURL, options: .mappedIfSafe)
        let outcome: HistoryMigrator.Outcome
        do {
            outcome = try EncryptedFileFormat.withDecryptedContents(of: file, keys: keys, role: Self.role) {
                try HistoryMigrator.migrate($0)
            }
        } catch EncryptedFileError.keyMismatch {
            throw HistoryStorageError.keyMismatch
        } catch EncryptedFileError.unsupportedVersion(let found) {
            throw HistoryStorageError.unsupportedVersion(found: found)
        } catch HistoryMigrationError.unsupportedVersion(let found) {
            throw HistoryStorageError.unsupportedVersion(found: found)
        } catch is EncryptedFileError {
            throw try moveAsideCorruptedFile()
        } catch is HistoryMigrationError {
            throw try moveAsideCorruptedFile()
        }

        if outcome.didMigrate {
            // 迁移只在内存中进行；保存前先留一份加密的原文件
            try backUpBeforeMigration(file, version: outcome.sourceVersion)
        }
        return outcome
    }

    /// 始终以当前 schema 版本写入；失败时原文件不变
    public func save(_ history: ClipHistory) throws {
        try PrivateFiles.createDirectory(at: vault.url)
        try StreamingFileWriter.write(to: fileURL) { write in
            try EncryptedFileFormat.encrypt(keys: keys, role: Self.role, into: write) { plaintext in
                try HistoryMigrator.encode(history, into: plaintext)
            }
        }
    }

    /// 迁移前备份：`Backups/history.v<旧版本>.bak.cubby`（加密原文件的副本）
    public func migrationBackupURL(forVersion version: Int) -> URL {
        backupsDirectory.appendingPathComponent("\(baseName).v\(version).bak.\(Self.backupExtension)")
    }

    // MARK: - 内部实现

    private var baseName: String {
        fileURL.deletingPathExtension().lastPathComponent
    }

    /// 已存在则保留最早的那份；以 0600 原子写入
    private func backUpBeforeMigration(_ file: Data, version: Int) throws {
        let backupURL = migrationBackupURL(forVersion: version)
        guard !FileManager.default.fileExists(atPath: backupURL.path) else { return }
        try PrivateFiles.createDirectory(at: backupsDirectory)
        try StreamingFileWriter.write(to: backupURL) { try $0(file) }
    }

    /// 把损坏的加密文件原样移入 Backups/，返回应抛出的 corrupted 错误
    private func moveAsideCorruptedFile() throws -> HistoryStorageError {
        try PrivateFiles.createDirectory(at: backupsDirectory)
        let suffix = UUID().uuidString.prefix(Self.backupSuffixLength)
        let timestamp = Int(Date().timeIntervalSince1970)
        let name = "\(baseName).\(Self.corruptBackupPrefix)-\(timestamp)-\(suffix).\(Self.backupExtension)"
        let backupURL = backupsDirectory.appendingPathComponent(name)
        try FileManager.default.moveItem(at: fileURL, to: backupURL)
        return .corrupted(backupURL: backupURL)
    }
}
