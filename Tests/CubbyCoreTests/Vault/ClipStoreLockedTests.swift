import Foundation
import os
import Testing
@testable import CubbyCore

/// E8 ①：锁定（内存模式）时什么都不写盘；解锁时先合并、再写盘、最后才清理
@Suite("ClipStore 锁定与解锁（E8 ①）", .timeLimit(.minutes(1)))
@MainActor
struct ClipStoreLockedTests {
    private func bigImage(_ seed: Int) -> ClipContent {
        let width = 2200 + seed
        return .image(png: LargeImageFixtures.png(width: width, height: 1200), width: width, height: 1200)
    }

    private func smallImage(_ seed: String) -> ClipContent {
        .image(png: Data("png-\(seed)".utf8), width: 8, height: 6)
    }

    @Test("内存模式：记录文本、富文本与图片都不写盘；删除只删内存；不回填缩略图")
    func lockedWritesNothing() async throws {
        let environment = try VaultEnvironment()
        defer { environment.remove() }
        let store = ClipStore(inMemoryWithLimit: 10, now: { Fixtures.baseDate })

        store.record(.text("hello"), source: nil)
        store.record(.richText("bold", formats: Fixtures.richFormats(for: "bold")), source: nil)
        let image = try #require(store.record(bigImage(0), source: nil))
        _ = await store.recordInBackground(smallImage("bg"), source: nil).value
        store.remove(id: image.id)
        store.discardUndo()

        #expect(store.isInMemory && !store.canPersist)
        #expect(store.history.items.count == 3)
        #expect(TempDirectory.fileNames(in: environment.root).isEmpty)
        #expect(await store.backfillThumbnails(after: .zero).value == 0)
        let memory = try #require(store.blobs as? InMemoryClipBlobStore)
        // 删除的大图连同缩略图从内存里清掉，富文本格式与小图还在
        #expect(memory.names.count == 2)
        #expect(memory.names.allSatisfy { $0.hasPrefix("mem-") })
    }

    @Test("内存模式：可读出图片与富文本格式")
    func lockedReadsFromMemory() async throws {
        let store = ClipStore(inMemoryWithLimit: 10)
        let png = LargeImageFixtures.png(width: 2300, height: 1200)
        let item = try #require(store.record(.image(png: png, width: 2300, height: 1200), source: nil))
        #expect(store.imageData(for: item) == png)
        #expect(store.imageSource(for: item)?.thumbnailData() != nil)
        let rich = try #require(store.record(.richText("r", formats: Fixtures.richFormats(for: "r")), source: nil))
        #expect(store.formats(for: rich) == Fixtures.richFormats(for: "r"))
    }

    @Test("解锁：合并磁盘历史与内存条目，图片按加密名搬进 Vault（含缩略图），引用改写，保存后可读")
    func unlockMergesAndPersists() async throws {
        let environment = try VaultEnvironment()
        defer { environment.remove() }
        let onDisk = Fixtures.text("from disk", favorite: false, at: Fixtures.baseDate.addingTimeInterval(-60))
        let duplicate = Fixtures.text("both", at: Fixtures.baseDate.addingTimeInterval(-120))
        try environment.storage.save(ClipHistory(items: [onDisk, duplicate]))

        let store = ClipStore(inMemoryWithLimit: 10, now: { Fixtures.baseDate })
        let image = try #require(store.record(bigImage(1), source: nil))
        store.record(.richText("rich", formats: Fixtures.richFormats(for: "rich")), source: nil)
        let both = try #require(store.record(.text("both"), source: nil))
        store.toggleFavorite(id: both.id)

        #expect(await store.unlock(storage: environment.storage, blobs: environment.blobs) == .unlocked)

        #expect(!store.isInMemory && store.canPersist)
        #expect(store.history.items.count == 4)
        let merged = try #require(store.history.items.first { $0.text == "both" })
        // M1：沿用内存中的 id
        #expect(merged.id == both.id && merged.isFavorite && merged.createdAt == Fixtures.baseDate)
        #expect(store.replacedItemIDs == [duplicate.id: both.id])
        let movedImage = try #require(store.history.items.first { $0.kind == .image })
        let imageName = try #require(movedImage.image?.name)
        #expect(imageName == environment.blobs.name(kind: .image, contentHash: try digest(of: image)))
        #expect(store.imageData(for: movedImage) != nil)
        #expect(environment.blobs.exists(environment.blobs.thumbnailName(forImage: imageName)))
        let rich = try #require(store.history.items.first { $0.text == "rich" })
        #expect(store.formats(for: rich) == Fixtures.richFormats(for: "rich"))
        #expect(environment.encryptedFileNames.count == 3)
        #expect(try environment.storage.load() == store.history)
    }

