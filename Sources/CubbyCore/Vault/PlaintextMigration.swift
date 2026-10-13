import Foundation
import os

/// 把明文历史迁移进加密 Vault（E6），兼顾降级后再升级的合并（E7）。调用方须持有 VaultLock。
///
/// 顺序固定、每一步都可中断后续做：
/// ① 读旧明文历史（history.json，旧格式会先在内存中迁移）；
/// ② 逐条把被引用的文件（原图、缩略图、富文本格式、译后图片）加密写入 `Vault/Blobs/`，新文件名为 HMAC，已存在则跳过；
/// ③ 生成改写了引用的历史；已有加密历史时按 HistoryMerge 合并（E7），否则原样使用；
/// ④ 写 history.cubby（fsync + 原子替换），**读回校验**与写入的相同；
/// ⑤ 损坏备份加密进 `Vault/Backups/`，再把 history.json、Images/、history.v*.bak.json、损坏备份逐个原子改名进
///    `.migrated-plain/`；⑥ 递归删除 `.migrated-plain/`。
/// ④ 成功之前任何明文都不移动、不删除；每次启动先删残留的 `.migrated-plain/`（其中的内容必然已在 Vault 里）。
public struct PlaintextMigration: Sendable {
    /// 可注入故障（模拟崩溃）的检查点，按执行顺序
    enum Checkpoint: CaseIterable, Sendable {
        case blobsEncrypted
        case historyWritten
        case historyVerified
        case backupsEncrypted
        case historyFileMoved
        case plaintextMoved
    }

    public enum MigrationError: Error, Equatable, Sendable {
        /// history.json 由更新版本写入：不迁移，明文原样保留
        case legacyHistoryFromNewerVersion(Int)
        /// 已有的 history.cubby 由更新版本写入或密钥不对：不迁移，明文原样保留
        case encryptedHistoryUnusable
        /// 写入后读回的历史与写入的不同：明文原样保留
        case verificationFailed
    }

    /// 迁移结果（只有数量，不含任何内容）
    public struct Report: Equatable, Sendable {
        /// 旧明文历史中的条目数
        public let legacyItems: Int
        /// 迁移后加密历史中的条目数
        public let resultItems: Int
        /// 因文件丢失而丢弃的条目数（与旧版本启动修复的规则相同）
        public let droppedItems: Int
    }

    public let files: PlaintextFiles
    let vault: VaultDirectory
    let keys: HistoryKeys
    let historyLimit: Int
    /// 测试注入：在检查点抛错即模拟进程在此处崩溃
    var checkpoint: @Sendable (Checkpoint) throws -> Void = { _ in }
    private let logger = Logger(subsystem: "io.github.no1coder.Cubby", category: "Vault")

    public init(dataDirectory: URL, vault: VaultDirectory, keys: HistoryKeys, historyLimit: Int) {
        files = PlaintextFiles(dataDirectory: dataDirectory)
        self.vault = vault
        self.keys = keys
        self.historyLimit = max(historyLimit, 1)
    }

    /// 是否还有明文要迁移（含上次中断留下的一部分）
    public var isNeeded: Bool {
        files.containsPlaintext
    }

    /// 执行迁移。progress(已处理, 总数) 按条目报告，在调用线程上回调
    @discardableResult
    public func run(progress: (_ done: Int, _ total: Int) -> Void = { _, _ in }) throws -> Report {
        try files.removeLeftovers()
        let legacy = try loadLegacyHistory()
        let target = EncryptedBlobStore(directory: vault.blobsDirectory, keys: keys)
        var migrated: [ClipItem] = []
        progress(0, legacy.items.count)
        for (index, item) in legacy.items.enumerated() {
            if let rewritten = try encryptBlobs(of: item, into: target) { migrated.append(rewritten) }
            progress(index + 1, legacy.items.count)
        }
        try checkpoint(.blobsEncrypted)

        let storage = EncryptedHistoryStorage(vaultDirectory: vault.url, keys: keys)
        let result = try writeHistory(migrated, to: storage)
        try encryptCorruptBackups()
        try checkpoint(.backupsEncrypted)
        try files.moveAside(after: { try checkpoint(.historyFileMoved) })
        try checkpoint(.plaintextMoved)
        try files.removeLeftovers()
        let dropped = legacy.items.count - migrated.count
        logger.info("Migrated \(legacy.items.count) items into the vault (\(dropped) dropped for missing files)")
        return Report(legacyItems: legacy.items.count, resultItems: result.items.count, droppedItems: dropped)
    }

