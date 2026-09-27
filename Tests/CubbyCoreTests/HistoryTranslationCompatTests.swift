import Foundation
import Testing
@testable import CubbyCore

/// 译文缓存不提升 schema 版本（docs/CLIP-TRANSLATION-DESIGN.md §2.2）。验收必查项 R3：
/// 某条的 translations 损坏（类型不对、垃圾项、不是数组）时整份历史照常读取，只丢弃坏掉的译文项
@Suite("历史文件兼容：translations 容错解码")
struct HistoryTranslationCompatTests {
    /// 7 条：完好的译文、字符串、对象、数字、混有垃圾项的数组、全是垃圾的数组、null
    static let corruptedJSON = #"""
        {"schemaVersion":1,"items":[
        {"id":"00000000-0000-4000-8000-000000000001","kind":"text","payload":{"text":{"_0":"Hello"}},"createdAt":715000300,"isFavorite":false,"contentHash":"text:1",
         "translations":[{"target":"zh-Hans","source":"en","engineName":"System","isOnDevice":true,"createdAt":715000400,"segmentation":1,"segments":["你好"]}]},
        {"id":"00000000-0000-4000-8000-000000000002","kind":"text","payload":{"text":{"_0":"Two"}},"createdAt":715000301,"isFavorite":true,"contentHash":"text:2",
         "translations":"garbage"},
        {"id":"00000000-0000-4000-8000-000000000003","kind":"text","payload":{"text":{"_0":"Three"}},"createdAt":715000302,"isFavorite":false,"contentHash":"text:3",
         "translations":{"target":"ja"}},
        {"id":"00000000-0000-4000-8000-000000000004","kind":"text","payload":{"text":{"_0":"Four"}},"createdAt":715000303,"isFavorite":false,"contentHash":"text:4",
         "translations":42},
        {"id":"00000000-0000-4000-8000-000000000005","kind":"text","payload":{"text":{"_0":"Five"}},"createdAt":715000304,"isFavorite":false,"contentHash":"text:5",
         "translations":[
           {"target":5,"source":"en","engineName":"System","isOnDevice":true,"createdAt":715000400,"segmentation":1,"segments":["x"]},
           42, null, "text", [1, [2, {"a": [3]}]], {"nested": {"deep": [null, true]}},
           {"target":"fr","source":null,"engineName":"DeepSeek","isOnDevice":false,"createdAt":715000500,"segmentation":1,"segments":["Cinq",null],"usesInlineMarkup":true,"futureField":{"x":1}},
           {"target":"de","engineName":"System","isOnDevice":true,"createdAt":"yesterday","segmentation":1,"segments":["x"]},
           {"target":"es","engineName":"System","isOnDevice":true,"createdAt":715000600,"segmentation":1,"segments":[1, 2]}
         ]},
        {"id":"00000000-0000-4000-8000-000000000006","kind":"text","payload":{"text":{"_0":"Six"}},"createdAt":715000305,"isFavorite":false,"contentHash":"text:6",
         "translations":[true, false, {}, []]},
        {"id":"00000000-0000-4000-8000-000000000007","kind":"text","payload":{"text":{"_0":"Seven"}},"createdAt":715000306,"isFavorite":false,"contentHash":"text:7",
         "translations":null}
        ]}
        """#

    private static func id(_ last: Int) -> UUID {
        UUID(uuidString: String(format: "00000000-0000-4000-8000-%012d", last))!
    }

    @Test("R3：损坏的 translations 不影响任何条目的读取，只丢弃坏掉的译文项")
    func corruptedTranslationsKeepAllItems() throws {
        let outcome = try HistoryMigrator.migrate(Data(Self.corruptedJSON.utf8))
        let items = outcome.history.items
        #expect(items.count == 7)
        #expect(items.map(\.text) == ["Hello", "Two", "Three", "Four", "Five", "Six", "Seven"])
        #expect(items[0].translations?.entries.map(\.target) == ["zh-Hans"])
        #expect(items[0].translation(for: "zh-Hans")?.segments == ["\u{4F60}\u{597D}"])
        #expect(items[1].isFavorite)
        // 不是数组：整体为空（不是 nil）；null：nil
        for index in [1, 2, 3, 5] {
            #expect(items[index].translations?.entries.isEmpty == true, "item \(index)")
        }
        #expect(items[6].translations == nil)
        let survivors = try #require(items[4].translations?.entries)
        #expect(survivors.map(\.target) == ["fr"])
        #expect(survivors.first?.segments == ["Cinq", nil])
        #expect(survivors.first?.usesInlineMarkup == true)
        #expect(survivors.first?.source == nil)
        #expect(!outcome.didMigrate)
    }

    @Test("R3：从磁盘加载损坏的译文不会触发「损坏备份后清空」，空的译文容器在启动修复时归为 nil 并写回")
    @MainActor
    func storeLoadsCorruptedTranslations() throws {
        let dir = try TempDirectory.make()
        defer { TempDirectory.remove(dir) }
        let fileURL = dir.appendingPathComponent("history.json")
        try HistoryFixtures.write(Self.corruptedJSON, to: fileURL)

        let store = StoreFactory.make(
            dir: dir.appendingPathComponent("Images"), storage: JSONHistoryStorage(fileURL: fileURL))
        store.flush()

        #expect(store.loadIssue == nil)
        #expect(store.canPersist)
        #expect(store.history.items.count == 7)
        #expect(store.history.items.filter { $0.translations != nil }.map(\.id) == [Self.id(1), Self.id(5)])
        #expect(TempDirectory.fileNames(in: dir) == ["history.json"])
        let reloaded = try JSONHistoryStorage(fileURL: fileURL).load()
        #expect(reloaded == store.history)
    }

    @Test("旧文件（没有该字段）无损读取，译文全部为 nil；格式版本保持 v1")
    func legacyFilesDecode() throws {
        #expect(HistoryMigrator.currentVersion == 1)
        let v0 = try HistoryMigrator.migrate(Data(HistoryFixtures.v0JSON.utf8))
        #expect(v0.history.items == HistoryFixtures.v0Items)
        #expect(v0.history.items.allSatisfy { $0.translations == nil })
        let v1 = try HistoryMigrator.migrate(Data(HistoryFixtures.v1WithRecognizedTextJSON.utf8))
        #expect(v1.history.items.allSatisfy { $0.translations == nil })
    }

    @Test("没有译文时编码不写该字段：与旧版本写出的内容一致")
    func encodingOmitsNil() throws {
        let data = try HistoryMigrator.encode(ClipHistory(items: HistoryFixtures.v0Items))
        #expect(!String(decoding: data, as: UTF8.self).contains("translations"))
    }

    @Test("新文件能被旧版本的解码逻辑读取（未知键忽略）：降级运行不会失败")
    func legacyDecoderReadsNewFile() throws {
        let history = ClipHistory(items: [
            Fixtures.text("Hello").translated(TranslationFixtures.text(), TranslationFixtures.text("ja", markup: true)),
            Fixtures.image(name: "a.png").translated(TranslationFixtures.image(blob: "t.png")),
        ])
        let data = try HistoryMigrator.encode(history)
        let legacy = try JSONDecoder().decode(LegacyHistoryFile.self, from: data)
        #expect(legacy.items.map(\.id) == history.items.map(\.id))
        #expect(legacy.items.map(\.contentHash) == history.items.map(\.contentHash))
        #expect(legacy.schemaVersion == 1)
    }

    @Test("带译文的历史保存后读回完全一致，仍写 schemaVersion 1、不产生迁移备份")
    func saveAndReload() throws {
        let dir = try TempDirectory.make()
        defer { TempDirectory.remove(dir) }
        let fileURL = dir.appendingPathComponent("history.json")
        let storage = JSONHistoryStorage(fileURL: fileURL)
        let history = ClipHistory(items: [
            Fixtures.text("Hello").translated(
                TranslationFixtures.text(segments: ["\u{4F60}\u{597D}", nil, "\"quoted\"\n\u{1F600}"]),
                TranslationFixtures.text(
                    "fr", segments: ["**Bonjour**"], engine: "DeepSeek", onDevice: false, markup: true)),
            Fixtures.image(name: "a.png").translated(TranslationFixtures.image(blob: "t.png")),
        ])

        try storage.save(history)
        let outcome = try storage.loadReportingMigration()

        #expect(outcome.history == history)
        #expect(!outcome.didMigrate)
        #expect(try HistoryFixtures.schemaVersion(ofFileAt: fileURL) == 1)
        #expect(TempDirectory.fileNames(in: dir) == ["history.json"])
    }

    /// R2：上线前量写盘耗时。500 条 × 3 种语言、每种约 1 200 字符（总量约 1.8 M 字符，超过上限的极端情形）
    @Test("R2 基准：500 条 × 3 种语言的历史整体写盘耗时在可接受范围内")
    func largeFixtureWriteBenchmark() throws {
        let dir = try TempDirectory.make()
        defer { TempDirectory.remove(dir) }
        let storage = JSONHistoryStorage(fileURL: dir.appendingPathComponent("history.json"))
        let paragraph = String(
            repeating: "\u{8FD9}\u{662F}\u{4E00}\u{6BB5}\u{8BD1}\u{6587} translated text. ", count: 20)
        let items = (0..<500).map { index in
            Fixtures.text("Item \(index) " + String(repeating: "original text ", count: 60)).translated(
                TranslationFixtures.text("zh-Hans", segments: [paragraph, nil, paragraph], at: Double(index)),
                TranslationFixtures.text("ja", segments: [paragraph, paragraph], at: Double(index) + 0.1),
                TranslationFixtures.text(
                    "fr", segments: ["**" + paragraph + "**"], at: Double(index) + 0.2, markup: true))
        }
        let history = ClipHistory(items: items)
        try storage.save(history)
        let clock = ContinuousClock()
        let saves = (0..<3).map { _ in clock.measure { try? storage.save(history) } }
        let loads = (0..<3).map { _ in clock.measure { _ = try? storage.load() } }
        let size = try Data(contentsOf: storage.fileURL).count
        let best = saves.min() ?? .zero
        print(
            "BENCH translations 500x3: save best \(best), load best \(loads.min() ?? .zero), "
                + "file \(size / 1024) KB, \(history.translationLength) chars")
        #expect(try storage.load() == history)
        #expect(best < .milliseconds(500))
    }
}

/// v0.2 时期的文件结构（冻结，不随模型变化）：模拟旧版本 Cubby 读取新文件
private struct LegacyHistoryFile: Decodable {
    let schemaVersion: Int
    let items: [LegacyItem]

    struct LegacyItem: Decodable {
        let id: UUID
        let kind: ClipKind
        let payload: ClipPayload
        let source: SourceApp?
        let createdAt: Date
        let isFavorite: Bool
        let contentHash: String
        let formatsName: String?
        let recognizedText: String?
    }
}
