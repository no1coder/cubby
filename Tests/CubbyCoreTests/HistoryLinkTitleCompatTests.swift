import Foundation
import Testing
@testable import CubbyCore

/// 新增可选字段 linkTitle 不提升 schema 版本（与 recognizedText、translations 的先例相同）：
/// 旧文件无损读取、没有标题时写出的内容与旧版本一致、带标题的文件读写往返一致
@Suite("历史文件兼容：linkTitle")
struct HistoryLinkTitleCompatTests {
    static let v1WithLinkTitleJSON = #"""
        {"schemaVersion":1,"items":[
        {"id":"1B2C3D4E-5F60-4718-8293-A4B5C6D7E8F9","kind":"link","payload":{"text":{"_0":"https:\/\/example.com\/docs"}},"createdAt":715000100,"isFavorite":true,"contentHash":"text:link","linkTitle":"Docs – \"Example\" 📋"},
        {"id":"2C3D4E5F-6071-4829-93A4-B5C6D7E8F901","kind":"link","payload":{"text":{"_0":"https:\/\/example.com\/plain"}},"createdAt":715000000,"isFavorite":false,"contentHash":"text:plain"}
        ]}
        """#

    static let v1WithLinkTitleItems: [ClipItem] = [
        ClipItem(
            id: UUID(uuidString: "1B2C3D4E-5F60-4718-8293-A4B5C6D7E8F9")!,
            kind: .link, payload: .text("https://example.com/docs"), source: nil,
            createdAt: Date(timeIntervalSinceReferenceDate: 715_000_100), isFavorite: true,
            contentHash: "text:link", linkTitle: "Docs – \"Example\" 📋"),
        ClipItem(
            id: UUID(uuidString: "2C3D4E5F-6071-4829-93A4-B5C6D7E8F901")!,
            kind: .link, payload: .text("https://example.com/plain"), source: nil,
            createdAt: Date(timeIntervalSinceReferenceDate: 715_000_000), contentHash: "text:plain"),
    ]

    @Test("格式版本保持 v1：可选字段按 decodeIfPresent 规则无需迁移")
    func schemaVersionUnchanged() {
        #expect(HistoryMigrator.currentVersion == 1)
    }

    @Test("冻结的 v0 / v1 样本无损读取，标题全部为 nil（包括其中的链接条目）")
    func legacyFixturesDecode() throws {
        let v0 = try HistoryMigrator.migrate(Data(HistoryFixtures.v0JSON.utf8))
        #expect(v0.history.items == HistoryFixtures.v0Items)
        #expect(v0.history.items.contains { $0.kind == .link })
        #expect(v0.history.items.allSatisfy { $0.linkTitle == nil })

        let v1 = try HistoryMigrator.migrate(Data(HistoryFixtures.v1JSON.utf8))
        #expect(v1.history.items == HistoryFixtures.v1Items)
        #expect(v1.history.items.allSatisfy { $0.linkTitle == nil })
        #expect(!v1.didMigrate)
    }

    @Test("带标题的 v1 文件直接读取，不视为迁移")
    func v1WithLinkTitleDecodes() throws {
        let outcome = try HistoryMigrator.migrate(Data(Self.v1WithLinkTitleJSON.utf8))
        #expect(outcome.history.items == Self.v1WithLinkTitleItems)
        #expect(outcome.sourceVersion == 1)
        #expect(!outcome.didMigrate)
    }

    @Test("保存带标题的历史：仍写 schemaVersion 1，读回一致且不产生迁移备份")
    func saveAndReload() throws {
        let dir = try TempDirectory.make()
        defer { TempDirectory.remove(dir) }
        let fileURL = dir.appendingPathComponent("history.json")
        let storage = JSONHistoryStorage(fileURL: fileURL)
        let history = ClipHistory(items: Self.v1WithLinkTitleItems)

        try storage.save(history)
        let outcome = try storage.loadReportingMigration()

        #expect(try HistoryFixtures.schemaVersion(ofFileAt: fileURL) == 1)
        #expect(outcome.history == history)
        #expect(outcome.history.items.first?.linkTitle == "Docs – \"Example\" 📋")
        #expect(!outcome.didMigrate)
        #expect(TempDirectory.fileNames(in: dir) == ["history.json"])
    }

    @Test("没有标题的历史写盘时不含该字段：与旧版本写出的内容一致")
    func encodingWithoutLinkTitleMatchesLegacy() throws {
        let data = try HistoryMigrator.encode(ClipHistory(items: HistoryFixtures.v0Items))
        #expect(!String(decoding: data, as: UTF8.self).contains("linkTitle"))
        let titled = try HistoryMigrator.encode(ClipHistory(items: Self.v1WithLinkTitleItems))
        #expect(String(decoding: titled, as: UTF8.self).components(separatedBy: "linkTitle").count == 2)
    }

    @Test("流式写盘与整块编码逐字节相同（含标题）")
    func streamingMatchesEncode() throws {
        let dir = try TempDirectory.make()
        defer { TempDirectory.remove(dir) }
        let fileURL = dir.appendingPathComponent("history.json")
        let history = ClipHistory(items: Self.v1WithLinkTitleItems)

        try JSONHistoryStorage(fileURL: fileURL).save(history)

        #expect(try Data(contentsOf: fileURL) == HistoryMigrator.encode(history))
    }
}
