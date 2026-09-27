import Foundation
import Testing
@testable import CubbyCore

/// 最近构建过的翻译文档：按 id、内容指纹与格式文件名对应，同一条目只留最新一份，超出容量丢弃最早的
@Suite("翻译文档缓存")
struct ClipDocumentCacheTests {
    @Test("放入后可取回；内容或格式变了、未放入的条目取不到")
    func lookup() {
        let item = Fixtures.text("Hello world", formatsName: "a.plist")
        let document = ClipTranslationDocument.plain("Hello world")
        let cache = ClipDocumentCache().inserting(document, for: item)
        #expect(cache.document(for: item) == document)
        #expect(ClipDocumentCache().document(for: item) == nil)
        #expect(cache.document(for: item.withFormatsName("b.plist")) == nil)
        let changed = Fixtures.text("Other text", formatsName: "a.plist")
        #expect(cache.document(for: changed) == nil)
    }

    @Test("同一条目只留最新的一份；超出容量丢弃最早的；原值不变")
    func replacesAndEvicts() {
        let item = Fixtures.text("One")
        let first = ClipDocumentCache().inserting(.plain("One"), for: item)
        let updated = first.inserting(.plain("One\n\nTwo"), for: item)
        #expect(updated.document(for: item) == .plain("One\n\nTwo"))
        #expect(first.document(for: item) == .plain("One"))

        let items = (0...ClipDocumentCache.capacity).map { Fixtures.text("Item \($0)") }
        let full = items.reduce(updated) { $0.inserting(.plain($1.text ?? ""), for: $1) }
        #expect(full.document(for: item) == nil)
        #expect(full.document(for: items[0]) == nil)
        #expect(full.document(for: items[1]) == .plain("Item 1"))
        #expect(full.document(for: items[ClipDocumentCache.capacity]) != nil)
    }
}
