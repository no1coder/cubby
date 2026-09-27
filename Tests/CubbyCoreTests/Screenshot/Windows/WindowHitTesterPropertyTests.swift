import CoreGraphics
import Darwin
import Testing
@testable import CubbyCore

/// WindowHitTester 对随机窗口栈成立的性质（§3.3.4、§9.2）
@Suite("WindowHitTester · 性质测试（随机窗口栈）")
struct WindowHitTesterPropertyTests {
    private static let iterations = FuzzBudget.scaled(1500)
    private static let ownPID: pid_t = 4242
    private typealias Gen = FuzzGeometry

    /// 随机窗口：含层级非 0、全透明、极小、属于自身进程、负尺寸 frame、跨屏与伸出屏幕的窗口；id 唯一
    private func windows(_ rng: inout FuzzRandom, screens: [CaptureScreen]) -> [WindowCandidate] {
        let count = rng.int(below: 16)
        return (0..<count).map { index in
            let screen = rng.pick(screens).frame
            var frame = Gen.rect(&rng, around: screen)
            if rng.chance(0.1) {
                frame = CGRect(x: frame.maxX, y: frame.maxY, width: -frame.width, height: -frame.height)
            }
            if rng.chance(0.1) {
                frame.size = CGSize(width: rng.pick([0, 1, 1.999, 2, 2.001]), height: rng.pick([1, 2, 5]))
            }
            return WindowCandidate(
                id: UInt32(100 + index),
                frame: frame,
                layer: rng.chance(0.85) ? 0 : rng.pick([-1, 3, 25, 1000]),
                ownerPID: rng.chance(0.1) ? Self.ownPID : pid_t(rng.int(below: 5) + 1),
                alpha: rng.chance(0.9) ? rng.pick([1, 0.5, 0.01]) : 0
            )
        }
    }

    private func isEligible(_ window: WindowCandidate, at point: CGPoint) -> Bool {
        let frame = window.frame.standardized
        return window.layer == 0 && window.alpha > 0 && frame.width >= 2 && frame.height >= 2
            && window.ownerPID != Self.ownPID && frame.contains(point)
    }

    @Test("候选栈：窗口按 z 序单调（前 → 后）、不重不漏、末尾是光标所在整屏；第一项 = hoverTarget = topmost")
    func candidatesAreZOrdered() {
        var rng = FuzzRandom(seed: 0x9119_0001)
        var failures = PropertyFailures()
        let screenSets: [[CaptureScreen]] = [
            [FuzzTopologies.primary, FuzzTopologies.external, FuzzTopologies.lower],
            [FuzzTopologies.primary],
            [FuzzTopologies.external, FuzzTopologies.primary],
        ]
        for _ in 0..<Self.iterations {
            let screens = rng.pick(screenSets)
            let windows = windows(&rng, screens: screens)
            let topology = ScreenTopology(screens: screens, windows: windows, ownPID: Self.ownPID)
            for _ in 0..<4 {
                let point =
                    rng.chance(0.3) && !windows.isEmpty
                    ? Gen.point(&rng, around: rng.pick(windows).frame.standardized)
                    : Gen.point(&rng, around: rng.pick(screens).frame)
                check(point, topology: topology, into: &failures)
            }
        }
        #expect(failures.count == 0, "\(failures.summary)")
    }

    private func check(_ point: CGPoint, topology: ScreenTopology, into failures: inout PropertyFailures) {
        let candidates = WindowHitTester.candidates(at: point, in: topology)
        let context = "point \(point), \(topology.windows.count) windows → \(candidates.count) candidates"
        guard let screen = topology.screen(containing: point) else {
            failures.check(candidates.isEmpty, "candidates in a gap: \(context)")
            let hover = WindowHitTester.hoverTarget(at: point, topology: topology)
            failures.check(hover == nil, "hover in gap: \(context)")
            return
        }
        failures.check(candidates.last == .screen(screen), "last candidate is not the screen: \(context)")
        let windowIDs = candidates.compactMap(\.windowID)
        failures.check(windowIDs.count == candidates.count - 1, "screen target not only at the end: \(context)")
        let indices = windowIDs.compactMap { id in topology.windows.firstIndex { $0.id == id } }
        failures.check(zip(indices, indices.dropFirst()).allSatisfy { $0 < $1 }, "not front-to-back: \(context)")
        let expected = topology.windows.filter { isEligible($0, at: point) }.map(\.id)
        failures.check(windowIDs == expected, "missing or extra windows \(windowIDs) vs \(expected): \(context)")
        for candidate in candidates {
            failures.check(candidate.screen == screen, "candidate on another screen: \(context)")
            let rect = candidate.selectionRect
            failures.check(Gen.contains(screen.frame, rect), "selectionRect outside the screen: \(context)")
            failures.check(rect.contains(point), "selectionRect does not contain the cursor: \(context)")
        }
        failures.check(
            WindowHitTester.hoverTarget(at: point, topology: topology) == candidates.first, "hoverTarget: \(context)")
        let topmost = WindowHitTester.topmost(at: point, in: topology.windows, excludingPID: Self.ownPID)
        failures.check(topmost?.id == windowIDs.first, "topmost != first window candidate: \(context)")
    }
}
