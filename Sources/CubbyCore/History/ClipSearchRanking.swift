import Foundation

/// 搜索结果的相关度分档（值越小越靠前）。
/// 前三档看正文（文本、文件路径）：整句命中 → 首个关键词靠前 → 其余（含仅来源应用名、图片类型名命中）；
/// 只有借助图片识别文字才能命中全部关键词的条目排在所有正文命中之后，内部同样分三档；
/// 再往后是还要借助译文才能命中的条目（原文 > 图中文字 > 译文），同样分三档。多个关键词可跨字段命中
public enum SearchRelevance: Int, Comparable, CaseIterable, Sendable {
    case phrase
    case leading
    case other
    case imageTextPhrase
    case imageTextLeading
    case imageTextOther
    case translationPhrase
    case translationLeading
    case translationOther

    public static func < (lhs: SearchRelevance, rhs: SearchRelevance) -> Bool {
        lhs.rawValue < rhs.rawValue
    }

    /// 为命中全部关键词还需要用到的字段：译文档位意味着卡片应显示译文首行，否则用户看不出为何命中
    public var matchedField: SearchMatchField {
        switch self {
        case .phrase, .leading, .other: .content
        case .imageTextPhrase, .imageTextLeading, .imageTextOther: .imageText
        case .translationPhrase, .translationLeading, .translationOther: .translation
        }
    }

    /// 同一判定落在图片识别文字上时对应的档位
    fileprivate var inImageText: SearchRelevance {
        switch self {
        case .phrase, .imageTextPhrase, .translationPhrase: .imageTextPhrase
        case .leading, .imageTextLeading, .translationLeading: .imageTextLeading
        case .other, .imageTextOther, .translationOther: .imageTextOther
        }
    }

    /// 同一判定落在译文上时对应的档位
    fileprivate var inTranslation: SearchRelevance {
        switch self {
        case .phrase, .imageTextPhrase, .translationPhrase: .translationPhrase
        case .leading, .imageTextLeading, .translationLeading: .translationLeading
        case .other, .imageTextOther, .translationOther: .translationOther
        }
    }
}

/// 命中所依赖的字段（见 SearchRelevance.matchedField）
public enum SearchMatchField: Equatable, Sendable {
    /// 正文与元数据（来源应用名、图片类型名）
    case content
    /// 还用到了图片中识别出的文字
    case imageText
    /// 还用到了译文
    case translation
}

/// 相关度判定用到的一段可搜索文字。原文（localizedStandard*）与预折叠索引（memmem）各实现一份，
/// 判定逻辑只写一次，两条路径的结果因此只取决于查找本身
protocol SearchText {
    associatedtype Needle
    associatedtype Position: Comparable
    /// 第一次出现的位置
    func firstMatch(of needle: Needle) -> Position?
    /// 从 position 起是否出现
    func contains(_ needle: Needle, from position: Position) -> Bool
    /// 位置是否落在前 leadingWindow 个字符内
    func isLeading(_ position: Position) -> Bool
}

/// 一条记录的可搜索字段
protocol SearchRecord {
    associatedtype Text: SearchText
    /// 正文（文本或逐行拼接的文件路径）；图片没有正文
    var content: Text? { get }
    /// 可搜索的图片识别文字；没有或为空时为 nil
    var imageText: Text? { get }
    /// 可搜索的译文（全部语言）；没有时为 nil
    var translation: Text? { get }
    /// 来源应用名、图片类型名是否包含
    func metadataContains(_ needle: Text.Needle) -> Bool
}

/// 一次查询的检索词（原文或已折叠）
struct SearchTerms<Needle> {
    let phrase: Needle
    let keywords: [Needle]
    /// 只有一个关键词且与整句相同：正文只需查找一次
    let isSingleKeyword: Bool
}

/// 条目及其相关度
struct GradedItem {
    let relevance: SearchRelevance
    let item: ClipItem
}

/// 搜索的匹配与相关度排序：一次遍历同时完成过滤与分档。
/// 排序稳定：同一档内保持原有顺序（历史顺序，最新在前）
public enum ClipSearchRanking {
    /// 首个关键词的起始位置落在前 leadingWindow 个字符内视为「靠前」
    public static let leadingWindow = 60

    /// 过滤出命中全部关键词的条目并按相关度分档拼接；没有关键词时原样返回。
    /// 传入索引时，可走索引的条目用折叠字节查找，其余条目逐条匹配，结果与不传索引完全一致
    public static func ranked(_ items: [ClipItem], query: ClipQuery, index: ClipSearchIndex? = nil) -> [ClipItem] {
        guard !query.keywords.isEmpty else { return items }
        return ordered(grade(items, query: query, index: index))
    }

    /// 命中全部关键词的条目及其相关度（保持输入顺序）；调用方需确认查询有关键词
    static func grade(_ items: [ClipItem], query: ClipQuery, index: ClipSearchIndex?) -> [GradedItem] {
        let keywords = query.keywords
        let raw = SearchTerms(
            phrase: query.phrase, keywords: keywords,
            isSingleKeyword: keywords.count == 1 && query.phrase == keywords[0])
        let folded = index?.terms(for: query)
        return items.compactMap { item in
            let relevance: SearchRelevance?
            if let folded, let entry = index?.entry(for: item) {
                relevance = Self.relevance(of: entry, terms: folded)
            } else {
                relevance = Self.relevance(of: RawSearchRecord(item), terms: raw)
            }
            return relevance.map { GradedItem(relevance: $0, item: item) }
        }
    }

