import Foundation

/// 目录中的一项：二级与三级标题
struct GuideContentsEntry: Identifiable, Hashable {
    /// 标题在全文中的字符位置，同时作为标识
    let id: Int
    let level: Int
    let title: String
}

/// 排版后文档的结构：目录、锚点、当前节与搜索命中的归属（纯计算，不涉及界面）
struct GuideOutline {
    static let empty = GuideOutline(headings: [])

    private static let contentsLevels = 2...3

    let contents: [GuideContentsEntry]
    private let anchors: [String: Int]

    init(headings: [GuideRenderedHeading]) {
        contents = headings.compactMap { rendered in
            guard Self.contentsLevels.contains(rendered.heading.level) else { return nil }
            return GuideContentsEntry(
                id: rendered.location, level: rendered.heading.level, title: rendered.heading.title)
        }
        // 重名锚点已在解析时加了序号，这里保留第一个即可
        anchors = Dictionary(headings.map { ($0.heading.anchor, $0.location) }, uniquingKeysWith: { first, _ in first })
    }

    /// 文内锚点链接（#anchor）对应的标题位置
    func location(ofAnchor anchor: String) -> Int? {
        anchors[anchor]
    }

    /// 当前节：顶部探测线之上最后一个目录标题；滚到底时取可见范围内最后一个
    func currentEntry(in region: GuideVisibleRegion) -> GuideContentsEntry.ID? {
        entry(containing: region.isAtBottom ? region.bottomLocation : region.topLocation)
    }

    /// 位置所在的目录项（位置之前最后一个目录标题）
    func entry(containing location: Int) -> GuideContentsEntry.ID? {
        entryIndex(containing: location).map { contents[$0].id }
    }

    /// 包含任一命中的目录项；命中在三级标题下时，它所属的二级标题也算
    func entries(containing matches: [NSRange]) -> Set<GuideContentsEntry.ID> {
        var result: Set<GuideContentsEntry.ID> = []
        for match in matches {
            guard let index = entryIndex(containing: match.location) else { continue }
            result.insert(contents[index].id)
            if let parent = contents[...index].last(where: { $0.level < contents[index].level }) {
                result.insert(parent.id)
            }
        }
        return result
    }

    /// 位置之前（含）最后一个目录项的下标（二分查找）
    private func entryIndex(containing location: Int) -> Int? {
        var low = 0
        var high = contents.count
        while low < high {
            let mid = (low + high) / 2
            if contents[mid].id <= location { low = mid + 1 } else { high = mid }
        }
        return low > 0 ? low - 1 : nil
    }
}

/// 全文搜索：忽略大小写、变音符号与全半角
enum GuideSearch {
    private static let options: NSString.CompareOptions = [.caseInsensitive, .diacriticInsensitive, .widthInsensitive]

    static func ranges(of query: String, in text: NSString) -> [NSRange] {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !needle.isEmpty else { return [] }
        var ranges: [NSRange] = []
        var searchRange = NSRange(location: 0, length: text.length)
        while searchRange.length > 0 {
            let found = text.range(of: needle, options: options, range: searchRange)
            guard found.location != NSNotFound, found.length > 0 else { break }
            ranges.append(found)
            searchRange = NSRange(location: NSMaxRange(found), length: text.length - NSMaxRange(found))
        }
        return ranges
    }
}
