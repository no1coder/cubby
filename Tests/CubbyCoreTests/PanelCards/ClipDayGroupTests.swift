import Foundation
import Testing
@testable import CubbyCore

/// 列表按「今天 / 昨天 / 更早」分组（docs/UI-UPGRADE-PLAN.md 第 1 节「分组标题」）
@Suite("ClipDayGroup 日期分组")
struct ClipDayGroupTests {
    /// 固定时区与日历，测试不随运行环境变化
    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Shanghai") ?? .gmt
        return calendar
    }()

    /// 2026-10-12 16:40（上海）
    private var now: Date {
        calendar.date(from: DateComponents(year: 2026, month: 10, day: 12, hour: 16, minute: 40)) ?? Date()
    }

    private func date(day: Int, hour: Int, minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 10, day: day, hour: hour, minute: minute)) ?? Date()
    }

    private func item(at date: Date) -> ClipItem {
        ClipItem(kind: .text, payload: .text("x"), source: nil, createdAt: date, contentHash: UUID().uuidString)
    }

    @Test(
        "按自然日分组：今天 0 点之后为今天，昨天整天为昨天，再早为更早",
        arguments: [
            (12, 16, ClipDayGroup.today),
            (12, 0, .today),
            (11, 23, .yesterday),
            (11, 0, .yesterday),
            (10, 23, .earlier),
            (1, 9, .earlier),
        ])
    func grouping(_ day: Int, _ hour: Int, _ expected: ClipDayGroup) {
        #expect(ClipDayGroup.group(for: date(day: day, hour: hour), now: now, calendar: calendar) == expected)
    }

    @Test("时间在未来（时钟回拨）时算作今天")
    func futureIsToday() {
        let future = now.addingTimeInterval(3 * 24 * 3600)
        #expect(ClipDayGroup.group(for: future, now: now, calendar: calendar) == .today)
    }

    @Test("显示名各不相同")
    func displayNames() {
        #expect(Set(ClipDayGroup.allCases.map(\.displayName)).count == 3)
    }

    @Test("分节：保持条目顺序，相邻同组合并")
    func sections() {
        let items = [
            item(at: date(day: 12, hour: 16)), item(at: date(day: 12, hour: 9)),
            item(at: date(day: 11, hour: 20)),
            item(at: date(day: 9, hour: 8)), item(at: date(day: 2, hour: 8)),
        ]
        let sections = ClipDayGroup.sections(items, now: now, calendar: calendar)
        #expect(sections.map(\.group) == [.today, .yesterday, .earlier])
        #expect(sections.map(\.items.count) == [2, 1, 2])
        #expect(sections.flatMap(\.items) == items)
    }

    @Test("没有今天的条目时不出现今天一节")
    func skipsEmptyGroups() {
        let items = [item(at: date(day: 11, hour: 8)), item(at: date(day: 3, hour: 8))]
        #expect(ClipDayGroup.sections(items, now: now, calendar: calendar).map(\.group) == [.yesterday, .earlier])
    }

    @Test("空列表没有分节")
    func emptyList() {
        #expect(ClipDayGroup.sections([], now: now, calendar: calendar).isEmpty)
    }

    @Test("顺序乱的条目（例如收藏置顶）按连续段分节，不重排")
    func nonMonotonicKeepsOrder() {
        let items = [item(at: date(day: 3, hour: 8)), item(at: date(day: 12, hour: 8))]
        let sections = ClipDayGroup.sections(items, now: now, calendar: calendar)
        #expect(sections.map(\.group) == [.earlier, .today])
        #expect(sections.flatMap(\.items) == items)
    }

    @Test("分节按线性时间完成：2 万条只需几十毫秒（逐条拼接数组会退化成二次方）")
    func linearTime() {
        let today = date(day: 12, hour: 8)
        let items = (0..<20_000).map { _ in item(at: today) }
        let cpuTime = threadCPUTime { ClipDayGroup.sections(items, now: now, calendar: calendar) }.duration
        #expect(cpuTime < .milliseconds(300))
    }

    @Test("分节的 id 唯一（同一组出现两段时也不同）")
    func sectionIDsAreUnique() {
        let items = [
            item(at: date(day: 12, hour: 8)), item(at: date(day: 3, hour: 8)), item(at: date(day: 12, hour: 7)),
        ]
        let sections = ClipDayGroup.sections(items, now: now, calendar: calendar)
        #expect(Set(sections.map(\.id)).count == sections.count)
    }
}
