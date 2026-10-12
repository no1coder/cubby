import Foundation
import Testing
@testable import CubbyCore

/// 记录链接时保存随复制带来的网页标题：只有链接条目有标题，重复复制时新标题优先、没有则沿用
@Suite("ClipStore 记录链接标题", .timeLimit(.minutes(1)))
@MainActor
struct ClipStoreLinkTitleTests {
    private static let url = "https://example.com/docs"

    private func withStore(_ body: (ClipStore) async throws -> Void) async throws {
        let dir = try TempDirectory.make()
        defer { TempDirectory.remove(dir) }
        try await body(StoreFactory.make(dir: dir))
    }

    @Test("同步记录：链接条目保存规范化后的标题")
    func recordKeepsTitle() async throws {
        try await withStore { store in
            let item = try #require(store.record(.text(Self.url), source: nil, linkTitle: "  Docs \n Home "))
            #expect(item.kind == .link)
            #expect(item.linkTitle == "Docs Home")
            #expect(store.history.items.first?.linkTitle == "Docs Home")
        }
    }

    @Test("后台记录：标题随内容一起入历史")
    func recordInBackgroundKeepsTitle() async throws {
        try await withStore { store in
            let item = try #require(
                await store.recordInBackground(.text(Self.url), source: nil, linkTitle: "Docs").value)
            #expect(item.linkTitle == "Docs")
            #expect(store.history.items.map(\.linkTitle) == ["Docs"])
        }
    }

    @Test("富文本链接同样保存标题")
    func richTextLinkKeepsTitle() async throws {
        try await withStore { store in
            let formats = ["public.html": Data("<a>Docs</a>".utf8)]
            let item = try #require(
                await store.recordInBackground(.richText(Self.url, formats: formats), source: nil, linkTitle: "Docs")
                    .value)
            #expect(item.linkTitle == "Docs")
            #expect(item.formatsName != nil)
        }
    }

    @Test("不是链接的内容丢弃标题", arguments: ["plain note", "#FF8800"])
    func nonLinkDropsTitle(text: String) async throws {
        try await withStore { store in
            let item = try #require(store.record(.text(text), source: nil, linkTitle: "Title"))
            #expect(item.linkTitle == nil)
        }
    }

    @Test("标题只是链接本身或为空白时不保存")
    func uselessTitleIsDropped() async throws {
        try await withStore { store in
            #expect(store.record(.text(Self.url), source: nil, linkTitle: "example.com/docs/")?.linkTitle == nil)
            #expect(store.record(.text(Self.url), source: nil, linkTitle: " \n ")?.linkTitle == nil)
        }
    }

    @Test("不传标题时与此前相同")
    func defaultsToNoTitle() async throws {
        try await withStore { store in
            #expect(store.record(.text(Self.url), source: nil)?.linkTitle == nil)
            #expect(await store.recordInBackground(.text(Self.url), source: nil).value?.linkTitle == nil)
        }
    }

    @Test("再次复制同一链接：带新标题时更新，没有标题时沿用旧标题")
    func recopyMergesTitle() async throws {
        try await withStore { store in
            let first = try #require(store.record(.text(Self.url), source: nil, linkTitle: "Old"))
            let untitled = try #require(store.record(.text(Self.url), source: nil))
            #expect(untitled.id == first.id)
            #expect(untitled.linkTitle == "Old")

            let retitled = try #require(store.record(.text(Self.url), source: nil, linkTitle: "New"))
            #expect(retitled.id == first.id)
            #expect(retitled.linkTitle == "New")
            #expect(store.history.items.count == 1)
        }
    }

    @Test("标题可搜索：索引随标题变化同步更新，结果与逐条匹配一致")
    func titleIsSearchable() async throws {
        try await withStore { store in
            await store.waitForSearchIndex()
            store.record(.text(Self.url), source: nil, linkTitle: "Getting Started")
            store.record(.text("unrelated note"), source: nil)

            let query = ClipQuery(text: "getting")
            #expect(store.search(query).map(\.text) == [Self.url])
            #expect(store.searchIndex?.isCurrent(for: store.history.items) == true)

            // 同一链接（内容哈希相同）换了标题：索引条目必须视为过期并重新折叠
            store.record(.text(Self.url), source: nil, linkTitle: "Release Notes")
            #expect(store.searchIndex?.isCurrent(for: store.history.items) == true)
            #expect(store.search(ClipQuery(text: "getting")).isEmpty)
            #expect(store.search(ClipQuery(text: "release")).map(\.text) == [Self.url])
            #expect(
                store.search(ClipQuery(text: "release"))
                    == ClipFilter.apply(store.history.items, query: ClipQuery(text: "release")))
        }
    }
}
