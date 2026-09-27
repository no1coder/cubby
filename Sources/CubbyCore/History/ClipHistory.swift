import Foundation

/// 剪贴板历史（不可变值类型）。所有操作返回新实例，顺序为最新在前。
public struct ClipHistory: Codable, Equatable, Sendable {
    public let items: [ClipItem]

    public static let empty = ClipHistory(items: [])

    public init(items: [ClipItem]) {
        self.items = items
    }

    /// 插入条目。相同内容会合并为一条并移到最前（保留原 id 与收藏状态，
    /// 富文本格式等取最新一次复制的值），然后按上限裁剪非收藏条目。
    public func inserting(_ item: ClipItem, limit: Int) -> ClipHistory {
        let existing = items.first { $0.contentHash == item.contentHash }
        let head = existing.map(item.replacing) ?? item
        let rest = items.filter { $0.contentHash != item.contentHash }
        return ClipHistory(items: [head] + rest).trimmed(to: limit)
    }

    /// 将条目移到最前并刷新时间（例如被粘贴后）
    public func promoting(id: UUID, at date: Date) -> ClipHistory {
        guard let target = items.first(where: { $0.id == id }) else { return self }
        let rest = items.filter { $0.id != id }
        return ClipHistory(items: [target.touched(at: date)] + rest)
    }

    public func removing(id: UUID) -> ClipHistory {
        ClipHistory(items: items.filter { $0.id != id })
    }

    public func togglingFavorite(id: UUID) -> ClipHistory {
        ClipHistory(items: items.map { $0.id == id ? $0.withFavorite(!$0.isFavorite) : $0 })
    }

    /// 设置图片条目的识别文字；条目不存在、不是图片或值未变时原样返回
    public func settingRecognizedText(_ text: String?, for id: UUID) -> ClipHistory {
        guard let target = items.first(where: { $0.id == id }), target.kind == .image,
            target.recognizedText != text
        else { return self }
        return ClipHistory(items: items.map { $0.id == id ? $0.withRecognizedText(text) : $0 })
    }

    /// 批量设置识别文字（id → 文字）；不存在、不是图片或值未变的条目忽略，全部无变化时原样返回
    public func settingRecognizedTexts(_ texts: [UUID: String]) -> ClipHistory {
        let isChange = { (item: ClipItem) in
            item.kind == .image && texts[item.id].map { $0 != item.recognizedText } == true
        }
        guard items.contains(where: isChange) else { return self }
        return ClipHistory(items: items.map { isChange($0) ? $0.withRecognizedText(texts[$0.id]) : $0 })
    }

    /// 清除全部识别文字（关闭图片文字搜索时）；本就没有时原样返回
    public func removingRecognizedText() -> ClipHistory {
        guard items.contains(where: { $0.recognizedText != nil }) else { return self }
        return ClipHistory(items: items.map { $0.recognizedText == nil ? $0 : $0.withRecognizedText(nil) })
    }

    /// 写入一条译文（docs/CLIP-TRANSLATION-DESIGN.md §2.3）：同一目标语言覆盖；每条最多 limits.maxLanguagesPerItem 种
    /// （淘汰最早的）；单种语言超过上限时不缓存；总量超限时按 createdAt 淘汰全历史中最早的译文（不动条目）。
    /// 条目不存在（含已删除待撤销）、类型不支持或值未变时原样返回
    public func settingTranslation(
        _ translation: ClipTranslation,
        for id: UUID,
        limits: ClipTranslationLimits = .standard
    ) -> ClipHistory {
        guard let target = items.first(where: { $0.id == id }), limits.accepts(translation, for: target),
            target.translations?.entry(for: translation.target) != translation
        else { return self }
        let updated = target.withTranslations(limits.inserting(translation, into: target.translations))
        let replaced = items.map { $0.id == id ? updated : $0 }
        return ClipHistory(items: limits.enforcingTotalLength(replaced, keeping: (id, translation.target)))
    }

    /// 清除全部译文（设置里的「清除全部译文」）；本就没有时原样返回
    public func removingTranslations() -> ClipHistory {
        guard items.contains(where: { $0.translations != nil }) else { return self }
        return ClipHistory(items: items.map { $0.translations == nil ? $0 : $0.withTranslations(nil) })
    }

    /// 清空历史，收藏的条目保留
    public func removingNonFavorites() -> ClipHistory {
        ClipHistory(items: items.filter(\.isFavorite))
    }

    /// 非收藏条目最多保留 limit 条（取最新的），收藏条目不受限制
    public func trimmed(to limit: Int) -> ClipHistory {
        let keepIDs = Set(items.lazy.filter { !$0.isFavorite }.prefix(max(limit, 1)).map(\.id))
        let kept = items.filter { $0.isFavorite || keepIDs.contains($0.id) }
        return kept.count == items.count ? self : ClipHistory(items: kept)
    }

    /// 恢复被删除的条目到原位置（越界时放到末尾）。
    /// 若删除后相同内容已被重新记录，则不再插入重复条目，只把收藏状态合并到现有条目上。
    public func restoring(_ item: ClipItem, at index: Int) -> ClipHistory {
        guard !items.contains(where: { $0.id == item.id }) else { return self }
        if let existing = items.first(where: { $0.contentHash == item.contentHash }) {
            guard item.isFavorite, !existing.isFavorite else { return self }
            return togglingFavorite(id: existing.id)
        }
        let position = min(max(index, 0), items.count)
        return ClipHistory(items: Array(items[..<position]) + [item] + Array(items[position...]))
    }

    /// 当前引用到的全部图片文件名
    public var imageNames: Set<String> {
        Set(items.compactMap { $0.image?.name })
    }

    /// 当前引用到的全部 blob 文件名（图片 + 富文本格式 + 译后图片），用于清理孤立文件
    public var blobNames: Set<String> {
        Set(items.flatMap(\.blobNames))
    }
}
