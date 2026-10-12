import Foundation
import Testing
@testable import CubbyCore

/// LinkTitle：浏览器随链接一起放上剪贴板的网页标题的规范化与解析（纯函数，不碰剪贴板）
@Suite("LinkTitle 网页标题规范化")
struct LinkTitleTests {
    private let url = "https://example.com/docs/intro"

    // MARK: - normalized

    @Test("nil、空串与纯空白返回 nil")
    func emptyInputIsNil() {
        #expect(LinkTitle.normalized(nil, url: url) == nil)
        #expect(LinkTitle.normalized("", url: url) == nil)
        #expect(LinkTitle.normalized(" \n\t\u{00A0}\u{3000} \r\n", url: url) == nil)
    }

    @Test("去掉首尾空白与换行")
    func trimsWhitespace() {
        #expect(LinkTitle.normalized("  Intro  \n", url: url) == "Intro")
    }

    @Test("内部连续空白（含换行、制表符、不换行空格、全角空格）折叠为一个空格")
    func collapsesInternalWhitespace() {
        let raw = "Getting\n\n  Started\t–\u{00A0}\u{00A0}Example\u{3000}Docs"
        #expect(LinkTitle.normalized(raw, url: url) == "Getting Started – Example Docs")
    }

    @Test("控制字符视同空白，不会留在标题里")
    func controlCharactersAreSeparators() {
        #expect(LinkTitle.normalized("A\u{0}B\u{7}\u{1B}C", url: url) == "A B C")
        #expect(LinkTitle.normalized("\u{0}\u{1}", url: url) == nil)
    }

    @Test("Unicode、表情与双向文字标记原样保留")
    func keepsUnicode() {
        let family = "\u{1F468}\u{200D}\u{1F469}\u{200D}\u{1F467}"
        #expect(LinkTitle.normalized("剪贴板 \(family) Café", url: url) == "剪贴板 \(family) Café")
        #expect(LinkTitle.normalized("\u{200F}שלום", url: url) == "\u{200F}שלום")
        #expect(LinkTitle.normalized("'; DROP TABLE x; --", url: url) == "'; DROP TABLE x; --")
    }

    @Test("恰好 maxLength 个字符时原样保留")
    func exactlyMaxLengthIsKept() {
        let raw = String(repeating: "a", count: LinkTitle.maxLength)
        #expect(LinkTitle.normalized(raw, url: url) == raw)
    }

    @Test("超长标题截断为 maxLength 个字符（以省略号结尾）")
    func longTitleIsCapped() throws {
        let raw = String(repeating: "word ", count: 1_000)
        let title = try #require(LinkTitle.normalized(raw, url: url))
        #expect(title.count == LinkTitle.maxLength)
        #expect(title.hasSuffix("…"))
        #expect(!title.dropLast().hasSuffix(" "))
        #expect(title.hasPrefix("word word"))
    }

    @Test("按字符（字形簇）截断，不会切开表情")
    func capsByCharacters() throws {
        let family = "\u{1F468}\u{200D}\u{1F469}\u{200D}\u{1F467}"
        let raw = String(repeating: family, count: LinkTitle.maxLength + 10)
        let title = try #require(LinkTitle.normalized(raw, url: url))
        #expect(title.count == LinkTitle.maxLength)
        #expect(title.dropLast().allSatisfy { $0 == Character(family) })
    }

    @Test("超大输入（MB 级）也能很快得到结果")
    func hugeInputIsBounded() throws {
        let raw = String(repeating: "x", count: 4_000_000)
        let title = try #require(LinkTitle.normalized(raw, url: url))
        #expect(title.count == LinkTitle.maxLength)
    }

    @Test(
        "标题只是链接本身（忽略协议、末尾斜杠、大小写与首尾空白）时返回 nil",
        arguments: [
            "https://example.com/docs/intro",
            "https://example.com/docs/intro/",
            "example.com/docs/intro",
            "example.com/docs/intro/",
            "HTTPS://EXAMPLE.COM/docs/intro",
            "  http://example.com/docs/intro \n",
        ])
    func urlAsTitleIsNil(raw: String) {
        #expect(LinkTitle.normalized(raw, url: url) == nil)
    }

    @Test("链接本身带首尾空白或末尾斜杠时同样识别")
    func urlWithDecorations() {
        #expect(LinkTitle.normalized("example.com", url: " https://example.com/\n") == nil)
        #expect(LinkTitle.normalized("https://example.com/", url: "https://example.com") == nil)
    }

    @Test("百分号编码与解码后的形式视为同一链接")
    func percentEncodingIsIgnored() {
        #expect(LinkTitle.normalized("example.com/a b", url: "https://example.com/a%20b") == nil)
    }

    @Test("与链接不同的标题保留：别的链接、只是主机名、包含链接的句子")
    func differentTextIsKept() {
        #expect(LinkTitle.normalized("https://example.com/other", url: url) == "https://example.com/other")
        #expect(LinkTitle.normalized("example.com", url: url) == "example.com")
        #expect(LinkTitle.normalized("See example.com/docs/intro", url: url) == "See example.com/docs/intro")
    }

