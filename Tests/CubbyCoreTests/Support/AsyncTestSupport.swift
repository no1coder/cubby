import Foundation
import Testing
import os
@testable import CubbyCore

/// 轮询等待条件成立。条件一成立立即返回，只有失败路径才会用满 timeout，
/// 所以 timeout 取得很宽：CI 上协作线程池被占满时，异步工作晚几秒才排上是常态，不能因此误报。
/// 被取消（超出套件的 timeLimit）时停止等待，由调用方的后续断言报错
func waitUntil(
    _ description: Comment,
    timeout: Duration = .seconds(30),
    isolation: isolated (any Actor)? = #isolation,
    sourceLocation: SourceLocation = #_sourceLocation,
    _ condition: () async -> Bool
) async {
    let deadline = ContinuousClock.now + timeout
    while !(await condition()) {
        guard ContinuousClock.now < deadline else {
            Issue.record("等待超时：\(description)", sourceLocation: sourceLocation)
            return
        }
        do {
            try await Task.sleep(for: .milliseconds(5))
        } catch {
            Issue.record("等待期间被取消：\(description)", sourceLocation: sourceLocation)
            return
        }
    }
}

/// 一次性闸门：打开后所有等待方继续，之后的 wait 立即返回。
/// wait 不响应任务取消（用来模拟无法取消的系统调用）；给了 fallback 时到时自动打开，
/// 被测代码回归成「一直等它」时测试也能结束并报错，而不是永远挂住
final class Latch: Sendable {
    private struct State {
        var isOpen = false
        var waiters: [CheckedContinuation<Void, Never>] = []
    }

    private let state = OSAllocatedUnfairLock(initialState: State())

    init(fallback: Duration? = nil) {
        guard let fallback else { return }
        let seconds = Double(fallback.components.seconds) + Double(fallback.components.attoseconds) / 1e18
        DispatchQueue.global().asyncAfter(deadline: .now() + seconds) { [weak self] in self?.open() }
    }

    var isOpen: Bool {
        state.withLock { $0.isOpen }
    }

    func open() {
        let waiters = state.withLock { state -> [CheckedContinuation<Void, Never>] in
            state.isOpen = true
            defer { state.waiters = [] }
            return state.waiters
        }
        waiters.forEach { $0.resume() }
    }

    func wait() async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            let resumeNow = state.withLock { state -> Bool in
                guard !state.isOpen else { return true }
                state.waiters.append(continuation)
                return false
            }
            if resumeNow { continuation.resume() }
        }
    }
}

/// 在 GCD 全局队列上执行 CPU 密集的同步工作并等待结果，不占协作线程池。
/// 协作线程池只有 CPU 核数那么宽（CI 为 3）；被长时间占住时，其他测试的异步续体与计时器会晚好几秒才排上。
/// 放到 GCD 后由系统按时间片与测试线程分享 CPU，协作线程随时有空。
/// QoS 与测试相同（default）：若取 utility，CPU 繁忙时这段工作被拖长数倍，更低优先级的后台任务
/// （如缩略图回填）被饿得更久（本地占满全部核心时实测模糊测试从 6 s 拖到 136 s）
func runOffCooperativePool<T: Sendable>(_ work: @escaping @Sendable () -> T) async -> T {
    await withCheckedContinuation { continuation in
        DispatchQueue.global(qos: .default).async { continuation.resume(returning: work()) }
    }
}

/// 手动触发的超时计时器：记录被安排的超时，由测试在确定的时刻触发。
/// 用它断言「超时触发时已经发生了什么」，而不是赌真实时间与线程调度的先后
final class ManualDeadlineTimer: Sendable {
    private struct Scheduled: Sendable {
        let timeout: Duration
        let fire: @Sendable () -> Void
    }

    private let pending = OSAllocatedUnfairLock(initialState: [Scheduled]())

    var timer: DeadlineTimer {
        DeadlineTimer { [pending] timeout, fire in
            pending.withLock { $0.append(Scheduled(timeout: timeout, fire: fire)) }
        }
    }

    /// 已安排、尚未触发的该时长计时器个数
    func scheduledCount(_ timeout: Duration) -> Int {
        pending.withLock { list in list.count { $0.timeout == timeout } }
    }

    /// 触发所有该时长的计时器（在调用方线程上同步执行）
    func fire(_ timeout: Duration) {
        let due = pending.withLock { list -> [Scheduled] in
            let due = list.filter { $0.timeout == timeout }
            list.removeAll { $0.timeout == timeout }
            return due
        }
        due.forEach { $0.fire() }
    }
}
