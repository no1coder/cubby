import Foundation
import Testing
@testable import CubbyCore

/// P1-10：搜索结果按相关度三档稳定排序（整句命中 → 首个关键词靠前 → 其余），图片文字命中排在正文命中之后
@Suite("ClipFilter 相关度排序")
struct ClipSearchRankingTests {
    private func texts(_ items: [ClipItem], _ query: String) -> [String?] {
        ClipFilter.apply(items, query: ClipQuery(text: query)).map(\.text)
    }

    /// 审计中的演示数据：第 N 条，越小越新（历史顺序为 1、2、3…）
    private static func demoItems(count: Int) -> [ClipItem] {
        (1...count).map { index in
            Fixtures.text(
                "第 \(index) 条演示文本，用于测试大量条目下的滚动与性能表现。Item \(index) of many.",
                at: Fixtures.baseDate.addingTimeInterval(-Double(index) * 10)
            )
        }
    }

    // MARK: - 审计示例

    @Test("审计示例「第 5」：整句命中的条目排在「第 15」「第 25」之前")
    func auditExample() {
        let items = Self.demoItems(count: 600)
        let result = ClipFilter.apply(items, query: ClipQuery(text: "第 5"))
        let numbers = result.map { item -> Int in
            let digits = item.text?.dropFirst(2).prefix { $0.isNumber } ?? ""
            return Int(digits) ?? -1
        }
        // 整句「第 5」命中：5、50–59、500–599，按原（时间）顺序
        let phraseHits = [5] + Array(50...59) + Array(500...599)
        #expect(Array(numbers.prefix(phraseHits.count)) == phraseHits)
        // 其余命中「第」与「5」的条目紧随其后，同样保持原顺序
        #expect(numbers[phraseHits.count] == 15)
        #expect(numbers[phraseHits.count + 1] == 25)
        #expect(result.count == items.filter { $0.text?.contains("5") == true }.count)
    }

    // MARK: - 三档

