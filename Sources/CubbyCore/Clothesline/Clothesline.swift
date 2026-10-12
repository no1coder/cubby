import Foundation

/// 晾衣绳上挂着的条目（纯值）：从左到右的顺序、去重与容量上限。
/// 新挂上的图片挂在最右端；已在绳上的再挂一次会移到最右端；超过容量时取下最左端（最早挂上）的
public struct Clothesline: Equatable, Sendable {
    /// 一根绳最多挂这么多张：再多在 13 寸屏上每张就窄得看不清
    public static let capacity = 12

    public let itemIDs: [UUID]

    /// 丢弃重复的 id（保留第一次出现的位置），超过容量时保留最右端（最新）的
    public init(itemIDs: [UUID] = []) {
        var seen = Set<UUID>()
        let unique = itemIDs.filter { seen.insert($0).inserted }
        self.itemIDs = Array(unique.suffix(Self.capacity))
    }

    public var isEmpty: Bool {
        itemIDs.isEmpty
    }

    public var count: Int {
        itemIDs.count
    }

    public func contains(_ id: UUID) -> Bool {
        itemIDs.contains(id)
    }

    /// 挂到最右端；返回新的绳子以及因超出容量被取下的条目
    public func hanging(_ id: UUID) -> (line: Clothesline, dropped: [UUID]) {
        let appended = itemIDs.filter { $0 != id } + [id]
        let overflow = max(appended.count - Self.capacity, 0)
        return (Clothesline(itemIDs: Array(appended.dropFirst(overflow))), Array(appended.prefix(overflow)))
    }

    public func removing(_ id: UUID) -> Clothesline {
        Clothesline(itemIDs: itemIDs.filter { $0 != id })
    }

    /// 只保留仍在历史中的条目（条目被删除、被清空或超出历史上限后从绳上消失）
    public func retaining(_ existing: Set<UUID>) -> Clothesline {
        Clothesline(itemIDs: itemIDs.filter(existing.contains))
    }
}
