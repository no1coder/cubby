import Foundation
import Testing
@testable import CubbyCore

/// 异常退出可能留下引用已删除文件的条目：启动时移除缺图条目、缺格式条目退化为纯文本
@Suite("ClipStore 启动时修复缺失的 blob")
@MainActor
struct ClipStoreRepairTests {
    private func writeBlob(_ name: String, in dir: URL) throws {
        try BlobStore(directory: dir).write(Data(name.utf8), name: name)
    }

    @Test("图片文件缺失的条目被移除，其余条目顺序与 id 不变，并安排保存")
    func removesItemsWithMissingImages() throws {
        let dir = try TempDirectory.make()
        defer { TempDirectory.remove(dir) }

        try writeBlob("present.png", in: dir)
        let a = Fixtures.text("a")
        let present = Fixtures.image(name: "present.png")
        let missing = Fixtures.image(name: "missing.png", favorite: true)
        let b = Fixtures.text("b")
        let storage = InMemoryHistoryStorage(initial: ClipHistory(items: [a, missing, present, b]))

        let store = StoreFactory.make(dir: dir, storage: storage)
        store.flush()

        #expect(store.history.items.map(\.id) == [a.id, present.id, b.id])
        #expect(storage.lastSaved == store.history)
        #expect(storage.savedSnapshots.count == 1)
    }

    @Test("格式文件缺失的条目保留，但退化为纯文本")
    func degradesItemsWithMissingFormats() throws {
        let dir = try TempDirectory.make()
        defer { TempDirectory.remove(dir) }

        let rich = Fixtures.text("rich", favorite: true, formatsName: "gone.formats")
        let storage = InMemoryHistoryStorage(initial: ClipHistory(items: [rich]))

        let store = StoreFactory.make(dir: dir, storage: storage)
        store.flush()

        let repaired = try #require(store.item(id: rich.id))
        #expect(repaired.formatsName == nil)
        #expect(repaired.isFavorite)
        #expect(repaired.text == "rich")
        #expect(storage.lastSaved?.items.first?.formatsName == nil)
        #expect(store.formats(for: repaired).isEmpty)
    }

    @Test("所有 blob 都在时不修改历史、不触发保存")
    func intactHistoryIsUntouched() throws {
        let dir = try TempDirectory.make()
        defer { TempDirectory.remove(dir) }

        try writeBlob("i.png", in: dir)
        try writeBlob("r.formats", in: dir)
        let history = ClipHistory(items: [
            Fixtures.image(name: "i.png"),
            Fixtures.text("rich", formatsName: "r.formats"),
            Fixtures.files(["/tmp/not-checked"]),
        ])
        let storage = InMemoryHistoryStorage(initial: history)

        let store = StoreFactory.make(dir: dir, storage: storage)
        store.flush()

        #expect(store.history == history)
        #expect(storage.savedSnapshots.isEmpty)
        #expect(store.revision == 0)
    }

    @Test("修复与孤立文件清理同时进行：保留被引用的图片与格式文件")
    func repairAndOrphanCleanup() throws {
        let dir = try TempDirectory.make()
        defer { TempDirectory.remove(dir) }

        for name in ["keep.png", "keep.formats", "orphan.png", "orphan.formats"] {
            try writeBlob(name, in: dir)
        }
        let storage = InMemoryHistoryStorage(
            initial: ClipHistory(items: [
                Fixtures.image(name: "keep.png"),
                Fixtures.text("rich", formatsName: "keep.formats"),
                Fixtures.image(name: "lost.png"),
                Fixtures.text("degraded", formatsName: "lost.formats"),
            ]))

        let store = StoreFactory.make(dir: dir, storage: storage)

        #expect(TempDirectory.fileNames(in: dir) == ["keep.png", "keep.formats"])
        #expect(store.history.items.map(\.text) == [nil, "rich", "degraded"])
        #expect(store.history.blobNames == ["keep.png", "keep.formats"])
    }

    @Test("blob 目录整体丢失时移除全部图片条目，文本条目保留")
    func missingBlobDirectory() throws {
        let root = try TempDirectory.make()
        defer { TempDirectory.remove(root) }

        let storage = InMemoryHistoryStorage(
            initial: ClipHistory(items: [
                Fixtures.image(name: "a.png"),
                Fixtures.text("t", formatsName: "t.formats"),
            ]))
        let store = StoreFactory.make(dir: root.appendingPathComponent("never-created"), storage: storage)

        #expect(store.history.items.map(\.text) == ["t"])
        #expect(store.history.items.first?.formatsName == nil)
    }

    @Test("修复后的历史可正常继续记录与保存")
    func continuesAfterRepair() throws {
        let dir = try TempDirectory.make()
        defer { TempDirectory.remove(dir) }

        let storage = InMemoryHistoryStorage(initial: ClipHistory(items: [Fixtures.image(name: "gone.png")]))
        let store = StoreFactory.make(dir: dir, storage: storage)
        store.record(.text("new"), source: nil)
        store.flush()

        #expect(storage.lastSaved?.items.map(\.text) == ["new"])
    }

    @Test("加载失败（普通错误）时不修复也不保存")
    func noRepairWhenLoadFails() throws {
        let dir = try TempDirectory.make()
        defer { TempDirectory.remove(dir) }

        try writeBlob("existing.png", in: dir)
        let storage = InMemoryHistoryStorage(loadError: SimulatedLoadError())
        let store = StoreFactory.make(dir: dir, storage: storage)
        store.flush()

        #expect(store.history == .empty)
        #expect(storage.savedSnapshots.isEmpty)
        #expect(TempDirectory.exists("existing.png", in: dir))
    }

    @Test("blob 目录不可读时初始化不崩溃，文本历史照常载入")
    func unreadableBlobDirectory() throws {
        let root = try TempDirectory.make()
        let blobDir = root.appendingPathComponent("blobs", isDirectory: true)
        try FileManager.default.createDirectory(at: blobDir, withIntermediateDirectories: true)
        defer {
            try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: blobDir.path)
            TempDirectory.remove(root)
        }
        try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: blobDir.path)

        let history = ClipHistory(items: [Fixtures.text("a"), Fixtures.text("b")])
        let store = StoreFactory.make(dir: blobDir, storage: InMemoryHistoryStorage(initial: history))

        #expect(store.history == history)
    }

    @Test("撤销期满删除 blob 失败时不影响历史状态")
    func discardUndoWithUndeletableBlob() throws {
        let dir = try TempDirectory.make()
        defer {
            try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: dir.path)
            TempDirectory.remove(dir)
        }

        let store = StoreFactory.make(dir: dir)
        let image = try #require(store.record(.image(png: Data("png".utf8), width: 1, height: 1), source: nil))
        store.remove(id: image.id)
        try FileManager.default.setAttributes([.posixPermissions: 0o500], ofItemAtPath: dir.path)

        store.discardUndo()

        #expect(store.history.items.isEmpty)
        #expect(store.lastRemoval == nil)
        #expect(TempDirectory.exists(try #require(image.image?.name), in: dir))
    }
}
