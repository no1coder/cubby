import CoreGraphics
import Testing
@testable import CubbyCore

/// 选区吸附像素网格（`ScreenshotReducer.snappedToPixelGrid`）对任意输入成立的性质
@Suite("选区吸附像素网格 · 性质测试（任意输入）")
struct PixelSnappingPropertyTests {
    private static let iterations = FuzzBudget.scaled(4000)
    private typealias Gen = FuzzGeometry

    /// 整数原点（含负坐标）的屏幕，@1x / @2x / @3x
    private func screen(_ rng: inout FuzzRandom) -> CaptureScreen {
        let frame = CGRect(
            x: CGFloat(rng.int(below: 6001) - 3000), y: CGFloat(rng.int(below: 4001) - 2000),
            width: CGFloat(rng.int(below: 3000) + 8), height: CGFloat(rng.int(below: 2000) + 8))
        return CaptureScreen(id: 1, frame: frame, scale: rng.pick([1, 2, 2, 3]))
    }

    /// 相对屏幕原点乘以缩放后是否为整数（@3x 的 k/3 不能精确表示，允许浮点误差）
    private func onGrid(_ value: CGFloat, origin: CGFloat, scale: CGFloat) -> Bool {
        let pixels = (value - origin) * scale
        return abs(pixels - pixels.rounded()) <= 1e-6
    }

    private func onGrid(_ rect: CGRect, screen: CaptureScreen) -> Bool {
        let origin = screen.frame.origin
        return onGrid(rect.minX, origin: origin.x, scale: screen.scale)
            && onGrid(rect.minY, origin: origin.y, scale: screen.scale)
            && onGrid(rect.maxX, origin: origin.x, scale: screen.scale)
            && onGrid(rect.maxY, origin: origin.y, scale: screen.scale)
    }

    @Test("吸附结果在网格上、在屏幕内、幂等，且每条边的移动不超过一个像素")
    func snappingProperties() {
        var rng = FuzzRandom(seed: 0x5A49_0001)
        var failures = PropertyFailures()
        for _ in 0..<Self.iterations {
            let screen = screen(&rng)
            let rect = rng.chance(0.8) ? Gen.insideRect(&rng, in: screen.frame) : Gen.rect(&rng, around: screen.frame)
            let anchored = (x: rng.chance(0.3), y: rng.chance(0.3))
            let snapped = ScreenshotReducer.snappedToPixelGrid(rect, screen: screen, anchoredHigh: anchored)
            let context = "\(rect) @\(screen.scale)x in \(screen.frame) anchored \(anchored) → \(snapped)"
            failures.check(onGrid(snapped, screen: screen), "off grid: \(context)")
            failures.check(Gen.contains(screen.frame, snapped), "outside screen: \(context)")
            // @1x / @2x 的网格值都能精确表示，要求逐位相等；@3x 的 k/3 不能精确表示，
            // 「屏幕边 − 尺寸」与「取最近格点」可能差一个 ulp，只要求在浮点容差内相等
            let exact = screen.scale != 3
            let same = { (lhs: CGRect, rhs: CGRect) in exact ? lhs == rhs : Gen.close(lhs, rhs) }
            let again = ScreenshotReducer.snappedToPixelGrid(snapped, screen: screen, anchoredHigh: anchored)
            failures.check(same(again, snapped), "not idempotent (\(again)): \(context)")
            failures.check(
                same(ScreenshotReducer.snappedToPixelGrid(snapped, screen: screen), snapped),
                "plain snapping moved an on-grid rect: \(context)")
            let box = rect.standardized
            guard Gen.contains(screen.frame, box) else { continue }
            let pixel = 1 / screen.scale + 1e-9
            let moves = [
                snapped.minX - box.minX, snapped.maxX - box.maxX, snapped.minY - box.minY, snapped.maxY - box.maxY,
            ]
            failures.check(moves.allSatisfy { abs($0) <= pixel }, "an edge moved more than a pixel: \(context)")
        }
        #expect(failures.count == 0, "\(failures.summary)")
    }

    @Test("固定边已在网格上时保持不动（缩放手柄的对边固定）")
    func anchoredEdgeStays() {
        var rng = FuzzRandom(seed: 0x5A49_0002)
        var failures = PropertyFailures()
        for _ in 0..<Self.iterations {
            let screen = screen(&rng)
            let origin = screen.frame.origin
            // 固定边取在网格上，另一边任意（小数）
            let highX = origin.x + CGFloat(rng.int(below: Int(screen.frame.width * screen.scale)) + 1) / screen.scale
            let highY = origin.y + CGFloat(rng.int(below: Int(screen.frame.height * screen.scale)) + 1) / screen.scale
            let lowX = origin.x + (highX - origin.x) * rng.unit()
            let lowY = origin.y + (highY - origin.y) * rng.unit()
            let rect = CGRect(x: lowX, y: lowY, width: highX - lowX, height: highY - lowY)
            let snapped = ScreenshotReducer.snappedToPixelGrid(rect, screen: screen, anchoredHigh: (true, true))
            let context = "\(rect) @\(screen.scale)x → \(snapped)"
            let kept = Gen.close(snapped.maxX, highX) && Gen.close(snapped.maxY, highY)
            failures.check(kept, "fixed edge moved: \(context)")
        }
        #expect(failures.count == 0, "\(failures.summary)")
    }

    /// 零面积的选区只在 selecting 拖拽途中短暂出现，导出对它无定义（`emptySelection`），因此排除
    @Test("吸附后尺寸标签 == 导出像素尺寸（@1x / @2x，非空选区）")
    func labelMatchesExport() {
        var rng = FuzzRandom(seed: 0x5A49_0003)
        var failures = PropertyFailures()
        for _ in 0..<Self.iterations {
            let base = screen(&rng)
            let screen = CaptureScreen(id: base.id, frame: base.frame, scale: rng.pick([1, 2]))
            let rect = Gen.insideRect(&rng, in: screen.frame)
            let anchored = (x: rng.chance(0.5), y: false)
            let snapped = ScreenshotReducer.snappedToPixelGrid(rect, screen: screen, anchoredHigh: anchored)
            guard snapped.width > 0, snapped.height > 0 else { continue }
            let pixels = screen.pixelRect(snapped)
            let exported = "\(Int(pixels.width)) × \(Int(pixels.height))"
            let label = SizeLabelPlacement.text(for: snapped, scale: screen.scale)
            failures.check(label == exported, "label \(label) != export \(exported) for \(snapped) @\(screen.scale)x")
        }
        #expect(failures.count == 0, "\(failures.summary)")
    }
}