    @Test("H1：解锁合并不按上限裁剪（晾衣绳的保护在内存模式下不可靠），磁盘与内存条目全部保留")
    func unlockMergeDoesNotTrim() async throws {
        let environment = try VaultEnvironment()
        defer { environment.remove() }
        let items = (0..<5).map {
            Fixtures.text("disk \($0)", at: Fixtures.baseDate.addingTimeInterval(Double(-60 - $0)))
        }
        try environment.storage.save(ClipHistory(items: items))

        let store = ClipStore(inMemoryWithLimit: 2, now: { Fixtures.baseDate })
        store.record(.text("memory"), source: nil)
        _ = await store.unlock(storage: environment.storage, blobs: environment.blobs)

        #expect(store.history.items.count == 6)
        #expect(try environment.storage.load().items.count == 6)
    }

    @Test("M1：内存条目与磁盘条目重复时沿用内存中的 id（地址守护、进行中的翻译、选中项都按它持有），并报告被替换的 id")
    func unlockKeepsInMemoryIDs() async throws {
        let environment = try VaultEnvironment()
        defer { environment.remove() }
        let disk = Fixtures.text("same", at: Fixtures.baseDate.addingTimeInterval(-60))
        try environment.storage.save(ClipHistory(items: [disk]))

        let store = ClipStore(inMemoryWithLimit: 10, now: { Fixtures.baseDate })
        // 地址守护把被替换进来的条目按这个 id 禁止粘贴
        let blocked = try #require(store.record(.text("same"), source: nil))
        _ = await store.unlock(storage: environment.storage, blobs: environment.blobs)

        #expect(store.history.items.map(\.id) == [blocked.id])
        #expect(store.item(id: blocked.id) != nil)
        #expect(store.replacedItemIDs == [disk.id: blocked.id])
        #expect(try environment.storage.load().items.map(\.id) == [blocked.id])
    }

    @Test("H3：启动前的步骤已发现历史损坏（移入了 Backups）：解锁按「从损坏中恢复」处理，本次不清理文件")
    func unlockWithKnownCorruptionSkipsCleanup() async throws {
        let environment = try VaultEnvironment()
        defer { environment.remove() }
        let orphan = environment.blobs.name(kind: .image, contentHash: "only-in-backup")
        try environment.blobs.write(Data("o".utf8), name: orphan)
        let backup = environment.vault.backupsDirectory.appendingPathComponent("history.corrupt-1-x.cubby")

        let store = ClipStore(inMemoryWithLimit: 10)
        _ = await store.unlock(storage: environment.storage, blobs: environment.blobs, knownCorruption: backup)

        #expect(store.loadIssue == .restoredFromCorruption(backupURL: backup))
        #expect(environment.blobs.exists(orphan))
        #expect(store.canPersist)
    }

    @Test("M3：解锁进行中（后台读写期间）新记录、删除与收藏都不丢，最终写进加密历史")
    func mutationsDuringUnlockAreKept() async throws {
        let environment = try VaultEnvironment()
        defer { environment.remove() }
        try environment.storage.save(
            ClipHistory(items: [Fixtures.text("disk", at: Fixtures.baseDate.addingTimeInterval(-60))]))
        let store = ClipStore(inMemoryWithLimit: 10, now: { Fixtures.baseDate })
        let removed = try #require(store.record(.text("removed later"), source: nil))
        let starred = try #require(store.record(.text("starred later"), source: nil))

        let gated = GatedLoadStorage(environment.storage)
        let unlocking = Task { await store.unlock(storage: gated, blobs: environment.blobs) }
        // 等后台开始读取（快照已取），这些变化确定发生在后台读写期间、切换之前
        await gated.waitUntilLoading()
        store.remove(id: removed.id)
        store.toggleFavorite(id: starred.id)
        let late = try #require(store.record(.image(png: Data("late".utf8), width: 4, height: 4), source: nil))
        let background = store.recordInBackground(.text("background"), source: nil)
        gated.release()
        _ = await unlocking.value
        _ = await background.value
        store.flush()

        let texts = Set(store.history.items.compactMap(\.text))
        #expect(texts == ["disk", "starred later", "background"])
        #expect(store.item(id: starred.id)?.isFavorite == true)
        let image = try #require(store.history.items.first { $0.kind == .image })
        #expect(image.id == late.id)
        #expect(store.imageData(for: image) == Data("late".utf8))
        #expect(try environment.storage.load() == store.history)
    }