    // MARK: - 步骤

    /// ① 旧明文历史；不存在时为空。损坏的会被 JSONHistoryStorage 改名为损坏备份，按空历史继续（备份随后加密）
    private func loadLegacyHistory() throws -> ClipHistory {
        guard FileManager.default.fileExists(atPath: files.historyURL.path) else { return .empty }
        do {
            return try JSONHistoryStorage(fileURL: files.historyURL).load()
        } catch HistoryStorageError.unsupportedVersion(let found) {
            throw MigrationError.legacyHistoryFromNewerVersion(found)
        } catch HistoryStorageError.corrupted {
            logger.error("The plaintext history is corrupted; its backup is encrypted instead")
            return .empty
        }
    }

    /// ② 加密条目引用的文件，返回改写引用后的条目；原图丢失时为 nil
    private func encryptBlobs(of item: ClipItem, into target: EncryptedBlobStore) throws -> ClipItem? {
        try item.rewritingBlobNames { reference in
            let name = target.name(kind: reference.kind, contentHash: Self.legacyContentHash(reference.name))
            if !target.exists(name) {
                guard let data = try files.readLegacyBlob(reference.name) else { return nil }
                try target.write(data, name: name)
            }
            if reference.kind == .image {
                try encryptLegacyThumbnail(of: reference.name, as: target.thumbnailName(forImage: name), into: target)
            }
            return name
        }
    }

    private func encryptLegacyThumbnail(of image: String, as name: String, into target: EncryptedBlobStore) throws {
        guard !target.exists(name),
            let data = try files.readLegacyBlob(ImageThumbnail.legacyName(forImage: image))
        else { return }
        try target.write(data, name: name)
    }

    /// 明文文件名 `<内容摘要>.<扩展名>` 中的摘要；与新记录计算 HMAC 名时用的内容哈希一致，迁移后仍能去重
    static func legacyContentHash(_ name: String) -> String {
        (name as NSString).deletingPathExtension
    }

    /// ③ ④ 合并（如需要）、写入并读回校验，返回写入的历史
    private func writeHistory(_ migrated: [ClipItem], to storage: EncryptedHistoryStorage) throws -> ClipHistory {
        let existing = try loadExistingHistory(storage)
        guard !migrated.isEmpty else { return existing }
        let merged =
            existing.items.isEmpty
            ? ClipHistory(items: migrated)
            : HistoryMerge.merging(base: existing, incoming: migrated, limit: historyLimit)
        try storage.save(merged)
        try checkpoint(.historyWritten)
        guard try storage.load() == merged else { throw MigrationError.verificationFailed }
        try checkpoint(.historyVerified)
        return merged
    }

    /// 已有的加密历史：损坏的已被移入 Backups，按空历史继续；更新版本或密钥不对时中止（明文保留）
    private func loadExistingHistory(_ storage: EncryptedHistoryStorage) throws -> ClipHistory {
        do {
            return try storage.load()
        } catch HistoryStorageError.corrupted(let backupURL) {
            logger.error(
                "The encrypted history is corrupted, moved to \(backupURL.lastPathComponent, privacy: .public)")
            return .empty
        } catch HistoryStorageError.unsupportedVersion, HistoryStorageError.keyMismatch {
            throw MigrationError.encryptedHistoryUnusable
        }
    }

    /// ⑤ 前半：明文损坏备份加密进 `Vault/Backups/<原名>.cubby`（已存在则跳过，可续做）
    private func encryptCorruptBackups() throws {
        for url in try files.corruptBackups() {
            let name = url.deletingPathExtension().lastPathComponent + ".cubby"
            let destination = vault.backupsDirectory.appendingPathComponent(name, isDirectory: false)
            guard !FileManager.default.fileExists(atPath: destination.path) else { continue }
            let data = try Data(contentsOf: url)
            try PrivateFiles.createDirectory(at: vault.backupsDirectory)
            try StreamingFileWriter.write(to: destination) { write in
                try EncryptedFileFormat.encrypt(keys: keys, role: Self.backupRole(name), into: write) { try $0(data) }
            }
        }
    }

    /// 加密损坏备份的角色（绑定文件名）
    public static func backupRole(_ name: String) -> String {
        "backup:" + name
    }
}
