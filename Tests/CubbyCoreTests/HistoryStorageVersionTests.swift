import Foundation
import Testing
@testable import CubbyCore

/// JSONHistoryStorage 的版本号写入、旧版本迁移备份与高版本保护
@Suite("JSONHistoryStorage 版本号与迁移")
struct HistoryStorageVersionTests {
    private func historyURL(in dir: URL) -> URL {
        dir.appendingPathComponent("history.json")
    }

    // MARK: - v0 迁移

    @Test("v0 文件无损加载，并报告来自 v0")
    func v0LoadsLosslessly() throws {
        let dir = try TempDirectory.make()
        defer { TempDirectory.remove(dir) }

        let fileURL = historyURL(in: dir)
        try HistoryFixtures.write(HistoryFixtures.v0JSON, to: fileURL)
        let storage = JSONHistoryStorage(fileURL: fileURL)

        let outcome = try storage.loadReportingMigration()
        #expect(outcome.history.items == HistoryFixtures.v0Items)
        #expect(outcome.sourceVersion == 0)
        #expect(outcome.didMigrate)
        // load() 是同一流程的便捷版本
        #expect(try storage.load().items == HistoryFixtures.v0Items)
    }

    @Test("v0 加载时备份为 history.v0.bak.json：字节一致、权限 0600，原文件暂不改动")
    func v0LoadCreatesPrivateBackup() throws {
        let dir = try TempDirectory.make()
        defer { TempDirectory.remove(dir) }

        let fileURL = historyURL(in: dir)
        let original = try HistoryFixtures.write(HistoryFixtures.v0JSON, to: fileURL)
        try FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: fileURL.path)
        let storage = JSONHistoryStorage(fileURL: fileURL)

        _ = try storage.loadReportingMigration()

