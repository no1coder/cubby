import CoreGraphics
@testable import CubbyCore

/// 生成随机序列、检查不变量、缩减失败序列
enum ReducerFuzzRunner {
    /// 每个种子的事件数
    static let stepsPerSeed = 200
    /// 种子基数（固定，保证可复现）
    static let seedBase: UInt64 = 0xC0BB_5EED_0000_0000
    /// 以调试场景为起点的比例（直接从深层状态开始）
    private static let scenarioStartRate: CGFloat = 0.35

    /// 一个失败：已缩减的最小序列
    struct Failure: Sendable {
        let seed: UInt64
        let violation: InvariantViolation
        let trace: FuzzTrace
        /// 缩减后序列中不可能由真实硬件产生的事件数（0 = 物理上可行）
        let nonPhysicalEvents: Int
    }

    static func seed(_ index: Int) -> UInt64 {
        seedBase &+ UInt64(index)
    }

    /// 按种子生成并执行一条序列；失败时序列截断到失败那一步，并返回违反的不变量
    static func run(
        seed: UInt64,
        coverage: inout FuzzCoverage,
        invariants: [ReducerInvariant] = ReducerInvariant.allCases
    ) -> (trace: FuzzTrace, violation: InvariantViolation?) {
        var rng = FuzzRandom(seed: seed)
        let topologyIndex = rng.weighted(Array(zip(FuzzTopologies.weights, FuzzTopologies.all.indices)))
        let topology = FuzzTopologies.isolated(topologyIndex)
        let start = randomStart(&rng, topology: topology)
        var replayer = FuzzReplayer(topology: topology, start: start, invariants: invariants)
        var input = FuzzInputState(session: replayer.session)
        var events: [ScreenshotEvent] = []
        events.reserveCapacity(stepsPerSeed)
        for _ in 0..<stepsPerSeed {
            let event = FuzzEventGenerator.next(&rng, session: replayer.session, input: &input, topology: topology)
            events.append(event)
            let finishedBefore = replayer.finishedSessions
            let (step, violation) = replayer.apply(event)
            coverage.record(step)
            if let violation {
                return (FuzzTrace(topologyIndex: topologyIndex, start: start, events: events), violation)
            }
            if replayer.finishedSessions != finishedBefore {
                input = FuzzInputState(session: replayer.session)
            }
        }
        return (FuzzTrace(topologyIndex: topologyIndex, start: start, events: events), nil)
    }

    private static func randomStart(_ rng: inout FuzzRandom, topology: ScreenTopology) -> FuzzStart {
        if rng.chance(scenarioStartRate) {
            return .scenario(rng.pick(FuzzStart.scenarioNames))
        }
        let cursor = FuzzPoints.interesting(
            &rng, session: .initial(styles: .default, cursor: .zero), topology: topology)
        return .initial(cursor: cursor)
    }

    // MARK: - 缩减

    /// 缩减：逐块（从大到小）删除事件，失败仍以同一不变量复现且没有引入新的「不可能事件」就保留删除；
    /// 最后把坐标化简为整数 / 十的倍数，便于写成回归测试
    static func shrink(_ trace: FuzzTrace, violation: InvariantViolation, seed: UInt64) -> Failure {
        guard var best = FuzzReplayer.firstViolation(in: trace), best.violation.invariant == violation.invariant
        else {
            return Failure(seed: seed, violation: violation, trace: trace, nonPhysicalEvents: -1)
        }
        var events = Array(trace.events.prefix(best.index + 1))
        func attempt(_ candidate: [ScreenshotEvent]) -> Bool {
            guard let result = FuzzReplayer.firstViolation(in: trace.with(events: candidate)),
                result.violation.invariant == violation.invariant, result.nonPhysical <= best.nonPhysical
            else { return false }
            events = Array(candidate.prefix(result.index + 1))
            best = result
            return true
        }
        // 块大小依次减半；小块（≤ 4，例如一次按下 + 松开）逐个偏移尝试，避免因对齐错过成对的事件
        var changed = true
        while changed {
            changed = false
            var chunk = max(events.count / 2, 1)
            while chunk >= 1 {
                var index = 0
                while index < events.count {
                    let end = min(index + chunk, events.count)
                    if attempt(Array(events[..<index] + events[end...])) {
                        changed = true
                    } else {
                        index += chunk <= 4 ? 1 : chunk
                    }
                }
                chunk = chunk > 4 ? chunk / 2 : chunk - 1
            }
        }
        for index in events.indices {
            for simplified in FuzzRendering.simplifications(of: events[index]) where index < events.count {
                var candidate = events
                candidate[index] = simplified
                if attempt(candidate) {
                    break
                }
            }
        }
        return Failure(
            seed: seed, violation: best.violation, trace: trace.with(events: events),
            nonPhysicalEvents: best.nonPhysical)
    }
}
