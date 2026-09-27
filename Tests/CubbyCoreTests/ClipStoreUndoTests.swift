import Foundation
import Testing
@testable import CubbyCore

/// 删除 → 撤销：被删条目的 blob 在下一次删除 / discardUndo / clearHistory 前保留
@Suite("ClipStore 撤销删除与 blob 保护")
@MainActor
struct ClipStoreUndoTests {
    private func image(_ seed: String) -> ClipContent {
        .image(png: Data("png-\(seed)".utf8), width: 4, height: 4)
    }

    private func rich(_ text: String) -> ClipContent {
        .richText(text, formats: ["public.html": Data("<b>\(text)</b>".utf8)])
    }

    // MARK: - lastRemoval / undoRemove

    @Test("删除后相同内容被重新记录，撤销时合并到现有条目并保留收藏，清理被删条目独有的格式文件")
    func undoMergesIntoRecopiedContent() throws {
        let dir = try TempDirectory.make()
        defer { TempDirectory.remove(dir) }

        let store = StoreFactory.make(dir: dir)
        let original = try #require(store.record(rich("dup"), source: nil))
        store.toggleFavorite(id: original.id)
        let oldFormats = try #require(original.formatsName)
        store.remove(id: original.id)
        let recopied = try #require(store.record(.text("dup"), source: nil))

        let restored = store.undoRemove()

        #expect(store.history.items.count == 1)
        #expect(restored?.id == recopied.id)
        #expect(store.history.items.first?.isFavorite == true)
        #expect(!FileManager.default.fileExists(atPath: dir.appendingPathComponent(oldFormats).path))
    }

    @Test("remove 记录被删条目及其原位置")
    func removeRecordsRemoval() throws {
        let dir = try TempDirectory.make()
        defer { TempDirectory.remove(dir) }

        let store = StoreFactory.make(dir: dir)
        store.record(.text("a"), source: nil)
        let b = try #require(store.record(.text("b"), source: nil))
        store.record(.text("c"), source: nil)

        store.remove(id: b.id)

        #expect(store.lastRemoval == ClipStore.Removal(item: b, index: 1))
        #expect(store.history.items.map(\.text) == ["c", "a"])
    }

    @Test("undoRemove 恢复到原位置，保留 id、收藏与格式，并持久化")
    func undoRestoresAtOriginalIndex() throws {
        let dir = try TempDirectory.make()
        defer { TempDirectory.remove(dir) }

        let storage = InMemoryHistoryStorage()
        let store = StoreFactory.make(dir: dir, storage: storage)
        store.record(.text("a"), source: nil)
        let target = try #require(store.record(rich("b"), source: SourceApp(bundleID: "x", name: "X")))
        store.record(.text("c"), source: nil)
        store.toggleFavorite(id: target.id)
        let before = store.history
        let favorited = try #require(store.item(id: target.id))

        store.remove(id: target.id)
        let restored = store.undoRemove()
        store.flush()

        #expect(restored == favorited)
        #expect(store.history == before)
        #expect(store.lastRemoval == nil)
        #expect(storage.lastSaved == before)
        #expect(store.formats(for: favorited) == ["public.html": Data("<b>b</b>".utf8)])
    }

    @Test("没有可撤销的删除时 undoRemove 返回 nil 且不改变状态")
    func undoWithoutRemoval() throws {
        let dir = try TempDirectory.make()
        defer { TempDirectory.remove(dir) }

        let store = StoreFactory.make(dir: dir)
        store.record(.text("a"), source: nil)
        let revision = store.revision

        #expect(store.undoRemove() == nil)
        #expect(store.revision == revision)
    }

    @Test("撤销只能执行一次")
    func undoOnlyOnce() throws {
        let dir = try TempDirectory.make()
        defer { TempDirectory.remove(dir) }

        let store = StoreFactory.make(dir: dir)
        let a = try #require(store.record(.text("a"), source: nil))
        store.remove(id: a.id)

        #expect(store.undoRemove()?.id == a.id)
        #expect(store.undoRemove() == nil)
        #expect(store.history.items.map(\.id) == [a.id])
    }

    @Test("只能撤销最近一次删除")
    func undoOnlyLatestRemoval() throws {
        let dir = try TempDirectory.make()
        defer { TempDirectory.remove(dir) }

        let store = StoreFactory.make(dir: dir)
        let a = try #require(store.record(.text("a"), source: nil))
        let b = try #require(store.record(.text("b"), source: nil))
        store.remove(id: a.id)
        store.remove(id: b.id)

        #expect(store.undoRemove()?.id == b.id)
        #expect(store.history.items.map(\.id) == [b.id])
    }

    @Test("删除后历史变短，撤销时原索引越界则放到末尾")
    func undoClampsIndexAfterTrim() throws {
        let dir = try TempDirectory.make()
        defer { TempDirectory.remove(dir) }

        let store = StoreFactory.make(dir: dir)
        let last = try #require(store.record(.text("last"), source: nil))
        store.record(.text("m"), source: nil)
        store.record(.text("n"), source: nil)
        store.remove(id: last.id)
        store.setLimit(1)

        store.undoRemove()
        #expect(store.history.items.map(\.text) == ["n", "last"])
    }

    // MARK: - blob 保护与清理时机

    @Test("删除后 blob 保留；撤销后仍在；再删除并 discardUndo 才清理", arguments: ["image", "rich"])
    func blobKeptUntilDiscard(_ kind: String) throws {
        let dir = try TempDirectory.make()
        defer { TempDirectory.remove(dir) }

        let store = StoreFactory.make(dir: dir)
        let item = try #require(store.record(kind == "image" ? image("x") : rich("x"), source: nil))
        let name = try #require(item.blobNames.first)

        store.remove(id: item.id)
        #expect(TempDirectory.exists(name, in: dir))

        store.undoRemove()
        #expect(TempDirectory.exists(name, in: dir))

        store.remove(id: item.id)
        store.discardUndo()
        #expect(!TempDirectory.exists(name, in: dir))
        #expect(store.lastRemoval == nil)
    }

