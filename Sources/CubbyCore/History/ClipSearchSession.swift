import Foundation

/// 逐键搜索会话（面板持有一份）：缓存上次结果，查询与历史版本都没变时直接返回。
/// 同一历史版本、同一分类下，新查询的每个旧关键词都被某个新关键词（折叠后）包含时——典型如继续输入——
/// 只在上次命中的条目中继续过滤。「包含」对折叠字节查找单调：凡命中新查询的条目必然命中旧查询，
/// 因此与全量计算完全一致；需逐条匹配（ICU 语义不一定单调）的条目则每次都重新判定
public struct ClipSearchSession {
    private struct Cache {
        let revision: Int
        let query: ClipQuery
        /// 上次命中的条目（保持历史顺序，作为收窄的候选）
        let matched: Set<UUID>
        let results: [ClipItem]
        /// 上次查询的折叠关键词；nil 表示当时走了逐条匹配，不能据此收窄
        let foldedKeywords: [[UInt8]]?
    }

    private var cache: Cache?

    public init() {}

    /// 上次计算的查询（测试用）
    var cachedQuery: ClipQuery? {
        cache?.query
    }

    /// 当前历史中与查询匹配的条目（已按相关度排序），与 ClipFilter.apply 的结果完全一致
    @MainActor
    public mutating func results(for query: ClipQuery, in store: ClipStore) -> [ClipItem] {
        let revision = store.revision
        if let cache, cache.revision == revision, cache.query == query { return cache.results }

        let index = store.searchIndex
        let terms = index?.terms(for: query)
        let scope = store.history.items.filter(query.category.matches)
        guard !query.keywords.isEmpty else {
            cache = Cache(revision: revision, query: query, matched: [], results: scope, foldedKeywords: nil)
            return scope
        }
        let candidates = narrowingBase(for: query, terms: terms, revision: revision).map { base in
            scope.filter { base.contains($0.id) || index?.entry(for: $0) == nil }
        }
        let graded = ClipSearchRanking.grade(candidates ?? scope, query: query, index: index)
        let results = ClipSearchRanking.ordered(graded)
        cache = Cache(
            revision: revision, query: query, matched: Set(graded.map(\.item.id)), results: results,
            foldedKeywords: terms?.keywords)
        return results
    }

    /// 可以收窄时返回上次命中的条目集合
    private func narrowingBase(
        for query: ClipQuery,
        terms: SearchTerms<[UInt8]>?,
        revision: Int
    ) -> Set<UUID>? {
        guard let cache, cache.revision == revision, cache.query.category == query.category,
            let previous = cache.foldedKeywords, let current = terms?.keywords
        else { return nil }
        let stricter = previous.allSatisfy { old in current.contains { Self.bytes($0, contain: old) } }
        return stricter ? cache.matched : nil
    }

    private static func bytes(_ haystack: [UInt8], contain needle: [UInt8]) -> Bool {
        guard haystack.count >= needle.count else { return false }
        return haystack.withUnsafeBufferPointer { hay in
            needle.withUnsafeBufferPointer { pin in
                guard let base = hay.baseAddress, let pinBase = pin.baseAddress else { return pin.isEmpty }
                return memmem(base, hay.count, pinBase, pin.count) != nil
            }
        }
    }
}
