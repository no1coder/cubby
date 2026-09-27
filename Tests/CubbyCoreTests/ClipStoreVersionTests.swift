import Foundation
import Testing
@testable import CubbyCore

/// ClipStore 对历史文件版本的处理：迁移后重新保存、高版本只读、loadIssue 报告原因
@Suite("ClipStore 版本迁移与只读模式")
@MainActor
struct ClipStoreVersionTests {
    /// 在 root 下准备历史文件与 blob 目录，返回 (历史文件, blob 目录)
    private func layout(in root: URL) -> (history: URL, blobs: URL) {
        (root.appendingPathComponent("history.json"), root.appendingPathComponent("blobs", isDirectory: true))
    }

    private func makeStore(fileURL: URL, blobDir: URL) -> ClipStore {
        StoreFactory.make(dir: blobDir, storage: JSONHistoryStorage(fileURL: fileURL))
    }

    private func writeBlobs(_ names: [String], in dir: URL) throws {
        let store = BlobStore(directory: dir)
        for name in names {
            try store.write(Data(name.utf8), name: name)
        }
    }

    // MARK: - 迁移

    @Test("v0 文件经 ClipStore 载入后内容不变，并自动以 v1 重新保存")
    func v0IsResavedAsCurrentVersion() throws {
        let root = try TempDirectory.make()
        defer { TempDirectory.remove(root) }

        let paths = layout(in: root)
        try HistoryFixtures.write(HistoryFixtures.v0JSON, to: paths.history)
        try writeBlobs(HistoryFixtures.v0BlobNames, in: paths.blobs)

        let store = makeStore(fileURL: paths.history, blobDir: paths.blobs)
        store.flush()

        #expect(store.history.items == HistoryFixtures.v0Items)
        #expect(store.canPersist)
        #expect(store.loadIssue == nil)
        #expect(try HistoryFixtures.schemaVersion(ofFileAt: paths.history) == 1)
        #expect(try JSONHistoryStorage(fileURL: paths.history).load().items == HistoryFixtures.v0Items)
        #expect(TempDirectory.exists("history.v0.bak.json", in: root))
        #expect(TempDirectory.fileNames(in: paths.blobs) == Set(HistoryFixtures.v0BlobNames))
    }

    @Test("存储报告发生迁移时安排一次保存，内容为载入的历史")
    func migrationSchedulesSave() throws {
        let dir = try TempDirectory.make()
        defer { TempDirectory.remove(dir) }

        let history = ClipHistory(items: [Fixtures.text("a"), Fixtures.text("b", favorite: true)])
        let storage = InMemoryHistoryStorage(initial: history, sourceVersion: 0)
        let store = StoreFactory.make(dir: dir, storage: storage)
        store.flush()

        #expect(storage.savedSnapshots == [history])
        #expect(store.loadIssue == nil)
    }

    @Test("v1 文件载入不触发保存，文件字节不变")
    func v1IsNotResaved() throws {
        let root = try TempDirectory.make()
        defer { TempDirectory.remove(root) }

        let paths = layout(in: root)
        let original = try HistoryFixtures.write(HistoryFixtures.v1JSON, to: paths.history)
        let store = makeStore(fileURL: paths.history, blobDir: paths.blobs)
        store.flush()

        #expect(store.history.items == HistoryFixtures.v1Items)
        #expect(store.loadIssue == nil)
        #expect(try Data(contentsOf: paths.history) == original)
    }

    @Test("只实现 load / save 的存储：默认视为当前版本，载入后不触发保存")
    func defaultReportingTreatsAsCurrent() throws {
        let dir = try TempDirectory.make()
        defer { TempDirectory.remove(dir) }

        let history = ClipHistory(items: [Fixtures.text("a")])
        let inner = InMemoryHistoryStorage(initial: history, sourceVersion: 0)
        let storage = LoadOnlyStorage(inner: inner)

        let outcome = try storage.loadReportingMigration()
        #expect(outcome == HistoryMigrator.Outcome(history: history, sourceVersion: HistoryMigrator.currentVersion))

        let store = StoreFactory.make(dir: dir, storage: storage)
        store.flush()
        #expect(store.history == history)
        #expect(inner.savedSnapshots.isEmpty)
    }

    // MARK: - 高版本：只读

    @Test("v99 文件：只读、loadIssue 为 newerVersion(99)、历史为空")
    func v99EntersReadOnlyMode() throws {
        let root = try TempDirectory.make()
        defer { TempDirectory.remove(root) }

        let paths = layout(in: root)
        try HistoryFixtures.write(HistoryFixtures.v99JSON, to: paths.history)
        let store = makeStore(fileURL: paths.history, blobDir: paths.blobs)

        #expect(!store.canPersist)
        #expect(store.loadIssue == .newerVersion(99))
        #expect(store.history == .empty)
    }

