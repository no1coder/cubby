import Foundation

/// 列表的日期分组：今天 / 昨天 / 更早（按复制时间所在的自然日）
public enum ClipDayGroup: Sendable, CaseIterable {
    case today
    case yesterday
    case earlier

    public var displayName: String {
        switch self {
        case .today: String(localized: "Today", comment: "Panel list group header")
        case .yesterday: String(localized: "Yesterday", comment: "Panel list group header")
        case .earlier: String(localized: "Earlier", comment: "Panel list group header: items older than yesterday")
        }
    }

    /// 时间在未来（时钟回拨）时算作今天
    public static func group(for date: Date, now: Date, calendar: Calendar = .current) -> ClipDayGroup {
        DayBoundaries(now: now, calendar: calendar).group(for: date)
    }

    /// 按连续段分节，不重排：历史按时间倒序时每组恰好一节；顺序乱时同一组可能出现多节。
    /// 线性时间：日界只算一次，每一段整体切片（逐条拼接数组会退化成二次方）
    public static func sections(_ items: [ClipItem], now: Date, calendar: Calendar = .current) -> [ClipDaySection] {
        let boundaries = DayBoundaries(now: now, calendar: calendar)
        var sections: [ClipDaySection] = []
        var runStart = 0
        var runGroup: ClipDayGroup?
        for (offset, item) in items.enumerated() {
            let group = boundaries.group(for: item.createdAt)
            guard group != runGroup else { continue }
            if let runGroup {
                sections.append(
                    ClipDaySection(group: runGroup, index: sections.count, items: Array(items[runStart..<offset])))
            }
            runGroup = group
            runStart = offset
        }
        if let runGroup {
            sections.append(ClipDaySection(group: runGroup, index: sections.count, items: Array(items[runStart...])))
        }
        return sections
    }
}

/// 今天与昨天的起点
private struct DayBoundaries {
    let startOfToday: Date
    let startOfYesterday: Date

    init(now: Date, calendar: Calendar) {
        startOfToday = calendar.startOfDay(for: now)
        startOfYesterday = calendar.date(byAdding: .day, value: -1, to: startOfToday) ?? startOfToday
    }

    func group(for date: Date) -> ClipDayGroup {
        if date >= startOfToday { return .today }
        return date >= startOfYesterday ? .yesterday : .earlier
    }
}

/// 一节：分组 + 该节的条目（保持原顺序）
public struct ClipDaySection: Equatable, Sendable, Identifiable {
    public let group: ClipDayGroup
    /// 第几节：同一组出现两节时用它区分 id
    public let index: Int
    public let items: [ClipItem]

    public var id: Int {
        index
    }
}
