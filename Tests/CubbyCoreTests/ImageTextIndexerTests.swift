import Foundation
import Testing
@testable import CubbyCore

/// 可控的假识别器：按文件名返回结果；开启闸门时每次调用挂起，直到测试放行。记录调用顺序与最大并发
actor FakeImageTextRecognizer: ImageTextRecognizing {
    private var results: [String: Result<String, any Error>] = [:]
    private var gates: [CheckedContinuation<Void, Never>] = []
    private var concurrent = 0
    private(set) var calls: [String] = []
    private(set) var maxConcurrent = 0
    private(set) var maxPixelSizes: [Int?] = []
    var isGated = false

    func setResult(_ result: Result<String, any Error>, for name: String) {
        results[name] = result
    }

    func setGated(_ gated: Bool) {
        isGated = gated
    }

    /// 放行最早挂起的一次调用；没有挂起的调用时返回 false
    func releaseOne() -> Bool {
        guard !gates.isEmpty else { return false }
        gates.removeFirst().resume()
        return true
    }

    var waitingCount: Int {
        gates.count
    }

    func recognizeText(at url: URL, maxPixelSize: Int?) async throws -> String {
        let name = url.lastPathComponent
        calls.append(name)
        maxPixelSizes.append(maxPixelSize)
        concurrent += 1
        maxConcurrent = max(maxConcurrent, concurrent)
        if isGated {
            await withCheckedContinuation { gates.append($0) }
        }
        concurrent -= 1
        return try (results[name] ?? .success("text of \(name)")).get()
    }
}

struct SimulatedRecognitionError: Error {}

/// ImageTextIndexer 的执行：回填顺序、串行、批量写盘、暂停 / 关闭 / 停止时的行为
@Suite("ImageTextIndexer 执行", .serialized)
@MainActor
struct ImageTextIndexerTests {
    /// 测试环境：独立的偏好、临时 blob 目录、内存存储
    @MainActor
    final class Harness {
        let dir: URL
        let suiteName = "cubby-indexer-\(UUID().uuidString)"
        let defaults: UserDefaults
        let settings: AppSettings
        let storage: InMemoryHistoryStorage
        let store: ClipStore
        let recognizer = FakeImageTextRecognizer()
        private(set) var indexer: ImageTextIndexer?

        init(initial: ClipHistory = .empty, storeNow: @escaping () -> Date = { Fixtures.baseDate }) throws {
            dir = try TempDirectory.make()
            defaults = UserDefaults(suiteName: suiteName) ?? .standard
            settings = AppSettings(defaults: defaults)
            storage = InMemoryHistoryStorage(initial: initial)
            store = StoreFactory.make(dir: dir, storage: storage, limit: 100, now: storeNow)
        }

        func start(schedule: ImageTextIndexSchedule = ImageTextIndexSchedule(startupDelay: 0, backfillInterval: 0)) {
            let indexer = ImageTextIndexer(store: store, settings: settings, recognizer: recognizer, schedule: schedule)
            self.indexer = indexer
            indexer.start()
        }

        /// 记录一张（假）图片，返回条目；blob 文件名即内容哈希
        @discardableResult
        func addImage(_ seed: String, width: Int = 8, height: Int = 6) -> ClipItem? {
            store.record(.image(png: Data("png-\(seed)".utf8), width: width, height: height), source: nil)
        }

        func texts() -> [String?] {
            store.history.items.map(\.recognizedText)
        }

        deinit {
            UserDefaults.standard.removePersistentDomain(forName: suiteName)
            TempDirectory.remove(dir)
        }
    }

    /// 轮询等待条件成立（最多 5 秒）
    private func waitUntil(_ condition: @MainActor () async -> Bool) async throws {
        let deadline = ContinuousClock.now + .seconds(5)
        while !(await condition()) {
            guard ContinuousClock.now < deadline else {
                Issue.record("等待超时")
                return
            }
            try await Task.sleep(for: .milliseconds(5))
        }
    }

