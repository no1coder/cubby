import Foundation
import Testing
@testable import CubbyCore

/// 预折叠索引（folding + memmem）与逐条 localizedStandardContains 的结果必须完全一致（含排序）
@Suite("ClipSearchIndex 语义对照")
struct ClipSearchIndexEquivalenceTests {
    private static let safari = SourceApp(bundleID: "com.apple.Safari", name: "Safari")
    private static let notes = SourceApp(bundleID: "com.apple.Notes", name: "Ångström Notes")

    /// 边界语料：变音符（预组合 / 分解）、ß 与 SS、连字、全角、土耳其 İ、ZWJ 表情、日文、中文、韩文、
    /// 其他书写系统的数字、带圈数字、上标、ŉ、天城文、文件路径、来源名、图片识别文字
    static let corpus: [ClipItem] = [
        Fixtures.text("Café au lait"),
        Fixtures.text("Cafe\u{301} decomposed"),
        Fixtures.text("Straße und STRASSE"),
        Fixtures.text("\u{1E9E}\u{00DF} only"),
        Fixtures.text("\u{FB01}le and \u{FB00}ect"),
        Fixtures.text("\u{FF21}\u{FF22}\u{FF23} \u{FF11}\u{FF12}\u{FF13} full width"),
        Fixtures.text("\u{0130}stanbul \u{0131}zmir"),
        Fixtures.text(
            "family \u{1F468}\u{200D}\u{1F469}\u{200D}\u{1F467} and \u{1F44D}\u{1F3FD} flag \u{1F1E8}\u{1F1F3}"),
        Fixtures.text(
            "\u{6771}\u{4EAC}\u{30BF}\u{30EF}\u{30FC} \u{304B}\u{305F}\u{304B}\u{306A} \u{30AB}\u{30BF}\u{30AB}\u{30CA}"
        ),
        Fixtures.text("\u{526A}\u{8D34}\u{677F}\u{5386}\u{53F2}\u{FF0C}\u{7B2C} 5 \u{6761}", source: safari),
        Fixtures.text("\u{D55C}\u{AD6D}\u{C5B4} \u{AC01}"),
        Fixtures.text("\u{0663}\u{0660}\u{0662}\u{0666} arabic digits"),
        Fixtures.text("\u{2460}\u{2461} circled, m\u{00B2}, \u{00BD}, \u{3007}"),
        Fixtures.text("\u{0149}ot a word"),
        Fixtures.text("\u{0915}\u{0902} \u{0939}\u{093F}\u{0902}\u{0926}\u{0940}"),
        Fixtures.text("resume R\u{00C9}SUM\u{00C9} na\u{00EF}ve \u{03A3}\u{03C2}"),
        Fixtures.text("2026 plain digits and cache"),
        Fixtures.files(["/Users/me/R\u{00E9}sum\u{00E9}.pdf", "/tmp/\u{6587}\u{4EF6}.txt"]),
        Fixtures.image(name: "a.png").withRecognizedText("Invoice 2026 \u{53D1}\u{7968} Caf\u{00E9}"),
        Fixtures.image(name: "b.png").withRecognizedText(""),
        ClipItem(
            kind: .image, payload: .image(ImageRef(name: "c.png", width: 1, height: 1)), source: notes,
            createdAt: Fixtures.baseDate, contentHash: "image:c", recognizedText: "Stra\u{00DF}e \u{FF12}\u{FF10}"),
        // 译文：纯文本、富文本标记、含不一致字符、图片译文、多种语言
        Fixtures.text("Bonjour le cache").translated(
            TranslationFixtures.text("en", segments: ["Hello Caf\u{00E9} cache 2026", nil, "invoice total"])),
        Fixtures.text("\u{7F13}\u{5B58}\u{8BF4}\u{660E}", source: safari).translated(
            TranslationFixtures.text("en", segments: ["**Cache** [notes](https://a.b/c)", "`resume`"], markup: true),
            TranslationFixtures.text("ja", segments: ["\u{30AD}\u{30E3}\u{30C3}\u{30B7}\u{30E5}"])),
        Fixtures.text("Gru\u{00DF}").translated(TranslationFixtures.text("de", segments: ["Stra\u{00DF}e \u{2460}"])),
        Fixtures.image(name: "d.png").withRecognizedText("Invoice").translated(
            TranslationFixtures.image(blob: "t.png", segments: ["\u{53D1}\u{7968} total", "Caf\u{00E9}"])),
    ]

