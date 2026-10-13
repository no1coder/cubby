import Foundation

/// 两份历史的合并规则（E7、E8 ① 重试、E8 ② 自动还原），纯函数。
///
/// - base 是加密历史（内容以它为准），incoming 是要并入的条目（降级期间的明文、锁定期间的内存条目、还原的旧数据）；
/// - 按内容哈希去重：同一内容保留 base 中的内容（富文本格式、译文、识别文字、网页标题以它为准，缺失时才取 incoming 的），
///   时间取较新的一个、来源随之取较新的一方，收藏取并集；id 由调用方选择保留哪一方的（见 IDSource）；
/// - 合并后按时间从新到旧排序（时间相同保持 base 在前、原有先后）。
/// - **不按条数上限裁剪**：合并发生在启动、解锁时，此时晾衣绳等「受保护的条目」尚未与历史同步，裁剪会悄悄丢掉它们；
///   上限在下次记录新内容时照常生效（与旧版本启动时一样）。
public enum HistoryMerge {
    /// 重复条目保留哪一方的 id
    public enum IDSource: Sendable {
        /// base 的 id（迁移、还原：incoming 的 id 此时没有任何人持有）
        case base
        /// incoming 的 id（解锁：内存模式下发出的 id 已被地址守护、进行中的翻译、面板选中项等持有）
        case incoming
    }

    public struct Result: Equatable, Sendable {
        public let history: ClipHistory
        /// 因去重而不再存在的 id → 接替它的 id
        public let replacedIDs: [UUID: UUID]
    }

    /// 合并（保留 base 的 id）
    public static func merging(base: ClipHistory, incoming: [ClipItem]) -> ClipHistory {
        merge(base: base, incoming: incoming, ids: .base).history
    }

    public static func merge(base: ClipHistory, incoming: [ClipItem], ids: IDSource) -> Result {
        var merged = base.items
        var replaced: [UUID: UUID] = [:]
        var indexByHash: [String: Int] = [:]
        for (index, item) in merged.enumerated() where indexByHash[item.contentHash] == nil {
            indexByHash[item.contentHash] = index
        }
        for item in incoming {
            guard let index = indexByHash[item.contentHash] else {
                indexByHash[item.contentHash] = merged.count
                merged.append(item)
                continue
            }
            let existing = merged[index]
            let id = ids == .incoming ? item.id : existing.id
            if id != existing.id { replaced[existing.id] = id }
            if id != item.id { replaced[item.id] = id }
            merged[index] = combine(existing, item, id: id)
        }
        return Result(history: ClipHistory(items: sortedByDate(merged)), replacedIDs: replaced)
    }

    /// 同一内容的两条：内容以 existing 为准，时间取较新、收藏取并集，existing 缺失的附加信息由 other 补上
    static func combine(_ existing: ClipItem, _ other: ClipItem, id: UUID) -> ClipItem {
        let newer = other.createdAt > existing.createdAt ? other : existing
        return ClipItem(
            id: id, kind: existing.kind, payload: existing.payload, source: newer.source ?? existing.source,
            createdAt: newer.createdAt, isFavorite: existing.isFavorite || other.isFavorite,
            contentHash: existing.contentHash, formatsName: existing.formatsName,
            recognizedText: existing.recognizedText ?? other.recognizedText,
            translations: existing.translations
                ?? (existing.formatsName == other.formatsName ? other.translations : nil),
            linkTitle: existing.linkTitle ?? other.linkTitle)
    }

    private static func sortedByDate(_ items: [ClipItem]) -> [ClipItem] {
        items.enumerated()
            .sorted { lhs, rhs in
                lhs.element.createdAt != rhs.element.createdAt
                    ? lhs.element.createdAt > rhs.element.createdAt : lhs.offset < rhs.offset
            }
            .map(\.element)
    }
}
