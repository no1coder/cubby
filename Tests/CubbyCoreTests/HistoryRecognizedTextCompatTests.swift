import Foundation
import Testing
@testable import CubbyCore

/// 新增可选字段 recognizedText 不提升 schema 版本：旧文件无损读取、新文件旧版本可读、高版本保护不受影响
@Suite("历史文件兼容：recognizedText")
struct HistoryRecognizedTextCompatTests {
    @Test("格式版本保持 v1：可选字段按 decodeIfPresent 规则无需迁移")
    func schemaVersionUnchanged() {
        #expect(HistoryMigrator.currentVersion == 1)
    }

    @Test("冻结的 v0 / v1 样本无损读取，识别文字全部为 nil")
    func legacyFixturesDecode() throws {
        let v0 = try HistoryMigrator.migrate(Data(HistoryFixtures.v0JSON.utf8))
        #expect(v0.history.items == HistoryFixtures.v0Items)
        #expect(v0.history.items.allSatisfy { $0.recognizedText == nil })

        let v1 = try HistoryMigrator.migrate(Data(HistoryFixtures.v1JSON.utf8))
        #expect(v1.history.items == HistoryFixtures.v1Items)
        #expect(!v1.didMigrate)
    }

    @Test("带识别文字的 v1 文件直接读取，不视为迁移（空串表示已识别无文字）")
    func v1WithRecognizedTextDecodes() throws {
        let outcome = try HistoryMigrator.migrate(Data(HistoryFixtures.v1WithRecognizedTextJSON.utf8))
        #expect(outcome.history.items == HistoryFixtures.v1WithRecognizedTextItems)
        #expect(outcome.sourceVersion == 1)
        #expect(!outcome.didMigrate)
    }

    @Test("保存带识别文字的历史：仍写 schemaVersion 1，读回一致且不产生迁移备份")
    func saveAndReload() throws {
        let dir = try TempDirectory.make()
        defer { TempDirectory.remove(dir) }
        let fileURL = dir.appendingPathComponent("history.json")
        let storage = JSONHistoryStorage(fileURL: fileURL)
        let history = ClipHistory(items: HistoryFixtures.v1WithRecognizedTextItems)

        try storage.save(history)
        let outcome = try storage.loadReportingMigration()

        #expect(try HistoryFixtures.schemaVersion(ofFileAt: fileURL) == 1)
        #expect(outcome.history == history)
        #expect(!outcome.didMigrate)
        #expect(TempDirectory.fileNames(in: dir) == ["history.json"])
    }

    @Test("未识别的历史写盘时不含该字段：与旧版本写出的内容一致")
    func encodingWithoutRecognizedTextMatchesLegacy() throws {
        let data = try HistoryMigrator.encode(ClipHistory(items: HistoryFixtures.v0Items))
        #expect(!String(decoding: data, as: UTF8.self).contains("recognizedText"))
    }

    @Test("更新版本写入的文件仍被拒绝读取，原文件不被改动")
    func newerVersionStillProtected() throws {
        let dir = try TempDirectory.make()
        defer { TempDirectory.remove(dir) }
        let fileURL = dir.appendingPathComponent("history.json")
        let original = try HistoryFixtures.write(HistoryFixtures.v99JSON, to: fileURL)

        #expect(throws: HistoryStorageError.unsupportedVersion(found: 99)) {
            try JSONHistoryStorage(fileURL: fileURL).loadReportingMigration()
        }
        #expect(try Data(contentsOf: fileURL) == original)
    }

    @Test("只读模式（更新版本的文件）下写入识别文字只改内存，不写盘")
    @MainActor
    func readOnlyStoreDoesNotPersistRecognizedText() throws {
        let dir = try TempDirectory.make()
        defer { TempDirectory.remove(dir) }
        let fileURL = dir.appendingPathComponent("history.json")
        let original = try HistoryFixtures.write(HistoryFixtures.v99JSON, to: fileURL)
        let store = StoreFactory.make(
            dir: dir.appendingPathComponent("Images"), storage: JSONHistoryStorage(fileURL: fileURL))

        store.clearRecognizedText()
        store.flush()

        #expect(!store.canPersist)
        #expect(store.loadIssue == .newerVersion(99))
        #expect(try Data(contentsOf: fileURL) == original)
    }
}
