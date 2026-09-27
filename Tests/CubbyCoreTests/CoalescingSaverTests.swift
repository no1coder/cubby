import Foundation
import Testing
@testable import CubbyCore

@Suite("CoalescingSaver 合并保存")
struct CoalescingSaverTests {
    private func snapshot(_ label: String) -> ClipHistory {
        ClipHistory(items: [Fixtures.text(label)])
    }

    @Test("单次调度在 flush 后写入")
    func singleSchedule() {
        let storage = InMemoryHistoryStorage()
        let saver = CoalescingSaver(storage: storage)
        let history = snapshot("a")

        saver.schedule(history)
        saver.flush()

        #expect(storage.savedSnapshots == [history])
    }

    @Test("未调度时 flush 立即返回且不写盘")
    func flushWithoutSchedule() {
        let storage = InMemoryHistoryStorage()
        CoalescingSaver(storage: storage).flush()
        #expect(storage.savedSnapshots.isEmpty)
    }

    @Test("保存进行中收到的多次请求只写最新快照")
    func coalescesWhileSaving() {
        let storage = GatedHistoryStorage()
        let saver = CoalescingSaver(storage: storage)
        let first = snapshot("first")
        let middle = (0..<20).map { snapshot("m\($0)") }
        let latest = snapshot("latest")

        saver.schedule(first)
        guard storage.waitUntilFirstSaveStarted() else {
            Issue.record("首次保存未在超时内开始")
            storage.release()
            return
        }
        // 首次保存被阻塞期间连续调度
        middle.forEach(saver.schedule)
        saver.schedule(latest)
        storage.release()
        saver.flush()

        #expect(storage.savedSnapshots == [first, latest])
    }

    @Test("快速连续调度：写入次数不超过调度次数，最后写入的是最新快照，且顺序单调")
    func rapidSchedulesEndWithLatest() throws {
        let storage = InMemoryHistoryStorage()
        let saver = CoalescingSaver(storage: storage)
        let snapshots = (0..<500).map { snapshot("s\($0)") }

        snapshots.forEach(saver.schedule)
        saver.flush()

        let saved = storage.savedSnapshots
        #expect(!saved.isEmpty)
        #expect(saved.count <= snapshots.count)
        #expect(saved.last == snapshots.last)
        let indices = try saved.map { try #require(snapshots.firstIndex(of: $0)) }
        #expect(indices == indices.sorted())
        #expect(Set(indices).count == indices.count)
    }

    @Test("保存失败不影响后续保存")
    func recoversFromSaveError() {
        let storage = FlakyHistoryStorage(failures: 1)
        let saver = CoalescingSaver(storage: storage)

        saver.schedule(snapshot("lost"))
        saver.flush()
        #expect(storage.savedSnapshots.isEmpty)

        let next = snapshot("next")
        saver.schedule(next)
        saver.flush()
        #expect(storage.savedSnapshots == [next])
    }

    @Test("多线程并发调度不丢失最终请求")
    func concurrentSchedules() {
        let storage = InMemoryHistoryStorage()
        let saver = CoalescingSaver(storage: storage)
        let snapshots = (0..<200).map { snapshot("c\($0)") }

        DispatchQueue.concurrentPerform(iterations: snapshots.count) { index in
            saver.schedule(snapshots[index])
        }
        let sentinel = snapshot("sentinel")
        saver.schedule(sentinel)
        saver.flush()

        let saved = storage.savedSnapshots
        #expect(saved.last == sentinel)
        #expect(saved.count <= snapshots.count + 1)
        #expect(saved.allSatisfy { $0 == sentinel || snapshots.contains($0) })
    }

    @Test("flush 之后再次调度会重新写入")
    func schedulesAfterFlush() {
        let storage = InMemoryHistoryStorage()
        let saver = CoalescingSaver(storage: storage)
        let a = snapshot("a")
        let b = snapshot("b")

        saver.schedule(a)
        saver.flush()
        saver.schedule(b)
        saver.flush()

        #expect(storage.savedSnapshots == [a, b])
    }
}