    static let queries: [String] = [
        "cafe", "CAFÉ", "e\u{301}", "e", "\u{00E9}", "strasse", "STRASSE", "straße", "ss", "s", "\u{1E9E}", "ß",
        "file", "\u{FB01}", "ff", "\u{FF41}\u{FF42}\u{FF43}", "abc", "123", "\u{FF11}", "1", "2", "3", "0",
        "istanbul", "\u{0130}", "i", "\u{0131}", "\u{1F468}", "\u{1F469}", "\u{1F44D}", "\u{1F1E8}",
        "\u{30BF}\u{30EF}", "\u{304B}", "\u{30AB}", "\u{8D34}\u{677F}", "\u{7B2C} 5", "\u{FF0C}", "\u{AC00}",
        "\u{AC01}",
        "\u{0663}", "2026", "m2", "\u{00B2}", "n", "\u{0902}", "\u{0915}", "resume", "\u{03C3}", "invoice",
        "\u{53D1}\u{7968}", "invoice total", "angstrom", "notes", "safari", "image", "pdf", "/tmp", "cache 2026",
        "  CAFÉ   au  ", "au lait", "zzqx", "\u{0301}", "\u{0301}e", "cafe\u{0301}",
        "hello", "bonjour hello", "hello bonjour", "cache hello", "invoice total", "total invoice", "notes",
        "safari cache", "\u{7F13}\u{5B58} cache", "\u{30AD}\u{30E3}", "**", "https", "resume notes", "c1",
        "\u{53D1}\u{7968} invoice", "invoice \u{53D1}\u{7968}", "2026 hello", "cafe cache",
    ]

    private func assertEquivalent(_ items: [ClipItem], _ texts: [String], category: ClipCategory = .all) {
        let index = ClipSearchIndex(items: items)
        for text in texts {
            let query = ClipQuery(text: text, category: category)
            let expected = ClipFilter.apply(items, query: query)
            let actual = ClipFilter.apply(items, query: query, index: index)
            #expect(actual.map(\.id) == expected.map(\.id), "query \(text.debugDescription)")
        }
    }

    @Test("边界语料：每个查询的结果与排序都与逐条匹配一致")
    func corpusEquivalence() {
        assertEquivalent(Self.corpus, Self.queries)
    }

    @Test("边界语料：按分类过滤时同样一致", arguments: [ClipCategory.text, .image, .file, .favorite])
    func corpusEquivalenceByCategory(_ category: ClipCategory) {
        assertEquivalent(Self.corpus, Self.queries, category: category)
    }

    @Test("两两组合的多关键词查询也一致（整句与靠前判定）")
    func pairwiseQueries() {
        let words = [
            "cafe", "e", "ss", "2026", "\u{8D34}\u{677F}", "\u{1F468}", "i", "image", "\u{FF11}", "invoice", "hello",
            "total", "\u{53D1}\u{7968}",
        ]
        let pairs = words.flatMap { first in words.map { "\(first) \($0)" } }
        assertEquivalent(Self.corpus, pairs)
    }

