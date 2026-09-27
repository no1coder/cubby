import Foundation
import Testing
@testable import CubbyCore

/// HistoryMigrator 是纯函数：只处理内存中的数据，不接触文件系统
@Suite("HistoryMigrator 版本识别与迁移")
struct HistoryMigratorTests {
    private func migrate(_ json: String) throws -> HistoryMigrator.Outcome {
        try HistoryMigrator.migrate(Data(json.utf8))
    }

    @Test("当前版本为 1")
    func currentVersion() {
        #expect(HistoryMigrator.currentVersion == 1)
    }

    // MARK: - v0

    @Test("v0 样本无损迁移：与逐字段手写的期望条目完全一致")
    func v0FixtureMigratesLosslessly() throws {
        let outcome = try migrate(HistoryFixtures.v0JSON)
        #expect(outcome.sourceVersion == 0)
        #expect(outcome.didMigrate)
        #expect(outcome.history.items == HistoryFixtures.v0Items)
    }

    @Test("v0 迁移结果与 v0.1 直接解码的结果相同")
    func v0MatchesLegacyDecoding() throws {
        let data = Data(HistoryFixtures.v0JSON.utf8)
        let legacy = try JSONDecoder().decode(ClipHistory.self, from: data)
        #expect(try HistoryMigrator.migrate(data).history == legacy)
    }

    @Test("空 items 的 v0 文件迁移为空历史")
    func emptyV0() throws {
        let outcome = try migrate(#"{"items":[]}"#)
        #expect(outcome.history == .empty)
        #expect(outcome.sourceVersion == 0)
    }

    @Test("schemaVersion 为 null 视为 v0")
    func nullVersionIsV0() throws {
        let outcome = try migrate(#"{"schemaVersion":null,"items":[]}"#)
        #expect(outcome.sourceVersion == 0)
        #expect(outcome.didMigrate)
    }

    @Test("迁移保留日期精度（小数秒、参考时间之前）", arguments: [0.123456789, -1.5, 1_000_000_000.000001, 1.0e-9])
    func v0PreservesDatePrecision(_ seconds: Double) throws {
        let history = ClipHistory(items: [Fixtures.text("x", at: Date(timeIntervalSince1970: seconds))])
        let outcome = try HistoryMigrator.migrate(HistoryFixtures.encodeAsV0(history))
        #expect(outcome.history == history)
    }

    @Test(
        "特殊字符经 v0 迁移后保持不变",
        arguments: [
            "\u{0}NUL 与 \u{1F} 控制符",
            "👨‍👩‍👧‍👦🏳️‍🌈 组合 emoji",
            "עברית RTL 混排 العربية",
            "\"'; DROP TABLE items; --",
            "\\\\server\\share\r\n换行",
            String(repeating: "长", count: 100_000),
        ]
    )
    func v0PreservesSpecialCharacters(_ text: String) throws {
        let history = ClipHistory(items: [Fixtures.text(text, source: SourceApp(bundleID: "a.b", name: "名 ✓"))])
        let outcome = try HistoryMigrator.migrate(HistoryFixtures.encodeAsV0(history))
        #expect(outcome.history == history)
    }

    @Test("一万条 v0 条目迁移后数量与顺序不变")
    func largeV0History() throws {
        let items = (0..<10_000).map { index in
            Fixtures.text(
                "条目 \(index)", favorite: index.isMultiple(of: 7), at: Date(timeIntervalSince1970: Double(index)))
        }
        let history = ClipHistory(items: items)
        let outcome = try HistoryMigrator.migrate(HistoryFixtures.encodeAsV0(history))
        #expect(outcome.history == history)
    }

    // MARK: - v1

    @Test("v1 数据按原样解码，不视为迁移")
    func v1IsNotMigrated() throws {
        let outcome = try migrate(HistoryFixtures.v1JSON)
        #expect(outcome.sourceVersion == 1)
        #expect(!outcome.didMigrate)
        #expect(outcome.history.items == HistoryFixtures.v1Items)
    }

    @Test("v1 忽略未知的顶层字段")
    func v1IgnoresUnknownKeys() throws {
        let outcome = try migrate(#"{"schemaVersion":1,"items":[],"extra":{"a":1}}"#)
        #expect(outcome.history == .empty)
        #expect(!outcome.didMigrate)
    }

    // MARK: - 更高版本

    @Test("v99 样本抛出 unsupportedVersion(found: 99)")
    func v99FixtureIsRejected() {
        #expect(throws: HistoryMigrationError.unsupportedVersion(found: 99)) {
            try migrate(HistoryFixtures.v99JSON)
        }
    }

    @Test("高于当前的版本一律拒绝，不关心其余结构", arguments: [2, 3, 99, Int(Int32.max)])
    func newerVersionIsRejected(_ version: Int) {
        #expect(throws: HistoryMigrationError.unsupportedVersion(found: version)) {
            try migrate(#"{"schemaVersion":\#(version),"items":"future-format"}"#)
        }
    }

    // MARK: - 无法识别

    @Test(
        "无法识别的数据抛出 malformed",
        arguments: [
            "",
            "{not json",
            "[]",
            "\"items\"",
            "null",
            #"{"foo":1}"#,
            #"{"items":null}"#,
            #"{"items":[{"id":"bad"}]}"#,
            #"{"schemaVersion":1}"#,
            #"{"schemaVersion":1,"items":[{"id":"bad"}]}"#,
            #"{"schemaVersion":-1,"items":[]}"#,
            #"{"schemaVersion":"1","items":[]}"#,
            #"{"schemaVersion":1.5,"items":[]}"#,
            #"{"schemaVersion":true,"items":[]}"#,
        ]
    )
    func malformedInput(_ json: String) {
        #expect(throws: HistoryMigrationError.malformed) {
            try migrate(json)
        }
    }

    // MARK: - 编码

    @Test("encode 写入当前版本号，读回不视为迁移且内容一致")
    func encodeWritesCurrentVersion() throws {
        let history = ClipHistory(items: HistoryFixtures.v0Items)
        let data = try HistoryMigrator.encode(history)

        let top = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(top["schemaVersion"] as? Int == HistoryMigrator.currentVersion)
        #expect(Set(top.keys) == ["schemaVersion", "items"])

        let outcome = try HistoryMigrator.migrate(data)
        #expect(outcome.history == history)
        #expect(!outcome.didMigrate)
    }

    @Test("encode 空历史仍带版本号")
    func encodeEmpty() throws {
        let data = try HistoryMigrator.encode(.empty)
        let top = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(top["schemaVersion"] as? Int == 1)
        #expect((top["items"] as? [Any])?.isEmpty == true)
    }

    // MARK: - Outcome

    @Test("Outcome 默认来源版本为当前版本，此时 didMigrate 为 false")
    func outcomeDefaults() {
        let outcome = HistoryMigrator.Outcome(history: .empty)
        #expect(outcome.sourceVersion == HistoryMigrator.currentVersion)
        #expect(!outcome.didMigrate)
        #expect(HistoryMigrator.Outcome(history: .empty, sourceVersion: 0).didMigrate)
    }
}