    @Test("内存里没有新条目：解锁不裁剪、不重写磁盘上的历史（与旧版本启动时一样，上限在下次记录时才生效）")
    func unlockWithoutIncomingKeepsHistory() async throws {
        let environment = try VaultEnvironment()
        defer { environment.remove() }
        let items = (0..<5).map { Fixtures.text("item \($0)", at: Fixtures.baseDate.addingTimeInterval(Double(-$0))) }
        try environment.storage.save(ClipHistory(items: items))
        let modified = try FileManager.default.attributesOfItem(atPath: environment.storage.fileURL.path)

        let store = ClipStore(inMemoryWithLimit: 2)
        #expect(await store.unlock(storage: environment.storage, blobs: environment.blobs) == .unlocked)

        #expect(store.history.items.count == 5)
        let after = try FileManager.default.attributesOfItem(atPath: environment.storage.fileURL.path)
        #expect(modified[.systemFileNumber] as? Int == after[.systemFileNumber] as? Int)
    }

    @Test("解锁后的变化照常写盘，删除照常清理文件")
    func persistsAfterUnlock() async throws {
        let environment = try VaultEnvironment()
        defer { environment.remove() }
        let store = ClipStore(inMemoryWithLimit: 10, now: { Fixtures.baseDate })
        await store.unlock(storage: environment.storage, blobs: environment.blobs)

        let item = try #require(store.record(bigImage(2), source: nil))
        store.flush()
        #expect(try environment.storage.load().items.map(\.id) == [item.id])
        #expect(environment.encryptedFileNames.count == 2)
        store.remove(id: item.id)
        store.discardUndo()
        store.flush()
        #expect(environment.encryptedFileNames.isEmpty)
    }

    @Test("解锁前在准备中的后台记录：入历史时按加密名写入 Vault")
    func backgroundRecordSpanningUnlock() async throws {
        let environment = try VaultEnvironment()
        defer { environment.remove() }
        let store = ClipStore(inMemoryWithLimit: 10, now: { Fixtures.baseDate })
        let recording = store.recordInBackground(bigImage(3), source: nil)
        await store.unlock(storage: environment.storage, blobs: environment.blobs)

        let item = try #require(await recording.value)
        let name = try #require(item.image?.name)
        #expect(InMemoryClipBlobStore.parse(name) == nil)
        #expect(environment.blobs.exists(name))
        #expect(environment.blobs.exists(environment.blobs.thumbnailName(forImage: name)))
    }

    @Test("解锁时待撤销的删除一并搬进 Vault，撤销后能读出图片")
    func pendingRemovalSurvivesUnlock() async throws {
        let environment = try VaultEnvironment()
        defer { environment.remove() }
        let store = ClipStore(inMemoryWithLimit: 10, now: { Fixtures.baseDate })
        let item = try #require(store.record(smallImage("undo"), source: nil))
        store.remove(id: item.id)
        await store.unlock(storage: environment.storage, blobs: environment.blobs)

        let restored = try #require(store.undoRemove())
        #expect(store.imageData(for: restored) == Data("png-undo".utf8))
    }

    @Test("加密历史来自更新版本：保持内存模式，不写盘")
    func unlockReadOnlyStaysInMemory() async throws {
        let environment = try VaultEnvironment()
        defer { environment.remove() }
        let storage = InMemoryHistoryStorage(loadError: HistoryStorageError.unsupportedVersion(found: 99))
        let store = ClipStore(inMemoryWithLimit: 10)
        store.record(.text("kept"), source: nil)

        #expect(await store.unlock(storage: storage, blobs: environment.blobs) == .readOnly)
        #expect(store.isInMemory && !store.canPersist)
        #expect(store.loadIssue == .newerVersion(99))
        #expect(store.history.items.map(\.text) == ["kept"])
        #expect(storage.savedSnapshots.isEmpty)
        #expect(TempDirectory.fileNames(in: environment.root).isEmpty)
    }

