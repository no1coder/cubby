import Foundation
import Testing
@testable import CubbyCore

/// ClipStore 的译文操作与译后图片 blob 的生命周期（docs/CLIP-TRANSLATION-DESIGN.md §2.4）
@Suite("ClipStore 译文 setTranslation / clearTranslations / 译后图片", .timeLimit(.minutes(1)))
@MainActor
struct ClipStoreTranslationTests {
    private func image(_ seed: String) -> ClipContent {
        .image(png: Data("png-\(seed)".utf8), width: 8, height: 6)
    }

    private let translatedPNG = Data("translated-png".utf8)
    private var translatedName: String { ContentHasher.sha256(translatedPNG) + ".png" }

    // MARK: - 文本

    @Test("setTranslation 写入、递增 revision 并经合并保存写盘；返回是否已缓存")
    func setPersists() async throws {
        let dir = try TempDirectory.make()
        defer { TempDirectory.remove(dir) }
        let storage = InMemoryHistoryStorage()
        let store = StoreFactory.make(dir: dir, storage: storage)
        let item = try #require(store.record(.text("Hello"), source: nil))
        store.flush()
        let revision = store.revision
        let saves = storage.savedSnapshots.count
        let translation = TranslationFixtures.text()

        #expect(store.setTranslation(translation, for: item.id))
        store.flush()

        #expect(store.item(id: item.id)?.translation(for: "zh-Hans") == translation)
        #expect(store.revision == revision + 1)
        #expect(storage.savedSnapshots.count == saves + 1)
        #expect(storage.lastSaved?.items.first?.translations?.entries == [translation])
    }

    @Test("id 不存在、类型不支持、超过上限或值未变时不写入：不递增 revision、不写盘")
    func setIgnoresInvalid() throws {
        let dir = try TempDirectory.make()
        defer { TempDirectory.remove(dir) }
        let storage = InMemoryHistoryStorage()
        let store = StoreFactory.make(dir: dir, storage: storage)
        let item = try #require(store.record(.text("Hello"), source: nil))
        let link = try #require(store.record(.text("https://example.com"), source: nil))
        let translation = TranslationFixtures.text()
        store.setTranslation(translation, for: item.id)
        store.flush()
        let revision = store.revision
        let saves = storage.savedSnapshots.count

        #expect(!store.setTranslation(TranslationFixtures.text("ja"), for: UUID()))
        #expect(!store.setTranslation(translation, for: link.id))
        #expect(!store.setTranslation(TranslationFixtures.sized("ja", length: 30_001), for: item.id))
        #expect(store.setTranslation(translation, for: item.id))
        store.flush()

        #expect(store.revision == revision)
        #expect(storage.savedSnapshots.count == saves)
    }

    @Test("已删除（待撤销）的条目不写入；撤销后恢复的是删除前的状态")
    func setIgnoresPendingRemoval() throws {
        let dir = try TempDirectory.make()
        defer { TempDirectory.remove(dir) }
        let store = StoreFactory.make(dir: dir)
        let item = try #require(store.record(.text("Hello"), source: nil))
        store.remove(id: item.id)

        #expect(!store.setTranslation(TranslationFixtures.text(), for: item.id))
        let restored = try #require(store.undoRemove())

        #expect(restored.translations == nil)
    }

    @Test("clearTranslations 清除全部并写盘，待撤销的条目一并清除；没有译文时不写盘")
    func clearAll() throws {
        let dir = try TempDirectory.make()
        defer { TempDirectory.remove(dir) }
        let storage = InMemoryHistoryStorage()
        let store = StoreFactory.make(dir: dir, storage: storage)
        let first = try #require(store.record(.text("one"), source: nil))
        let second = try #require(store.record(.text("two"), source: nil))
        store.setTranslation(TranslationFixtures.text(), for: first.id)
        store.setTranslation(TranslationFixtures.text("ja"), for: second.id)
        store.remove(id: second.id)

        store.clearTranslations()
        store.flush()
        let restored = try #require(store.undoRemove())
        store.flush()

        #expect(restored.translations == nil)
        #expect(store.history.items.allSatisfy { $0.translations == nil })
        #expect(storage.lastSaved?.items.count == 2)
        #expect(storage.lastSaved?.items.allSatisfy { $0.translations == nil } == true)

        let revision = store.revision
        let saves = storage.savedSnapshots.count
        store.clearTranslations()
        store.flush()
        #expect(store.revision == revision)
        #expect(storage.savedSnapshots.count == saves)
    }

    // MARK: - 译后图片

