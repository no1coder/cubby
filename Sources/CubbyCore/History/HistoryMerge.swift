import Foundation

/// 两份历史的合并规则（E7、E8 ① 重试、E8 ② 自动还原），纯函数。
///
/// - base 是加密历史（以它为准），incoming 是要并入的条目（降级期间的明文、锁定期间的内存条目、还原的旧数据）；
/// - 按内容哈希去重：同一内容保留 base 中的条目（id、富文本格式、译文、识别文字、网页标题以它为准，
///   缺失时才取 incoming 的），时间取较新的一个、来源随之取较新的一方，收藏取并集；
/// - 合并后按时间从新到旧排序（时间相同保持 base 在前、原有先后），再按上限裁剪（收藏与 protected 不占名额）。
public enum HistoryMerge {
    public static func merging(
        base: ClipHistory,
        incoming: [ClipItem],
        limit: Int,
        keeping protected: Set<UUID> = []
    ) -> ClipHistory {
        var merged = base.items
        var indexByHash: [String: Int] = [:]
        for (index, item) in merged.enumerated() where indexByHash[item.contentHash] == nil {
            indexByHash[item.contentHash] = index
        }
        for item in incoming {
            if let index = indexByHash[item.contentHash] {
                merged[index] = combine(merged[index], item)
            } else {
                indexByHash[item.contentHash] = merged.count
                merged.append(item)
            }
        }
        let sorted = merged.enumerated()
            .sorted { lhs, rhs in
                lhs.element.createdAt != rhs.element.createdAt
                    ? lhs.element.createdAt > rhs.element.createdAt : lhs.offset < rhs.offset
            }
            .map(\.element)
        return ClipHistory(items: sorted).trimmed(to: max(limit, 1), keeping: protected)
    }

    /// 同一内容的两条：以 existing 为准，时间取较新、收藏取并集，existing 缺失的附加信息由 other 补上
    static func combine(_ existing: ClipItem, _ other: ClipItem) -> ClipItem {
        let newer = other.createdAt > existing.createdAt ? other : existing
        return ClipItem(
            id: existing.id, kind: existing.kind, payload: existing.payload, source: newer.source ?? existing.source,
            createdAt: newer.createdAt, isFavorite: existing.isFavorite || other.isFavorite,
            contentHash: existing.contentHash, formatsName: existing.formatsName,
            recognizedText: existing.recognizedText ?? other.recognizedText,
            translations: existing.translations
                ?? (existing.formatsName == other.formatsName ? other.translations : nil),
            linkTitle: existing.linkTitle ?? other.linkTitle)
    }
}
