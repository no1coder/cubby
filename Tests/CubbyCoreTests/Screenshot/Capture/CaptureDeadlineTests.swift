import Foundation
import Testing
@testable import CubbyCore

private struct SampleError: Error, Equatable {}

/// 这些用例只断言事件的先后，不断言耗时：CI 的协作线程池被 CPU 密集测试占满时，
/// 异步工作可能晚好几秒才排上（实测「立即返回」用了 3–4 s），耗时上限必然误报。
/// 「无法取消的操作」由闸门拦住，只有测试在断言之后放行才会结束（兜底 20 s 自动放行，
/// 被测代码回归成等它结束时，测试也能在套件时限内结束并报错）
@Suite("CaptureDeadline 超时与取消", .timeLimit(.minutes(1)))
struct CaptureDeadlineTests {
    /// 远大于任何调度延迟的超时：用例证明结果 / 错误原样送达，而不是证明它们「够快」。
    /// 原先是 2 s，CI 上操作迟迟排不上线程，GCD 计时器先到而误报 TimedOut
    private static let generous: Duration = .seconds(60)

    @Test("操作先完成：返回结果")
    func returnsResult() async throws {
        let value = try await CaptureDeadline.run(Self.generous) { 42 }
        #expect(value == 42)
    }

    @Test("操作抛错：原样抛出")
    func propagatesError() async {
        await #expect(throws: SampleError.self) {
            try await CaptureDeadline.run(Self.generous) { () async throws -> Int in throw SampleError() }
        }
    }

    @Test("超时：不等待无法取消的操作，立即抛出 TimedOut")
    func timesOutWithoutWaiting() async {
        let release = Latch(fallback: .seconds(20))
        await #expect(throws: CaptureDeadline.TimedOut.self) {
            try await CaptureDeadline.run(.milliseconds(50)) { () async -> Int in
                await release.wait()
                return 1
            }
        }
        // 操作仍被拦着时 run 已经抛出：证明没有等它（原先断言耗时 < 3 s，CI 实测 3.07 s 误报）
        #expect(!release.isOpen)
        release.open()
    }

    @Test("超时后取消可取消的操作")
    func cancelsOperationOnTimeout() async {
        let cancelled = Latch()
        await #expect(throws: CaptureDeadline.TimedOut.self) {
            try await CaptureDeadline.run(.milliseconds(30)) { () async throws -> Int in
                do {
                    try await Task.sleep(for: Self.generous)
                } catch {
                    cancelled.open()
                    throw error
                }
                return 1
            }
        }
        // 取消是异步传达的：一直等到操作观察到取消（原先只等 2 s，线程池繁忙时不够）
        await waitUntil("操作收到取消") { cancelled.isOpen }
    }

    @Test("外层任务取消：立即抛出 CancellationError")
    func outerCancellation() async {
        let started = Latch()
        let release = Latch(fallback: .seconds(20))
        let task = Task {
            try await CaptureDeadline.run(Self.generous) { () async -> Int in
                started.open()
                await release.wait()
                return 1
            }
        }
        // 确认操作已在执行（run 正在等待）后再取消外层任务。原先固定睡 30 ms：线程池繁忙时可能在 run
        // 开始之前就取消，测到的是另一条路径；并断言耗时 < 3 s，CI 实测 3.98 s 误报
        await waitUntil("操作开始执行") { started.isOpen }
        task.cancel()
        let result = await task.result
        #expect(throws: CancellationError.self) { try result.get() }
        // 操作仍被拦着时外层已经拿到 CancellationError：证明没有等它
        #expect(!release.isOpen)
        release.open()
    }

    @Test("开始前已取消：不执行操作")
    func cancelledBeforeStart() async {
        let observed = Latch()
        let task = Task {
            // 保证取消先于 run 发生：取消后 sleep 立即返回
            try? await Task.sleep(for: Self.generous)
            return try await CaptureDeadline.run(.seconds(1)) { () async -> Int in
                observed.open()
                return 1
            }
        }
        task.cancel()
        let result = await task.result
        #expect(throws: CancellationError.self) { try result.get() }
        #expect(!observed.isOpen)
    }

    @Test("结果与超时几乎同时到达：只恢复一次（重复 200 次不崩溃）")
    func resumesExactlyOnce() async {
        for _ in 0..<200 {
            _ = try? await CaptureDeadline.run(.microseconds(200)) { () async -> Int in
                await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                    DispatchQueue.global().asyncAfter(deadline: .now() + 0.0002) { continuation.resume() }
                }
                return 1
            }
        }
    }

    @Test("注入的计时器：触发之前不超时；触发后立即抛出 TimedOut 并取消操作")
    func injectedTimerDecidesWhenToTimeOut() async {
        let clock = ManualDeadlineTimer()
        let started = Latch()
        let cancelled = Latch()
        let finished = Latch()
        let task = Task {
            defer { finished.open() }
            return try await CaptureDeadline.run(.milliseconds(1), timer: clock.timer) { () async throws -> Int in
                started.open()
                do {
                    try await Task.sleep(for: Self.generous)
                } catch {
                    cancelled.open()
                    throw error
                }
                return 1
            }
        }
        await waitUntil("操作开始执行，计时器已安排") { started.isOpen && clock.scheduledCount(.milliseconds(1)) == 1 }
        // 真实时间早已超过 1 ms（sleep 只会晚、不会早），但计时器没触发，run 仍在等待
        try? await Task.sleep(for: .milliseconds(20))
        #expect(!finished.isOpen)
        #expect(!cancelled.isOpen)
        clock.fire(.milliseconds(1))
        await #expect(throws: CaptureDeadline.TimedOut.self) { try await task.value }
        await waitUntil("操作收到取消") { cancelled.isOpen }
    }
}
