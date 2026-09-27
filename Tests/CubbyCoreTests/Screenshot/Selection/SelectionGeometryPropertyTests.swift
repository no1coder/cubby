import CoreGraphics
import Testing
@testable import CubbyCore

/// SelectionGeometry 对任意输入成立的性质（§3.3.2 契约：夹紧到 bounds、不小于 minSize、对边固定）
///
/// 输入由固定种子生成：边界含负坐标与小数，矩形含零尺寸、负尺寸、跨边、完全在外、比边界还大。
@Suite("SelectionGeometry · 性质测试（任意输入）")
struct SelectionGeometryPropertyTests {
    private static let iterations = 4000
    private typealias Gen = FuzzGeometry

    @Test("clamped：结果在 bounds 内、尺寸取 min(|原尺寸|, bounds)、幂等、已在内部的矩形不变")
    func clamped() {
        var rng = FuzzRandom(seed: 0xC1A0_0001)
        var failures = PropertyFailures()
        for _ in 0..<Self.iterations {
            let bounds = Gen.bounds(&rng)
            let rect = Gen.rect(&rng, around: bounds)
            let result = SelectionGeometry.clamped(rect, to: bounds)
            let context = "rect \(rect) bounds \(bounds) → \(result)"
            failures.check(Gen.contains(bounds, result), "outside: \(context)")
            failures.check(Gen.close(result.width, min(abs(rect.width), bounds.width)), "width: \(context)")
            failures.check(Gen.close(result.height, min(abs(rect.height), bounds.height)), "height: \(context)")
            let again = SelectionGeometry.clamped(result, to: bounds)
            failures.check(Gen.close(again, result), "not idempotent: \(context)")
            if bounds.contains(rect.standardized) {
                failures.check(Gen.close(result, rect.standardized), "moved an inside rect: \(context)")
            }
        }
        #expect(failures.count == 0, "\(failures.summary)")
    }

    @Test("moved / nudged：结果在 bounds 内，尺寸与夹紧后相同；零位移等于 clamped")
    func movedAndNudged() {
        var rng = FuzzRandom(seed: 0xC1A0_0002)
        var failures = PropertyFailures()
        let directions: [NudgeDirection] = [.up, .down, .left, .right]
        for _ in 0..<Self.iterations {
            let bounds = Gen.bounds(&rng)
            let rect = Gen.rect(&rng, around: bounds)
            let delta = CGVector(dx: rng.value(in: -5000, 5000), dy: rng.value(in: -5000, 5000))
            let moved = SelectionGeometry.moved(rect, by: delta, bounds: bounds)
            let expectedSize = SelectionGeometry.clamped(rect, to: bounds).size
            let context = "rect \(rect) by \(delta) in \(bounds) → \(moved)"
            failures.check(Gen.contains(bounds, moved), "moved outside: \(context)")
            failures.check(
                Gen.close(moved.width, expectedSize.width) && Gen.close(moved.height, expectedSize.height),
                "moved resized: \(context)")
            failures.check(
                SelectionGeometry.moved(rect, by: .zero, bounds: bounds) == SelectionGeometry.clamped(rect, to: bounds),
                "zero move != clamped: \(context)")
            let step: CGFloat = rng.pick([1, 10, 0.5])
            let nudged = SelectionGeometry.nudged(rect, rng.pick(directions), step: step, bounds: bounds)
            failures.check(Gen.contains(bounds, nudged), "nudged outside: rect \(rect) in \(bounds) → \(nudged)")
            failures.check(
                Gen.close(nudged.width, expectedSize.width) && Gen.close(nudged.height, expectedSize.height),
                "nudged resized: rect \(rect) in \(bounds) → \(nudged)")
        }
        #expect(failures.count == 0, "\(failures.summary)")
    }

    @Test("normalized：结果在 bounds 内、尺寸非负；⇧ 为正方形；⌥ 以（夹进 bounds 的）起点为中心，否则起点是一个角")
    func normalized() {
        var rng = FuzzRandom(seed: 0xC1A0_0003)
        var failures = PropertyFailures()
        for _ in 0..<Self.iterations {
            let bounds = Gen.bounds(&rng)
            let anchor = Gen.point(&rng, around: bounds)
            let point = Gen.point(&rng, around: bounds)
            let square = rng.chance(0.5)
            let fromCenter = rng.chance(0.5)
            let result = SelectionGeometry.normalized(
                from: anchor, to: point, constrainSquare: square, fromCenter: fromCenter, bounds: bounds)
            let context = "\(anchor) → \(point) square \(square) center \(fromCenter) in \(bounds) → \(result)"
            failures.check(Gen.contains(bounds, result), "outside: \(context)")
            if square {
                failures.check(Gen.close(result.width, result.height), "not square: \(context)")
            }
            let start = CGPoint(
                x: min(max(anchor.x, bounds.minX), bounds.maxX), y: min(max(anchor.y, bounds.minY), bounds.maxY))
            if fromCenter {
                failures.check(Gen.close(result.midX, start.x) && Gen.close(result.midY, start.y), "center: \(context)")
            } else {
                let cornerX = Gen.close(result.minX, start.x) || Gen.close(result.maxX, start.x)
                let cornerY = Gen.close(result.minY, start.y) || Gen.close(result.maxY, start.y)
                failures.check(cornerX && cornerY, "anchor is not a corner: \(context)")
            }
        }
        #expect(failures.count == 0, "\(failures.summary)")
    }