    /// 按档位拼接；Dictionary(grouping:) 保持各组内元素的原有顺序
    static func ordered(_ graded: [GradedItem]) -> [ClipItem] {
        let groups = Dictionary(grouping: graded, by: \.relevance)
        return SearchRelevance.allCases.flatMap { groups[$0]?.map(\.item) ?? [] }
    }

    /// 条目命中全部关键词时返回其相关度，否则返回 nil（忽略大小写与变音符）
    public static func relevance(of item: ClipItem, phrase: String, keywords: [String]) -> SearchRelevance? {
        let single = keywords.count == 1 && phrase == keywords.first
        return relevance(
            of: RawSearchRecord(item), terms: SearchTerms(phrase: phrase, keywords: keywords, isSingleKeyword: single))
    }

    static func relevance<Record: SearchRecord>(
        of record: Record,
        terms: SearchTerms<Record.Text.Needle>
    ) -> SearchRelevance? {
        guard let first = terms.keywords.first else { return nil }
        let content = record.content
        if terms.isSingleKeyword {
            if content?.firstMatch(of: first) != nil { return .phrase }
            if record.metadataContains(first) { return .other }
            if record.imageText?.firstMatch(of: first) != nil { return .imageTextPhrase }
            return record.translation?.firstMatch(of: first) != nil ? .translationPhrase : nil
        }
        // 先查短字段（来源名、类型名），再查正文
        let matchesOutsideImage = { (keyword: Record.Text.Needle) in
            record.metadataContains(keyword) || content?.firstMatch(of: keyword) != nil
        }
        // 记下首个关键词在正文中的首次出现位置：「靠前」直接由它判定，整句也只需从这里往后找
        let firstInContent = content?.firstMatch(of: first)
        if firstInContent != nil || record.metadataContains(first),
            terms.keywords.dropFirst().allSatisfy(matchesOutsideImage)
        {
            return tier(in: content, first: firstInContent, phrase: terms.phrase)
        }
        return fallbackRelevance(of: record, terms: terms, matchesOutsideImage: matchesOutsideImage)
    }

    /// 正文与元数据命中不了全部关键词时：先允许图片识别文字，再允许译文
    private static func fallbackRelevance<Record: SearchRecord>(
        of record: Record,
        terms: SearchTerms<Record.Text.Needle>,
        matchesOutsideImage: (Record.Text.Needle) -> Bool
    ) -> SearchRelevance? {
        guard let first = terms.keywords.first else { return nil }
        let image = record.imageText
        func matchesWithImage(_ keyword: Record.Text.Needle) -> Bool {
            matchesOutsideImage(keyword) || image?.firstMatch(of: keyword) != nil
        }
        // 只有带识别文字的图片才可能依赖识别文字命中
        if let image, terms.keywords.allSatisfy(matchesWithImage) {
            return tier(in: image, first: image.firstMatch(of: first), phrase: terms.phrase).inImageText
        }
        guard let translation = record.translation,
            terms.keywords.allSatisfy({ matchesWithImage($0) || translation.firstMatch(of: $0) != nil })
        else { return nil }
        return tier(in: translation, first: translation.firstMatch(of: first), phrase: terms.phrase).inTranslation
    }

    /// 在一段文字中判定前三档之一（调用方已确认全部关键词命中）。
    /// 整句以首个关键词开头，若存在必定始于首个关键词首次出现处或其后
    private static func tier<Text: SearchText>(
        in text: Text?,
        first position: Text.Position?,
        phrase: Text.Needle
    ) -> SearchRelevance {
        guard let text, let position else { return .other }
        if text.contains(phrase, from: position) { return .phrase }
        return text.isLeading(position) ? .leading : .other
    }
}

// MARK: - 原文查找（localizedStandardRange / localizedStandardContains）

/// 原文的一段可搜索文字
struct RawSearchText: SearchText {
    let text: Substring

    func firstMatch(of needle: String) -> String.Index? {
        text.localizedStandardRange(of: needle)?.lowerBound
    }

    func contains(_ needle: String, from position: String.Index) -> Bool {
        text[position...].localizedStandardContains(needle)
    }

    func isLeading(_ position: String.Index) -> Bool {
        let limit =
            text.index(text.startIndex, offsetBy: ClipSearchRanking.leadingWindow, limitedBy: text.endIndex)
            ?? text.endIndex
        return position < limit
    }
}

/// 以原文逐条匹配的记录
struct RawSearchRecord: SearchRecord {
    let item: ClipItem
    let content: RawSearchText?
    let imageText: RawSearchText?

    init(_ item: ClipItem) {
        self.item = item
        content = item.searchableContent.map(RawSearchText.init)
        imageText = item.hasImageText ? item.recognizedText.map { RawSearchText(text: $0[...]) } : nil
    }

    /// 只在正文与图中文字都命中不了时才用到，按需生成（富文本译文要去掉行内标记）
    var translation: RawSearchText? {
        item.translationSearchText.map { RawSearchText(text: $0[...]) }
    }

    func metadataContains(_ needle: String) -> Bool {
        item.matchesMetadata(needle)
    }
}
