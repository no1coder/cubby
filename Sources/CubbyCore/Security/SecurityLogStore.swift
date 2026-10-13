import Foundation
import os

/// 安全记录的读写：加密文件 `Vault/security-log.cubby`（E1、E8）。
///
/// - 读取失败（密钥不对、内容损坏、无法解码）而不是「文件不存在」时，本次运行不得保存——
///   否则会用空记录覆盖读不出来的旧记录；load() 的结果据此给出 allowsSaving；
/// - 旧版本的明文 `security-log.json`：加密文件不存在时读入、加密保存成功后删除；读不出来时原样保留且不保存；
/// - 历史已锁定时根本不创建本类型（只在内存里记录，见 AddressGuardController）。
public struct SecurityLogStore: Sendable {
    /// 加密文件的角色（参与认证）
    public static let role = "security-log"
    static let legacyFileName = "security-log.json"

    /// 读取结果
    public struct Loaded: Equatable, Sendable {
        public let log: SecurityLog
        /// false：已有的记录读不出来，本次运行不保存
        public let allowsSaving: Bool
    }

    public let url: URL
    public let legacyURL: URL
    private let keys: HistoryKeys
    private let logger = Logger(subsystem: "io.github.no1coder.Cubby", category: "Security")

    public init(dataDirectory: URL, vault: VaultDirectory, keys: HistoryKeys) {
        url = vault.securityLogURL
        legacyURL = dataDirectory.appendingPathComponent(Self.legacyFileName, isDirectory: false)
        self.keys = keys
    }

    public func load() -> Loaded {
        StreamingFileWriter.removeStaleTemporaryFiles(for: url)
        if FileManager.default.fileExists(atPath: url.path) {
            do {
                return Loaded(log: mergingLegacyFile(into: try decrypt()), allowsSaving: true)
            } catch {
                logger.error(
                    "Failed to read the security log, not saving: \(error.localizedDescription, privacy: .public)")
                return Loaded(log: SecurityLog(), allowsSaving: false)
            }
        }
        guard FileManager.default.fileExists(atPath: legacyURL.path) else {
            return Loaded(log: SecurityLog(), allowsSaving: true)
        }
        return migrateLegacyFile()
    }

    /// 加密后原子写入（0600 临时文件 → fsync → rename），全程不落明文
    public func save(_ log: SecurityLog) throws {
        let data = try Self.encoder.encode(log)
        try PrivateFiles.createDirectory(at: url.deletingLastPathComponent())
        try StreamingFileWriter.write(to: url) { write in
            try EncryptedFileFormat.encrypt(keys: keys, role: Self.role, into: write) { try $0(data) }
        }
    }

    private func decrypt() throws -> SecurityLog {
        let file = try Data(contentsOf: url)
        return try EncryptedFileFormat.withDecryptedContents(of: file, keys: keys, role: Self.role) {
            try Self.decoder.decode(SecurityLog.self, from: $0)
        }
    }

    /// 读入旧明文记录、加密保存，成功后删除明文；任何一步失败都保留明文
    private func migrateLegacyFile() -> Loaded {
        let log: SecurityLog
        do {
            log = try Self.decoder.decode(SecurityLog.self, from: Data(contentsOf: legacyURL))
        } catch {
            logger.error(
                "Failed to read the legacy security log, not saving: \(error.localizedDescription, privacy: .public)")
            return Loaded(log: SecurityLog(), allowsSaving: false)
        }
        do {
            try save(log)
            try FileManager.default.removeItem(at: legacyURL)
        } catch {
            logger.error("Failed to encrypt the legacy security log: \(error.localizedDescription, privacy: .public)")
        }
        return Loaded(log: log, allowsSaving: true)
    }

    /// 加密文件与明文同时存在（降级期间旧版本又写了明文，或上次没删掉）：并入明文、保存后删除明文。
    /// 明文读不出来或保存失败时原样保留明文，返回加密文件中的记录
    private func mergingLegacyFile(into log: SecurityLog) -> SecurityLog {
        guard FileManager.default.fileExists(atPath: legacyURL.path) else { return log }
        do {
            let legacy = try Self.decoder.decode(SecurityLog.self, from: Data(contentsOf: legacyURL))
            let merged = log.merging(legacy)
            try save(merged)
            try FileManager.default.removeItem(at: legacyURL)
            return merged
        } catch {
            logger.error("Failed to merge the legacy security log: \(error.localizedDescription, privacy: .public)")
            return log
        }
    }

    private static var encoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }

    private static var decoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}

extension SecurityLog {
    /// 并入另一份记录（解锁时把内存中的记录并进磁盘上的）：按 id 去重，同 id 以 self 为准，按时间从新到旧
    public func merging(_ other: SecurityLog) -> SecurityLog {
        let ids = Set(entries.map(\.id))
        let combined = entries + other.entries.filter { !ids.contains($0.id) }
        return SecurityLog(entries: combined.sorted { $0.date > $1.date })
    }
}
