import Foundation
import Testing
@testable import CubbyCore

/// ClipItem.linkTitle：链接条目随复制带来的网页标题（不可变更新、匹配、编解码）
@Suite("ClipItem 网页标题 linkTitle")
struct ClipItemLinkTitleTests {
    private static let url = "https://example.com/docs"

    private static func link(
        _ title: String?,
        url: String = url,
        favorite: Bool = false,
        at date: Date = Fixtures.baseDate
    ) -> ClipItem {
        ClipItem(
            kind: .link, payload: .text(url), source: nil, createdAt: date, isFavorite: favorite,
            contentHash: ContentHasher.hash(text: url), linkTitle: title)
    }

    // MARK: - 只属于链接条目

    @Test("默认为 nil")
    func defaultsToNil() {
        #expect(Fixtures.text(Self.url).linkTitle == nil)
        #expect(Fixtures.image(name: "a.png").linkTitle == nil)
    }

    @Test("链接条目保存标题")
    func linkKeepsTitle() {
        #expect(Self.link("Docs").linkTitle == "Docs")
    }

    @Test("非链接条目即使传入标题也为 nil", arguments: [ClipKind.text, .color, .image, .file])
    func nonLinkDropsTitle(kind: ClipKind) {
        let item = ClipItem(
            kind: kind, payload: .text("x"), source: nil, createdAt: Fixtures.baseDate, contentHash: "h",
            linkTitle: "Title")
        #expect(item.linkTitle == nil)
    }

    // MARK: - 不可变更新

    @Test("收藏、设置格式名、识别文字、译文、刷新时间都保留标题")
    func copyingMethodsKeepTitle() {
        let item = Self.link("Docs")
        #expect(item.withFavorite(true).linkTitle == "Docs")
        #expect(item.withFormatsName("f.formats").linkTitle == "Docs")
        #expect(item.withRecognizedText("x").linkTitle == "Docs")
        #expect(item.withTranslations(ClipTranslations([])).linkTitle == "Docs")
        #expect(item.touched(at: Fixtures.baseDate.addingTimeInterval(5)).linkTitle == "Docs")
        #expect(item.touched(at: Fixtures.baseDate, source: SourceApp(bundleID: "a", name: "A")).linkTitle == "Docs")
        #expect(item.linkTitle == "Docs")
    }

    @Test("replacing：新复制带来的标题优先")
    func replacingPrefersNewTitle() {
        let old = Self.link("Old", favorite: true)
        let fresh = Self.link("New", at: Fixtures.baseDate.addingTimeInterval(60))
        let merged = fresh.replacing(old)
        #expect(merged.linkTitle == "New")
        #expect(merged.id == old.id && merged.isFavorite)
    }

    @Test("replacing：新复制没有标题时沿用旧条目的（同一链接）")
    func replacingInheritsTitle() {
        let old = Self.link("Old")
        let fresh = Self.link(nil, at: Fixtures.baseDate.addingTimeInterval(60))
        #expect(fresh.replacing(old).linkTitle == "Old")
        #expect(fresh.replacing(Self.link(nil)).linkTitle == nil)
    }

    // MARK: - 匹配

    @Test("matches(keyword:) 命中标题，忽略大小写与变音符")
    func matchesTitle() {
        let item = Self.link("Café Getting Started")
        #expect(item.matches(keyword: "cafe"))
        #expect(item.matches(keyword: "GETTING"))
        #expect(item.matchesMetadata("started"))
        #expect(!item.matches(keyword: "missing"))
        #expect(!Self.link(nil).matches(keyword: "cafe"))
    }

    @Test("标题与链接分别命中不同关键词时同样算命中")
    func keywordsAcrossTitleAndURL() {
        let item = Self.link("Getting Started")
        let ranked = ClipSearchRanking.relevance(of: item, phrase: "example started", keywords: ["example", "started"])
        #expect(ranked == .leading)
        #expect(ClipSearchRanking.relevance(of: item, phrase: "started", keywords: ["started"]) == .other)
    }

    // MARK: - 编解码

    @Test("旧条目 JSON（无该字段）解码为 nil")
    func decodesLegacyItemWithoutField() throws {
        let json = #"""
            {"id":"3D4E5F60-7182-493A-A4B5-C6D7E8F90112","kind":"link","payload":{"text":{"_0":"https://example.com/docs"}},"createdAt":715000300,"isFavorite":false,"contentHash":"text:1"}
            """#
        let item = try JSONDecoder().decode(ClipItem.self, from: Data(json.utf8))
        #expect(item.linkTitle == nil)
        #expect(item.text == Self.url)
    }

    @Test("带标题的条目编解码往返一致")
    func roundTrips() throws {
        let item = Self.link("Docs \u{1F4CB} \"quoted\"")
        let data = try JSONEncoder().encode(item)
        #expect(String(decoding: data, as: UTF8.self).contains("\"linkTitle\""))
        #expect(try JSONDecoder().decode(ClipItem.self, from: data) == item)
    }

    @Test("为 nil 时不写该字段")
    func omitsNil() throws {
        let data = try JSONEncoder().encode(Self.link(nil))
        #expect(!String(decoding: data, as: UTF8.self).contains("linkTitle"))
    }
}
