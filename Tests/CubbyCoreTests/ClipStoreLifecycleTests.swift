import Foundation
import Testing
@testable import CubbyCore

/// ClipStore 加载、持久化与孤立 blob 清理
@Suite("ClipStore 加载与持久化")
@MainActor
struct ClipStoreLifecycleTests {
    private func makeStore(storage: InMemoryHistoryStorage, blobDir: URL, limit: Int = 10) -> ClipStore {
        ClipStore(storage: storage, blobs: BlobStore(directory: blobDir), limit: limit, now: { Fixtures.baseDate })
    }

    private func writeBlob(_ name: String, in dir: URL) throws {
        try BlobStore(directory: dir).write(Data(name.utf8), name: name)
    }

    @Test("初始化时载入已有历史且不触发保存")
    func loadsExistingHistory() throws {
        let dir = try TempDirectory.make()
        defer { TempDirectory.remove(dir) }

        let existing = ClipHistory(items: [Fixtures.text("a"), Fixtures.text("b", favorite: true)])
        let storage = InMemoryHistoryStorage(initial: existing)
        let store = makeStore(storage: storage, blobDir: dir)
        store.flush()

        #expect(store.history == existing)
        #expect(storage.savedSnapshots.isEmpty)
    }

    @Test("flush 后假存储收到最新快照（中间快照可能被合并）")
    func flushDeliversLatestSnapshot() throws {
        let dir = try TempDirectory.make()
        defer { TempDirectory.remove(dir) }

        let storage = InMemoryHistoryStorage()
        let store = makeStore(storage: storage, blobDir: dir)
        let a = try #require(store.record(.text("a"), source: nil))
        store.record(.text("b"), source: nil)
        store.toggleFavorite(id: a.id)
        store.flush()

        #expect(storage.lastSaved == store.history)
        #expect((1...3).contains(storage.savedSnapshots.count))
        #expect(storage.lastSaved?.items.map(\.text) == ["b", "a"])
    }

    @Test("快照按变更顺序保存，最后一次为最终状态")
    func snapshotsAreOrdered() throws {
        let dir = try TempDirectory.make()
        defer { TempDirectory.remove(dir) }

        let storage = InMemoryHistoryStorage()
        let store = makeStore(storage: storage, blobDir: dir)
        for index in 0..<50 {
            store.record(.text("t\(index)"), source: nil)
        }
        store.flush()

        // 每个快照的最新条目序号严格递增（不会写回旧状态）
        let heads = storage.savedSnapshots.compactMap { $0.items.first?.text?.dropFirst() }.compactMap { Int($0) }
        #expect(heads.count == storage.savedSnapshots.count)
        #expect(heads == heads.sorted() && Set(heads).count == heads.count)
        #expect(heads.last == 49)
        #expect(storage.savedSnapshots.count <= 50)
        #expect(storage.lastSaved?.items.count == 10)
    }

    @Test("加载失败（普通错误）时不写盘，也不清理已有 blob")
    func loadFailureDisablesPersistence() throws {
        let dir = try TempDirectory.make()
        defer { TempDirectory.remove(dir) }

        try writeBlob("existing.png", in: dir)
        let storage = InMemoryHistoryStorage(
            initial: ClipHistory(items: [Fixtures.text("never-seen")]),
            loadError: SimulatedLoadError()
        )
        let store = makeStore(storage: storage, blobDir: dir)
        store.record(.text("new"), source: nil)
        store.clearHistory()
        store.flush()

        #expect(storage.savedSnapshots.isEmpty)
        #expect(TempDirectory.fileNames(in: dir).contains("existing.png"))
    }

    @Test("加载失败时本次运行仍可在内存中使用")
    func loadFailureStillWorksInMemory() throws {
        let dir = try TempDirectory.make()
        defer { TempDirectory.remove(dir) }

        let storage = InMemoryHistoryStorage(loadError: SimulatedLoadError())
        let store = makeStore(storage: storage, blobDir: dir)
        #expect(store.history == .empty)
        store.record(.text("x"), source: nil)
        #expect(store.history.items.map(\.text) == ["x"])
    }

    @Test("历史文件损坏时从空历史开始并正常写盘")
    func corruptedHistoryStillPersists() throws {
        let dir = try TempDirectory.make()
        defer { TempDirectory.remove(dir) }

        let backup = dir.appendingPathComponent("history.corrupt-1.json")
        let storage = InMemoryHistoryStorage(loadError: HistoryStorageError.corrupted(backupURL: backup))
        let store = makeStore(storage: storage, blobDir: dir)
        store.record(.text("x"), source: nil)
        store.flush()

        #expect(store.history.items.count == 1)
        #expect(storage.lastSaved == store.history)
    }

    @Test("初始化时清理孤立 blob，保留被引用的文件")
    func initRemovesOrphanedBlobs() throws {
        let dir = try TempDirectory.make()
        defer { TempDirectory.remove(dir) }

        for name in ["keep.png", "orphan1.png", "orphan2.png"] {
            try writeBlob(name, in: dir)
        }
        let storage = InMemoryHistoryStorage(initial: ClipHistory(items: [Fixtures.image(name: "keep.png")]))
        _ = makeStore(storage: storage, blobDir: dir)

        #expect(TempDirectory.fileNames(in: dir) == ["keep.png"])
    }

    @Test("被加载历史中引用非法文件名时不会越界删除或访问")
    func maliciousImageNameIsIgnored() throws {
        let root = try TempDirectory.make()
        defer { TempDirectory.remove(root) }

        let outside = root.appendingPathComponent("secret.txt")
        try Data("secret".utf8).write(to: outside)
        let blobDir = root.appendingPathComponent("blobs")
        let evil = Fixtures.image(name: "../secret.txt")
        let storage = InMemoryHistoryStorage(initial: ClipHistory(items: [evil]))
        let store = makeStore(storage: storage, blobDir: blobDir)

        #expect(store.imageURL(for: evil) == nil)
        // 非法名称无法确认文件存在，启动修复时该条目被移除
        #expect(store.item(id: evil.id) == nil)
        store.remove(id: evil.id)
        store.discardUndo()
        #expect(FileManager.default.fileExists(atPath: outside.path))
    }

    @Test("记录新内容时按当前上限裁剪载入的历史")
    func loadedHistoryTrimmedOnRecord() throws {
        let dir = try TempDirectory.make()
        defer { TempDirectory.remove(dir) }

        let items = (0..<5).map { Fixtures.text("old\($0)") }
        let storage = InMemoryHistoryStorage(initial: ClipHistory(items: items))
        let store = makeStore(storage: storage, blobDir: dir, limit: 2)

        store.record(.text("new"), source: nil)
        #expect(store.history.items.map(\.text) == ["new", "old0"])
    }
}
