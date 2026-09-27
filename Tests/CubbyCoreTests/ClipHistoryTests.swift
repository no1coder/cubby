import Foundation
import Testing
@testable import CubbyCore

@Suite("ClipHistory 不可变历史操作")
struct ClipHistoryTests {
    private let later = Fixtures.baseDate.addingTimeInterval(3600)

    // MARK: - inserting

    @Test("新条目插入到最前")
    func insertsAtFront() {
        let a = Fixtures.text("a")
        let b = Fixtures.text("b")
        let history = ClipHistory.empty.inserting(a, limit: 10).inserting(b, limit: 10)
        #expect(history.items.map(\.id) == [b.id, a.id])
    }

    @Test("相同内容去重：移到最前并保留原 id 与收藏状态")
    func deduplicatesKeepingIdentityAndFavorite() throws {
        let original = Fixtures.text("dup", favorite: true, source: SourceApp(bundleID: "old", name: "Old"))
        let other = Fixtures.text("other")
        let history = ClipHistory(items: [other, original])

        let newSource = SourceApp(bundleID: "new", name: "New")
        let again = Fixtures.text("dup", source: newSource, at: later)
        let result = history.inserting(again, limit: 10)

        try #require(result.items.count == 2)
        let head = result.items[0]
        #expect(head.id == original.id)
        #expect(head.id != again.id)
        #expect(head.isFavorite)
        #expect(head.createdAt == later)
        #expect(head.source == newSource)
        #expect(result.items[1].id == other.id)
    }

    @Test("重复插入且新来源为空时保留原来源")
    func deduplicateKeepsSourceWhenNewIsNil() {
        let source = SourceApp(bundleID: "a", name: "A")
        let history = ClipHistory(items: [Fixtures.text("x", source: source)])
        let result = history.inserting(Fixtures.text("x", at: later), limit: 10)
        #expect(result.items.first?.source == source)
    }

    @Test("超过上限时只裁剪最旧的非收藏条目")
    func trimsOnlyNonFavorites() {
        let oldFavorite = Fixtures.text("fav", favorite: true)
        let old1 = Fixtures.text("old1")
        let old2 = Fixtures.text("old2")
        // 顺序：最新在前
        let history = ClipHistory(items: [old2, old1, oldFavorite])

        let result = history.inserting(Fixtures.text("new"), limit: 2)

        #expect(result.items.map(\.text) == ["new", "old2", "fav"])
        #expect(result.items.contains { $0.id == oldFavorite.id })
    }

    @Test("收藏条目不计入上限")
    func favoritesDoNotCountTowardsLimit() {
        let favorites = (0..<5).map { Fixtures.text("fav\($0)", favorite: true) }
        let history = ClipHistory(items: favorites).inserting(Fixtures.text("n"), limit: 1)
        #expect(history.items.count == 6)
    }

    @Test("上限小于 1 时按 1 处理", arguments: [0, -5])
    func nonPositiveLimitTreatedAsOne(_ limit: Int) {
        let history = ClipHistory.empty
            .inserting(Fixtures.text("a"), limit: limit)
            .inserting(Fixtures.text("b"), limit: limit)
        #expect(history.items.map(\.text) == ["b"])
    }

    @Test("插入不修改原历史")
    func insertingIsNonMutating() {
        let history = ClipHistory(items: [Fixtures.text("a")])
        _ = history.inserting(Fixtures.text("b"), limit: 10)
        #expect(history.items.map(\.text) == ["a"])
    }

    @Test("trimmed 无需裁剪时返回相等的历史")
    func trimmedNoop() {
        let history = ClipHistory(items: [Fixtures.text("a"), Fixtures.text("b")])
        #expect(history.trimmed(to: 5) == history)
        #expect(history.trimmed(to: 1).items.map(\.text) == ["a"])
    }

    // MARK: - promoting

    @Test("promoting 将条目移到最前并刷新时间，其余顺序不变")
    func promotingMovesToFront() {
        let a = Fixtures.text("a")
        let b = Fixtures.text("b")
        let c = Fixtures.text("c")
        let history = ClipHistory(items: [a, b, c])

        let result = history.promoting(id: c.id, at: later)

        #expect(result.items.map(\.id) == [c.id, a.id, b.id])
        #expect(result.items.first?.createdAt == later)
        #expect(history.items.map(\.id) == [a.id, b.id, c.id])
    }

    // MARK: - removing / togglingFavorite / removingNonFavorites

    @Test("removing 删除指定条目")
    func removingDeletes() {
        let a = Fixtures.text("a")
        let b = Fixtures.text("b")
        let result = ClipHistory(items: [a, b]).removing(id: a.id)
        #expect(result.items.map(\.id) == [b.id])
    }

    @Test("togglingFavorite 切换收藏且两次后复原")
    func togglingFavorite() {
        let a = Fixtures.text("a")
        let b = Fixtures.text("b")
        let history = ClipHistory(items: [a, b])

        let once = history.togglingFavorite(id: b.id)
        #expect(once.items.map(\.isFavorite) == [false, true])
        #expect(once.togglingFavorite(id: b.id) == history)
    }

    @Test("removingNonFavorites 只保留收藏并维持顺序")
    func removingNonFavorites() {
        let f1 = Fixtures.text("f1", favorite: true)
        let n1 = Fixtures.text("n1")
        let f2 = Fixtures.image(name: "f2.png", favorite: true)
        let n2 = Fixtures.files(["/x"])
        let result = ClipHistory(items: [f1, n1, f2, n2]).removingNonFavorites()
        #expect(result.items.map(\.id) == [f1.id, f2.id])
    }

    @Test("不存在的 id 保持历史不变")
    func unknownIDIsNoop() {
        let history = ClipHistory(items: [Fixtures.text("a"), Fixtures.text("b", favorite: true)])
        let unknown = UUID()
        #expect(history.promoting(id: unknown, at: later) == history)
        #expect(history.removing(id: unknown) == history)
        #expect(history.togglingFavorite(id: unknown) == history)
    }

    @Test("空历史上的操作均安全")
    func operationsOnEmptyHistory() {
        let empty = ClipHistory.empty
        #expect(empty.removingNonFavorites() == empty)
        #expect(empty.trimmed(to: 1) == empty)
        #expect(empty.imageNames.isEmpty)
    }

    // MARK: - imageNames

    @Test("imageNames 只包含图片条目的文件名")
    func imageNames() {
        let history = ClipHistory(items: [
            Fixtures.image(name: "a.png"),
            Fixtures.text("t"),
            Fixtures.image(name: "b.png", favorite: true),
            Fixtures.files(["/c.png"]),
        ])
        #expect(history.imageNames == ["a.png", "b.png"])
    }

    @Test("大量条目插入后仍按上限保留最新的")
    func largeHistory() {
        let history = (0..<5_000).reduce(ClipHistory.empty) { partial, index in
            partial.inserting(Fixtures.text("item-\(index)"), limit: 500)
        }
        #expect(history.items.count == 500)
        #expect(history.items.first?.text == "item-4999")
        #expect(history.items.last?.text == "item-4500")
    }
}
