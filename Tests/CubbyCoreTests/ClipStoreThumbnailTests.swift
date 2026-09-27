import Foundation
import Testing
@testable import CubbyCore

/// 图片条目的预生成缩略图：随记录生成；删除 / 撤销 / 清空 / 上限淘汰 / 孤儿清理与原图同进退；旧条目后台回填
@Suite("ClipStore 预生成缩略图的生命周期")
@MainActor
struct ClipStoreThumbnailTests {
    /// 每个种子生成内容不同（尺寸不同）的大图，确保摘要不同
    private func bigImage(_ seed: Int, width: Int = 2200, height: Int = 1200) -> ClipContent {
        let w = width + seed
        return .image(png: LargeImageFixtures.png(width: w, height: height), width: w, height: height)
    }

    private func thumbnailName(of item: ClipItem) throws -> String {
        ImageThumbnail.name(forImage: try #require(item.image?.name))
    }

    private func exists(_ name: String, in dir: URL) -> Bool {
        TempDirectory.exists(name, in: dir)
    }

    // MARK: - 记录

    @Test("记录大图：同时写入缩略图（0600），入历史的条目不变")
    func recordingWritesThumbnail() throws {
        let dir = try TempDirectory.make()
        defer { TempDirectory.remove(dir) }
        let store = StoreFactory.make(dir: dir)

        let item = try #require(store.record(bigImage(0), source: nil))
        let name = try thumbnailName(of: item)

        #expect(exists(name, in: dir))
        #expect(try TempDirectory.permissions(of: dir.appendingPathComponent(name)) == 0o600)
        let data = try Data(contentsOf: dir.appendingPathComponent(name))
        #expect(LargeImageFixtures.info(of: data)?.width == 720)
        #expect(item.image?.width == 2200)
    }

    @Test("后台记录与同步记录生成相同的缩略图；PreparedClip 报告缩略图名")
    func backgroundRecordingWritesThumbnail() async throws {
        let dir = try TempDirectory.make()
        defer { TempDirectory.remove(dir) }
        let store = StoreFactory.make(dir: dir)

        let prepared = try ClipStore.prepare(bigImage(1), blobs: BlobStore(directory: dir.appendingPathComponent("p")))
        #expect(prepared.thumbnailName == prepared.blobName.map(ImageThumbnail.name(forImage:)))

        let item = try #require(await store.recordInBackground(bigImage(1), source: nil).value)
        #expect(exists(try thumbnailName(of: item), in: dir))
    }

    @Test("小图与无法解码的数据不生成缩略图，记录照常成功")
    func smallOrUndecodableImagesHaveNoThumbnail() throws {
        let dir = try TempDirectory.make()
        defer { TempDirectory.remove(dir) }
        let store = StoreFactory.make(dir: dir)

        let smallPNG = LargeImageFixtures.png(width: 1920, height: 1080)
        let small = try #require(store.record(.image(png: smallPNG, width: 1920, height: 1080), source: nil))
        let fake = try #require(store.record(.image(png: Data("png".utf8), width: 5000, height: 3000), source: nil))

        #expect(!exists(try thumbnailName(of: small), in: dir))
        #expect(!exists(try thumbnailName(of: fake), in: dir))
        #expect(store.history.items.count == 2)
    }

    @Test("准备后缩略图在入历史前被删：入历史时补写")
    func rewritesMissingThumbnail() throws {
        let dir = try TempDirectory.make()
        defer { TempDirectory.remove(dir) }
        let store = StoreFactory.make(dir: dir)
        let blobs = BlobStore(directory: dir)

        let prepared = try ClipStore.prepare(bigImage(2), blobs: blobs)
        let name = try #require(prepared.thumbnailName)
        blobs.remove([name])

        _ = try #require(store.record(prepared, source: nil))
        #expect(exists(name, in: dir))
    }

    @Test("同一张图再次记录：沿用已有的缩略图文件")
    func reusesExistingThumbnail() throws {
        let dir = try TempDirectory.make()
        defer { TempDirectory.remove(dir) }
        let blobs = BlobStore(directory: dir)

        let first = try ClipStore.prepare(bigImage(3), blobs: blobs)
        let name = try #require(first.thumbnailName)
        let before = try FileManager.default.attributesOfItem(atPath: dir.appendingPathComponent(name).path)
        let second = try ClipStore.prepare(bigImage(3), blobs: blobs)
        let after = try FileManager.default.attributesOfItem(atPath: dir.appendingPathComponent(name).path)

        #expect(second.thumbnailName == name)
        #expect(before[.systemFileNumber] as? Int == after[.systemFileNumber] as? Int)
    }

    // MARK: - 删除与撤销

    @Test("删除：缩略图保留到撤销机会失效；撤销后仍在；放弃撤销后与原图一起删除")
    func removalKeepsThumbnailUntilUndoExpires() throws {
        let dir = try TempDirectory.make()
        defer { TempDirectory.remove(dir) }
        let store = StoreFactory.make(dir: dir)
        let item = try #require(store.record(bigImage(4), source: nil))
        let thumbnail = try thumbnailName(of: item)
        let image = try #require(item.image?.name)

        store.remove(id: item.id)
        #expect(exists(thumbnail, in: dir))
        _ = store.undoRemove()
        #expect(exists(thumbnail, in: dir))

        store.remove(id: item.id)
        store.discardUndo()
        #expect(!exists(thumbnail, in: dir))
        #expect(!exists(image, in: dir))
    }

    @Test("连续删除两条：前一条的撤销机会失效，其缩略图随之删除")
    func secondRemovalDeletesPreviousThumbnail() throws {
        let dir = try TempDirectory.make()
        defer { TempDirectory.remove(dir) }
        let store = StoreFactory.make(dir: dir)
        let first = try #require(store.record(bigImage(5), source: nil))
        let second = try #require(store.record(bigImage(6), source: nil))

        store.remove(id: first.id)
        store.remove(id: second.id)

        #expect(!exists(try thumbnailName(of: first), in: dir))
        #expect(exists(try thumbnailName(of: second), in: dir))
    }

    @Test("清空历史：非收藏图片的缩略图删除，收藏图片的保留")
    func clearHistoryDeletesNonFavoriteThumbnails() throws {
        let dir = try TempDirectory.make()
        defer { TempDirectory.remove(dir) }
        let store = StoreFactory.make(dir: dir)
        let plain = try #require(store.record(bigImage(7), source: nil))
        let favorite = try #require(store.record(bigImage(8), source: nil))
        store.toggleFavorite(id: favorite.id)

        store.clearHistory()

        #expect(!exists(try thumbnailName(of: plain), in: dir))
        #expect(exists(try thumbnailName(of: favorite), in: dir))
    }

    @Test("超出上限淘汰：被淘汰图片的缩略图一并删除")
    func trimmingDeletesThumbnails() throws {
        let dir = try TempDirectory.make()
        defer { TempDirectory.remove(dir) }
        let store = StoreFactory.make(dir: dir, limit: 1)
        let old = try #require(store.record(bigImage(9), source: nil))
        let new = try #require(store.record(bigImage(10), source: nil))

        #expect(!exists(try thumbnailName(of: old), in: dir))
        #expect(exists(try thumbnailName(of: new), in: dir))

        store.record(.text("x"), source: nil)
        #expect(!exists(try thumbnailName(of: new), in: dir))
    }

    // MARK: - 启动清理

    @Test("启动时孤儿清理：保留在用图片的缩略图，删除原图已不在历史中的缩略图")
    func orphanCleanupCoversThumbnails() throws {
        let dir = try TempDirectory.make()
        defer { TempDirectory.remove(dir) }
        let blobs = BlobStore(directory: dir)
        for name in ["kept.png", "kept.thumb", "gone.thumb", "stray.png"] {
            try blobs.write(Data(name.utf8), name: name)
        }
        let storage = InMemoryHistoryStorage(initial: ClipHistory(items: [Fixtures.image(name: "kept.png")]))

        _ = StoreFactory.make(dir: dir, storage: storage)

        #expect(TempDirectory.fileNames(in: dir) == ["kept.png", "kept.thumb"])
    }

    @Test("原图缺失的条目被修复移除时，其缩略图也被清理")
    func repairRemovesThumbnailOfMissingImage() throws {
        let dir = try TempDirectory.make()
        defer { TempDirectory.remove(dir) }
        try BlobStore(directory: dir).write(Data("t".utf8), name: "lost.thumb")
        let storage = InMemoryHistoryStorage(initial: ClipHistory(items: [Fixtures.image(name: "lost.png")]))

        let store = StoreFactory.make(dir: dir, storage: storage)

        #expect(store.history.items.isEmpty)
        #expect(TempDirectory.fileNames(in: dir).isEmpty)
    }

    // MARK: - 回填

    /// 把大图写成「旧版本记录的条目」：只有原图，没有缩略图
    private func legacyImage(_ seed: Int, in dir: URL, width: Int = 2200, height: Int = 1200) throws -> ClipItem {
        let name = "legacy-\(seed).png"
        try BlobStore(directory: dir).write(LargeImageFixtures.png(width: width, height: height), name: name)
        return Fixtures.image(name: name, width: width, height: height)
    }

    @Test("回填：为缺缩略图的大图逐张生成，跳过小图与已有缩略图的图，返回生成数量")
    func backfillCreatesMissingThumbnails() async throws {
        let dir = try TempDirectory.make()
        defer { TempDirectory.remove(dir) }
        let first = try legacyImage(1, in: dir)
        let second = try legacyImage(2, in: dir, width: 1000, height: 3000)
        let small = try legacyImage(3, in: dir, width: 1600, height: 900)
        let done = try legacyImage(4, in: dir)
        try BlobStore(directory: dir).write(Data("existing".utf8), name: "legacy-4.thumb")
        let storage = InMemoryHistoryStorage(initial: ClipHistory(items: [first, second, small, done]))
        let store = StoreFactory.make(dir: dir, storage: storage)

        let created = await store.backfillThumbnails(after: .zero).value

        #expect(created == 2)
        let tall = try Data(contentsOf: dir.appendingPathComponent("legacy-2.thumb"))
        #expect(LargeImageFixtures.info(of: tall)?.height == 2048)
        #expect(try TempDirectory.permissions(of: dir.appendingPathComponent("legacy-1.thumb")) == 0o600)
        #expect(!exists("legacy-3.thumb", in: dir))
        #expect(try Data(contentsOf: dir.appendingPathComponent("legacy-4.thumb")) == Data("existing".utf8))
        // 历史本身不变、不触发保存
        #expect(store.history.items.map(\.id) == [first.id, second.id, small.id, done.id])
        #expect(storage.savedSnapshots.isEmpty)
        // 再次回填无事可做
        #expect(await store.backfillThumbnails(after: .zero).value == 0)
    }

    @Test("回填开始前条目已被删除（撤销机会也已失效）：不为它生成缩略图")
    func backfillSkipsRemovedItems() async throws {
        let dir = try TempDirectory.make()
        defer { TempDirectory.remove(dir) }
        let legacy = try legacyImage(5, in: dir)
        let store = StoreFactory.make(dir: dir, storage: InMemoryHistoryStorage(initial: ClipHistory(items: [legacy])))

        let task = store.backfillThumbnails(after: .milliseconds(200))
        store.remove(id: legacy.id)
        store.discardUndo()

        #expect(await task.value == 0)
        #expect(TempDirectory.fileNames(in: dir).isEmpty)
    }

    @Test("回填生成期间条目被删除（撤销机会也已失效）：无论删除落在哪一步，最终都不留下缩略图")
    func backfillDropsThumbnailOfItemRemovedMidway() async throws {
        let dir = try TempDirectory.make()
        defer { TempDirectory.remove(dir) }
        // 较大的图让生成耗时更长，删除大概率落在后台生成期间
        let legacy = try legacyImage(7, in: dir, width: 6000, height: 4000)
        let store = StoreFactory.make(dir: dir, storage: InMemoryHistoryStorage(initial: ClipHistory(items: [legacy])))

        let task = store.backfillThumbnails(after: .zero)
        try await Task.sleep(for: .milliseconds(5))
        store.remove(id: legacy.id)
        store.discardUndo()

        #expect(await task.value == 0)
        #expect(TempDirectory.fileNames(in: dir).isEmpty)
    }

    @Test("回填可取消；重复调用只保留最新一次")
    func backfillIsCancellable() async throws {
        let dir = try TempDirectory.make()
        defer { TempDirectory.remove(dir) }
        let legacy = try legacyImage(6, in: dir)
        let store = StoreFactory.make(dir: dir, storage: InMemoryHistoryStorage(initial: ClipHistory(items: [legacy])))

        let first = store.backfillThumbnails(after: .seconds(30))
        let second = store.backfillThumbnails(after: .seconds(30))
        #expect(await first.value == 0)
        second.cancel()
        #expect(await second.value == 0)
        #expect(!exists("legacy-6.thumb", in: dir))
    }

    @Test("只读模式（历史来自更新版本等）不回填")
    func readOnlyStoreDoesNotBackfill() async throws {
        let dir = try TempDirectory.make()
        defer { TempDirectory.remove(dir) }
        let store = StoreFactory.make(dir: dir, storage: InMemoryHistoryStorage(loadError: SimulatedLoadError()))
        #expect(!store.canPersist)
        #expect(await store.backfillThumbnails(after: .zero).value == 0)
    }
}