    @Test("下一次删除时清理上一次被删条目的 blob，保留本次的")
    func nextRemovalCleansPrevious() throws {
        let dir = try TempDirectory.make()
        defer { TempDirectory.remove(dir) }

        let store = StoreFactory.make(dir: dir)
        let first = try #require(store.record(image("1"), source: nil))
        let second = try #require(store.record(image("2"), source: nil))
        let firstName = try #require(first.image?.name)
        let secondName = try #require(second.image?.name)

        store.remove(id: first.id)
        store.remove(id: second.id)

        #expect(!TempDirectory.exists(firstName, in: dir))
        #expect(TempDirectory.exists(secondName, in: dir))
    }

    @Test("删除期间的其他变更（裁剪、切换收藏）不会清理待撤销条目的 blob")
    func otherChangesKeepProtectedBlob() throws {
        let dir = try TempDirectory.make()
        defer { TempDirectory.remove(dir) }

        let store = StoreFactory.make(dir: dir, limit: 5)
        let target = try #require(store.record(image("t"), source: nil))
        let other = try #require(store.record(.text("other"), source: nil))
        let name = try #require(target.image?.name)

        store.remove(id: target.id)
        store.toggleFavorite(id: other.id)
        store.promote(id: other.id)
        for index in 0..<10 {
            store.record(.text("n\(index)"), source: nil)
        }
        store.setLimit(1)

        #expect(TempDirectory.exists(name, in: dir))
        #expect(store.undoRemove()?.id == target.id)
        #expect(store.imageURL(for: target).map { FileManager.default.fileExists(atPath: $0.path) } == true)
    }

    @Test("clearHistory 同时清理待撤销条目与非收藏条目的 blob，并放弃撤销")
    func clearHistoryDiscardsUndo() throws {
        let dir = try TempDirectory.make()
        defer { TempDirectory.remove(dir) }

        let store = StoreFactory.make(dir: dir)
        let removed = try #require(store.record(image("removed"), source: nil))
        let plain = try #require(store.record(image("plain"), source: nil))
        let kept = try #require(store.record(image("kept"), source: nil))
        store.toggleFavorite(id: kept.id)
        store.remove(id: removed.id)

        store.clearHistory()

        #expect(store.lastRemoval == nil)
        #expect(store.undoRemove() == nil)
        #expect(TempDirectory.fileNames(in: dir) == [try #require(kept.image?.name)])
        #expect(store.item(id: plain.id) == nil)
    }

    @Test("discardUndo 不会删除仍被其他条目引用的 blob")
    func discardKeepsSharedBlob() throws {
        let dir = try TempDirectory.make()
        defer { TempDirectory.remove(dir) }

        let store = StoreFactory.make(dir: dir)
        let shared = ["public.html": Data("<i>same</i>".utf8)]
        let first = try #require(store.record(.richText("one", formats: shared), source: nil))
        let second = try #require(store.record(.richText("two", formats: shared), source: nil))
        let name = try #require(first.formatsName)
        #expect(second.formatsName == name)

        store.remove(id: first.id)
        store.discardUndo()

        #expect(TempDirectory.exists(name, in: dir))
        #expect(store.formats(for: second) == shared)
    }

    @Test("连续删除两个共享 blob 的条目后，撤销第二次删除仍能读取格式")
    func consecutiveRemovalsKeepSharedProtectedBlob() throws {
        let dir = try TempDirectory.make()
        defer { TempDirectory.remove(dir) }

        let store = StoreFactory.make(dir: dir)
        let shared = ["public.html": Data("<i>same</i>".utf8)]
        let first = try #require(store.record(.richText("one", formats: shared), source: nil))
        let second = try #require(store.record(.richText("two", formats: shared), source: nil))
        let name = try #require(second.formatsName)

        store.remove(id: first.id)
        store.remove(id: second.id)

        #expect(TempDirectory.exists(name, in: dir))
        let restored = try #require(store.undoRemove())
        #expect(store.formats(for: restored) == shared)
    }

    @Test("删除后重新记录相同内容，再 discardUndo 不会删除新条目的 blob")
    func rerecordAfterRemoveKeepsBlob() throws {
        let dir = try TempDirectory.make()
        defer { TempDirectory.remove(dir) }

        let store = StoreFactory.make(dir: dir)
        let original = try #require(store.record(image("same"), source: nil))
        store.remove(id: original.id)
        let again = try #require(store.record(image("same"), source: nil))
        store.discardUndo()

        #expect(again.image?.name == original.image?.name)
        #expect(store.imageURL(for: again).map { FileManager.default.fileExists(atPath: $0.path) } == true)
    }

    @Test("删除不存在的 id 不影响已有的撤销记录")
    func removeUnknownKeepsUndo() throws {
        let dir = try TempDirectory.make()
        defer { TempDirectory.remove(dir) }

        let store = StoreFactory.make(dir: dir)
        let a = try #require(store.record(.text("a"), source: nil))
        store.remove(id: a.id)
        store.remove(id: UUID())

        #expect(store.lastRemoval?.item.id == a.id)
    }

    @Test("discardUndo 在无撤销记录时安全")
    func discardWithoutRemoval() throws {
        let dir = try TempDirectory.make()
        defer { TempDirectory.remove(dir) }

        let store = StoreFactory.make(dir: dir)
        store.discardUndo()
        #expect(store.lastRemoval == nil)
    }
}
