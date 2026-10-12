import Foundation
import Testing
@testable import CubbyCore

/// ClipStore 的裁剪保护：protectedIDs（晾衣绳上的条目）不被上限裁掉；显式删除与清空不受影响
@Suite("ClipStore 裁剪保护")
@MainActor
struct ClipStoreProtectionTests {
    private func imageContent(_ seed: String) -> ClipContent {
        .image(png: Data("fake-png-\(seed)".utf8), width: 8, height: 6)
    }

    @Test("默认没有受保护的条目")
    func defaultIsEmpty() throws {
        let dir = try TempDirectory.make()
        defer { TempDirectory.remove(dir) }
        #expect(StoreFactory.make(dir: dir).protectedIDs.isEmpty)
    }

    @Test("记录新内容时受保护的图片不被挤出，文件也保留")
    func recordKeepsProtected() throws {
        let dir = try TempDirectory.make()
        defer { TempDirectory.remove(dir) }

        let store = StoreFactory.make(dir: dir, limit: 1)
        let image = try #require(store.record(imageContent("hung"), source: nil))
        let url = try #require(store.imageURL(for: image))
        store.protectedIDs = [image.id]

        store.record(.text("a"), source: nil)
        store.record(.text("b"), source: nil)

        // 上限 1 只算未受保护的条目：a 被挤出，图片留下
        #expect(store.history.items.map(\.id).last == image.id)
        #expect(store.history.items.map(\.text) == ["b", nil])
        #expect(FileManager.default.fileExists(atPath: url.path))
    }

    @Test("后台记录同样遵守保护")
    func backgroundRecordKeepsProtected() async throws {
        let dir = try TempDirectory.make()
        defer { TempDirectory.remove(dir) }

        let store = StoreFactory.make(dir: dir, limit: 1)
        let pinned = try #require(store.record(.text("pinned"), source: nil))
        store.protectedIDs = [pinned.id]

        _ = await store.recordInBackground(.text("later"), source: nil).value

        #expect(store.history.items.map(\.text) == ["later", "pinned"])
    }

    @Test("setLimit 裁剪时跳过受保护的条目")
    func setLimitKeepsProtected() throws {
        let dir = try TempDirectory.make()
        defer { TempDirectory.remove(dir) }

        let store = StoreFactory.make(dir: dir, limit: 10)
        let first = try #require(store.record(.text("t0"), source: nil))
        for index in 1..<5 {
            store.record(.text("t\(index)"), source: nil)
        }
        store.protectedIDs = [first.id]

        store.setLimit(2)

        #expect(store.history.items.map(\.text) == ["t4", "t3", "t0"])
    }

    @Test("设置 protectedIDs 本身不裁剪、不保存；取消保护后下次裁剪才移除")
    func settingDoesNotTrimOrSave() throws {
        let dir = try TempDirectory.make()
        defer { TempDirectory.remove(dir) }

        let storage = InMemoryHistoryStorage()
        let store = StoreFactory.make(dir: dir, storage: storage, limit: 1)
        let pinned = try #require(store.record(.text("pinned"), source: nil))
        store.protectedIDs = [pinned.id]
        store.record(.text("newer"), source: nil)
        store.flush()
        let saves = storage.savedSnapshots.count
        let revision = store.revision

        store.protectedIDs = []
        store.flush()

        #expect(store.history.items.map(\.text) == ["newer", "pinned"])
        #expect(storage.savedSnapshots.count == saves)
        #expect(store.revision == revision)

        store.record(.text("newest"), source: nil)
        #expect(store.history.items.map(\.text) == ["newest"])
    }

    @Test("显式删除受保护的条目照常生效，并可撤销")
    func removeStillWorks() throws {
        let dir = try TempDirectory.make()
        defer { TempDirectory.remove(dir) }

        let store = StoreFactory.make(dir: dir)
        let pinned = try #require(store.record(.text("pinned"), source: nil))
        store.protectedIDs = [pinned.id]

        store.remove(id: pinned.id)
        #expect(store.item(id: pinned.id) == nil)

        store.undoRemove()
        #expect(store.item(id: pinned.id) != nil)
    }

    @Test("清空历史只保留收藏：受保护但未收藏的条目也被清掉")
    func clearHistoryIgnoresProtection() throws {
        let dir = try TempDirectory.make()
        defer { TempDirectory.remove(dir) }

        let store = StoreFactory.make(dir: dir)
        let pinned = try #require(store.record(imageContent("pinned"), source: nil))
        let favorite = try #require(store.record(.text("fav"), source: nil))
        store.toggleFavorite(id: favorite.id)
        store.protectedIDs = [pinned.id]

        store.clearHistory()

        #expect(store.history.items.map(\.id) == [favorite.id])
        #expect(TempDirectory.fileNames(in: dir).isEmpty)
    }
}
