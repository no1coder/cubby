import Foundation
import Testing
@testable import CubbyCore

@Suite("ClipFilter 分类与关键词过滤")
struct ClipFilterTests {
    /// 每个测试实例只生成一次，保证多次比较时 id 一致
    private let sample = Self.makeSample()

    private static func makeSample() -> [ClipItem] {
        let safari = SourceApp(bundleID: "com.apple.Safari", name: "Safari")
        return [
            Fixtures.text("Hello brave new World", source: safari),
            Fixtures.text("https://example.com/docs"),
            Fixtures.text("#FF8800", favorite: true),
            Fixtures.image(name: "shot.png"),
            Fixtures.files(["/Users/me/Documents/Quarterly-Report.pdf"], favorite: true),
            Fixtures.text("hello there"),
            Fixtures.text("Café au lait"),
        ]
    }

    private func titles(_ query: ClipQuery) -> [String] {
        ClipFilter.apply(sample, query: query).map(\.title)
    }

    @Test("默认查询返回全部且保持顺序")
    func defaultQueryReturnsAll() {
        #expect(ClipFilter.apply(sample, query: ClipQuery()) == sample)
    }

    @Test("仅空白的关键词等同于无关键词")
    func whitespaceOnlyQuery() {
        #expect(ClipFilter.apply(sample, query: ClipQuery(text: "  \n\t ")) == sample)
    }

    @Test(
        "按类型分类过滤",
        arguments: [
            (ClipCategory.text, ClipKind.text),
            (.link, .link),
            (.color, .color),
            (.image, .image),
            (.file, .file),
        ])
    func filtersByKind(_ category: ClipCategory, _ kind: ClipKind) {
        let result = ClipFilter.apply(sample, query: ClipQuery(category: category))
        #expect(!result.isEmpty)
        #expect(result.allSatisfy { $0.kind == kind })
        #expect(result.count == sample.filter { $0.kind == kind }.count)
    }

    @Test("收藏分类只返回收藏条目")
    func filtersFavorites() {
        let result = ClipFilter.apply(sample, query: ClipQuery(category: .favorite))
        #expect(result.count == 2)
        #expect(result.allSatisfy { $0.isFavorite })
    }

    @Test("多个关键词需全部命中")
    func keywordsAreANDed() {
        #expect(titles(ClipQuery(text: "hello world")) == ["Hello brave new World"])
        #expect(titles(ClipQuery(text: "hello")) == ["Hello brave new World", "hello there"])
        #expect(titles(ClipQuery(text: "hello missing")).isEmpty)
    }

    @Test("忽略大小写与变音符")
    func caseAndDiacriticInsensitive() {
        #expect(titles(ClipQuery(text: "HELLO THERE")) == ["hello there"])
        #expect(titles(ClipQuery(text: "cafe")) == ["Café au lait"])
    }

    @Test("可按文件路径搜索")
    func searchesFilePaths() {
        #expect(titles(ClipQuery(text: "documents report")) == ["Quarterly-Report.pdf"])
    }

    @Test("可按来源应用名搜索")
    func searchesSourceAppName() {
        #expect(titles(ClipQuery(text: "safari")) == ["Hello brave new World"])
    }

    @Test("分类与关键词同时生效")
    func categoryAndKeywordCombined() {
        #expect(titles(ClipQuery(text: "hello", category: .favorite)).isEmpty)
        #expect(titles(ClipQuery(text: "example", category: .link)) == ["https://example.com/docs"])
        #expect(titles(ClipQuery(text: "example", category: .text)).isEmpty)
    }

    @Test("特殊字符按字面匹配")
    func specialCharacters() {
        let items = [Fixtures.text("SELECT * FROM t WHERE a = '1'; -- 📋")]
        #expect(ClipFilter.apply(items, query: ClipQuery(text: "'1';")).count == 1)
        #expect(ClipFilter.apply(items, query: ClipQuery(text: "📋")).count == 1)
        #expect(ClipFilter.apply(items, query: ClipQuery(text: ".*")).isEmpty)
    }

    @Test("空列表返回空")
    func emptyInput() {
        #expect(ClipFilter.apply([], query: ClipQuery(text: "x", category: .link)).isEmpty)
    }

    @Test("超过 searchLimit 的正文部分不参与过滤")
    func respectsSearchLimit() {
        let tail = Fixtures.text(String(repeating: "a", count: ClipItem.searchLimit) + " needle")
        let head = Fixtures.text("needle " + String(repeating: "a", count: ClipItem.searchLimit))
        #expect(ClipFilter.apply([tail, head], query: ClipQuery(text: "needle")) == [head])
    }

