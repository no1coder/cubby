import Foundation
import Testing
@testable import CubbyCore

/// 译文参与搜索（docs/CLIP-TRANSLATION-DESIGN.md §3）：档位「原文 > 图中文字 > 译文」、跨字段关键词、
/// 预折叠索引与逐条匹配等价、写入译文只重折叠该条、会话收窄仍成立
@Suite("搜索 · 译文档位")
struct ClipSearchTranslationTests {
    private func ranked(_ items: [ClipItem], _ query: String, index: Bool = false) -> [UUID] {
        let clipQuery = ClipQuery(text: query)
        let built = index ? ClipSearchIndex(items: items) : nil
        return ClipFilter.apply(items, query: clipQuery, index: built).map(\.id)
    }

    private func relevance(_ item: ClipItem, _ query: String) -> SearchRelevance? {
        let clipQuery = ClipQuery(text: query)
        return ClipSearchRanking.relevance(of: item, phrase: clipQuery.phrase, keywords: clipQuery.keywords)
    }

    @Test("原文 > 图中文字 > 译文：同一关键词按命中字段分档，译文命中排在最后")
    func tierOrder() {
        let viaTranslation = Fixtures.text("Bonjour tout le monde").translated(
            TranslationFixtures.text("en", segments: ["Hello everyone"]))
        let viaImage = Fixtures.image(name: "a.png").withRecognizedText("hello from image")
        let viaContent = Fixtures.text("hello world")
        let items = [viaTranslation, viaImage, viaContent]
        for useIndex in [false, true] {
            #expect(ranked(items, "hello", index: useIndex) == [viaContent.id, viaImage.id, viaTranslation.id])
        }
        #expect(relevance(viaTranslation, "hello") == .translationPhrase)
        #expect(relevance(viaTranslation, "hello")?.matchedField == .translation)
        #expect(relevance(viaImage, "hello")?.matchedField == .imageText)
        #expect(relevance(viaContent, "hello")?.matchedField == .content)
    }

    @Test("译文内同样分整句 / 靠前 / 其余三档")
    func tiersWithinTranslation() {
        let padding = String(repeating: "x", count: 80)
        let phrase = Fixtures.text("un").translated(TranslationFixtures.text("en", segments: ["quarterly report due"]))
        let leading = Fixtures.text("deux").translated(
            TranslationFixtures.text("en", segments: ["quarterly \(padding) report"]))
        let other = Fixtures.text("trois").translated(
            TranslationFixtures.text("en", segments: ["\(padding) report quarterly"]))
        #expect(relevance(phrase, "quarterly report") == .translationPhrase)
        #expect(relevance(leading, "quarterly report") == .translationLeading)
        #expect(relevance(other, "quarterly report") == .translationOther)
        #expect(ranked([other, leading, phrase], "quarterly report") == [phrase.id, leading.id, other.id])
        #expect(
            ranked([other, leading, phrase], "quarterly report", index: true) == [phrase.id, leading.id, other.id])
    }

    @Test("多个关键词可跨字段命中：原文 + 译文、图中文字 + 译文、来源名 + 译文")
    func crossFieldKeywords() {
        let safari = SourceApp(bundleID: "com.apple.Safari", name: "Safari")
        let text = Fixtures.text("Rapport trimestriel", source: safari).translated(
            TranslationFixtures.text("en", segments: ["Quarterly report"]))
        let image = Fixtures.image(name: "a.png").withRecognizedText("Invoice 2026")
            .translated(TranslationFixtures.image(blob: "t.png", segments: ["\u{53D1}\u{7968}"]))
        #expect(relevance(text, "rapport quarterly") == .translationOther)
        #expect(relevance(text, "safari quarterly") == .translationOther)
        #expect(relevance(text, "quarterly rapport") == .translationLeading)
        #expect(relevance(image, "invoice \u{53D1}\u{7968}") == .translationOther)
        #expect(relevance(image, "\u{53D1}\u{7968} invoice") == .translationLeading)
        #expect(relevance(image, "invoice 2026") == .imageTextPhrase)
        #expect(relevance(text, "rapport zzz") == nil)
    }

    @Test("富文本译文去掉行内标记后参与搜索：标记符号与链接地址不会被搜到")
    func markupIsStripped() {
        let item = Fixtures.text("Rich").translated(
            TranslationFixtures.text(
                "zh-Hans", segments: ["**\u{7C97}\u{4F53}** [\u{94FE}\u{63A5}](https://secret.example)"], markup: true))
        for useIndex in [false, true] {
            #expect(ranked([item], "\u{7C97}\u{4F53} \u{94FE}\u{63A5}", index: useIndex) == [item.id])
            #expect(ranked([item], "secret", index: useIndex).isEmpty)
            #expect(ranked([item], "**", index: useIndex).isEmpty)
        }
    }

    @Test("写入译文后索引只重折叠该条，查询立即反映新译文")
    func refoldsOnlyChangedItem() {
        let items = (0..<10).map { Fixtures.text("item \($0)") }
        let index = ClipSearchIndex(items: items)
        let translated = items.enumerated().map { offset, item in
            offset == 3 ? item.translated(TranslationFixtures.text("fr", segments: ["\u{00E9}l\u{00E9}ment"])) : item
        }

        let updated = index.updated(for: translated)

        #expect(updated.lastFoldedCount == 1)
        #expect(updated.isCurrent(for: translated))
        #expect(!index.isCurrent(for: translated))
        let query = ClipQuery(text: "element")
        #expect(ClipFilter.apply(translated, query: query, index: updated).map(\.id) == [items[3].id])
        #expect(updated.updated(for: translated).lastFoldedCount == 0)
        #expect(updated.updated(for: items).lastFoldedCount == 1)
    }

    @Test("含折叠语义不一致字符的译文：该条走逐条匹配，结果不变")
    func exactOnlyTranslationFallsBack() {
        let item = Fixtures.text("plain").translated(TranslationFixtures.text("de", segments: ["Stra\u{00DF}e"]))
        let index = ClipSearchIndex(items: [item])
        #expect(index.entry(for: item) == nil)
        #expect(ClipFilter.apply([item], query: ClipQuery(text: "stra"), index: index).map(\.id) == [item.id])
    }
}