    @Test("resizing：任意输入都不出 bounds；输入不小于 minSize 时结果也不小于，且（非 ⇧）对边固定；⇧ 为正方形")
    func resizing() {
        var rng = FuzzRandom(seed: 0xC1A0_0004)
        var failures = PropertyFailures()
        let minimum = SelectionGeometry.minSize
        for _ in 0..<Self.iterations * 2 {
            let bounds = Gen.bounds(&rng)
            let rect = rng.chance(0.7) ? Gen.insideRect(&rng, in: bounds) : Gen.rect(&rng, around: bounds)
            let handle = rng.pick(SelectionHandle.allCases)
            let point = Gen.point(&rng, around: bounds)
            let square = rng.chance(0.4)
            let result = SelectionGeometry.resizing(
                rect, handle: handle, to: point, constrainSquare: square, bounds: bounds)
            let box = SelectionGeometry.clamped(rect, to: bounds)
            let context = "\(rect) \(handle) → \(point) square \(square) in \(bounds) → \(result)"
            failures.check(Gen.contains(bounds, result), "outside bounds: \(context)")
            if square {
                failures.check(Gen.close(result.width, result.height), "not square: \(context)")
            }
            guard box.width >= minimum.width, box.height >= minimum.height else { continue }
            failures.check(
                result.width >= minimum.width - Gen.tolerance && result.height >= minimum.height - Gen.tolerance,
                "smaller than minSize: \(context)")
            guard !square else { continue }
            let fixedEdges: [(Bool, CGFloat, CGFloat)] = [
                (handle.movesLeftEdge, box.minX, result.minX), (handle.movesRightEdge, box.maxX, result.maxX),
                (handle.movesTopEdge, box.minY, result.minY), (handle.movesBottomEdge, box.maxY, result.maxY),
            ]
            for (moves, before, after) in fixedEdges where !moves {
                failures.check(Gen.close(before, after), "fixed edge moved \(before) → \(after): \(context)")
            }
        }
        #expect(failures.count == 0, "\(failures.summary)")
    }

    // MARK: - 性质测试发现的反例（固化为具名回归用例）

    @Test("⇧ 拖角手柄：输入比 minSize 还细、贴在 bounds 右缘时，正方形不能伸出 bounds")
    func squareCornerOnDegenerateInputStaysInBounds() {
        let bounds = CGRect(x: 0, y: 0, width: 20, height: 100)
        let rect = CGRect(x: 19.999, y: 50, width: 0.001, height: 30)
        let result = SelectionGeometry.resizing(
            rect, handle: .topRight, to: CGPoint(x: 10, y: 90), constrainSquare: true, bounds: bounds)
        #expect(Gen.contains(bounds, result), "\(result)")
        #expect(result.width == result.height)
        // 固定角（左下）不动
        #expect(result.minX == 19.999)
        #expect(Gen.close(result.maxY, 80))
    }

    @Test("⇧ 拖边手柄：输入高度为 0、贴在 bounds 上缘时，正方形不能伸出 bounds")
    func squareEdgeOnDegenerateInputStaysInBounds() {
        let bounds = CGRect(x: 0, y: 0, width: 100, height: 100)
        let rect = CGRect(x: 10, y: 0, width: 50, height: 0)
        let result = SelectionGeometry.resizing(
            rect, handle: .right, to: CGPoint(x: 80, y: 0), constrainSquare: true, bounds: bounds)
        #expect(Gen.contains(bounds, result), "\(result)")
        #expect(result.width == result.height)
        #expect(result.minX == 10)
    }

    @Test("⇧ 缩放正常尺寸的选区：行为不变（仍不小于 minSize）")
    func squareResizeOfNormalSelectionUnchanged() {
        let bounds = CGRect(x: 0, y: 0, width: 1440, height: 900)
        let rect = CGRect(x: 100, y: 100, width: 200, height: 100)
        let corner = SelectionGeometry.resizing(
            rect, handle: .bottomRight, to: CGPoint(x: 101, y: 101), constrainSquare: true, bounds: bounds)
        #expect(corner == CGRect(x: 100, y: 100, width: 4, height: 4))
        let edge = SelectionGeometry.resizing(
            rect, handle: .right, to: CGPoint(x: 400, y: 150), constrainSquare: true, bounds: bounds)
        #expect(edge == CGRect(x: 100, y: 0, width: 300, height: 300))
    }

    @Test("hitRegion：只返回可见手柄；点在矩形外且远离边线时为 outside")
    func hitRegion() {
        var rng = FuzzRandom(seed: 0xC1A0_0005)
        var failures = PropertyFailures()
        for _ in 0..<Self.iterations {
            let bounds = Gen.bounds(&rng)
            let rect = Gen.insideRect(&rng, in: bounds)
            let point = Gen.point(&rng, around: rect.insetBy(dx: -12, dy: -12))
            let region = SelectionGeometry.hitRegion(at: point, in: rect)
            let context = "\(point) in \(rect) → \(region)"
            let visible = SelectionGeometry.visibleHandles(for: rect)
            if case .handle(let handle) = region, rect.width >= 16, rect.height >= 16 {
                // 手柄容差命中只来自可见手柄；边带命中映射出的手柄不受此限制，故只在都可见时检查
                failures.check(visible.contains(handle) || visible.count < 8, "invisible handle: \(context)")
            }
            let far = rect.insetBy(dx: -9, dy: -9)
            if !far.contains(point) {
                failures.check(region == .outside, "far point not outside: \(context)")
            }
        }
        #expect(failures.count == 0, "\(failures.summary)")
    }
}
