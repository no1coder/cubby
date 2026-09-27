import Foundation
import Testing
@testable import CubbyCore

@Suite("ClipStore 富文本、revision 与 canPersist")
@MainActor
struct ClipStoreRichTextTests {
    private let formats = Fixtures.richFormats(for: "粗体文本")

    // MARK: - record(.richText)

    @Test("记录富文本：写入 <sha>.formats blob，条目为文本类型并带格式名")
    func recordRichTextWritesFormatsBlob() throws {
        let dir = try TempDirectory.make()
        defer { TempDirectory.remove(dir) }

        let store = StoreFactory.make(dir: dir)
        let item = try #require(store.record(.richText("粗体文本", formats: formats), source: nil))

        let expectedName = ContentHasher.sha256(try RichFormats.encode(formats)) + ".formats"
        #expect(item.formatsName == expectedName)
        #expect(item.kind == .text)
        #expect(item.text == "粗体文本")
        #expect(item.contentHash == ContentHasher.hash(text: "粗体文本"))
        #expect(TempDirectory.fileNames(in: dir) == [expectedName])
        #expect(store.formats(for: item) == formats)
    }

    @Test("富文本同样按内容分类（链接 / 颜色）")
    func richTextClassified() throws {
        let dir = try TempDirectory.make()
        defer { TempDirectory.remove(dir) }

        let store = StoreFactory.make(dir: dir)
        let link = try #require(store.record(.richText("https://example.com", formats: formats), source: nil))
        let color = try #require(store.record(.richText("#123456", formats: formats), source: nil))
        #expect(link.kind == .link)
        #expect(color.kind == .color)
    }

    @Test("纯文本与富文本的相同内容合并为一条，格式取最新")
    func plainAndRichMerge() throws {
        let dir = try TempDirectory.make()
        defer { TempDirectory.remove(dir) }

        let store = StoreFactory.make(dir: dir)
        let plain = try #require(store.record(.text("粗体文本"), source: nil))
        let rich = try #require(store.record(.richText("粗体文本", formats: formats), source: nil))

        #expect(rich.id == plain.id)
        #expect(store.history.items.count == 1)
        #expect(rich.formatsName != nil)
    }

    @Test("富文本被纯文本覆盖后，旧格式 blob 立即清理")
    func richReplacedByPlainRemovesBlob() throws {
        let dir = try TempDirectory.make()
        defer { TempDirectory.remove(dir) }

        let store = StoreFactory.make(dir: dir)
        let rich = try #require(store.record(.richText("粗体文本", formats: formats), source: nil))
        let name = try #require(rich.formatsName)

        let plain = try #require(store.record(.text("粗体文本"), source: nil))

        #expect(plain.id == rich.id)
        #expect(plain.formatsName == nil)
        #expect(!TempDirectory.exists(name, in: dir))
        #expect(store.formats(for: plain).isEmpty)
    }

    @Test("格式 blob 写入失败时返回 nil 且历史不变")
    func richTextWriteFailure() throws {
        let dir = try TempDirectory.make()
        defer { TempDirectory.remove(dir) }

        let blocker = dir.appendingPathComponent("blocker")
        try Data().write(to: blocker)
        let store = StoreFactory.make(dir: blocker.appendingPathComponent("blobs"))
        store.record(.text("before"), source: nil)
        let before = store.history

        #expect(store.record(.richText("x", formats: formats), source: nil) == nil)
        #expect(store.history == before)
    }

    @Test("格式为空字典时仍按富文本记录")
    func emptyFormatsStillRecorded() throws {
        let dir = try TempDirectory.make()
        defer { TempDirectory.remove(dir) }

        let store = StoreFactory.make(dir: dir)
        let item = try #require(store.record(.richText("x", formats: [:]), source: nil))
        #expect(item.formatsName != nil)
        #expect(store.formats(for: item).isEmpty)
    }

    // MARK: - formats(for:)

    @Test("formats(for:)：纯文本、blob 缺失、blob 损坏、非法名称均返回空字典")
    func formatsFallbacks() throws {
        let dir = try TempDirectory.make()
        defer { TempDirectory.remove(dir) }

        let store = StoreFactory.make(dir: dir)
        try BlobStore(directory: dir).write(Data("not a plist".utf8), name: "broken.formats")

        #expect(store.formats(for: Fixtures.text("plain")).isEmpty)
        #expect(store.formats(for: Fixtures.text("x", formatsName: "missing.formats")).isEmpty)
        #expect(store.formats(for: Fixtures.text("x", formatsName: "broken.formats")).isEmpty)
        #expect(store.formats(for: Fixtures.text("x", formatsName: "../evil")).isEmpty)
    }

    @Test("重启后（真实 JSON 存储）富文本格式仍可读取")
    func formatsSurviveRestart() throws {
        let dir = try TempDirectory.make()
        defer { TempDirectory.remove(dir) }

        let storage = JSONHistoryStorage(fileURL: dir.appendingPathComponent("history.json"))
        let blobDir = dir.appendingPathComponent("blobs")
        let first = StoreFactory.make(dir: blobDir, storage: storage)
        let item = try #require(first.record(.richText("粗体文本", formats: formats), source: nil))
        first.flush()

        let reopened = StoreFactory.make(dir: blobDir, storage: storage)
        let loaded = try #require(reopened.item(id: item.id))
        #expect(loaded.formatsName == item.formatsName)
        #expect(reopened.formats(for: loaded) == formats)
    }

    // MARK: - revision

    @Test("revision 仅在历史实际变化时递增")
    func revisionIncrementsOnChange() throws {
        let dir = try TempDirectory.make()
        defer { TempDirectory.remove(dir) }

        let store = StoreFactory.make(dir: dir)
        #expect(store.revision == 0)

        let a = try #require(store.record(.text("a"), source: nil))
        #expect(store.revision == 1)

        store.toggleFavorite(id: a.id)
        #expect(store.revision == 2)

        store.promote(id: UUID())
        store.toggleFavorite(id: UUID())
        store.remove(id: UUID())
        store.setLimit(10)
        store.discardUndo()
        #expect(store.revision == 2)

        store.remove(id: a.id)
        #expect(store.revision == 3)
        store.undoRemove()
        #expect(store.revision == 4)
    }

    @Test("重复记录相同内容（同一时间）不改变历史时 revision 不变")
    func revisionUnchangedForIdenticalRecord() throws {
        let dir = try TempDirectory.make()
        defer { TempDirectory.remove(dir) }

        let store = StoreFactory.make(dir: dir)
        store.record(.text("same"), source: nil)
        let revision = store.revision
        store.record(.text("same"), source: nil)
        #expect(store.revision == revision)
    }

    // MARK: - canPersist

    @Test("正常加载或文件损坏时 canPersist 为 true，普通读取错误时为 false")
    func canPersistReflectsLoad() throws {
        let dir = try TempDirectory.make()
        defer { TempDirectory.remove(dir) }

        let backup = dir.appendingPathComponent("history.corrupt.json")
        let ok = StoreFactory.make(dir: dir)
        let corrupted = StoreFactory.make(
            dir: dir, storage: InMemoryHistoryStorage(loadError: HistoryStorageError.corrupted(backupURL: backup))
        )
        let failed = StoreFactory.make(dir: dir, storage: InMemoryHistoryStorage(loadError: SimulatedLoadError()))

        #expect(ok.canPersist)
        #expect(corrupted.canPersist)
        #expect(!failed.canPersist)
    }
}
