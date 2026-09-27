import Foundation

/// 预折叠搜索索引（不可变值）：每条历史的可搜索字段只折叠一次，逐键搜索只做字节查找。
/// 由 ClipStore 在加载后于后台构建，之后随每次历史变化在主线程增量更新（只折叠新增或变化的条目）。
/// 查询时逐条校验：条目缺失、已过期或含折叠语义不一致的字符时，该条改走 localizedStandardContains，
/// 因此即使索引落后于历史，也不会搜到过期数据
public struct ClipSearchIndex: Sendable {
    /// 一条历史的折叠结果
    struct Entry: Sendable, SearchRecord {
        let contentHash: String
        let kind: ClipKind
        let sourceName: String?
        let recognizedText: String?
        /// 折叠时的译文缓存：与条目共享存储，比较通常只需比较引用
        let translations: ClipTranslations?
        /// 含折叠语义不一致的字符：整条走逐条匹配
        let requiresExactMatch: Bool
        let content: FoldedText?
        let imageText: FoldedText?
        let translation: FoldedText?
        /// 来源应用名、图片类型名
        let metadata: [FoldedText]

        init(_ item: ClipItem, locale: Locale) {
            contentHash = item.contentHash
            kind = item.kind
            sourceName = item.source?.name
            recognizedText = item.recognizedText
            translations = item.translations
            let rawContent = Self.rawContent(of: item)
            let imageText = item.hasImageText ? item.recognizedText : nil
            let translation = item.translationSearchText
            requiresExactMatch =
                (rawContent.map(SearchFolding.requiresExactMatch) ?? false)
                || [sourceName, imageText, translation].contains { $0.map(SearchFolding.requiresExactMatch) ?? false }
            guard !requiresExactMatch else {
                content = nil
                self.imageText = nil
                self.translation = nil
                metadata = []
                return
            }
            content = rawContent.map { FoldedText($0, locale: locale) }
            self.imageText = imageText.map { FoldedText($0, locale: locale) }
            self.translation = translation.map { FoldedText($0, locale: locale) }
            let kindName = item.kind == .image ? item.kind.displayName : nil
            metadata = [sourceName, kindName].compactMap { $0.map { FoldedText($0, locale: locale) } }
        }

        /// 可搜索字段与条目一致（内容由 contentHash 唯一确定）
        func isCurrent(for item: ClipItem) -> Bool {
            contentHash == item.contentHash && kind == item.kind && sourceName == item.source?.name
                && recognizedText == item.recognizedText && translations == item.translations
        }

        func metadataContains(_ needle: [UInt8]) -> Bool {
            metadata.contains { $0.firstMatch(of: needle) != nil }
        }

        /// 与 ClipItem.searchableContent 相同的正文；短文本不复制
        private static func rawContent(of item: ClipItem) -> Substring? {
            switch item.payload {
            case .text(let value):
                return value.utf8.count <= ClipItem.searchLimit ? value[...] : value.prefix(ClipItem.searchLimit)
            case .image:
                return nil
            case .files(let paths):
                return Substring(paths.joined(separator: "\n"))
            }
        }
    }

    private let entries: [UUID: Entry]
    private let locale: Locale
    /// 本次构建或更新中新折叠的条目数（测试与性能统计用）
    let lastFoldedCount: Int

    public init(items: [ClipItem], locale: Locale = .current) {
        self.init(reusing: [:], items: items, locale: locale)
    }

    private init(reusing previous: [UUID: Entry], items: [ClipItem], locale: Locale) {
        var folded = 0
        let pairs = items.map { item -> (UUID, Entry) in
            if let existing = previous[item.id], existing.isCurrent(for: item) {
                return (item.id, existing)
            }
            folded += 1
            return (item.id, Entry(item, locale: locale))
        }
        self.entries = Dictionary(pairs, uniquingKeysWith: { _, latest in latest })
        self.locale = locale
        self.lastFoldedCount = folded
    }

    /// 与新历史对应的索引：复用未变化的条目，只折叠新增或内容变化的条目，已移除的条目随之丢弃
    public func updated(for items: [ClipItem]) -> ClipSearchIndex {
        ClipSearchIndex(reusing: entries, items: items, locale: locale)
    }

    /// 索引是否与这组历史逐条对应（没有缺失、多余或过期的条目）
    public func isCurrent(for items: [ClipItem]) -> Bool {
        items.count == entries.count && items.allSatisfy { entries[$0.id]?.isCurrent(for: $0) == true }
    }

    /// 可走索引的条目；缺失、过期或需逐条匹配时为 nil
    func entry(for item: ClipItem) -> Entry? {
        guard let entry = entries[item.id], entry.isCurrent(for: item), !entry.requiresExactMatch else { return nil }
        return entry
    }

    /// 查询的折叠检索词；没有关键词或含折叠语义不一致的字符时为 nil（整次查询走逐条匹配）
    func terms(for query: ClipQuery) -> SearchTerms<[UInt8]>? {
        let keywords = query.keywords
        guard !keywords.isEmpty, keywords.allSatisfy(SearchFolding.isIndexable(keyword:)) else { return nil }
        let folded = keywords.map { SearchFolding.foldedBytes($0, locale: locale) }
        guard !folded.contains(where: \.isEmpty) else { return nil }
        return SearchTerms(
            phrase: SearchFolding.foldedBytes(query.phrase, locale: locale),
            keywords: folded,
            isSingleKeyword: keywords.count == 1 && query.phrase == keywords[0]
        )
    }
}

// MARK: - 折叠文字的查找

extension FoldedText: SearchText {
    func firstMatch(of needle: [UInt8]) -> Int? {
        firstMatch(of: needle, from: 0)
    }

    func contains(_ needle: [UInt8], from position: Int) -> Bool {
        firstMatch(of: needle, from: position) != nil
    }

    func isLeading(_ position: Int) -> Bool {
        position < leadingLimit
    }
}
