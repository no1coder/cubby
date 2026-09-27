import Foundation
import Testing
@testable import CubbyCore

/// ClipHistory / ClipStore 的识别文字更新与清除
@Suite("ClipStore 识别文字 setRecognizedText / clearRecognizedText", .timeLimit(.minutes(1)))
@MainActor
struct ClipStoreRecognizedTextTests {
    private func image(_ seed: String) -> ClipContent {
        .image(png: Data("png-\(seed)".utf8), width: 8, height: 6)
    }

    // MARK: - ClipHistory

    @Test("settingRecognizedText 只更新目标图片，返回新实例且不修改原值")
    func historySettingIsNonMutating() {
        let first = Fixtures.image(name: "a.png")
        let second = Fixtures.image(name: "b.png")
        let history = ClipHistory(items: [first, second])

        let updated = history.settingRecognizedText("hello", for: second.id)

        #expect(history.items.allSatisfy { $0.recognizedText == nil })
        #expect(updated.items.map(\.recognizedText) == [nil, "hello"])
        #expect(updated.items.map(\.id) == history.items.map(\.id))
    }

    @Test("settingRecognizedText：id 不存在、不是图片或值未变时原样返回")
    func historySettingIgnoresInvalidTargets() {
        let text = Fixtures.text("plain")
        let recognized = Fixtures.image(name: "a.png").withRecognizedText("same")
        let history = ClipHistory(items: [text, recognized])

        #expect(history.settingRecognizedText("x", for: UUID()) == history)
        #expect(history.settingRecognizedText("x", for: text.id) == history)
        #expect(history.settingRecognizedText("same", for: recognized.id) == history)
    }

    @Test("removingRecognizedText 清除全部；本就没有时原样返回")
    func historyRemovingAll() {
        let history = ClipHistory(items: [
            Fixtures.image(name: "a.png").withRecognizedText("a"),
            Fixtures.image(name: "b.png").withRecognizedText(""),
            Fixtures.text("t"),
        ])
        let cleared = history.removingRecognizedText()
        #expect(cleared.items.allSatisfy { $0.recognizedText == nil })
        #expect(cleared.removingRecognizedText() == cleared)
        #expect(history.items[0].recognizedText == "a")
    }

    @Test("重复记录同一张图片：合并后保留已识别的文字")
    func reinsertKeepsRecognizedText() {
        let existing = Fixtures.image(name: "a.png").withRecognizedText("kept")
        let history = ClipHistory(items: [Fixtures.text("x"), existing])
        let again = Fixtures.image(name: "a.png", at: Fixtures.baseDate.addingTimeInterval(9))

        let merged = history.inserting(again, limit: 10)

        #expect(merged.items.first?.id == existing.id)
        #expect(merged.items.first?.recognizedText == "kept")
    }

    // MARK: - ClipStore

    @Test("setRecognizedText 更新条目、递增 revision 并经合并保存写盘")
    func storeSetPersists() async throws {
        let dir = try TempDirectory.make()
        defer { TempDirectory.remove(dir) }
        let storage = InMemoryHistoryStorage()
        let store = StoreFactory.make(dir: dir, storage: storage)
        let item = try #require(await store.recordInBackground(image("a"), source: nil).value)
        let revision = store.revision

        store.setRecognizedText("Invoice 2026", for: item.id)
        store.flush()

        #expect(store.item(id: item.id)?.recognizedText == "Invoice 2026")
        #expect(store.revision == revision + 1)
        #expect(storage.lastSaved?.items.first?.recognizedText == "Invoice 2026")
    }

    @Test("setRecognizedText：id 不存在或值未变时忽略，不递增 revision、不写盘")
    func storeSetIgnoresUnknownID() async throws {
        let dir = try TempDirectory.make()
        defer { TempDirectory.remove(dir) }
        let storage = InMemoryHistoryStorage()
        let store = StoreFactory.make(dir: dir, storage: storage)
        let item = try #require(await store.recordInBackground(image("a"), source: nil).value)
        store.setRecognizedText("x", for: item.id)
        store.flush()
        let revision = store.revision
        let saves = storage.savedSnapshots.count

        store.setRecognizedText("y", for: UUID())
        store.setRecognizedText("x", for: item.id)
        store.flush()

        #expect(store.revision == revision)
        #expect(storage.savedSnapshots.count == saves)
    }

    @Test("不影响撤销：删除后更新其他条目，撤销仍恢复到原位置")
    func storeSetKeepsUndo() async throws {
        let dir = try TempDirectory.make()
        defer { TempDirectory.remove(dir) }
        let store = StoreFactory.make(dir: dir)
        let first = try #require(await store.recordInBackground(image("a"), source: nil).value)
        let second = try #require(await store.recordInBackground(image("b"), source: nil).value)

        store.remove(id: second.id)
        store.setRecognizedText("first", for: first.id)
        // 已删除（待撤销）的条目不在历史中：忽略
        store.setRecognizedText("gone", for: second.id)
        let restored = try #require(store.undoRemove())

        #expect(restored.id == second.id)
        #expect(restored.recognizedText == nil)
        #expect(store.history.items.map(\.id) == [second.id, first.id])
        #expect(store.item(id: first.id)?.recognizedText == "first")
        #expect(store.imageURL(for: restored).map { FileManager.default.fileExists(atPath: $0.path) } == true)
    }

    @Test("clearRecognizedText 清除全部并写盘，待撤销的条目也一并清除")
    func storeClearAll() async throws {
        let dir = try TempDirectory.make()
        defer { TempDirectory.remove(dir) }
        let storage = InMemoryHistoryStorage()
        let store = StoreFactory.make(dir: dir, storage: storage)
        let first = try #require(await store.recordInBackground(image("a"), source: nil).value)
        let second = try #require(await store.recordInBackground(image("b"), source: nil).value)
        store.setRecognizedText("one", for: first.id)
        store.setRecognizedText("two", for: second.id)
        store.remove(id: second.id)

        store.clearRecognizedText()
        store.flush()
        let restored = try #require(store.undoRemove())
        store.flush()

        #expect(restored.recognizedText == nil)
        #expect(store.history.items.allSatisfy { $0.recognizedText == nil })
        #expect(storage.lastSaved?.items.allSatisfy { $0.recognizedText == nil } == true)
        #expect(storage.lastSaved?.items.count == 2)
    }

    @Test("clearRecognizedText 在没有识别文字时不递增 revision、不写盘")
    func storeClearNoop() async throws {
        let dir = try TempDirectory.make()
        defer { TempDirectory.remove(dir) }
        let storage = InMemoryHistoryStorage()
        let store = StoreFactory.make(dir: dir, storage: storage)
        _ = await store.recordInBackground(image("a"), source: nil).value
        store.flush()
        let revision = store.revision
        let saves = storage.savedSnapshots.count

        store.clearRecognizedText()
        store.flush()

        #expect(store.revision == revision)
        #expect(storage.savedSnapshots.count == saves)
    }

    @Test("启动时从磁盘读到的识别文字原样保留")
    func loadKeepsRecognizedText() throws {
        let dir = try TempDirectory.make()
        defer { TempDirectory.remove(dir) }
        try BlobStore(directory: dir).write(Data("png".utf8), name: "a.png")
        let recognized = Fixtures.image(name: "a.png").withRecognizedText("persisted")
        let storage = InMemoryHistoryStorage(initial: ClipHistory(items: [recognized]))

        let store = StoreFactory.make(dir: dir, storage: storage)

        #expect(store.history.items == [recognized])
    }
}