    @Test("随机语料与随机查询（固定种子）结果一致")
    func randomizedEquivalence() {
        var random = SeededGenerator(seed: 20_260_927)
        let alphabet = Array(
            "abcdeEFGHéÉèüÜßẞﬁ0123456789 ２３①²İıςσΣ中文剪贴板第条タワかカ한국\u{0301}\u{1F44D}\u{1F468}\u{200D}\u{1F469}-_/.:")
        let items = (0..<300).map { index -> ClipItem in
            let length = Int.random(in: 1...80, using: &random)
            let text = String((0..<length).map { _ in alphabet.randomElement(using: &random) ?? "a" })
            let item =
                index.isMultiple(of: 7)
                ? Fixtures.image(name: "\(index).png").withRecognizedText(text)
                : Fixtures.text(text + " #\(index)")
            guard index.isMultiple(of: 3) else { return item }
            let translated = String(text.shuffled(using: &random))
            return item.kind == .image
                ? item.translated(TranslationFixtures.image(blob: "t\(index).png", segments: [translated]))
                : item.translated(TranslationFixtures.text("en", segments: [translated, nil]))
        }
        let queries = (0..<FuzzBudget.scaled(200)).map { _ -> String in
            let item = items.randomElement(using: &random)
            let preferTranslation = Bool.random(using: &random)
            let source = (preferTranslation ? item?.translationSample : nil) ?? item?.searchSample ?? "a"
            let characters = Array(source)
            let start = Int.random(in: 0..<max(characters.count, 1), using: &random)
            let length = Int.random(in: 1...4, using: &random)
            let slice = String(characters[start..<min(start + length, characters.count)])
            return Bool.random(using: &random) ? slice.uppercased() : slice
        }
        assertEquivalent(items, queries)
    }

    @Test("含与折叠语义不一致字符的查询整体走逐条匹配")
    func exactOnlyQueriesFallBack() {
        let index = ClipSearchIndex(items: Self.corpus)
        #expect(index.terms(for: ClipQuery(text: "cafe 2026")) != nil)
        #expect(index.terms(for: ClipQuery(text: "\u{FF11}")) == nil)
        #expect(index.terms(for: ClipQuery(text: "\u{0902}")) == nil)
        #expect(index.terms(for: ClipQuery(text: "\u{00DF}")) == nil)
        #expect(index.terms(for: ClipQuery(text: "\u{0301}")) == nil)
        #expect(index.terms(for: ClipQuery(text: "   ")) == nil)
    }

    @Test("含不一致字符的条目标记为逐条匹配，其余走索引")
    func exactOnlyEntries() {
        let index = ClipSearchIndex(items: Self.corpus)
        let flagged = Self.corpus.filter { index.entry(for: $0) == nil }.compactMap(\.searchSample)
        #expect(flagged.contains { $0.contains("\u{00DF}") })
        #expect(flagged.contains { $0.contains("\u{0663}") })
        #expect(flagged.contains { $0.contains("\u{2460}") })
        #expect(!flagged.contains { $0.hasPrefix("Caf") })
        #expect(!flagged.contains { $0.contains("\u{526A}") })
    }

    @Test("折叠字符判定：ASCII、中日韩快速路径不标记；数字、大小写展开、较新书写系统的大小写标记")
    func exactOnlyScalars() {
        let safe: [Unicode.Scalar] = [
            "a", "\u{00E9}", "\u{00C9}", "\u{4E00}", "\u{4E8C}", "\u{30AB}", "\u{AC00}", "\u{FF21}",
        ]
        let flagged: [Unicode.Scalar] = [
            "\u{00DF}", "\u{1E9E}", "\u{0149}", "\u{FB01}", "\u{FF11}", "\u{0663}", "\u{2460}", "\u{00B2}", "\u{3007}",
            "\u{0130}", "\u{10400}",
        ]
        #expect(safe.allSatisfy { !SearchFolding.isExactOnly($0) })
        #expect(flagged.allSatisfy { SearchFolding.isExactOnly($0) })
    }
}

private extension ClipItem {
    /// 测试用：条目中可供搜索的主要文字（有译文时随机取原文或译文）
    var searchSample: String? {
        text ?? recognizedText ?? filePaths.first
    }

    var translationSample: String? {
        translationSearchText
    }
}

/// 可复现的伪随机数（SplitMix64）
struct SeededGenerator: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) {
        state = seed
    }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var value = state
        value = (value ^ (value >> 30)) &* 0xBF58_476D_1CE4_E5B9
        value = (value ^ (value >> 27)) &* 0x94D0_49BB_1331_11EB
        return value ^ (value >> 31)
    }
}
