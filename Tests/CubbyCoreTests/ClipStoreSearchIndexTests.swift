import Foundation
import Testing
@testable import CubbyCore

/// ClipStore 维护搜索索引：加载后后台构建，之后随每次历史变化同步增量更新
@Suite("ClipStore 搜索索引维护")
@MainActor
struct ClipStoreSearchIndexTests {
    private func image(_ seed: String) -> ClipContent {
        .image(png: Data("png-\(seed)".utf8), width: 8, height: 6)
    }

    private func texts(_ items: [ClipItem]) -> [String?] {
        items.map(\.text)
    }

    /// 索引与当前历史逐条对应（没有过期条目），且搜索结果与逐条匹配一致
    private func expectIndexCurrent(_ store: ClipStore, queries: [String]) {
        let index = store.searchIndex
        #expect(index != nil)
        #expect(index?.isCurrent(for: store.history.items) == true)
        for text in queries {
            let query = ClipQuery(text: text)
            #expect(store.search(query).map(\.id) == ClipFilter.apply(store.history.items, query: query).map(\.id))
        }
    }

    @Test("启动后在后台构建索引；构建完成前搜索走逐条匹配，结果同样正确")
    func buildsInBackground() async throws {
        let dir = try TempDirectory.make()
        defer { TempDirectory.remove(dir) }
        let items = (0..<50).map { Fixtures.text("note \($0) cache") }
        let store = StoreFactory.make(dir: dir, storage: InMemoryHistoryStorage(initial: ClipHistory(items: items)))

        let query = ClipQuery(text: "cache 4")
        #expect(store.searchIndex == nil)
        #expect(store.search(query) == ClipFilter.apply(items, query: query))
        #expect(store.search(query).count == 14)
        await store.waitForSearchIndex()

        expectIndexCurrent(store, queries: ["cache", "note 4", "zz"])
    }

    @Test("新增一条只折叠这一条，立即可搜")
    func recordUpdatesIncrementally() async throws {
        let dir = try TempDirectory.make()
        defer { TempDirectory.remove(dir) }
        let items = (0..<20).map { Fixtures.text("old \($0)") }
        let store = StoreFactory.make(dir: dir, storage: InMemoryHistoryStorage(initial: ClipHistory(items: items)))
        await store.waitForSearchIndex()

        store.record(.text("Fresh Café entry"), source: nil)

        #expect(store.searchIndex?.lastFoldedCount == 1)
        #expect(texts(store.search(ClipQuery(text: "cafe"))) == ["Fresh Café entry"])
        expectIndexCurrent(store, queries: ["old", "fresh", "old 1"])
    }

    @Test("删除、撤销、清空、收藏、置顶后索引都与历史同步")
    func mutationsKeepIndexInSync() async throws {
        let dir = try TempDirectory.make()
        defer { TempDirectory.remove(dir) }
        let store = StoreFactory.make(dir: dir)
        await store.waitForSearchIndex()
        let kept = try #require(store.record(.text("keep me cache"), source: nil))
        let gone = try #require(store.record(.text("delete me cache"), source: nil))
        store.toggleFavorite(id: kept.id)

        store.remove(id: gone.id)
        #expect(texts(store.search(ClipQuery(text: "cache"))) == ["keep me cache"])
        expectIndexCurrent(store, queries: ["cache", "delete"])

        store.undoRemove()
        #expect(store.search(ClipQuery(text: "delete")).map(\.id) == [gone.id])
        store.promote(id: kept.id)
        expectIndexCurrent(store, queries: ["cache", "me"])

        store.clearHistory()
        #expect(texts(store.search(ClipQuery(text: "cache"))) == ["keep me cache"])
        expectIndexCurrent(store, queries: ["cache", "delete"])
    }

    @Test("识别文字的写入与清除立即反映到搜索")
    func recognizedTextUpdatesIndex() async throws {
        let dir = try TempDirectory.make()
        defer { TempDirectory.remove(dir) }
        let store = StoreFactory.make(dir: dir)
        await store.waitForSearchIndex()
        let item = try #require(await store.recordInBackground(image("a"), source: nil).value)
        #expect(store.search(ClipQuery(text: "invoice")).isEmpty)

        store.setRecognizedText("Invoice 2026", for: item.id)
        #expect(store.search(ClipQuery(text: "invoice")).map(\.id) == [item.id])

        store.clearRecognizedText()
        #expect(store.search(ClipQuery(text: "invoice")).isEmpty)
        expectIndexCurrent(store, queries: ["invoice", "image"])
    }

    @Test("构建期间历史发生变化：采用时补齐差异，不会搜到过期数据")
    func changesDuringBuildAreMerged() async throws {
        let dir = try TempDirectory.make()
        defer { TempDirectory.remove(dir) }
        let items = (0..<200).map { Fixtures.text("bulk \($0) " + String(repeating: "x", count: 500)) }
        let store = StoreFactory.make(dir: dir, storage: InMemoryHistoryStorage(initial: ClipHistory(items: items)))
        // 构建任务尚未完成（后台执行、主线程被本测试占用）时修改历史
        store.record(.text("added while building"), source: nil)
        let removed = store.history.items[3]
        store.remove(id: removed.id)

        await store.waitForSearchIndex()

        #expect(texts(store.search(ClipQuery(text: "while building"))) == ["added while building"])
        #expect(!store.search(ClipQuery(text: "bulk")).contains { $0.id == removed.id })
        expectIndexCurrent(store, queries: ["bulk 1", "added"])
    }

    @Test("索引缺失或过期的条目逐条匹配：结果仍与全量扫描一致")
    func staleIndexFallsBackPerItem() {
        let items = [Fixtures.text("alpha one"), Fixtures.text("alpha two")]
        let index = ClipSearchIndex(items: [items[0]])
        let edited = [items[0].withRecognizedText(nil), items[1], Fixtures.text("alpha three")]

        #expect(!index.isCurrent(for: edited))
        let query = ClipQuery(text: "alpha")
        #expect(ClipFilter.apply(edited, query: query, index: index) == ClipFilter.apply(edited, query: query))
    }

    @Test("增量更新复用未变化的条目，只折叠新增或内容变化的条目")
    func updatedReusesEntries() {
        let items = (0..<10).map { Fixtures.text("item \($0)") }
        let index = ClipSearchIndex(items: items)
        #expect(index.lastFoldedCount == 10)

        let recognized = Fixtures.image(name: "x.png")
        let next = index.updated(for: [recognized] + items.dropLast(2))
        #expect(next.lastFoldedCount == 1)
        #expect(next.isCurrent(for: [recognized] + items.dropLast(2)))

        let withText = next.updated(for: [recognized.withRecognizedText("hello")] + items.dropLast(2))
        #expect(withText.lastFoldedCount == 1)
        #expect(withText.updated(for: [recognized.withRecognizedText("hello")]).lastFoldedCount == 0)
    }
}
