import Foundation
import os
@testable import CubbyCore

/// 普通读取错误（非损坏），用于模拟磁盘权限等问题
struct SimulatedLoadError: Error {}

/// 内存中的 HistoryPersisting 假实现；save 在后台队列调用，因此状态用锁保护
final class InMemoryHistoryStorage: HistoryPersisting {
    private struct State: Sendable {
        var saved: [ClipHistory] = []
    }

    private let initial: ClipHistory
    private let loadError: (any Error)?
    /// 模拟读取到的数据格式版本；小于当前版本表示“已在内存中迁移”
    private let sourceVersion: Int
    private let state = OSAllocatedUnfairLock(initialState: State())

    init(
        initial: ClipHistory = .empty,
        loadError: (any Error)? = nil,
        sourceVersion: Int = HistoryMigrator.currentVersion
    ) {
        self.initial = initial
        self.loadError = loadError
        self.sourceVersion = sourceVersion
    }

    func load() throws -> ClipHistory {
        try loadReportingMigration().history
    }

    func loadReportingMigration() throws -> HistoryMigrator.Outcome {
        if let loadError { throw loadError }
        return HistoryMigrator.Outcome(history: initial, sourceVersion: sourceVersion)
    }

    func save(_ history: ClipHistory) throws {
        state.withLock { $0.saved.append(history) }
    }

    /// 已保存的全部快照（按保存顺序）
    var savedSnapshots: [ClipHistory] {
        state.withLock { $0.saved }
    }

    var lastSaved: ClipHistory? {
        savedSnapshots.last
    }
}

/// 首次 save 阻塞直到 release()，用于确定性地制造"保存进行中"的窗口
final class GatedHistoryStorage: HistoryPersisting {
    private let inner = InMemoryHistoryStorage()
    private let started = DispatchSemaphore(value: 0)
    private let gate = DispatchSemaphore(value: 0)
    private let isFirst = OSAllocatedUnfairLock(initialState: true)

    func load() throws -> ClipHistory { .empty }

    func save(_ history: ClipHistory) throws {
        let first = isFirst.withLock { value in
            defer { value = false }
            return value
        }
        if first {
            started.signal()
            gate.wait()
        }
        try inner.save(history)
    }

    /// 等待首次保存开始；超时返回 false（上限只影响失败路径，取得宽一些，慢机器上不误报）
    func waitUntilFirstSaveStarted(timeout seconds: Double = 30) -> Bool {
        started.wait(timeout: .now() + seconds) == .success
    }

    func release() {
        gate.signal()
    }

    var savedSnapshots: [ClipHistory] { inner.savedSnapshots }
}

struct SimulatedSaveError: Error {}

/// 前 failures 次保存抛错，之后正常保存
final class FlakyHistoryStorage: HistoryPersisting {
    private let inner = InMemoryHistoryStorage()
    private let remainingFailures: OSAllocatedUnfairLock<Int>

    init(failures: Int) {
        remainingFailures = OSAllocatedUnfairLock(initialState: failures)
    }

    func load() throws -> ClipHistory { .empty }

    func save(_ history: ClipHistory) throws {
        let shouldFail = remainingFailures.withLock { count in
            guard count > 0 else { return false }
            count -= 1
            return true
        }
        if shouldFail { throw SimulatedSaveError() }
        try inner.save(history)
    }

    var savedSnapshots: [ClipHistory] { inner.savedSnapshots }
}

/// 可手动推进的测试时钟
@MainActor
final class TestClock {
    private(set) var current: Date

    init(start: Date = Fixtures.baseDate) {
        current = start
    }

    func advance(by seconds: TimeInterval) {
        current = current.addingTimeInterval(seconds)
    }

    /// 强引用时钟：ClipStore 持有闭包期间时钟不会被提前释放（时钟不反向引用 store，无循环）
    var now: () -> Date {
        { self.current }
    }
}
