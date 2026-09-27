import Foundation
import os

/// 给异步操作加超时（屏幕采集 2 s，设计文档 §2.12、§6 R2）。
///
/// 与 TaskGroup 不同：超时或外层取消后立即返回，不等待不响应取消的系统调用结束
/// （ScreenCaptureKit 在权限确认弹窗期间可能长时间不返回）。结果、超时、外层取消三方竞争，
/// 续体只恢复一次；输家任务随即被取消，不会继续占用资源
public enum CaptureDeadline {
    /// 超时错误
    public struct TimedOut: Error, Equatable, Sendable {
        public init() {}
    }

    public static func run<T: Sendable>(
        _ timeout: Duration,
        _ operation: @escaping @Sendable () async throws -> T
    ) async throws -> T {
        try Task.checkCancellation()
        let gate = ResumeGate()
        let work = Task { try await operation() }
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<T, any Error>) in
                // 计时器走 GCD 而非协作线程池：线程池被 CPU 密集任务占满时，超时仍按时触发。
                // 无需取消：恢复权由 gate 保证唯一，晚到的计时器 claim 失败即返回（至多多持有闭包到超时时刻）
                DispatchQueue.global(qos: .userInitiated).asyncAfter(deadline: .now() + timeout.timeInterval) {
                    guard gate.claim() else { return }
                    work.cancel()
                    continuation.resume(throwing: TimedOut())
                }
                Task {
                    let result = await work.result
                    guard gate.claim() else { return }
                    continuation.resume(with: result)
                }
                gate.onCancel {
                    work.cancel()
                    continuation.resume(throwing: CancellationError())
                }
            }
        } onCancel: {
            gate.cancel()
        }
    }
}

/// 保证续体只被恢复一次：先 claim 成功的一方负责恢复
private final class ResumeGate: Sendable {
    private struct State {
        var isClaimed = false
        var isCancelled = false
        var cancelHandler: (@Sendable () -> Void)?
    }

    private let state = OSAllocatedUnfairLock(initialState: State())

    /// 抢占恢复权；已被抢占时返回 false
    func claim() -> Bool {
        state.withLock { state in
            guard !state.isClaimed else { return false }
            state.isClaimed = true
            return true
        }
    }

    /// 登记外层取消时的处理；若取消已先发生，立即执行（前提是恢复权还在）
    func onCancel(_ handler: @escaping @Sendable () -> Void) {
        let runNow = state.withLock { state -> Bool in
            state.cancelHandler = handler
            return state.isCancelled
        }
        if runNow, claim() { handler() }
    }

    func cancel() {
        let handler = state.withLock { state -> (@Sendable () -> Void)? in
            state.isCancelled = true
            return state.cancelHandler
        }
        if let handler, claim() { handler() }
    }
}

private extension Duration {
    /// 换算为秒（供 GCD 定时使用）
    var timeInterval: TimeInterval {
        let parts = components
        return TimeInterval(parts.seconds) + TimeInterval(parts.attoseconds) / 1e18
    }
}