/// 译文路径的 ClipStore 集成：搜索索引随 setTranslation 更新，会话收窄与全量计算一致
@Suite("搜索 · 译文与 ClipStore")
@MainActor
struct ClipStoreTranslationSearchTests {
    @Test("setTranslation 后立即可搜（只重折叠一条），清除译文后搜不到")
    func storeSearchFollowsTranslations() async throws {
        let dir = try TempDirectory.make()
        defer { TempDirectory.remove(dir) }
        let items = (0..<20).map { Fixtures.text("note \($0)") }
        let store = StoreFactory.make(dir: dir, storage: InMemoryHistoryStorage(initial: ClipHistory(items: items)))
        await store.waitForSearchIndex()

        store.setTranslation(TranslationFixtures.text("zh-Hans", segments: ["\u{7B14}\u{8BB0} 7"]), for: items[7].id)

        #expect(store.searchIndex?.lastFoldedCount == 1)
        #expect(store.search(ClipQuery(text: "\u{7B14}\u{8BB0}")).map(\.id) == [items[7].id])
        store.clearTranslations()
        #expect(store.search(ClipQuery(text: "\u{7B14}\u{8BB0}")).isEmpty)
    }

    @Test("逐键收窄：继续输入时只在上次命中的条目中过滤，结果与全量计算一致（含译文命中）")
    func sessionNarrowingWithTranslations() async throws {
        let dir = try TempDirectory.make()
        defer { TempDirectory.remove(dir) }
        let items = (0..<30).map { index in
            index.isMultiple(of: 3)
                ? Fixtures.text("texte \(index)").translated(
                    TranslationFixtures.text("en", segments: ["cache line \(index)"]))
                : Fixtures.text("cache entry \(index)")
        }
        let store = StoreFactory.make(
            dir: dir, storage: InMemoryHistoryStorage(initial: ClipHistory(items: items)), limit: 100)
        await store.waitForSearchIndex()
        var session = ClipSearchSession()
        for text in ["c", "ca", "cac", "cach", "cache", "cache l", "cache li"] {
            let query = ClipQuery(text: text)
            #expect(
                session.results(for: query, in: store) == ClipFilter.apply(store.history.items, query: query), "\(text)"
            )
        }
    }
}
