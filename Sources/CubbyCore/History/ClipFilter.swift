import Foundation

/// 面板中的分类筛选
public enum ClipCategory: String, CaseIterable, Sendable {
    case all
    case text
    case link
    case image
    case file
    case color
    case favorite

    /// 分类栏中的标签（复数形式；英文不超过 9 个字符）
    public var displayName: String {
        switch self {
        case .all: String(localized: "All", comment: "Category tab: all items")
        case .text: String(localized: "Text", comment: "Category tab: text items")
        case .link: String(localized: "Links", comment: "Category tab: link items")
        case .image: String(localized: "Images", comment: "Category tab: image items")
        case .file: String(localized: "Files", comment: "Category tab: file items")
        case .color: String(localized: "Colors", comment: "Category tab: color items")
        case .favorite: String(localized: "Favorites", comment: "Category tab: favorite items")
        }
    }

    public var symbolName: String {
        switch self {
        case .all: "tray.full"
        case .favorite: "star"
        default: kind?.symbolName ?? "questionmark"
        }
    }

    /// 对应的内容类型；all / favorite 不限定类型
    public var kind: ClipKind? {
        switch self {
        case .all, .favorite: nil
        case .text: .text
        case .link: .link
        case .image: .image
        case .file: .file
        case .color: .color
        }
    }

    public func matches(_ item: ClipItem) -> Bool {
        switch self {
        case .all: true
        case .favorite: item.isFavorite
        default: item.kind == kind
        }
    }

    /// 循环切换到相邻分类
    public func cycled(by offset: Int) -> ClipCategory {
        let all = Self.allCases
        let index = all.firstIndex(of: self) ?? 0
        let next = ((index + offset) % all.count + all.count) % all.count
        return all[next]
    }
}

public struct ClipQuery: Equatable, Sendable {
    public let text: String
    public let category: ClipCategory

    public init(text: String = "", category: ClipCategory = .all) {
        self.text = text
        self.category = category
    }

    /// 以空白分隔的关键词
    public var keywords: [String] {
        text.split(whereSeparator: \.isWhitespace).map(String.init)
    }

    /// 整句：去掉首尾空白后的完整查询串（内部空白原样保留），用于相关度排序
    public var phrase: String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

public enum ClipFilter {
    /// 先按分类过滤，再按关键词过滤。关键词以空白分隔，需全部命中（忽略大小写与变音符）。
    /// 有关键词时结果按相关度稳定排序（见 ClipSearchRanking），同一档内保持历史顺序。
    /// 传入搜索索引（ClipStore.searchIndex）可大幅加速，结果与不传完全一致
    public static func apply(_ items: [ClipItem], query: ClipQuery, index: ClipSearchIndex? = nil) -> [ClipItem] {
        ClipSearchRanking.ranked(items.filter(query.category.matches), query: query, index: index)
    }
}
