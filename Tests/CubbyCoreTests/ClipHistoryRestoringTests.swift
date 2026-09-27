import Foundation
import Testing
@testable import CubbyCore

@Suite("ClipHistory 恢复、blob 引用与富文本合并")
struct ClipHistoryRestoringTests {
    private let a = Fixtures.text("a")
    private let b = Fixtures.text("b")
    private let c = Fixtures.text("c")

    // MARK: - restoring

    @Test("恢复到原位置", arguments: [0, 1, 2])
    func restoresAtIndex(_ index: Int) {
        let removed = Fixtures.text("removed")
        let history = ClipHistory(items: [a, b])
        let restored = history.restoring(removed, at: index)

        #expect(restored.items.count == 3)
        #expect(restored.items[index].id == removed.id)
        #expect(restored.items.filter { $0.id != removed.id }.map(\.id) == [a.id, b.id])
    }

    @Test("索引越界时放到末尾，负数时放到开头")
    func clampsIndex() {
        let history = ClipHistory(items: [a, b])
        #expect(history.restoring(c, at: 99).items.map(\.id) == [a.id, b.id, c.id])
        #expect(history.restoring(c, at: -3).items.map(\.id) == [c.id, a.id, b.id])
    }

    @Test("恢复到空历史")
    func restoresIntoEmpty() {
        #expect(ClipHistory.empty.restoring(a, at: 5).items == [a])
    }

    @Test("同 id 条目已存在时保持不变")
    func ignoresExistingID() {
        let history = ClipHistory(items: [a, b])
        #expect(history.restoring(a, at: 1) == history)
        #expect(history.restoring(a.withFavorite(true), at: 0) == history)
    }

    @Test("恢复保留条目的全部字段且不修改原历史")
    func restoringIsNonMutating() {
        let rich = Fixtures.text("rich", favorite: true, formatsName: "r.formats")
        let history = ClipHistory(items: [a])
        let restored = history.restoring(rich, at: 0)

        #expect(restored.items.first == rich)
        #expect(history.items == [a])
    }

    @Test("恢复时相同内容已被重新记录：不插入重复条目，并把收藏状态合并到现有条目")
    func restoringDuplicateContent() {
        let original = Fixtures.text("dup", favorite: true)
        let recopied = Fixtures.text("dup", at: Fixtures.baseDate.addingTimeInterval(60))
        let restored = ClipHistory(items: [recopied]).restoring(original, at: 0)

        #expect(restored.items.count == 1)
        #expect(restored.items.first?.id == recopied.id)
        #expect(restored.items.first?.isFavorite == true)
    }

    @Test("恢复时相同内容已存在且被恢复条目未收藏：历史保持不变")
    func restoringDuplicateContentWithoutFavorite() {
        let original = Fixtures.text("dup")
        let recopied = Fixtures.text("dup", favorite: true, at: Fixtures.baseDate.addingTimeInterval(60))
        let history = ClipHistory(items: [recopied])
        #expect(history.restoring(original, at: 0) == history)
    }

    @Test("删除后恢复可回到删除前的历史", arguments: [0, 1, 2])
    func removeThenRestoreRoundTrip(_ index: Int) {
        let history = ClipHistory(items: [a, b, c])
        let target = history.items[index]
        #expect(history.removing(id: target.id).restoring(target, at: index) == history)
    }

    // MARK: - blobNames

    @Test("blobNames 汇总图片与富文本格式，忽略纯文本与文件")
    func blobNames() {
        let history = ClipHistory(items: [
            Fixtures.image(name: "a.png"),
            Fixtures.text("plain"),
            Fixtures.text("rich", formatsName: "r.formats"),
            Fixtures.image(name: "b.png", favorite: true),
            Fixtures.files(["/c.png"]),
        ])
        #expect(history.blobNames == ["a.png", "b.png", "r.formats"])
        #expect(history.imageNames == ["a.png", "b.png"])
    }

    @Test("多个条目引用同一 blob 时只出现一次")
    func sharedBlobNamesAreDeduplicated() {
        let history = ClipHistory(items: [
            Fixtures.text("x", formatsName: "same.formats"),
            Fixtures.text("y", formatsName: "same.formats"),
        ])
        #expect(history.blobNames == ["same.formats"])
    }

    @Test("空历史的 blobNames 为空")
    func emptyBlobNames() {
        #expect(ClipHistory.empty.blobNames.isEmpty)
    }

    // MARK: - inserting 合并富文本

    @Test("重复复制时富文本格式取最新一次的值")
    func mergeTakesLatestFormats() throws {
        let later = Fixtures.baseDate.addingTimeInterval(60)
        let old = Fixtures.text("dup", favorite: true, formatsName: "old.formats")
        let history = ClipHistory(items: [b, old])

        let result = history.inserting(Fixtures.text("dup", at: later, formatsName: "new.formats"), limit: 10)

        let head = try #require(result.items.first)
        #expect(head.id == old.id)
        #expect(head.isFavorite)
        #expect(head.formatsName == "new.formats")
        #expect(result.blobNames == ["new.formats"])
    }

    @Test("以纯文本再次复制富文本内容时清除格式")
    func mergePlainClearsFormats() {
        let history = ClipHistory(items: [Fixtures.text("dup", formatsName: "old.formats")])
        let result = history.inserting(Fixtures.text("dup"), limit: 10)
        #expect(result.items.first?.formatsName == nil)
        #expect(result.blobNames.isEmpty)
    }

    @Test("以富文本再次复制纯文本内容时补上格式")
    func mergeRichAddsFormats() {
        let history = ClipHistory(items: [Fixtures.text("dup")])
        let result = history.inserting(Fixtures.text("dup", formatsName: "new.formats"), limit: 10)
        #expect(result.items.first?.formatsName == "new.formats")
        #expect(result.items.count == 1)
    }
}
