import CoreGraphics
import Foundation
import Testing
@testable import CubbyCore

/// 截图会话状态机的基于性质的模糊测试
///
/// 固定种子（SplitMix64）生成覆盖全部 `ScreenshotEvent` 的随机序列，坐标偏向屏幕边缘、两屏交界、负坐标、
/// 屏幕间空隙、窗口边缘与小数坐标；每一步之后检查 `ReducerInvariant` 的全部不变量。
/// 发现违反时自动缩减为最小序列并以 Swift 代码报告，便于固化为回归测试（见 ReducerFuzzRegressionTests）。
///
/// 默认 2048 个种子 × 200 步，分 16 片并行；设置环境变量 `CUBBY_FUZZ_SEEDS` 可放大种子数做深度模糊。
@Suite("ScreenshotReducer · 基于性质的模糊测试")
struct ReducerFuzzTests {
    /// 分片数（Swift Testing 并行执行各分片）
    static let shardCount = 16
    static let defaultSeedCount = 2048

    static var seedCount: Int {
        ProcessInfo.processInfo.environment["CUBBY_FUZZ_SEEDS"].flatMap(Int.init) ?? defaultSeedCount
    }

    @Test("固定种子的随机事件序列：每一步之后全部不变量成立", arguments: 0..<ReducerFuzzTests.shardCount)
    func invariantsHold(shard: Int) async {
        var coverage = FuzzCoverage(enabled: false)
        var failures: [ReducerInvariant: Int] = [:]
        for index in stride(from: shard, to: Self.seedCount, by: Self.shardCount) {
            // 纯 CPU 循环：每个种子后让出协作线程，避免 16 个分片占满线程池、饿死并行运行的计时类测试
            await Task.yield()
            let seed = ReducerFuzzRunner.seed(index)
            let result = ReducerFuzzRunner.run(seed: seed, coverage: &coverage)
            guard let violation = result.violation else { continue }
            failures[violation.invariant, default: 0] += 1
            // 每个不变量只缩减并报告第一次失败，避免系统性问题淹没输出
            if failures[violation.invariant] == 1 {
                let failure = ReducerFuzzRunner.shrink(result.trace, violation: violation, seed: seed)
                Issue.record(Comment(rawValue: FuzzRendering.report(failure)))
            }
        }
        #expect(failures.isEmpty, "failing seeds per invariant: \(failures)")
    }

    /// 实测前 22 个种子即可覆盖全部特征，取 64 留出余量
    @Test("生成器覆盖全部事件、命令、出口，并走到深层状态")
    func generatorCoverage() {
        var coverage = FuzzCoverage(enabled: true)
        for index in 0..<64 {
            _ = ReducerFuzzRunner.run(seed: ReducerFuzzRunner.seed(index), coverage: &coverage)
        }
        let missing = FuzzCoverage.required.subtracting(coverage.features)
        #expect(missing.isEmpty, "never reached: \(missing.sorted())")
    }

    @Test("同一种子生成同一序列（可复现）")
    func deterministic() {
        var coverage = FuzzCoverage(enabled: false)
        for index in [0, 7, 1999] {
            let first = ReducerFuzzRunner.run(seed: ReducerFuzzRunner.seed(index), coverage: &coverage)
            let second = ReducerFuzzRunner.run(seed: ReducerFuzzRunner.seed(index), coverage: &coverage)
            #expect(first.trace.events == second.trace.events)
            #expect(first.trace.start == second.trace.start)
            #expect(first.trace.topologyIndex == second.trace.topologyIndex)
        }
    }

    @Test("SplitMix64 与参考实现一致")
    func splitMixReference() {
        var rng = FuzzRandom(seed: 0)
        #expect(rng.next() == 0xE220_A839_7B1D_CDAF)
        #expect(rng.next() == 0x6E78_9E6A_A1B9_65F4)
        var bounded = FuzzRandom(seed: 42)
        #expect((0..<1000).allSatisfy { _ in (0..<7).contains(bounded.int(below: 7)) })
        #expect((0..<1000).allSatisfy { _ in (0..<1).contains(bounded.unit()) })
    }

    @Test("渲染的字符串字面量不含非 ASCII 字符")
    func renderingEscapesNonASCII() {
        let rendered = FuzzRendering.swift("a\u{4F60}\"\n\u{1F600}")
        #expect(rendered == "\"a\\u{4F60}\\\"\\n\\u{1F600}\"")
        #expect(rendered.unicodeScalars.allSatisfy { $0.isASCII })
    }
}