        let backupURL = dir.appendingPathComponent("history.v0.bak.json")
        #expect(storage.migrationBackupURL(forVersion: 0).standardizedFileURL == backupURL.standardizedFileURL)
        #expect(try Data(contentsOf: backupURL) == original)
        #expect(try TempDirectory.permissions(of: backupURL) == 0o600)
        #expect(try Data(contentsOf: fileURL) == original)
        #expect(TempDirectory.fileNames(in: dir) == ["history.json", "history.v0.bak.json"])
    }

    @Test("v0 加载后再次保存：文件带 schemaVersion 1，再读不再迁移，备份保持不变")
    func v0SaveWritesCurrentVersion() throws {
        let dir = try TempDirectory.make()
        defer { TempDirectory.remove(dir) }

        let fileURL = historyURL(in: dir)
        let original = try HistoryFixtures.write(HistoryFixtures.v0JSON, to: fileURL)
        let storage = JSONHistoryStorage(fileURL: fileURL)

        let migrated = try storage.loadReportingMigration().history
        try storage.save(migrated)

        #expect(try HistoryFixtures.schemaVersion(ofFileAt: fileURL) == 1)
        let reloaded = try storage.loadReportingMigration()
        #expect(reloaded.history.items == HistoryFixtures.v0Items)
        #expect(!reloaded.didMigrate)
        #expect(try Data(contentsOf: storage.migrationBackupURL(forVersion: 0)) == original)
    }

    @Test("迁移备份已存在时不覆盖（保留最早的原始数据）")
    func existingBackupIsNotOverwritten() throws {
        let dir = try TempDirectory.make()
        defer { TempDirectory.remove(dir) }

        let fileURL = historyURL(in: dir)
        try HistoryFixtures.write(HistoryFixtures.v0JSON, to: fileURL)
        let storage = JSONHistoryStorage(fileURL: fileURL)
        let backupURL = storage.migrationBackupURL(forVersion: 0)
        let earlier = Data("earlier-backup".utf8)
        try earlier.write(to: backupURL)

        #expect(try storage.loadReportingMigration().didMigrate)
        #expect(try Data(contentsOf: backupURL) == earlier)
    }

    @Test("备份写入失败时抛出普通错误（非损坏），原文件不变")
    func backupFailureKeepsOriginal() throws {
        let dir = try TempDirectory.make()
        defer {
            try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: dir.path)
            TempDirectory.remove(dir)
        }

        let fileURL = historyURL(in: dir)
        let original = try HistoryFixtures.write(HistoryFixtures.v0JSON, to: fileURL)
        // 目录只读：文件仍可读，但无法创建备份
        try FileManager.default.setAttributes([.posixPermissions: 0o500], ofItemAtPath: dir.path)
        let storage = JSONHistoryStorage(fileURL: fileURL)

        #expect {
            try storage.loadReportingMigration()
        } throws: { error in
            !(error is HistoryStorageError)
        }
        #expect(try Data(contentsOf: fileURL) == original)
        #expect(TempDirectory.fileNames(in: dir) == ["history.json"])
    }

    // MARK: - v1

    @Test("v1 往返：保存后读取内容相同、不视为迁移、不产生备份")
    func v1RoundTrip() throws {
        let dir = try TempDirectory.make()
        defer { TempDirectory.remove(dir) }

        let storage = JSONHistoryStorage(fileURL: historyURL(in: dir))
        let history = ClipHistory(items: HistoryFixtures.v0Items)
        try storage.save(history)

        let outcome = try storage.loadReportingMigration()
        #expect(outcome.history == history)
        #expect(outcome.sourceVersion == 1)
        #expect(!outcome.didMigrate)
        #expect(TempDirectory.fileNames(in: dir) == ["history.json"])
    }

    @Test("冻结的 v1 样本可直接读取")
    func v1FixtureLoads() throws {
        let dir = try TempDirectory.make()
        defer { TempDirectory.remove(dir) }

        let fileURL = historyURL(in: dir)
        try HistoryFixtures.write(HistoryFixtures.v1JSON, to: fileURL)
        let outcome = try JSONHistoryStorage(fileURL: fileURL).loadReportingMigration()
        #expect(outcome.history.items == HistoryFixtures.v1Items)
        #expect(!outcome.didMigrate)
    }

    @Test("保存始终写入 schemaVersion 1（含空历史）", arguments: [0, 1, 3])
    func saveAlwaysWritesVersion(_ count: Int) throws {
        let dir = try TempDirectory.make()
        defer { TempDirectory.remove(dir) }

        let fileURL = historyURL(in: dir)
        let items = (0..<count).map { Fixtures.text("t\($0)") }
        try JSONHistoryStorage(fileURL: fileURL).save(ClipHistory(items: items))
        #expect(try HistoryFixtures.schemaVersion(ofFileAt: fileURL) == 1)
    }

    @Test("文件不存在时返回空历史，不视为迁移")
    func missingFileIsNotMigration() throws {
        let dir = try TempDirectory.make()
        defer { TempDirectory.remove(dir) }

        let outcome = try JSONHistoryStorage(fileURL: historyURL(in: dir)).loadReportingMigration()
        #expect(outcome.history == .empty)
        #expect(!outcome.didMigrate)
        #expect(TempDirectory.fileNames(in: dir).isEmpty)
    }

    // MARK: - 更高版本

    @Test("v99 文件抛出 unsupportedVersion(found: 99)，字节不变且不产生任何备份")
    func v99IsLeftUntouched() throws {
        let dir = try TempDirectory.make()
        defer { TempDirectory.remove(dir) }

        let fileURL = historyURL(in: dir)
        let original = try HistoryFixtures.write(HistoryFixtures.v99JSON, to: fileURL)
        let storage = JSONHistoryStorage(fileURL: fileURL)

        // 多次读取都不应改动文件
        for _ in 0..<2 {
            #expect(throws: HistoryStorageError.unsupportedVersion(found: 99)) {
                try storage.loadReportingMigration()
            }
            #expect(throws: HistoryStorageError.unsupportedVersion(found: 99)) {
                try storage.load()
            }
        }
        #expect(try Data(contentsOf: fileURL) == original)
        #expect(TempDirectory.fileNames(in: dir) == ["history.json"])
    }

    // MARK: - 损坏（行为保持不变）

    @Test(
        "带版本号或结构错误的损坏文件仍按损坏处理，不产生迁移备份",
        arguments: [
            #"{"schemaVersion":1,"items":[{"id":"bad"}]}"#,
            #"{"items":[{"id":"bad"}]}"#,
            #"{"schemaVersion":-3,"items":[]}"#,
            #"{"schemaVersion":99"#,
        ]
    )
    func corruptedStillMovedAside(_ content: String) throws {
        let dir = try TempDirectory.make()
        defer { TempDirectory.remove(dir) }

        let fileURL = historyURL(in: dir)
        let original = try HistoryFixtures.write(content, to: fileURL)
        let storage = JSONHistoryStorage(fileURL: fileURL)

        let error = #expect(throws: HistoryStorageError.self) {
            try storage.loadReportingMigration()
        }
        guard case .corrupted(let backupURL) = error else {
            Issue.record("应当抛出 corrupted 错误，实际为 \(String(describing: error))")
            return
        }
        #expect(try Data(contentsOf: backupURL) == original)
        #expect(!FileManager.default.fileExists(atPath: fileURL.path))
        #expect(!TempDirectory.exists("history.v0.bak.json", in: dir))
        #expect(TempDirectory.fileNames(in: dir) == [backupURL.lastPathComponent])
    }

    // MARK: - 备份文件名

    @Test("迁移备份位于同目录，按原文件名与版本号命名")
    func backupURLNaming() {
        let storage = JSONHistoryStorage(fileURL: URL(fileURLWithPath: "/tmp/cubby/history.json"))
        #expect(storage.migrationBackupURL(forVersion: 0).path == "/tmp/cubby/history.v0.bak.json")
        #expect(storage.migrationBackupURL(forVersion: 3).path == "/tmp/cubby/history.v3.bak.json")
    }
}
