import Foundation
import Testing
@testable import CubbyCore

@Suite("ClipItem 关键词匹配 matches(keyword:)")
struct ClipItemMatchTests {
    private let safari = SourceApp(bundleID: "com.apple.Safari", name: "Safari")

    // MARK: - 文本

    @Test("命中正文，忽略大小写与变音符")
    func matchesTextBody() {
        let item = Fixtures.text("Hello Café 剪贴板 📋")
        #expect(item.matches(keyword: "hello"))
        #expect(item.matches(keyword: "HELLO"))
        #expect(item.matches(keyword: "cafe"))
        #expect(item.matches(keyword: "剪贴"))
        #expect(item.matches(keyword: "📋"))
        #expect(!item.matches(keyword: "missing"))
    }

    @Test("链接与颜色条目同样按正文匹配")
    func matchesLinkAndColorText() {
        #expect(Fixtures.text("https://example.com/docs").matches(keyword: "example"))
        #expect(Fixtures.text("#FF8800").matches(keyword: "ff88"))
    }

    @Test("文本条目不会因类型名命中")
    func textDoesNotMatchKindName() {
        #expect(!Fixtures.text("hello").matches(keyword: ClipKind.text.displayName))
    }

    @Test("特殊字符按字面匹配，不作为正则")
    func specialCharactersAreLiteral() {
        let item = Fixtures.text("SELECT * FROM t WHERE a = '1';")
        #expect(item.matches(keyword: "'1';"))
        #expect(item.matches(keyword: "*"))
        #expect(!item.matches(keyword: ".*"))
    }

    // MARK: - searchLimit

    @Test("searchLimit 为 200_000")
    func searchLimitValue() {
        #expect(ClipItem.searchLimit == 200_000)
    }

    @Test("关键词完整落在前 searchLimit 个字符内时命中")
    func matchesWithinLimit() {
        let padding = String(repeating: "a", count: ClipItem.searchLimit - "needle".count)
        #expect(Fixtures.text(padding + "needle").matches(keyword: "needle"))
    }

    @Test("关键词位于 searchLimit 之后时不命中")
    func ignoresBeyondLimit() {
        let padding = String(repeating: "a", count: ClipItem.searchLimit)
        #expect(!Fixtures.text(padding + "needle").matches(keyword: "needle"))
    }

    @Test("关键词跨越 searchLimit 边界时不命中")
    func ignoresStraddlingLimit() {
        let padding = String(repeating: "a", count: ClipItem.searchLimit - 3)
        let item = Fixtures.text(padding + "needle")
        #expect(!item.matches(keyword: "needle"))
        #expect(item.matches(keyword: "nee"))
    }

    @Test("searchLimit 按字符计数（多字节字符不提前截断）")
    func limitCountsCharacters() {
        let padding = String(repeating: "汉", count: ClipItem.searchLimit - 2)
        #expect(Fixtures.text(padding + "目标").matches(keyword: "目标"))
    }

    // MARK: - 来源应用

    @Test("来源应用名对任意类型的条目都可命中")
    func matchesSourceNameForAllPayloads() {
        let text = Fixtures.text("body", source: safari)
        let image = ClipItem(
            kind: .image, payload: .image(ImageRef(name: "a.png", width: 1, height: 1)),
            source: safari, createdAt: Fixtures.baseDate, contentHash: "image:a"
        )
        let files = ClipItem(
            kind: .file, payload: .files(["/tmp/x"]),
            source: safari, createdAt: Fixtures.baseDate, contentHash: "files:x"
        )
        for item in [text, image, files] {
            #expect(item.matches(keyword: "safari"), "\(item.kind)")
        }
    }

    @Test("超长文本中仍可按来源应用名命中")
    func sourceNameMatchesEvenForHugeText() {
        let huge = String(repeating: "a", count: ClipItem.searchLimit + 10)
        #expect(Fixtures.text(huge, source: safari).matches(keyword: "Safari"))
    }

    @Test("来源为空或名称为空时不影响正文匹配")
    func nilSourceOrName() {
        #expect(Fixtures.text("abc").matches(keyword: "abc"))
        #expect(!Fixtures.text("abc").matches(keyword: "safari"))
        let unnamed = Fixtures.text("abc", source: SourceApp(bundleID: "com.apple.Safari", name: nil))
        #expect(unnamed.matches(keyword: "abc"))
        #expect(!unnamed.matches(keyword: "com.apple"))
    }

    // MARK: - 图片 / 文件

    @Test("图片条目以类型名匹配，不暴露内部 blob 文件名")
    func imageMatchesKindNameOnly() {
        let image = Fixtures.image(name: "deadbeef.png")
        #expect(image.matches(keyword: ClipKind.image.displayName))
        #expect(!image.matches(keyword: "deadbeef"))
    }

    @Test("文件条目按任一路径匹配")
    func filesMatchAnyPath() {
        let item = Fixtures.files(["/tmp/a.txt", "/Users/me/Quarterly-Report.pdf"])
        #expect(item.matches(keyword: "a.txt"))
        #expect(item.matches(keyword: "report"))
        #expect(item.matches(keyword: "/users/me"))
        #expect(!item.matches(keyword: "b.log"))
    }

    @Test("空文件列表不命中任何路径关键词")
    func emptyFilesDoNotMatch() {
        #expect(!Fixtures.files([]).matches(keyword: "tmp"))
    }
}
