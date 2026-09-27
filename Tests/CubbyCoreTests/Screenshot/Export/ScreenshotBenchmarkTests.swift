import AppKit
import Foundation
import Testing
@testable import CubbyCore

/// 性能基线（只在设置 CUBBY_BENCH=1 时运行；建议 release：
/// `CUBBY_BENCH=1 swift test -c release -Xswiftc -enable-testing --filter ScreenshotBenchmark`）
@Suite("ScreenshotBenchmark 6K 性能基线", .enabled(if: ProcessInfo.processInfo.environment["CUBBY_BENCH"] != nil))
struct ScreenshotBenchmarkTests {
    /// 6016×3384 = Pro Display XDR 原生像素（3008×1692 pt @2x）
    private let screen = CaptureScreen(id: 1, frame: CGRect(x: 0, y: 0, width: 3008, height: 1692), scale: 2)

    private func best(of runs: Int = 3, _ body: () throws -> Void) rethrows -> Duration {
        let clock = ContinuousClock()
        var best = Duration.seconds(1000)
        for _ in 0..<runs {
            let start = clock.now
            try body()
            best = min(best, clock.now - start)
        }
        return best
    }

    @Test("整屏导出（裁剪 + 标注 + PNG）与写剪贴板")
    func fullScreenExport() throws {
        let image = TestImage.checkerboard(
            width: 6016, height: 3384, cell: 37, first: Pixel(20, 120, 200), second: .white)
        let frame = FrozenFrame(screen: screen, image: image)
        let pixelated = try #require(Pixelator.pixelated(image, blockSize: 24))
        let style = AnnotationStyle(color: .red, weight: .regular)
        let document = AnnotationDocument.empty
            .adding(Annotation(shape: .arrow(from: CGPoint(x: 100, y: 100), to: CGPoint(x: 900, y: 600)), style: style))
            .adding(Annotation(shape: .mosaic([CGPoint(x: 1000, y: 800), CGPoint(x: 1600, y: 900)]), style: style))
            .adding(
                Annotation(
                    shape: .text("Hello \u{4F60}\u{597D}", origin: CGPoint(x: 300, y: 300), maxWidth: 800), style: style
                ))

        var export: ScreenshotExport?
        let exportTime = try best {
            export = try ScreenshotExporter.export(
                frame: frame, selection: screen.frame, document: document, pixelatedFrame: pixelated)
        }
        let png = try #require(export?.png)
        let pasteTime = try best {
            try withTemporaryPasteboard { try ScreenshotPasteboard.write(png: png, to: $0) }
        }
        print("BENCH export 6016x3384: \(exportTime), png \(png.count / 1024) KB; pasteboard write: \(pasteTime)")
        #expect(export?.pixelSize == CGSize(width: 6016, height: 3384))
    }

    @Test("最坏情况：随机噪声整屏的 PNG 编码")
    func noiseExport() throws {
        let canvas = TestCanvas(width: 6016, height: 3384, fill: nil)
        var generator = SystemRandomNumberGenerator()
        let bytes = canvas.context.data!.assumingMemoryBound(to: UInt32.self)
        for index in 0..<(canvas.context.bytesPerRow / 4 * 3384) {
            bytes[index] = UInt32.random(in: 0...UInt32.max, using: &generator) | 0xFF00_0000
        }
        let frame = FrozenFrame(screen: screen, image: canvas.makeImage())
        var size = 0
        let time = try best(of: 1) {
            size = try ScreenshotExporter.export(
                frame: frame, selection: screen.frame, document: .empty, pixelatedFrame: nil
            ).png.count
        }
        print("BENCH noise export 6016x3384: \(time), png \(size / 1024 / 1024) MB")
        #expect(size > 0)
    }
}
