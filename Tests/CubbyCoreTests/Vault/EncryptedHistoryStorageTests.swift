import Foundation
import Testing
@testable import CubbyCore

@Suite("EncryptedHistoryStorage 加密历史的读写与异常")
struct EncryptedHistoryStorageTests {
    private func sampleHistory() -> ClipHistory {
        ClipHistory(items: [
            Fixtures.text("你好 📋 secret", favorite: true, source: SourceApp(bundleID: "com.apple.Notes", name: "备忘录")),
            Fixtures.text("https://example.com"),
            Fixtures.text("富文本", formatsName: "abc.formats"),
            Fixtures.image(name: "abc.png", width: 3, height: 4),
            Fixtures.files(["/tmp/a b.txt"]),
        ])
    }

    private func makeStorage(_ vault: URL, keyByte: UInt8 = 0x42) throws -> EncryptedHistoryStorage {
        EncryptedHistoryStorage(vaultDirectory: vault, keys: try VaultFixtures.keys(keyByte))
    }

    @Test("文件不存在时返回空历史，且不创建任何文件")
    func missingFileReturnsEmpty() throws {
        let dir = try TempDirectory.make()
        defer { TempDirectory.remove(dir) }
        let vault = dir.appendingPathComponent("Vault")

        let outcome = try makeStorage(vault).loadReportingMigration()
        #expect(outcome.history == .empty)
        #expect(!outcome.didMigrate)
        #expect(!FileManager.default.fileExists(atPath: vault.path))
    }

    @Test("保存后读取得到相同历史；文件为 0600、目录为 0700，内容不含明文")
    func roundTrip() throws {
        let dir = try TempDirectory.make()
        defer { TempDirectory.remove(dir) }
        let vault = dir.appendingPathComponent("Vault")
        let storage = try makeStorage(vault)

        let history = sampleHistory()
        try storage.save(history)

        #expect(try storage.load() == history)
        #expect(storage.fileURL.lastPathComponent == "history.cubby")
        #expect(storage.fileURL.deletingLastPathComponent().standardizedFileURL == vault.standardizedFileURL)
        #expect(try TempDirectory.permissions(of: storage.fileURL) == 0o600)
        #expect(try TempDirectory.permissions(of: vault) == 0o700)
        let raw = try Data(contentsOf: storage.fileURL)
        #expect(raw.prefix(4) == Data("CBYV".utf8))
        #expect(raw.range(of: Data("secret".utf8)) == nil)
        #expect(raw.range(of: Data("schemaVersion".utf8)) == nil)
    }

    @Test("解密后的明文与整块编码逐字节相同；角色为 history")
    func plaintextMatchesEncoder() throws {
        let dir = try TempDirectory.make()
        defer { TempDirectory.remove(dir) }
        let keys = try VaultFixtures.keys()
        let storage = EncryptedHistoryStorage(vaultDirectory: dir, keys: keys)

        let history = sampleHistory()
        try storage.save(history)

        let file = try Data(contentsOf: storage.fileURL)
        let plaintext = try EncryptedFileFormat.decrypt(file, keys: keys, role: EncryptedHistoryStorage.role)
        #expect(plaintext == (try HistoryMigrator.encode(history)))
        #expect(EncryptedHistoryStorage.role == "history")
    }

    @Test("空历史与跨多个 64KB 段的大历史都能往返")
    func emptyAndLargeRoundTrip() throws {
        let dir = try TempDirectory.make()
        defer { TempDirectory.remove(dir) }
        let storage = try makeStorage(dir)

        try storage.save(.empty)
        #expect(try storage.load() == .empty)

        let large = ClipHistory(
            items: (0..<400).map { Fixtures.text("条目 \($0) " + String(repeating: "x", count: 900)) })
        try storage.save(large)
        #expect(try storage.load() == large)
        let size = try #require(try FileManager.default.attributesOfItem(atPath: storage.fileURL.path)[.size] as? Int)
        #expect(size > 4 * EncryptedFileFormat.segmentPlaintextByteCount)
    }

    @Test("密钥不对：抛 keyMismatch，文件原样保留、不产生备份")
    func keyMismatchLeavesFile() throws {
        let dir = try TempDirectory.make()
        defer { TempDirectory.remove(dir) }
        try makeStorage(dir, keyByte: 1).save(sampleHistory())
        let storage = try makeStorage(dir, keyByte: 2)
        let before = try Data(contentsOf: storage.fileURL)

        #expect(throws: HistoryStorageError.keyMismatch) { try storage.load() }
        #expect(try Data(contentsOf: storage.fileURL) == before)
        #expect(!FileManager.default.fileExists(atPath: storage.backupsDirectory.path))
    }

