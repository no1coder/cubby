import Foundation
import Testing
@testable import CubbyCore

/// 不响应任务取消的慢操作：模拟 ScreenCaptureKit 在权限弹窗期间迟迟不返回
private func uncancellableSleep(_ seconds: Double) async {
    await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
        DispatchQueue.global().asyncAfter(deadline: .now() + seconds) { continuation.resume() }
    }
}

private struct SampleError: Error, Equatable {}

@Suite("CaptureDeadline 超时与取消")
struct CaptureDeadlineTests {
    @Test("操作先完成：返回结果")
    func returnsResult() async throws {
        let value = try await CaptureDeadline.run(.seconds(2)) { 42 }
        #expect(value == 42)
    }

    @Test("操作抛错：原样抛出")
    func propagatesError() async {
        await #expect(throws: SampleError.self) {
            try await CaptureDeadline.run(.seconds(2)) { () async throws -> Int in throw SampleError() }
        }
    }

    @Test("超时：不等待无法取消的操作，立即抛出 TimedOut")
    func timesOutWithoutWaiting() async {
        let clock = ContinuousClock()
        let start = clock.now
        await #expect(throws: CaptureDeadline.TimedOut.self) {
            try await CaptureDeadline.run(.milliseconds(50)) { () async -> Int in
                await uncancellableSleep(5)
                return 1
            }
        }
        // 上限远小于操作本身的 5 s（证明没有等它），又给满载的机器留足余量（并行编译时 1 s 偶发超时）
        #expect(clock.now - start < .seconds(3))
    }

    @Test("超时后取消可取消的操作")
    func cancelsOperationOnTimeout() async {
        let observed = CancellationProbe()
        await #expect(throws: CaptureDeadline.TimedOut.self) {
            try await CaptureDeadline.run(.milliseconds(30)) { () async throws -> Int in
                do {
                    try await Task.sleep(for: .seconds(5))
                } catch {
                    observed.mark()
                    throw error
                }
                return 1
            }
        }
        // 取消是异步传达的，稍等片刻
        for _ in 0..<200 where !observed.isMarked {
            try? await Task.sleep(for: .milliseconds(10))
        }
        #expect(observed.isMarked)
    }

    @Test("外层任务取消：立即抛出 CancellationError")
    func outerCancellation() async {
        let clock = ContinuousClock()
        let start = clock.now
        let task = Task {
            try await CaptureDeadline.run(.seconds(5)) { () async -> Int in
                await uncancellableSleep(5)
                return 1
            }
        }
        try? await Task.sleep(for: .milliseconds(30))
        task.cancel()
        let result = await task.result
        #expect(throws: CancellationError.self) { try result.get() }
        // 上限远小于操作本身的 5 s（证明没有等它），又给满载的机器留足余量（并行编译时 1 s 偶发超时）
        #expect(clock.now - start < .seconds(3))
    }

    @Test("开始前已取消：不执行操作")
    func cancelledBeforeStart() async {
        let observed = CancellationProbe()
        let task = Task {
            // 保证取消先于 run 发生：取消后 sleep 立即返回
            try? await Task.sleep(for: .seconds(5))
            return try await CaptureDeadline.run(.seconds(1)) { () async -> Int in
                observed.mark()
                return 1
            }
        }
        task.cancel()
        let result = await task.result
        #expect(throws: CancellationError.self) { try result.get() }
        #expect(!observed.isMarked)
    }

    @Test("结果与超时几乎同时到达：只恢复一次（重复 200 次不崩溃）")
    func resumesExactlyOnce() async {
        for _ in 0..<200 {
            _ = try? await CaptureDeadline.run(.microseconds(200)) { () async -> Int in
                await uncancellableSleep(0.0002)
                return 1
            }
        }
    }
}

/// 线程安全的一次性标记
private final class CancellationProbe: @unchecked Sendable {
    private let lock = NSLock()
    private var marked = false

    func mark() {
        lock.withLock { marked = true }
    }

    var isMarked: Bool {
        lock.withLock { marked }
    }
}
