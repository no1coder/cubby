import Foundation
import Testing
@testable import CubbyCore

/// 自动裁剪时受保护的条目（晾衣绳上的条目，docs/UI-UPGRADE-PLAN.md 第 5 节）：与收藏一样不被裁掉，也不占上限名额
@Suite("ClipHistory 裁剪保护")
struct ClipHistoryProtectionTests {
    /// 最新在前：t4 … t0
    private func history(_ count: Int) -> ClipHistory {
        ClipHistory(items: (0..<count).reversed().map { Fixtures.text("t\($0)") })
    }

    @Test("不传保护集合时行为不变")
    func defaultKeepsNothingExtra() {
        let full = history(5)
        #expect(full.trimmed(to: 2).items.map(\.text) == ["t4", "t3"])
        #expect(full.trimmed(to: 2, keeping: []).items.map(\.text) == ["t4", "t3"])
    }

    @Test("受保护的旧条目不被裁掉，且不占上限名额")
    func protectedSurviveAndDoNotCount() throws {
        let full = history(5)
        let oldest = try #require(full.items.last)

        let result = full.trimmed(to: 2, keeping: [oldest.id])

        // 上限 2 只算未受保护的非收藏条目：t4、t3 保留，t0 受保护也保留
        #expect(result.items.map(\.text) == ["t4", "t3", "t0"])
    }

    @Test("受保护条目夹在中间时保持原有顺序")
    func keepsOrder() throws {
        let full = history(5)
        let middle = full.items[2]  // t2

        let result = full.trimmed(to: 1, keeping: [middle.id])

        #expect(result.items.map(\.text) == ["t4", "t2"])
    }

    @Test("收藏与受保护同时存在：两者都保留，都不占名额")
    func favoritesAndProtected() {
        let favorite = Fixtures.text("fav", favorite: true)
        let pinned = Fixtures.text("pinned")
        let plain = (0..<3).reversed().map { Fixtures.text("p\($0)") }
        let full = ClipHistory(items: plain + [pinned, favorite])

        let result = full.trimmed(to: 1, keeping: [pinned.id])

        #expect(result.items.map(\.text) == ["p2", "pinned", "fav"])
    }

    @Test("既收藏又受保护的条目只出现一次")
    func favoriteAndProtectedSameItem() {
        let both = Fixtures.text("both", favorite: true)
        let full = ClipHistory(items: [Fixtures.text("a"), Fixtures.text("b"), both])

        let result = full.trimmed(to: 1, keeping: [both.id])

        #expect(result.items.map(\.text) == ["a", "both"])
    }

    @Test("保护集合里有不存在的 id 时忽略，未发生裁剪时返回同一个值")
    func unknownIDsIgnored() {
        let full = history(3)
        #expect(full.trimmed(to: 3, keeping: [UUID()]) == full)
        #expect(full.trimmed(to: 2, keeping: [UUID()]).items.map(\.text) == ["t2", "t1"])
    }

    @Test("全部条目受保护时上限不生效")
    func allProtected() {
        let full = history(4)
        #expect(full.trimmed(to: 1, keeping: Set(full.items.map(\.id))) == full)
    }

    @Test("上限不大于 0 时按 1 处理，受保护条目照样保留", arguments: [0, -5])
    func nonPositiveLimit(_ limit: Int) throws {
        let full = history(3)
        let oldest = try #require(full.items.last)
        #expect(full.trimmed(to: limit, keeping: [oldest.id]).items.map(\.text) == ["t2", "t0"])
    }

    // MARK: - inserting

    @Test("插入新条目时受保护的最旧条目不被挤出")
    func insertingKeepsProtected() throws {
        let full = history(2)  // t1, t0
        let oldest = try #require(full.items.last)

        let result = full.inserting(Fixtures.text("new"), limit: 2, keeping: [oldest.id])

        #expect(result.items.map(\.text) == ["new", "t1", "t0"])
    }

    @Test("插入不传保护集合时与原来一样裁剪")
    func insertingDefault() {
        let result = history(2).inserting(Fixtures.text("new"), limit: 2)
        #expect(result.items.map(\.text) == ["new", "t1"])
    }

    @Test("重复内容合并到受保护条目时保留原 id，仍受保护")
    func insertingDuplicateOfProtected() throws {
        let full = history(3)  // t2, t1, t0
        let oldest = try #require(full.items.last)

        let result = full.inserting(Fixtures.text("t0"), limit: 1, keeping: [oldest.id])

        #expect(result.items.map(\.id) == [oldest.id, full.items[0].id])
    }

    @Test("清空历史只保留收藏：受保护但未收藏的条目被移除")
    func clearRemovesProtectedNonFavorites() {
        let favorite = Fixtures.text("fav", favorite: true)
        let full = ClipHistory(items: [Fixtures.text("pinned"), favorite])
        #expect(full.removingNonFavorites().items == [favorite])
    }
}