    @Test("图片译文：后台写入 PNG（内容哈希命名、0600），缓存里记下文件名；可取得文件地址")
    func imageTranslationWritesBlob() async throws {
        let dir = try TempDirectory.make()
        defer { TempDirectory.remove(dir) }
        let store = StoreFactory.make(dir: dir)
        let item = try #require(await store.recordInBackground(image("a"), source: nil).value)

        let stored = try #require(
            await store.setTranslation(
                TranslationFixtures.image(blob: "ignored.png"), imagePNG: translatedPNG, for: item.id))

        #expect(stored.imageName == translatedName)
        #expect(store.item(id: item.id)?.translation(for: "zh-Hans") == stored)
        #expect(TempDirectory.exists(translatedName, in: dir))
        #expect(try TempDirectory.permissions(of: dir.appendingPathComponent(translatedName)) == 0o600)
        #expect(store.translatedImageURL(for: stored) == dir.appendingPathComponent(translatedName))
        #expect(store.translatedImageURL(for: TranslationFixtures.text()) == nil)
    }

    @Test("图片译文未能缓存（条目已删除、类型不对）时返回 nil，且不留下没有主人的文件")
    func imageTranslationRejectedRemovesBlob() async throws {
        let dir = try TempDirectory.make()
        defer { TempDirectory.remove(dir) }
        let store = StoreFactory.make(dir: dir)
        let text = try #require(store.record(.text("Hello"), source: nil))

        let rejected = await store.setTranslation(
            TranslationFixtures.image(blob: "x.png"), imagePNG: translatedPNG, for: text.id)
        let missing = await store.setTranslation(
            TranslationFixtures.image(blob: "x.png"), imagePNG: translatedPNG, for: UUID())

        #expect(rejected == nil && missing == nil)
        #expect(!TempDirectory.exists(translatedName, in: dir))
    }

    @Test("译后图片写入失败（blob 目录不可用）时返回 nil，缓存不变")
    func imageTranslationWriteFailure() async throws {
        let dir = try TempDirectory.make()
        defer { TempDirectory.remove(dir) }
        let blocked = dir.appendingPathComponent("Images")
        try Data("not a directory".utf8).write(to: blocked)
        let item = Fixtures.image(name: "a.png")
        let store = StoreFactory.make(
            dir: blocked, storage: InMemoryHistoryStorage(initial: ClipHistory(items: [item])))

        let stored = await store.setTranslation(
            TranslationFixtures.image(blob: "x.png"), imagePNG: translatedPNG, for: item.id)

        #expect(stored == nil)
        #expect(store.history.items.allSatisfy { $0.translations == nil })
    }

    @Test("译后图片随条目走：删除后保留以便撤销，撤销后仍在，放弃撤销后删除")
    func imageBlobFollowsItemThroughUndo() async throws {
        let dir = try TempDirectory.make()
        defer { TempDirectory.remove(dir) }
        let store = StoreFactory.make(dir: dir)
        let item = try #require(await store.recordInBackground(image("a"), source: nil).value)
        _ = await store.setTranslation(TranslationFixtures.image(blob: "x"), imagePNG: translatedPNG, for: item.id)

        store.remove(id: item.id)
        #expect(TempDirectory.exists(translatedName, in: dir))
        let restored = try #require(store.undoRemove())
        #expect(restored.translation(for: "zh-Hans")?.imageName == translatedName)
        #expect(TempDirectory.exists(translatedName, in: dir))

        store.remove(id: item.id)
        store.discardUndo()
        #expect(!TempDirectory.exists(translatedName, in: dir))
        #expect(!TempDirectory.exists(item.image?.name ?? "", in: dir))
    }

    @Test("覆盖、淘汰或清除译文时删除旧的译后图片；与其他条目共享的文件保留")
    func replacedImageBlobIsRemoved() async throws {
        let dir = try TempDirectory.make()
        defer { TempDirectory.remove(dir) }
        let store = StoreFactory.make(dir: dir)
        let first = try #require(await store.recordInBackground(image("a"), source: nil).value)
        _ = await store.setTranslation(TranslationFixtures.image(blob: "x"), imagePNG: translatedPNG, for: first.id)
        // 同一张译后图片被「存为新条目」：文件名相同，共享
        let saved = try #require(
            await store.recordInBackground(.image(png: translatedPNG, width: 8, height: 6), source: nil).value)
        #expect(saved.image?.name == translatedName)

        let newer = Data("newer-png".utf8)
        _ = await store.setTranslation(TranslationFixtures.image(blob: "y", at: 5), imagePNG: newer, for: first.id)
        #expect(TempDirectory.exists(translatedName, in: dir))

        store.clearTranslations()
        #expect(!TempDirectory.exists(ContentHasher.sha256(newer) + ".png", in: dir))
        #expect(TempDirectory.exists(translatedName, in: dir))
    }

    @Test("清空历史、按上限裁剪时译后图片随条目删除；清除译文时待撤销条目的译后图片也删除")
    func clearAndTrimRemoveImageBlobs() async throws {
        let dir = try TempDirectory.make()
        defer { TempDirectory.remove(dir) }
        let store = StoreFactory.make(dir: dir, limit: 2)
        let first = try #require(await store.recordInBackground(image("a"), source: nil).value)
        _ = await store.setTranslation(TranslationFixtures.image(blob: "x"), imagePNG: translatedPNG, for: first.id)
        _ = await store.recordInBackground(image("b"), source: nil).value
        _ = await store.recordInBackground(image("c"), source: nil).value
        #expect(store.item(id: first.id) == nil)
        #expect(!TempDirectory.exists(translatedName, in: dir))

        let second = try #require(store.history.items.last)
        let png = Data("second".utf8)
        _ = await store.setTranslation(TranslationFixtures.image(blob: "x"), imagePNG: png, for: second.id)
        store.remove(id: second.id)
        store.clearTranslations()
        #expect(!TempDirectory.exists(ContentHasher.sha256(png) + ".png", in: dir))

        let third = try #require(store.history.items.first)
        _ = await store.setTranslation(TranslationFixtures.image(blob: "x"), imagePNG: png, for: third.id)
        store.clearHistory()
        #expect(!TempDirectory.exists(ContentHasher.sha256(png) + ".png", in: dir))
    }

    // MARK: - 启动

    @Test("启动时译后图片被引用则保留，孤立的删除；缺失的只丢弃该条译文、不删条目，并写回")
    func launchCleanupAndRepair() throws {
        let dir = try TempDirectory.make()
        defer { TempDirectory.remove(dir) }
        let blobs = BlobStore(directory: dir)
        for name in ["a.png", "kept.png", "orphan.png"] {
            try blobs.write(Data(name.utf8), name: name)
        }
        let item = Fixtures.image(name: "a.png", favorite: true).translated(
            TranslationFixtures.image("zh-Hans", blob: "kept.png"), TranslationFixtures.image("ja", blob: "gone.png"))
        let text = Fixtures.text("Hello").translated(TranslationFixtures.text())
        let storage = InMemoryHistoryStorage(initial: ClipHistory(items: [item, text]))

        let store = StoreFactory.make(dir: dir, storage: storage)
        store.flush()

        let repaired = try #require(store.item(id: item.id))
        #expect(repaired.isFavorite && repaired.image?.name == "a.png")
        #expect(repaired.translations?.entries.map(\.target) == ["zh-Hans"])
        #expect(store.item(id: text.id)?.translations == text.translations)
        #expect(TempDirectory.fileNames(in: dir) == ["a.png", "kept.png"])
        #expect(storage.lastSaved == store.history)
    }

    @Test("启动修复：全部译后图片缺失时译文为 nil；富文本格式缺失时译文随格式一起丢弃")
    func repairDropsAllMissing() throws {
        let dir = try TempDirectory.make()
        defer { TempDirectory.remove(dir) }
        try BlobStore(directory: dir).write(Data("a".utf8), name: "a.png")
        let item = Fixtures.image(name: "a.png").translated(TranslationFixtures.image(blob: "gone.png"))
        let rich = Fixtures.text("Rich", formatsName: "gone.formats").translated(TranslationFixtures.text())
        let storage = InMemoryHistoryStorage(initial: ClipHistory(items: [item, rich]))

        let store = StoreFactory.make(dir: dir, storage: storage)

        #expect(store.item(id: item.id)?.translations == nil)
        #expect(store.item(id: rich.id)?.translations == nil)
        #expect(store.item(id: rich.id)?.formatsName == nil)
    }

    @Test("持久化往返：写入译文后重启读回一致")
    func persistsAcrossLaunches() throws {
        let dir = try TempDirectory.make()
        defer { TempDirectory.remove(dir) }
        let fileURL = dir.appendingPathComponent("history.json")
        let images = dir.appendingPathComponent("Images")
        let store = StoreFactory.make(dir: images, storage: JSONHistoryStorage(fileURL: fileURL))
        let item = try #require(store.record(.text("Hello"), source: nil))
        let translation = TranslationFixtures.text(segments: ["\u{4F60}\u{597D}", nil])
        store.setTranslation(translation, for: item.id)
        store.flush()

        let reopened = StoreFactory.make(dir: images, storage: JSONHistoryStorage(fileURL: fileURL))

        #expect(reopened.item(id: item.id)?.translation(for: "zh-Hans") == translation)
    }
}