    @Test("已经写盘时再解锁：什么也不做")
    func unlockWhenPersistent() async throws {
        let environment = try VaultEnvironment()
        defer { environment.remove() }
        let store = ClipStore(storage: environment.storage, blobs: environment.blobs, limit: 10)
        #expect(await store.unlock(storage: environment.storage, blobs: environment.blobs) == .alreadyPersistent)
    }

    @Test("合并后的历史保存失败：照常切换，但本次运行不清理磁盘上的文件")
    func unlockSaveFailureSkipsCleanup() async throws {
        let environment = try VaultEnvironment()
        defer { environment.remove() }
        let orphan = environment.blobs.name(kind: .image, contentHash: "orphan")
        try environment.blobs.write(Data("o".utf8), name: orphan)
        let store = ClipStore(inMemoryWithLimit: 10)
        store.record(.text("x"), source: nil)

        #expect(
            await store.unlock(storage: FlakyHistoryStorage(failures: 1), blobs: environment.blobs)
                == .unlockedWithoutSaving)
        #expect(environment.blobs.exists(orphan))
        #expect(store.canPersist && !store.isInMemory)
    }

    @Test("解锁成功后才清理孤儿文件；内存存储随之清空")
    func unlockCleansOrphansAfterSave() async throws {
        let environment = try VaultEnvironment()
        defer { environment.remove() }
        let orphan = environment.blobs.name(kind: .image, contentHash: "orphan")
        try environment.blobs.write(Data("o".utf8), name: orphan)
        let store = ClipStore(inMemoryWithLimit: 10)
        store.record(smallImage("m"), source: nil)
        let memory = try #require(store.blobs as? InMemoryClipBlobStore)

        await store.unlock(storage: environment.storage, blobs: environment.blobs)
        #expect(!environment.blobs.exists(orphan))
        #expect(memory.names.isEmpty)
        #expect(environment.encryptedFileNames.count == 1)
    }

    @Test("内存文件丢失的条目在搬迁时按启动修复的规则丢弃")
    func transferDropsMissing() async throws {
        let environment = try VaultEnvironment()
        defer { environment.remove() }
        let memory = InMemoryClipBlobStore()
        let lost = Fixtures.image(name: memory.name(kind: .image, contentHash: "lost"))
        let logger = Logger(subsystem: "test", category: "test")
        #expect(ClipStore.transfer(lost, from: memory, to: environment.blobs, logger: logger) == nil)
        let text = Fixtures.text("plain")
        #expect(ClipStore.transfer(text, from: memory, to: environment.blobs, logger: logger) == text)
    }

    private func digest(of item: ClipItem) throws -> String {
        let name = try #require(item.image?.name)
        return try #require(InMemoryClipBlobStore.parse(name)).contentHash
    }
}

/// 读取在后台开始后阻塞，直到测试放行：把主线程上的变化确定地插进解锁的后台阶段
final class GatedLoadStorage: HistoryPersisting, @unchecked Sendable {
    private let inner: EncryptedHistoryStorage
    private let started = DispatchSemaphore(value: 0)
    private let gate = DispatchSemaphore(value: 0)

    init(_ inner: EncryptedHistoryStorage) {
        self.inner = inner
    }

    func load() throws -> ClipHistory {
        try loadReportingMigration().history
    }

    func loadReportingMigration() throws -> HistoryMigrator.Outcome {
        started.signal()
        gate.wait()
        return try inner.loadReportingMigration()
    }

    func save(_ history: ClipHistory) throws {
        try inner.save(history)
    }

    /// 在后台线程上等待，不阻塞主线程
    func waitUntilLoading() async {
        await withCheckedContinuation { continuation in
            DispatchQueue.global().async {
                self.started.wait()
                continuation.resume()
            }
        }
    }

    func release() {
        gate.signal()
    }
}