    @Test("v99 只读模式下 record / remove / 清空等操作都不写盘，原文件字节不变")
    func v99NeverWritesHistory() throws {
        let root = try TempDirectory.make()
        defer { TempDirectory.remove(root) }

        let paths = layout(in: root)
        let original = try HistoryFixtures.write(HistoryFixtures.v99JSON, to: paths.history)
        let store = makeStore(fileURL: paths.history, blobDir: paths.blobs)

        let a = try #require(store.record(.text("a"), source: nil))
        let b = try #require(store.record(.text("b"), source: nil))
        store.toggleFavorite(id: a.id)
        store.promote(id: a.id)
        store.remove(id: b.id)
        store.undoRemove()
        store.remove(id: a.id)
        store.discardUndo()
        store.setLimit(1)
        store.clearHistory()
        store.flush()

        #expect(try Data(contentsOf: paths.history) == original)
        #expect(TempDirectory.fileNames(in: root) == ["history.json"])
    }

    @Test("v99 只读模式下不清理也不删除已有 blob（含与新记录同名的文件）")
    func v99KeepsExistingBlobs() throws {
        let root = try TempDirectory.make()
        defer { TempDirectory.remove(root) }

        let paths = layout(in: root)
        try HistoryFixtures.write(HistoryFixtures.v99JSON, to: paths.history)
        // 高版本历史引用的图片，与本次运行将要记录的图片内容相同（文件名基于内容哈希）
        let png = Data("shared-png".utf8)
        let sharedName = ContentHasher.sha256(png) + ".png"
        try BlobStore(directory: paths.blobs).write(png, name: sharedName)
        try writeBlobs(["future-only.png"], in: paths.blobs)

        let store = makeStore(fileURL: paths.history, blobDir: paths.blobs)
        let image = try #require(store.record(.image(png: png, width: 1, height: 1), source: nil))
        #expect(image.image?.name == sharedName)
        store.remove(id: image.id)
        store.discardUndo()
        store.flush()

        #expect(TempDirectory.fileNames(in: paths.blobs) == [sharedName, "future-only.png"])
    }

    @Test("v99 只读模式下仍可在内存中正常使用")
    func v99WorksInMemory() throws {
        let root = try TempDirectory.make()
        defer { TempDirectory.remove(root) }

        let paths = layout(in: root)
        try HistoryFixtures.write(HistoryFixtures.v99JSON, to: paths.history)
        let store = makeStore(fileURL: paths.history, blobDir: paths.blobs)

        store.record(.text("x"), source: nil)
        store.record(.text("y"), source: nil)
        #expect(store.history.items.map(\.text) == ["y", "x"])
    }

    // MARK: - 其他 loadIssue

    @Test("损坏文件：loadIssue 为 restoredFromCorruption（指向真实备份），仍可写盘")
    func corruptionIsReported() throws {
        let root = try TempDirectory.make()
        defer { TempDirectory.remove(root) }

        let paths = layout(in: root)
        let original = try HistoryFixtures.write("{not json", to: paths.history)
        let store = makeStore(fileURL: paths.history, blobDir: paths.blobs)

        guard case .restoredFromCorruption(let backupURL) = store.loadIssue else {
            Issue.record("应报告 restoredFromCorruption，实际为 \(String(describing: store.loadIssue))")
            return
        }
        #expect(try Data(contentsOf: backupURL) == original)
        #expect(store.canPersist)

        store.record(.text("fresh"), source: nil)
        store.flush()
        #expect(try JSONHistoryStorage(fileURL: paths.history).load().items.map(\.text) == ["fresh"])
    }

    @Test("普通读取错误：loadIssue 为 unreadable，只读")
    func unreadableIsReported() throws {
        let dir = try TempDirectory.make()
        defer { TempDirectory.remove(dir) }

        let storage = InMemoryHistoryStorage(loadError: SimulatedLoadError())
        let store = StoreFactory.make(dir: dir, storage: storage)
        store.record(.text("x"), source: nil)
        store.flush()

        #expect(store.loadIssue == .unreadable)
        #expect(!store.canPersist)
        #expect(storage.savedSnapshots.isEmpty)
    }

    @Test("假存储抛出 unsupportedVersion 时同样进入只读")
    func unsupportedVersionFromAnyStorage() throws {
        let dir = try TempDirectory.make()
        defer { TempDirectory.remove(dir) }

        let storage = InMemoryHistoryStorage(loadError: HistoryStorageError.unsupportedVersion(found: 7))
        let store = StoreFactory.make(dir: dir, storage: storage)
        store.record(.text("x"), source: nil)
        store.flush()

        #expect(store.loadIssue == .newerVersion(7))
        #expect(!store.canPersist)
        #expect(storage.savedSnapshots.isEmpty)
    }
}

/// 只实现协议必需的 load / save（不报告格式版本），用于验证 loadReportingMigration 的默认实现
private struct LoadOnlyStorage: HistoryPersisting {
    let inner: InMemoryHistoryStorage

    func load() throws -> ClipHistory {
        try inner.load()
    }

    func save(_ history: ClipHistory) throws {
        try inner.save(history)
    }
}
