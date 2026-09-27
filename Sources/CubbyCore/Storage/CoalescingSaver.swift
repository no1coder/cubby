import Foundation
import os

/// 合并保存请求：后台串行写盘，保存进行中收到的多次请求只写最新快照
final class CoalescingSaver: Sendable {
    private let storage: HistoryPersisting
    private let queue = DispatchQueue(label: "io.github.no1coder.Cubby.history-save", qos: .utility)
    private let pending = OSAllocatedUnfairLock<ClipHistory?>(initialState: nil)
    private let logger = Logger(subsystem: "io.github.no1coder.Cubby", category: "ClipStore")

    init(storage: HistoryPersisting) {
        self.storage = storage
    }

    func schedule(_ snapshot: ClipHistory) {
        let wasIdle = pending.withLock { state in
            defer { state = snapshot }
            return state == nil
        }
        guard wasIdle else { return }

        queue.async { [pending, storage, logger] in
            guard
                let latest = pending.withLock({ state in
                    defer { state = nil }
                    return state
                })
            else { return }
            do {
                try storage.save(latest)
            } catch {
                logger.error("Failed to save history: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    /// 阻塞等待所有已排队的保存完成
    func flush() {
        queue.sync {}
    }
}
