import Foundation
import Testing
@testable import CubbyCore

/// ClipStore 记录与变更操作
@Suite("ClipStore 记录与变更")
@MainActor
struct ClipStoreTests {
    private let fixedNow = Fixtures.baseDate

    private func makeStore(
        blobDir: URL,
        storage: InMemoryHistoryStorage = InMemoryHistoryStorage(),
        limit: Int = 10,
        now: (() -> Date)? = nil
    ) -> ClipStore {
        let fixed = fixedNow
        return ClipStore(
            storage: storage,
            blobs: BlobStore(directory: blobDir),
            limit: limit,
            now: now ?? { fixed }
        )
    }

    private func imageContent(_ seed: String) -> ClipContent {
        .image(png: Data("fake-png-\(seed)".utf8), width: 8, height: 6)
    }

    // MARK: - record

    @Test(
        "记录文本按内容分类",
        arguments: [
            ("hello world", ClipKind.text),
            ("https://example.com", .link),
            ("#FF8800", .color),
        ])
    func recordClassifiesText(_ text: String, _ kind: ClipKind) throws {
        let dir = try TempDirectory.make()
        defer { TempDirectory.remove(dir) }

        let store = makeStore(blobDir: dir)
        let source = SourceApp(bundleID: "com.test", name: "Test")
        let item = try #require(store.record(.text(text), source: source))

        #expect(item.kind == kind)
        #expect(item.text == text)
        #expect(item.source == source)
        #expect(item.createdAt == fixedNow)
        #expect(item.contentHash == ContentHasher.hash(text: text))
        #expect(store.history.items == [item])
    }

    @Test("记录图片：kind 为 image，PNG 写入 blob 目录")
    func recordImageWritesBlob() throws {
        let dir = try TempDirectory.make()
        defer { TempDirectory.remove(dir) }

        let store = makeStore(blobDir: dir)
        let png = Data("fake-png".utf8)
        let item = try #require(store.record(.image(png: png, width: 8, height: 6), source: nil))

        #expect(item.kind == .image)
        let ref = try #require(item.image)
        #expect(ref.width == 8 && ref.height == 6)
        #expect(ref.name == ContentHasher.sha256(png) + ".png")

        let url = try #require(store.imageURL(for: item))
        #expect(try Data(contentsOf: url) == png)
    }

    @Test("记录文件：kind 为 file，保存路径")
    func recordFiles() throws {
        let dir = try TempDirectory.make()
        defer { TempDirectory.remove(dir) }

        let store = makeStore(blobDir: dir)
        let urls = [URL(fileURLWithPath: "/tmp/a.txt"), URL(fileURLWithPath: "/tmp/b c.txt")]
        let item = try #require(store.record(.files(urls), source: nil))

        #expect(item.kind == .file)
        #expect(item.filePaths == ["/tmp/a.txt", "/tmp/b c.txt"])
        #expect(store.imageURL(for: item) == nil)
    }

    @Test("同内容重复记录只保留一条，并刷新时间")
    func recordDeduplicates() throws {
        let dir = try TempDirectory.make()
        defer { TempDirectory.remove(dir) }

        let clock = TestClock()
        let store = makeStore(blobDir: dir, now: clock.now)
        let first = try #require(store.record(.text("same"), source: nil))
        store.record(.text("other"), source: nil)
        clock.advance(by: 30)
        let again = try #require(store.record(.text("same"), source: nil))

        #expect(store.history.items.count == 2)
        #expect(again.id == first.id)
        #expect(again.createdAt == clock.current)
        #expect(store.history.items.first?.id == first.id)
    }

    @Test("同一图片重复记录只保留一条，blob 文件仍在")
    func recordSameImageTwice() throws {
        let dir = try TempDirectory.make()
        defer { TempDirectory.remove(dir) }

        let clock = TestClock()
        let store = makeStore(blobDir: dir, now: clock.now)
        let first = try #require(store.record(imageContent("x"), source: nil))
        clock.advance(by: 1)
        store.record(imageContent("x"), source: nil)

        #expect(store.history.items.count == 1)
        let url = try #require(store.imageURL(for: first))
        #expect(FileManager.default.fileExists(atPath: url.path))
    }

    @Test("blob 写入失败时返回 nil 且历史不变")
    func recordImageFailure() throws {
        let dir = try TempDirectory.make()
        defer { TempDirectory.remove(dir) }

        // blob 目录的父路径是普通文件，无法创建目录
        let blocker = dir.appendingPathComponent("blocker")
        try Data().write(to: blocker)
        let store = makeStore(blobDir: blocker.appendingPathComponent("blobs"))
        store.record(.text("before"), source: nil)
        let before = store.history

        #expect(store.record(imageContent("x"), source: nil) == nil)
        #expect(store.history == before)
    }

    // MARK: - 删除与裁剪时清理 blob

