import Foundation
import Testing
@testable import CubbyCore

@Suite("HistoryMerge：合并规则（E7）")
struct HistoryMergeTests {
    private func at(_ minutes: Double) -> Date {
        Fixtures.baseDate.addingTimeInterval(minutes * 60)
    }

    @Test("按内容去重：保留 base 的条目，时间取较新、来源随之，收藏取并集")
    func dedupesByContent() {
        let base = Fixtures.text("same", source: SourceApp(bundleID: "a", name: "A"), at: at(1))
        let newer = Fixtures.text("same", favorite: true, source: SourceApp(bundleID: "b", name: "B"), at: at(5))
        let merged = HistoryMerge.merging(base: ClipHistory(items: [base]), incoming: [newer])

        let item = try? #require(merged.items.first)
        #expect(merged.items.count == 1)
        #expect(item?.id == base.id)
        #expect(item?.createdAt == at(5))
        #expect(item?.isFavorite == true)
        #expect(item?.source?.bundleID == "b")
    }

    @Test("较旧的重复条目不改时间，收藏仍取并集")
    func olderDuplicateKeepsDate() {
        let base = Fixtures.text("same", favorite: true, at: at(5))
        let older = Fixtures.text("same", at: at(1))
        let merged = HistoryMerge.merging(base: ClipHistory(items: [base]), incoming: [older])
        #expect(merged.items == [base])
    }

    @Test("译文以 base 为准；base 没有时取 incoming 的（富文本格式相同才取）")
    func translationsPreferBase() {
        let mine = TranslationFixtures.text("zh-Hans", segments: ["base"])
        let theirs = TranslationFixtures.text("zh-Hans", segments: ["incoming"])
        let base = Fixtures.text("t", at: at(1)).translated(mine)
        let other = Fixtures.text("t", at: at(2)).translated(theirs)
        let kept = HistoryMerge.merging(base: ClipHistory(items: [base]), incoming: [other])
        #expect(kept.items.first?.translations == ClipTranslations([mine]))

        let bare = Fixtures.text("t", at: at(1))
        let filled = HistoryMerge.merging(base: ClipHistory(items: [bare]), incoming: [other])
        #expect(filled.items.first?.translations == ClipTranslations([theirs]))

        let otherFormats = Fixtures.text("t", at: at(2), formatsName: "f.formats").translated(theirs)
        let skipped = HistoryMerge.merging(base: ClipHistory(items: [bare]), incoming: [otherFormats])
        #expect(skipped.items.first?.translations == nil)
        #expect(skipped.items.first?.formatsName == nil)
    }

    @Test("识别文字与网页标题：base 缺失时由 incoming 补上")
    func fillsMissingDetails() {
        let base = Fixtures.image(name: "i.png", at: at(1))
        let other = Fixtures.image(name: "i.png", at: at(0)).withRecognizedText("hello")
        let merged = HistoryMerge.merging(base: ClipHistory(items: [base]), incoming: [other])
        #expect(merged.items.first?.recognizedText == "hello")
    }

    @Test("合并后按时间从新到旧排序（时间相同保持原先后），不按条数裁剪（H1：保护名单此时不可靠，上限在下次记录时生效）")
    func sortsWithoutTrimming() {
        let a = Fixtures.text("a", at: at(3))
        let b = Fixtures.text("b", favorite: true, at: at(1))
        let c = Fixtures.text("c", at: at(4))
        let d = Fixtures.text("d", at: at(2))
        let e = Fixtures.text("e", at: at(2))
        let merged = HistoryMerge.merging(base: ClipHistory(items: [a, b, d]), incoming: [c, e])
        #expect(merged.items.map(\.text) == ["c", "a", "d", "e", "b"])
    }

    @Test("M1：重复条目可选保留 incoming 的 id，并报告被替换的 id")
    func keepsIncomingIDs() {
        let disk = Fixtures.text("same", at: at(1))
        let memory = Fixtures.text("same", at: at(2))
        let fresh = Fixtures.text("fresh", at: at(3))
        let result = HistoryMerge.merge(base: ClipHistory(items: [disk]), incoming: [memory, fresh], ids: .incoming)
        #expect(result.history.items.map(\.id) == [fresh.id, memory.id])
        #expect(result.replacedIDs == [disk.id: memory.id])

        let kept = HistoryMerge.merge(base: ClipHistory(items: [disk]), incoming: [memory], ids: .base)
        #expect(kept.history.items.map(\.id) == [disk.id])
        #expect(kept.replacedIDs == [memory.id: disk.id])
    }

    @Test("incoming 内部的重复也合并为一条；空输入不变")
    func incomingDuplicates() {
        let first = Fixtures.text("x", at: at(1))
        let second = Fixtures.text("x", favorite: true, at: at(2))
        let merged = HistoryMerge.merging(base: .empty, incoming: [first, second])
        #expect(merged.items.count == 1)
        #expect(merged.items.first?.id == first.id)
        #expect(merged.items.first?.isFavorite == true)
        #expect(HistoryMerge.merging(base: .empty, incoming: []) == .empty)
    }
}