    @Test("首个关键词在前 60 个字符内的排在关键词分散的条目之前")
    func leadingKeywordTier() {
        let padding = String(repeating: "x", count: 80)
        let items = [
            Fixtures.text("\(padding) report quarterly"),
            Fixtures.text("quarterly \(padding) report"),
            Fixtures.text("the quarterly report"),
        ]
        #expect(
            texts(items, "quarterly report") == [
                "the quarterly report", "quarterly \(padding) report", "\(padding) report quarterly",
            ])
    }

    @Test("首个关键词的起始位置恰在第 60 个字符算靠前，第 61 个字符不算")
    func leadingWindowBoundary() {
        let inside = Fixtures.text(String(repeating: "a", count: 59) + "key tail zz")
        let outside = Fixtures.text(String(repeating: "b", count: 60) + "key tail zz")
        #expect(texts([outside, inside], "key zz") == [inside.text, outside.text])
        #expect(
            ClipSearchRanking.relevance(of: inside, phrase: "key zz", keywords: ["key", "zz"]) == .leading)
        #expect(
            ClipSearchRanking.relevance(of: outside, phrase: "key zz", keywords: ["key", "zz"]) == .other)
    }

    @Test("同一档内保持原顺序（稳定），收藏不额外置顶")
    func stableWithinTier() {
        let items = [
            Fixtures.text("alpha beta one"),
            Fixtures.text("beta alpha two", favorite: true),
            Fixtures.text("alpha beta three", favorite: true),
            Fixtures.text("beta alpha four"),
        ]
        #expect(
            texts(items, "alpha beta") == [
                "alpha beta one", "alpha beta three", "beta alpha two", "beta alpha four",
            ])
    }

    // MARK: - 语言、大小写与空白

    @Test("中英文混排：整句（含空格）命中优先")
    func mixedChineseAndEnglish() {
        let items = [
            Fixtures.text("Swift 教程与并发笔记"),
            Fixtures.text("学习 Swift 并发"),
            Fixtures.text("Swift 并发 入门"),
        ]
        #expect(texts(items, "Swift 并发") == ["学习 Swift 并发", "Swift 并发 入门", "Swift 教程与并发笔记"])
    }

    @Test("整句匹配忽略大小写与变音符")
    func caseAndDiacriticInsensitivePhrase() {
        let items = [
            Fixtures.text("lait, café au"),
            Fixtures.text("menu: CAFE AU LAIT"),
        ]
        #expect(texts(items, "  Café au Lait ") == ["menu: CAFE AU LAIT", "lait, café au"])
    }

    @Test("只输入空格：不过滤也不重排")
    func whitespaceOnlyKeepsOrder() {
        let items = Self.demoItems(count: 20)
        #expect(ClipFilter.apply(items, query: ClipQuery(text: "   \u{3000} ")) == items)
        #expect(ClipQuery(text: " \t ").phrase.isEmpty)
    }

    @Test("只有一个关键词：正文命中排在仅来源应用名命中之前")
    func singleKeyword() {
        let notes = SourceApp(bundleID: "com.apple.Notes", name: "Notes")
        let items = [
            Fixtures.text("meeting minutes", source: notes),
            Fixtures.text("notes for tomorrow"),
            Fixtures.text("grocery list", source: notes),
        ]
        #expect(texts(items, "notes") == ["notes for tomorrow", "meeting minutes", "grocery list"])
    }

    @Test("首尾空白不影响整句，但保留查询内部的空白")
    func phraseTrimsOuterWhitespaceOnly() {
        #expect(ClipQuery(text: "  hello   world \n").phrase == "hello   world")
        #expect(ClipQuery(text: "单个").phrase == "单个")
    }

    // MARK: - 文件与图片

    @Test("文件路径同样参与整句与靠前判定")
    func filePaths() {
        let items = [
            Fixtures.files(["/Users/me/Documents/archive/2024/report-final.pdf"]),
            Fixtures.files(["/tmp/final report.pdf"]),
        ]
        let titles = ClipFilter.apply(items, query: ClipQuery(text: "final report")).map(\.title)
        #expect(titles == ["final report.pdf", "report-final.pdf"])
    }

    @Test("图片文字命中排在所有正文命中之后，其内部同样按三档排序")
    func imageTextRanksBelowContent() {
        let scattered = Fixtures.text(String(repeating: "x", count: 80) + " invoice ... total")
        let photo = Fixtures.image(name: "a.png").withRecognizedText("Invoice total 2026")
        let receipt = Fixtures.image(name: "b.png").withRecognizedText("total due, see invoice")
        let items = [receipt, photo, scattered]

        let result = ClipFilter.apply(items, query: ClipQuery(text: "invoice total"))
        #expect(result.map(\.id) == [scattered.id, photo.id, receipt.id])
        #expect(
            ClipSearchRanking.relevance(of: photo, phrase: "invoice total", keywords: ["invoice", "total"])
                == .imageTextPhrase)
        #expect(
            ClipSearchRanking.relevance(of: receipt, phrase: "invoice total", keywords: ["invoice", "total"])
                == .imageTextLeading)
    }

    @Test("图片仅靠类型名或来源命中时属于正文档，不因有识别文字而降档")
    func imageMatchedByKindName() {
        let image = Fixtures.image(name: "a.png").withRecognizedText("unrelated words")
        #expect(
            ClipSearchRanking.relevance(
                of: image, phrase: ClipKind.image.displayName, keywords: [ClipKind.image.displayName]) == .other)
    }

    @Test("关键词一部分在图片文字、一部分在来源名：按图片文字档排序")
    func mixedImageTextAndSource() {
        let source = SourceApp(bundleID: "io.github.no1coder.Cubby", name: "Cubby Screenshot")
        let image = ClipItem(
            kind: .image, payload: .image(ImageRef(name: "c.png", width: 1, height: 1)), source: source,
            createdAt: Fixtures.baseDate, contentHash: "image:c", recognizedText: "Invoice 2026"
        )
        let result = ClipFilter.apply([image], query: ClipQuery(text: "invoice screenshot"))
        #expect(result == [image])
        #expect(
            ClipSearchRanking.relevance(of: image, phrase: "invoice screenshot", keywords: ["invoice", "screenshot"])
                == .imageTextLeading)
    }

    @Test("未命中全部关键词时 relevance 为 nil；没有关键词时也为 nil")
    func relevanceOfNonMatching() {
        let item = Fixtures.text("alpha beta")
        #expect(ClipSearchRanking.relevance(of: item, phrase: "alpha gamma", keywords: ["alpha", "gamma"]) == nil)
        #expect(ClipSearchRanking.relevance(of: item, phrase: "gamma", keywords: ["gamma"]) == nil)
        #expect(ClipSearchRanking.relevance(of: item, phrase: "", keywords: []) == nil)
        let image = Fixtures.image(name: "a.png").withRecognizedText("alpha")
        #expect(ClipSearchRanking.relevance(of: image, phrase: "alpha beta", keywords: ["alpha", "beta"]) == nil)
    }

    @Test("单个关键词只命中图片文字：图片文字整句档，排在来源名命中之后")
    func singleKeywordInImageText() {
        let notes = SourceApp(bundleID: "com.apple.Notes", name: "Invoice Notes")
        let image = Fixtures.image(name: "a.png").withRecognizedText("Invoice 2026")
        let text = Fixtures.text("meeting minutes", source: notes)
        #expect(ClipSearchRanking.relevance(of: image, phrase: "invoice", keywords: ["invoice"]) == .imageTextPhrase)
        #expect(ClipFilter.apply([image, text], query: ClipQuery(text: "invoice")).map(\.id) == [text.id, image.id])
    }

    @Test("首个关键词只命中来源名、其余命中正文：属于其余档")
    func firstKeywordInSourceOnly() {
        let safari = SourceApp(bundleID: "com.apple.Safari", name: "Safari")
        let item = Fixtures.text("release notes", source: safari)
        #expect(ClipSearchRanking.relevance(of: item, phrase: "safari notes", keywords: ["safari", "notes"]) == .other)
    }

    @Test("整句出现在首个关键词第二次出现处也能识别")
    func phraseAfterEarlierFirstKeyword() {
        let item = Fixtures.text("report: see the final report today")
        #expect(
            ClipSearchRanking.relevance(of: item, phrase: "report today", keywords: ["report", "today"]) == .phrase)
    }

    @Test("分档枚举按声明顺序比较")
    func relevanceOrdering() {
        #expect(SearchRelevance.allCases.sorted() == SearchRelevance.allCases)
        #expect(SearchRelevance.phrase < .imageTextPhrase)
    }
}