    @Test("一万条目中按关键词与分类过滤，保持原顺序")
    func largeInput() {
        let items = (0..<10_000).map { index in
            Fixtures.text(
                index.isMultiple(of: 100) ? "match-\(index)" : "other-\(index)", favorite: index.isMultiple(of: 200))
        }
        let matched = ClipFilter.apply(items, query: ClipQuery(text: "MATCH"))
        #expect(matched.count == 100)
        #expect(matched.map(\.id) == items.filter { $0.text?.hasPrefix("match") == true }.map(\.id))
        #expect(ClipFilter.apply(items, query: ClipQuery(text: "match", category: .favorite)).count == 50)
    }
}

@Suite("ClipQuery 关键词拆分")
struct ClipQueryTests {
    @Test(
        "按任意空白拆分并去掉空段",
        arguments: [
            ("hello world", ["hello", "world"]),
            ("  hello   world  ", ["hello", "world"]),
            ("a\tb\nc", ["a", "b", "c"]),
            ("中文\u{3000}全角空格", ["中文", "全角空格"]),
            ("单个关键词", ["单个关键词"]),
            ("", []),
            (" \n\t ", []),
        ])
    func keywords(_ text: String, _ expected: [String]) {
        #expect(ClipQuery(text: text).keywords == expected)
    }

    @Test("关键词保留原始大小写与标点")
    func keywordsKeepOriginalForm() {
        #expect(ClipQuery(text: "Café 'x'; 📋").keywords == ["Café", "'x';", "📋"])
    }

    @Test("全角空格分隔的两个中文关键词需同时命中")
    func fullWidthSpaceSeparatesKeywords() {
        let items = [Fixtures.text("剪贴板历史"), Fixtures.text("剪贴板")]
        #expect(ClipFilter.apply(items, query: ClipQuery(text: "剪贴板\u{3000}历史")).map(\.text) == ["剪贴板历史"])
    }
}

@Suite("ClipCategory 分类元数据与循环切换")
struct ClipCategoryTests {
    @Test("向后循环：最后一个回到第一个")
    func cyclesForward() {
        #expect(ClipCategory.all.cycled(by: 1) == .text)
        #expect(ClipCategory.favorite.cycled(by: 1) == .all)
    }

    @Test("向前循环：第一个回到最后一个")
    func cyclesBackward() {
        #expect(ClipCategory.all.cycled(by: -1) == .favorite)
        #expect(ClipCategory.text.cycled(by: -1) == .all)
    }

    @Test("偏移为 0 或整圈时保持不变", arguments: [0, 7, -7, 14])
    func fullCycles(_ offset: Int) {
        for category in ClipCategory.allCases {
            #expect(category.cycled(by: offset) == category)
        }
    }

    @Test("超过一圈的负向偏移正确取模")
    func largeNegativeOffset() {
        #expect(ClipCategory.all.cycled(by: -8) == .favorite)
        #expect(ClipCategory.all.cycled(by: 9) == .link)
    }

    @Test("类型分类映射到同名 ClipKind，all/favorite 不限类型")
    func kindMapping() {
        #expect(ClipCategory.all.kind == nil)
        #expect(ClipCategory.favorite.kind == nil)
        for category in ClipCategory.allCases where category != .all && category != .favorite {
            #expect(category.kind == ClipKind(rawValue: category.rawValue))
            #expect(category.symbolName == category.kind?.symbolName)
        }
    }

    @Test("分类显示名为复数形式，互不重复且不超过 9 个字符（英文分类栏宽度约束）")
    func categoryDisplayNames() {
        let names = ClipCategory.allCases.map(\.displayName)
        #expect(names == ["All", "Text", "Links", "Images", "Files", "Colors", "Favorites"])
        #expect(Set(names).count == names.count)
        #expect(names.allSatisfy { $0.count <= 9 })
    }

    @Test("all 与 favorite 有专属显示名和图标")
    func specialCategories() {
        #expect(ClipCategory.all.displayName == "All")
        #expect(ClipCategory.favorite.displayName == "Favorites")
        #expect(ClipCategory.all.symbolName == "tray.full")
        #expect(ClipCategory.favorite.symbolName == "star")
    }

    @Test("ClipQuery 默认值")
    func queryDefaults() {
        #expect(ClipQuery() == ClipQuery(text: "", category: .all))
    }
}
