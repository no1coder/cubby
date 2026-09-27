import Foundation
import Testing
@testable import CubbyCore

/// 逐键搜索会话：同一历史版本下新查询以旧查询为前缀时只在上次命中里继续过滤，结果与全量计算完全一致
@Suite("ClipSearchSession 逐键收窄")
@MainActor
struct ClipSearchSessionTests {
    private static let items: [ClipItem] = [
        Fixtures.text("cache miss in the network layer"),
        Fixtures.text("clear the cache"),
        Fixtures.text("cachet is not cache"),
        Fixtures.text("Café cache \u{1F44D}"),
        Fixtures.text("\u{00DF} only"),
        Fixtures.text("\u{7B2C} 5 \u{6761} cache"),
        Fixtures.files(["/tmp/cache/log.txt"]),
        Fixtures.image(name: "a.png").withRecognizedText("Cache Invoice"),
    ]

    private func makeStore(_ dir: URL, items: [ClipItem] = Self.items) async -> ClipStore {
        let store = StoreFactory.make(dir: dir, storage: InMemoryHistoryStorage(initial: ClipHistory(items: items)))
        await store.waitForSearchIndex()
        return store
    }

    /// 依次输入每个查询，逐一与全量计算对照
    private func expectTyping(_ texts: [String], store: ClipStore, category: ClipCategory = .all) {
        var session = ClipSearchSession()
        for text in texts {
            let query = ClipQuery(text: text, category: category)
            let expected = ClipFilter.apply(store.history.items, query: query)
            #expect(session.results(for: query, in: store).map(\.id) == expected.map(\.id), "\(text.debugDescription)")
        }
    }

    @Test("逐字输入、追加关键词、退格：每一步都与全量计算一致")
    func typingSequence() async throws {
        let dir = try TempDirectory.make()
        defer { TempDirectory.remove(dir) }
        let store = await makeStore(dir)
        expectTyping(
            ["c", "ca", "cac", "cach", "cache", "cache ", "cache i", "cache in", "cache", "ca", ""], store: store)
    }

    @Test("收窄后排序仍以历史顺序为同档基准，与全量计算一致")
    func narrowingKeepsHistoryOrder() async throws {
        let dir = try TempDirectory.make()
        defer { TempDirectory.remove(dir) }
        let store = await makeStore(dir)
        expectTyping(["the", "the cache", "cache the"], store: store)
        expectTyping(["c", "cache", "cache c"], store: store)
    }

    @Test("收窄不适用于逐条匹配的条目：「s」→「ss」时只含 ß 的条目按原语义出现")
    func exactOnlyItemsAreReevaluated() async throws {
        let dir = try TempDirectory.make()
        defer { TempDirectory.remove(dir) }
        let store = await makeStore(dir)
        expectTyping(["s", "ss", "\u{00DF}", "\u{00DF} o"], store: store)
    }

    @Test("历史变化后不再收窄：新记录的条目出现在结果中")
    func revisionChangeResetsNarrowing() async throws {
        let dir = try TempDirectory.make()
        defer { TempDirectory.remove(dir) }
        let store = await makeStore(dir)
        var session = ClipSearchSession()
        _ = session.results(for: ClipQuery(text: "cach"), in: store)

        store.record(.text("brand new cache entry"), source: nil)
        let result = session.results(for: ClipQuery(text: "cache"), in: store)

        #expect(result.contains { $0.text == "brand new cache entry" })
        #expect(result == ClipFilter.apply(store.history.items, query: ClipQuery(text: "cache")))
    }

    @Test("切换分类后重新计算")
    func categoryChange() async throws {
        let dir = try TempDirectory.make()
        defer { TempDirectory.remove(dir) }
        let store = await makeStore(dir)
        var session = ClipSearchSession()
        _ = session.results(for: ClipQuery(text: "ca", category: .image), in: store)
        let text = session.results(for: ClipQuery(text: "cache", category: .text), in: store)
        #expect(text == ClipFilter.apply(store.history.items, query: ClipQuery(text: "cache", category: .text)))
        expectTyping(["ca", "cache"], store: store, category: .file)
    }

    @Test("索引尚未就绪时同样正确")
    func worksBeforeIndexIsReady() throws {
        let dir = try TempDirectory.make()
        defer { TempDirectory.remove(dir) }
        let store = StoreFactory.make(
            dir: dir, storage: InMemoryHistoryStorage(initial: ClipHistory(items: Self.items)))
        #expect(store.searchIndex == nil)
        expectTyping(["c", "cache", "cache inv"], store: store)
    }

    @Test("相同查询重复访问直接返回缓存")
    func sameQueryIsCached() async throws {
        let dir = try TempDirectory.make()
        defer { TempDirectory.remove(dir) }
        let store = await makeStore(dir)
        var session = ClipSearchSession()
        let first = session.results(for: ClipQuery(text: "cache"), in: store)
        #expect(session.results(for: ClipQuery(text: "cache"), in: store) == first)
        #expect(session.cachedQuery == ClipQuery(text: "cache"))
    }
}