    /// 让已排队的主线程任务与后台识别跑一会儿
    private func settle() async throws {
        try await Task.sleep(for: .milliseconds(60))
    }

    @Test("回填按历史顺序（最新在前）串行识别，写回时去空白、过滤密钥，并持久化")
    func backfillInHistoryOrder() async throws {
        let harness = try Harness()
        let first = try #require(harness.addImage("a"))
        let second = try #require(harness.addImage("b"))
        let third = try #require(harness.addImage("c"))
        await harness.recognizer.setResult(.success("  Hello A \n"), for: try #require(first.image?.name))
        await harness.recognizer.setResult(
            .success("key " + FakeSecrets.github()), for: try #require(second.image?.name))

        harness.start()
        try await waitUntil { harness.texts().allSatisfy { $0 != nil } }
        harness.store.flush()

        let names = [third, second, first].compactMap { $0.image?.name }
        #expect(await harness.recognizer.calls == names)
        #expect(await harness.recognizer.maxConcurrent == 1)
        #expect(harness.store.item(id: first.id)?.recognizedText == "Hello A")
        #expect(harness.store.item(id: second.id)?.recognizedText == "")
        #expect(harness.store.item(id: third.id)?.recognizedText == "text of \(names[0])")
        #expect(harness.storage.lastSaved?.items.allSatisfy { $0.recognizedText != nil } == true)
    }

    @Test("文本与已识别的图片不识别；识别失败的条目本次运行不再重试")
    func skipsNonImagesAndFailures() async throws {
        let harness = try Harness()
        harness.store.record(.text("plain"), source: nil)
        let broken = try #require(harness.addImage("broken"))
        let done = try #require(harness.addImage("done"))
        harness.store.setRecognizedText("already", for: done.id)
        let fine = try #require(harness.addImage("fine"))
        await harness.recognizer.setResult(.failure(SimulatedRecognitionError()), for: try #require(broken.image?.name))

        harness.start()
        try await waitUntil { harness.store.item(id: fine.id)?.recognizedText != nil }
        try await settle()

        #expect(await harness.recognizer.calls == [fine, broken].compactMap { $0.image?.name })
        #expect(harness.store.item(id: broken.id)?.recognizedText == nil)
        #expect(harness.store.item(id: done.id)?.recognizedText == "already")
    }

    @Test("新图片入历史后立即识别；超大图片先缩放")
    func newImagesAreIndexedPromptly() async throws {
        let harness = try Harness(storeNow: Date.init)
        harness.start(schedule: .standard)
        try await settle()
        #expect(await harness.recognizer.calls.isEmpty)

        let item = try #require(harness.addImage("fresh", width: 7000, height: 5000))
        try await waitUntil { harness.store.item(id: item.id)?.recognizedText != nil }

        #expect(await harness.recognizer.maxPixelSizes == [3407])
    }

    @Test("暂停记录：停止识别，进行中的结果照常保存；恢复后继续")
    func pauseAndResume() async throws {
        let harness = try Harness()
        let older = try #require(harness.addImage("older"))
        let newer = try #require(harness.addImage("newer"))
        await harness.recognizer.setGated(true)
        harness.start()
        try await waitUntil { await harness.recognizer.waitingCount == 1 }

        harness.settings.isPaused = true
        try await settle()
        #expect(await harness.recognizer.releaseOne())
        try await waitUntil { harness.store.item(id: newer.id)?.recognizedText != nil }
        try await settle()
        #expect(await harness.recognizer.calls.count == 1)

        await harness.recognizer.setGated(false)
        harness.settings.isPaused = false
        try await waitUntil { harness.store.item(id: older.id)?.recognizedText != nil }
        #expect(await harness.recognizer.calls.count == 2)
    }

    @Test("关闭开关：丢弃进行中的结果，清除全部识别文字并写盘；重新开启后重新回填")
    func disableClearsAndReenableRefills() async throws {
        let harness = try Harness()
        let older = try #require(harness.addImage("older"))
        let newer = try #require(harness.addImage("newer"))
        harness.store.setRecognizedText("stale", for: newer.id)
        await harness.recognizer.setGated(true)
        harness.start()
        try await waitUntil { await harness.recognizer.waitingCount == 1 }

        harness.settings.indexesImageText = false
        try await settle()
        #expect(await harness.recognizer.releaseOne())
        try await settle()
        harness.store.flush()
        #expect(harness.texts() == [nil, nil])
        #expect(harness.storage.lastSaved?.items.allSatisfy { $0.recognizedText == nil } == true)

        await harness.recognizer.setGated(false)
        harness.settings.indexesImageText = true
        try await waitUntil { harness.texts().allSatisfy { $0 != nil } }
        #expect(harness.store.item(id: older.id)?.recognizedText != nil)
    }

    @Test("启动时开关已关闭：清除残留的识别文字，不识别")
    func startsDisabled() async throws {
        let harness = try Harness()
        let item = try #require(harness.addImage("a"))
        harness.store.setRecognizedText("left over", for: item.id)
        harness.settings.indexesImageText = false

        harness.start()
        try await settle()

        #expect(harness.texts() == [nil])
        #expect(await harness.recognizer.calls.isEmpty)
    }

    @Test("stop 后不再识别，进行中的结果丢弃")
    func stopDiscardsInFlight() async throws {
        let harness = try Harness()
        harness.addImage("a")
        harness.addImage("b")
        await harness.recognizer.setGated(true)
        harness.start()
        try await waitUntil { await harness.recognizer.waitingCount == 1 }

        harness.indexer?.stop()
        #expect(await harness.recognizer.releaseOne())
        harness.addImage("c")
        try await settle()

        #expect(harness.texts().allSatisfy { $0 == nil })
        #expect(await harness.recognizer.calls.count == 1)
    }

    @Test("历史只读（来自更新版本的文件）时不索引")
    func readOnlyStoreIsNotIndexed() async throws {
        let dir = try TempDirectory.make()
        defer { TempDirectory.remove(dir) }
        let fileURL = dir.appendingPathComponent("history.json")
        try HistoryFixtures.write(HistoryFixtures.v99JSON, to: fileURL)
        let store = StoreFactory.make(dir: dir, storage: JSONHistoryStorage(fileURL: fileURL))
        let recognizer = FakeImageTextRecognizer()
        try await withIsolatedDefaultsAsync { defaults in
            let indexer = ImageTextIndexer(
                store: store, settings: AppSettings(defaults: defaults), recognizer: recognizer)
            indexer.start()
            try await settle()
        }
        #expect(!store.canPersist)
        #expect(await recognizer.calls.isEmpty)
    }

    @Test("回填结果按批合并写盘，而不是每张图片重写一次历史")
    func backfillIsBatched() async throws {
        let harness = try Harness()
        for index in 0..<20 { harness.addImage("img-\(index)") }
        harness.store.flush()
        let savesBefore = harness.storage.savedSnapshots.count
        let revisionBefore = harness.store.revision

        harness.start()
        try await waitUntil { harness.texts().allSatisfy { $0 != nil } }
        harness.store.flush()

        #expect(harness.store.revision - revisionBefore <= 3)
        #expect(harness.storage.savedSnapshots.count - savesBefore <= 3)
    }
}

/// 异步版的独立 UserDefaults 域
@MainActor
func withIsolatedDefaultsAsync(_ body: (UserDefaults) async throws -> Void) async rethrows {
    let suiteName = "cubby-test-\(UUID().uuidString)"
    guard let defaults = UserDefaults(suiteName: suiteName) else {
        Issue.record("无法创建独立的 UserDefaults")
        return
    }
    defer { defaults.removePersistentDomain(forName: suiteName) }
    try await body(defaults)
}