    @Test("只去掉开头的协议：句中出现链接本身的标题保留")
    func onlyLeadingSchemeIsDropped() {
        let mirror = "Mirror of https://example.com/docs/intro"
        #expect(LinkTitle.normalized(mirror, url: url) == mirror)
        #expect(LinkTitle.normalized("://example.com/docs/intro", url: url) == "://example.com/docs/intro")
        #expect(LinkTitle.normalized("1x://example.com/docs/intro", url: url) == "1x://example.com/docs/intro")
        #expect(LinkTitle.normalized("é://example.com/docs/intro", url: url) == "é://example.com/docs/intro")
        #expect(LinkTitle.normalized("web+x://example.com/docs/intro", url: url) == nil)
    }

    @Test("截断处正好是空格时去掉空格再补省略号")
    func capDropsTrailingSpace() throws {
        let raw = String(repeating: "a", count: LinkTitle.maxLength - 2) + " bbbb"
        let title = try #require(LinkTitle.normalized(raw, url: url))
        #expect(title == String(repeating: "a", count: LinkTitle.maxLength - 2) + "…")
    }

    @Test("百分号编码无效时按原文比较")
    func invalidPercentEncoding() {
        #expect(LinkTitle.normalized("100% done", url: url) == "100% done")
        #expect(LinkTitle.isSameURL("https://a.com/100%", "a.com/100%"))
    }

    // MARK: - isSameURL

    @Test("isSameURL：忽略协议、末尾斜杠、大小写与百分号编码")
    func sameURL() {
        #expect(LinkTitle.isSameURL("https://a.com/x/", "http://A.com/x"))
        #expect(LinkTitle.isSameURL("a.com/x%41", "https://a.com/xA"))
        #expect(!LinkTitle.isSameURL("https://a.com/x", "https://a.com/y"))
        #expect(!LinkTitle.isSameURL("", "https://a.com"))
    }

    // MARK: - WebURLsWithTitlesPboardType

    @Test("WebURLsWithTitles：取第一个链接匹配的标题")
    func webURLsWithTitlesPicksMatchingURL() {
        let plist: [Any] = [
            ["https://other.com/", url, url + "/"],
            ["Other", "  Intro\n Page ", "Second"],
        ]
        #expect(LinkTitle.fromWebURLsWithTitles(plist, url: url) == "Intro Page")
    }

    @Test("WebURLsWithTitles：匹配的标题为空或只是链接时继续找下一个匹配")
    func webURLsWithTitlesSkipsUselessTitles() {
        let plist: [Any] = [[url, url, url], ["  ", url, "Real"]]
        #expect(LinkTitle.fromWebURLsWithTitles(plist, url: url) == "Real")
    }

    @Test("WebURLsWithTitles：没有匹配的链接时为 nil")
    func webURLsWithTitlesWithoutMatch() {
        let plist: [Any] = [["https://other.com/"], ["Other"]]
        #expect(LinkTitle.fromWebURLsWithTitles(plist, url: url) == nil)
    }

    @Test("WebURLsWithTitles：结构不对时为 nil，不会崩溃")
    func malformedWebURLsWithTitles() {
        let malformed: [Any?] = [
            nil,
            "not an array",
            [Any](),
            [[url]] as [Any],
            [[url], "title"] as [Any],
            [[42], ["Intro"]] as [Any],
            [[url], [42]] as [Any],
            ["\(url)", ["Intro"]] as [Any],
        ]
        for plist in malformed {
            #expect(LinkTitle.fromWebURLsWithTitles(plist, url: url) == nil, "\(String(describing: plist))")
        }
    }

    @Test("WebURLsWithTitles：链接比标题多时，没有对应标题的链接跳过")
    func webURLsWithTitlesWithFewerTitles() {
        #expect(LinkTitle.fromWebURLsWithTitles([[url, url], ["Intro"]] as [Any], url: url) == "Intro")
        #expect(LinkTitle.fromWebURLsWithTitles([["https://other.com", url], ["Other"]] as [Any], url: url) == nil)
    }

    // MARK: - resolve

    @Test("resolve：优先 public.url-name")
    func resolvePrefersURLName() {
        let plist: [Any] = [[url], ["From list"]]
        #expect(LinkTitle.resolve(urlName: "From name", webURLsWithTitles: plist, url: url) == "From name")
    }

    @Test("resolve：url-name 缺失、为空或只是链接时退到 WebURLsWithTitles")
    func resolveFallsBackToList() {
        let plist: [Any] = [[url], ["From list"]]
        #expect(LinkTitle.resolve(urlName: nil, webURLsWithTitles: plist, url: url) == "From list")
        #expect(LinkTitle.resolve(urlName: " \n ", webURLsWithTitles: plist, url: url) == "From list")
        #expect(LinkTitle.resolve(urlName: url, webURLsWithTitles: plist, url: url) == "From list")
    }

    @Test("resolve：两者都没有时为 nil")
    func resolveWithoutAnything() {
        #expect(LinkTitle.resolve(urlName: nil, webURLsWithTitles: nil, url: url) == nil)
    }
}
