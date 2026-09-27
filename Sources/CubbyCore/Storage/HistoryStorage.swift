import Foundation

/// 历史记录持久化抽象，便于替换实现与测试
public protocol HistoryPersisting: Sendable {
    func load() throws -> ClipHistory
    /// 读取历史并报告原始数据的格式版本；发生迁移时调用方应以当前版本重新保存
    func loadReportingMigration() throws -> HistoryMigrator.Outcome
    func save(_ history: ClipHistory) throws
}

public extension HistoryPersisting {
    /// 默认实现：不涉及格式版本的存储视为始终是当前版本
    func loadReportingMigration() throws -> HistoryMigrator.Outcome {
        HistoryMigrator.Outcome(history: try load())
    }
}

public enum HistoryStorageError: Error, Equatable {
    /// 历史文件损坏，已移动到 backupURL 以免被覆盖
    case corrupted(backupURL: URL)
    /// 历史文件由更新版本的 Cubby 写入（版本号高于当前支持的版本）；原文件保持原样，调用方应只读
    case unsupportedVersion(found: Int)
}

/// 以 JSON 文件保存历史记录，写入为原子操作。
/// 读取时识别格式版本：旧版本先备份再在内存中迁移，更高版本拒绝读取且绝不改动原文件。
public struct JSONHistoryStorage: HistoryPersisting {
    public let fileURL: URL

    public init(fileURL: URL) {
        self.fileURL = fileURL
    }

    public func load() throws -> ClipHistory {
        try loadReportingMigration().history
    }

    public func loadReportingMigration() throws -> HistoryMigrator.Outcome {
        StreamingFileWriter.removeStaleTemporaryFiles(for: fileURL)
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            return HistoryMigrator.Outcome(history: .empty)
        }

        // 内存映射读取：映射页是文件的干净页，不计入 footprint；整块读入的 26MB 级 malloc 缓冲释放后
        // 仍会以空闲大块的形式滞留在进程里（实测 +26.5MB 对比 +0.1MB）。
        // 安全前提：本文件只会被原子替换（StreamingFileWriter / PrivateFiles.write 都是写临时文件再 rename），
        // 从不就地截断或改写；映射始终指向旧 inode，替换或移走（损坏备份）都不影响已映射的内容。
        // 若有外部进程就地截断该文件，访问映射会触发 SIGBUS；data 只在本次读取与解码期间存活，窗口很短。
        // 用 mappedIfSafe 而非 alwaysMapped：本地卷上同样映射，网络卷（他机可能就地改写）自动退回整块读取
        let data = try Data(contentsOf: fileURL, options: .mappedIfSafe)
        let outcome: HistoryMigrator.Outcome
        do {
            outcome = try HistoryMigrator.migrate(data)
        } catch HistoryMigrationError.unsupportedVersion(let found) {
            // 更新版本写入的文件：不移动、不备份、不改写，防止降级运行时丢数据
            throw HistoryStorageError.unsupportedVersion(found: found)
        } catch {
            throw try moveAsideCorruptedFile()
        }

        if outcome.didMigrate {
            // 迁移只发生在内存中，原文件要等调用方保存时才会被改写；在此之前先留好原始数据
            try backUpBeforeMigration(data, version: outcome.sourceVersion)
        }
        return outcome
    }

    /// 始终以当前格式版本写入：逐条流式编码进 0600 的临时文件，再原子替换原文件；失败时原文件不变
    public func save(_ history: ClipHistory) throws {
        try PrivateFiles.createDirectory(at: fileURL.deletingLastPathComponent())
        try StreamingFileWriter.write(to: fileURL) { write in
            try HistoryMigrator.encode(history, into: write)
        }
    }

    /// 迁移前备份的位置：同目录下 `<文件名>.v<旧版本>.bak.json`，如 history.v0.bak.json
    public func migrationBackupURL(forVersion version: Int) -> URL {
        let baseName = fileURL.deletingPathExtension().lastPathComponent
        return fileURL.deletingLastPathComponent().appendingPathComponent("\(baseName).v\(version).bak.json")
    }

    // MARK: - 内部实现

    /// 写入迁移备份（0600）；已存在则保留，确保留下的是最早的原始数据。写入失败会抛出，调用方据此不再写盘
    private func backUpBeforeMigration(_ data: Data, version: Int) throws {
        let backupURL = migrationBackupURL(forVersion: version)
        guard !FileManager.default.fileExists(atPath: backupURL.path) else { return }
        try PrivateFiles.write(data, to: backupURL)
    }

    /// 把损坏的文件移到备份位置，返回应抛出的 corrupted 错误
    private func moveAsideCorruptedFile() throws -> HistoryStorageError {
        // 追加随机后缀：同一秒内再次损坏时备份名不冲突，否则 moveItem 失败会抛出普通错误
        let suffix = UUID().uuidString.prefix(8)
        let backupURL = fileURL.deletingPathExtension()
            .appendingPathExtension("corrupt-\(Int(Date().timeIntervalSince1970))-\(suffix).json")
        try FileManager.default.moveItem(at: fileURL, to: backupURL)
        return .corrupted(backupURL: backupURL)
    }
}