    @Test("密钥正确但内容损坏：加密文件原样移入 Backups/ 并抛 corrupted，之后视为空历史")
    func corruptedIsMovedToBackups() throws {
        let dir = try TempDirectory.make()
        defer { TempDirectory.remove(dir) }
        let storage = try makeStorage(dir)
        try storage.save(sampleHistory())
        var damaged = try Data(contentsOf: storage.fileURL)
        damaged[damaged.count - 1] ^= 0xFF
        try damaged.write(to: storage.fileURL)

        let error = #expect(throws: HistoryStorageError.self) { try storage.load() }
        guard case .corrupted(let backupURL) = error else {
            Issue.record("应当抛出 corrupted 错误")
            return
        }

        #expect(!FileManager.default.fileExists(atPath: storage.fileURL.path))
        #expect(
            backupURL.deletingLastPathComponent().standardizedFileURL == storage.backupsDirectory.standardizedFileURL)
        #expect(storage.backupsDirectory.lastPathComponent == "Backups")
        #expect(backupURL.lastPathComponent.hasPrefix("history.corrupt-"))
        #expect(backupURL.pathExtension == "cubby")
        #expect(try Data(contentsOf: backupURL) == damaged)
        #expect(try TempDirectory.permissions(of: storage.backupsDirectory) == 0o700)
        #expect(try storage.load() == .empty)
    }

    @Test("头部非法、截断到头部以内的文件同样移入 Backups/", arguments: ["", "CBY", "not encrypted json {}"])
    func malformedHeaderIsMoved(_ content: String) throws {
        let dir = try TempDirectory.make()
        defer { TempDirectory.remove(dir) }
        let storage = try makeStorage(dir)
        try Data(content.utf8).write(to: storage.fileURL)

        let error = #expect(throws: HistoryStorageError.self) { try storage.load() }
        guard case .corrupted(let backupURL) = error else {
            Issue.record("应当抛出 corrupted 错误")
            return
        }
        #expect(try Data(contentsOf: backupURL) == Data(content.utf8))
    }

    @Test("同一秒内两次损坏：备份互不覆盖")
    func repeatedCorruption() throws {
        let dir = try TempDirectory.make()
        defer { TempDirectory.remove(dir) }
        let storage = try makeStorage(dir)
        var backups: Set<URL> = []
        for content in ["bad-1", "bad-2"] {
            try Data(content.utf8).write(to: storage.fileURL)
            if case .corrupted(let url) = #expect(throws: HistoryStorageError.self, performing: { try storage.load() })
            {
                backups.insert(url)
            }
        }
        #expect(backups.count == 2)
    }

    @Test("解密成功但 JSON 非法：按损坏处理并移入 Backups/")
    func decryptedGarbageIsCorrupted() throws {
        let dir = try TempDirectory.make()
        defer { TempDirectory.remove(dir) }
        let keys = try VaultFixtures.keys()
        let storage = EncryptedHistoryStorage(vaultDirectory: dir, keys: keys)
        try EncryptedFileFormat.encrypt(Data("{not json".utf8), keys: keys, role: "history").write(to: storage.fileURL)

        let error = #expect(throws: HistoryStorageError.self) { try storage.load() }
        guard case .corrupted = error else {
            Issue.record("应当抛出 corrupted 错误")
            return
        }
        #expect(!FileManager.default.fileExists(atPath: storage.fileURL.path))
    }

    @Test("把其他角色的加密文件换成历史文件：按损坏处理")
    func swappedFileIsCorrupted() throws {
        let dir = try TempDirectory.make()
        defer { TempDirectory.remove(dir) }
        let keys = try VaultFixtures.keys()
        let storage = EncryptedHistoryStorage(vaultDirectory: dir, keys: keys)
        let json = try HistoryMigrator.encode(sampleHistory())
        try EncryptedFileFormat.encrypt(json, keys: keys, role: "security-log").write(to: storage.fileURL)

        #expect(throws: HistoryStorageError.self) { try storage.load() }
        #expect(!FileManager.default.fileExists(atPath: storage.fileURL.path))
    }

    @Test("更高的历史 schema 版本：抛 unsupportedVersion，文件不动、不备份")
    func newerSchemaVersion() throws {
        let dir = try TempDirectory.make()
        defer { TempDirectory.remove(dir) }
        let keys = try VaultFixtures.keys()
        let storage = EncryptedHistoryStorage(vaultDirectory: dir, keys: keys)
        let file = try EncryptedFileFormat.encrypt(
            Data("{\"schemaVersion\":99,\"items\":[]}".utf8), keys: keys, role: "history")
        try file.write(to: storage.fileURL)

        #expect(throws: HistoryStorageError.unsupportedVersion(found: 99)) { try storage.load() }
        #expect(try Data(contentsOf: storage.fileURL) == file)
        #expect(!FileManager.default.fileExists(atPath: storage.backupsDirectory.path))
    }

    @Test("更高的加密格式版本：抛 unsupportedVersion，文件不动")
    func newerFileFormatVersion() throws {
        let dir = try TempDirectory.make()
        defer { TempDirectory.remove(dir) }
        let storage = try makeStorage(dir)
        try storage.save(sampleHistory())
        var file = try Data(contentsOf: storage.fileURL)
        file[4] = EncryptedFileFormat.currentVersion + 1
        try file.write(to: storage.fileURL)

        let expected = HistoryStorageError.unsupportedVersion(found: Int(EncryptedFileFormat.currentVersion) + 1)
        #expect(throws: expected) { try storage.load() }
        #expect(try Data(contentsOf: storage.fileURL) == file)
    }

    @Test("旧 schema 版本：在内存中迁移，并先把加密原文件复制到 Backups/ 留底（已有则保留）")
    func olderSchemaIsBackedUp() throws {
        let dir = try TempDirectory.make()
        defer { TempDirectory.remove(dir) }
        let keys = try VaultFixtures.keys()
        let storage = EncryptedHistoryStorage(vaultDirectory: dir, keys: keys)
        let v0 = try EncryptedFileFormat.encrypt(Data("{\"items\":[]}".utf8), keys: keys, role: "history")
        try v0.write(to: storage.fileURL)

        let outcome = try storage.loadReportingMigration()

        #expect(outcome.didMigrate)
        #expect(outcome.sourceVersion == 0)
        let backup = storage.migrationBackupURL(forVersion: 0)
        #expect(backup.lastPathComponent == "history.v0.bak.cubby")
        #expect(backup.deletingLastPathComponent().standardizedFileURL == storage.backupsDirectory.standardizedFileURL)
        #expect(try Data(contentsOf: backup) == v0)
        #expect(try TempDirectory.permissions(of: backup) == 0o600)

        // 再次读取：备份已存在则保持最早的那份
        let later = try EncryptedFileFormat.encrypt(Data("{\"items\":[ ]}".utf8), keys: keys, role: "history")
        try later.write(to: storage.fileURL)
        _ = try storage.loadReportingMigration()
        #expect(try Data(contentsOf: backup) == v0)
    }

    @Test("读取时清理过期的临时文件，保留新的")
    func removesStaleTemporaryFiles() throws {
        let dir = try TempDirectory.make()
        defer { TempDirectory.remove(dir) }
        let storage = try makeStorage(dir)
        let stale = dir.appendingPathComponent(".history.cubby.\(UUID().uuidString).tmp")
        let fresh = dir.appendingPathComponent(".history.cubby.\(UUID().uuidString).tmp")
        try Data("x".utf8).write(to: stale)
        try Data("y".utf8).write(to: fresh)
        try FileManager.default.setAttributes(
            [.modificationDate: Date(timeIntervalSinceNow: -3600)], ofItemAtPath: stale.path)

        #expect(try storage.load() == .empty)
        #expect(!FileManager.default.fileExists(atPath: stale.path))
        #expect(FileManager.default.fileExists(atPath: fresh.path))
    }

    @Test("保存失败（目标位置被目录占用）时抛出，且不留临时文件")
    func saveFailureLeavesNoTemporaryFile() throws {
        let dir = try TempDirectory.make()
        defer { TempDirectory.remove(dir) }
        let storage = try makeStorage(dir)
        try FileManager.default.createDirectory(
            at: storage.fileURL.appendingPathComponent("child"), withIntermediateDirectories: true)

        #expect(throws: (any Error).self) { try storage.save(sampleHistory()) }
        let names = try FileManager.default.contentsOfDirectory(atPath: dir.path)
        #expect(names == ["history.cubby"])
    }
}