    @Test("删除图片条目后 blob 暂留以便撤销，discardUndo 后被删")
    func removeDeletesBlobAfterDiscard() throws {
        let dir = try TempDirectory.make()
        defer { TempDirectory.remove(dir) }

        let store = makeStore(blobDir: dir)
        let item = try #require(store.record(imageContent("x"), source: nil))
        let url = try #require(store.imageURL(for: item))

        store.remove(id: item.id)
        #expect(store.history.items.isEmpty)
        #expect(FileManager.default.fileExists(atPath: url.path))

        store.discardUndo()
        #expect(!FileManager.default.fileExists(atPath: url.path))
    }

    @Test("图片被上限裁剪后 blob 文件被删")
    func trimmingDeletesBlob() throws {
        let dir = try TempDirectory.make()
        defer { TempDirectory.remove(dir) }

        let store = makeStore(blobDir: dir, limit: 1)
        let image = try #require(store.record(imageContent("x"), source: nil))
        let url = try #require(store.imageURL(for: image))
        store.record(.text("newer"), source: nil)

        #expect(store.history.items.map(\.text) == ["newer"])
        #expect(!FileManager.default.fileExists(atPath: url.path))
        #expect(TempDirectory.fileNames(in: dir).isEmpty)
    }

    // MARK: - promote / favorite / clear / limit

    @Test("promote 将条目移到最前")
    func promoteMovesToFront() throws {
        let dir = try TempDirectory.make()
        defer { TempDirectory.remove(dir) }

        let clock = TestClock()
        let store = makeStore(blobDir: dir, now: clock.now)
        let a = try #require(store.record(.text("a"), source: nil))
        store.record(.text("b"), source: nil)
        clock.advance(by: 10)

        store.promote(id: a.id)

        #expect(store.history.items.map(\.text) == ["a", "b"])
        #expect(store.item(id: a.id)?.createdAt == clock.current)
    }

    @Test("toggleFavorite 切换收藏状态")
    func toggleFavorite() throws {
        let dir = try TempDirectory.make()
        defer { TempDirectory.remove(dir) }

        let store = makeStore(blobDir: dir)
        let item = try #require(store.record(.text("a"), source: nil))
        store.toggleFavorite(id: item.id)
        #expect(store.item(id: item.id)?.isFavorite == true)
        store.toggleFavorite(id: item.id)
        #expect(store.item(id: item.id)?.isFavorite == false)
    }

    @Test("clearHistory 保留收藏，并只删除非收藏图片的 blob")
    func clearHistoryKeepsFavorites() throws {
        let dir = try TempDirectory.make()
        defer { TempDirectory.remove(dir) }

        let store = makeStore(blobDir: dir)
        let favImage = try #require(store.record(imageContent("fav"), source: nil))
        let plainImage = try #require(store.record(imageContent("plain"), source: nil))
        let favText = try #require(store.record(.text("keep"), source: nil))
        store.record(.text("drop"), source: nil)
        store.toggleFavorite(id: favImage.id)
        store.toggleFavorite(id: favText.id)

        store.clearHistory()

        #expect(Set(store.history.items.map(\.id)) == [favImage.id, favText.id])
        #expect(TempDirectory.fileNames(in: dir) == [try #require(favImage.image?.name)])
        #expect(store.item(id: plainImage.id) == nil)
    }

    @Test("setLimit 立即裁剪，且上限最小为 1")
    func setLimitTrims() throws {
        let dir = try TempDirectory.make()
        defer { TempDirectory.remove(dir) }

        let store = makeStore(blobDir: dir, limit: 10)
        for index in 0..<5 {
            store.record(.text("t\(index)"), source: nil)
        }

        store.setLimit(3)
        #expect(store.limit == 3)
        #expect(store.history.items.map(\.text) == ["t4", "t3", "t2"])

        store.setLimit(0)
        #expect(store.limit == 1)
        #expect(store.history.items.map(\.text) == ["t4"])
    }

    @Test("初始化上限小于 1 时按 1 处理")
    func initClampsLimit() throws {
        let dir = try TempDirectory.make()
        defer { TempDirectory.remove(dir) }

        #expect(makeStore(blobDir: dir, limit: -3).limit == 1)
    }

    @Test("对不存在的 id 操作不触发保存")
    func unknownIDDoesNotPersist() throws {
        let dir = try TempDirectory.make()
        defer { TempDirectory.remove(dir) }

        let storage = InMemoryHistoryStorage()
        let store = makeStore(blobDir: dir, storage: storage)
        store.record(.text("a"), source: nil)
        store.flush()
        let savesBefore = storage.savedSnapshots.count

        store.promote(id: UUID())
        store.remove(id: UUID())
        store.toggleFavorite(id: UUID())
        store.flush()

        #expect(storage.savedSnapshots.count == savesBefore)
    }
}
