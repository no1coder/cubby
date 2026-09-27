import AppKit
import CoreGraphics
import Foundation
import Testing
@testable import CubbyCore

/// 版面与绘制的性能基线（只在设置 CUBBY_BENCH=1 时运行；建议 release：
/// `CUBBY_BENCH=1 swift test -c release -Xswiftc -enable-testing --filter TranslationBenchmark`）。
/// 目标（docs/TRANSLATION-DESIGN.md 任务说明）：单块 place ≤ 5 ms；整个选区全部块 draw ≤ 8 ms（2x）
@Suite("TranslationBenchmark 版面性能基线", .enabled(if: ProcessInfo.processInfo.environment["CUBBY_BENCH"] != nil))
struct TranslationBenchmarkTests {
    private let hans = "\u{50A8}\u{5B58}\u{7A7A}\u{95F4}"

    private func best(of runs: Int = 5, _ body: () -> Void) -> Duration {
        let clock = ContinuousClock()
        var best = Duration.seconds(1000)
        for _ in 0..<runs {
            let start = clock.now
            body()
            best = min(best, clock.now - start)
        }
        return best
    }

    /// 800×500 pt @2x（1600×1000 像素）：40 个标签 + 一段 4 行正文，白底；右侧一块渐变横幅
    private func scene() -> (TranslationTestScene, [TextBlock]) {
        var texts: [TranslationTestScene.Text] = []
        for row in 0..<20 {
            for column in 0..<2 {
                texts.append(
                    .init(
                        string: "Label \(row * 2 + column) settings",
                        origin: CGPoint(x: 20 + 200 * CGFloat(column), y: 30 + 20 * CGFloat(row))))
            }
        }
        let paragraph = (0..<4).map { index in
            TranslationTestScene.Text(
                string: "Optimize storage to free up space automatically \(index)",
                origin: CGPoint(x: 440, y: 40 + 19 * CGFloat(index)))
        }
        let scene = TranslationTestScene(
            size: CGSize(width: 800, height: 500), scale: 2, background: .solid(.srgb(0xFFFFFF)),
            texts: texts + paragraph
        ) { context in
            let gradient = CGGradient(
                colorsSpace: TestCanvas.colorSpace,
                colors: [CGColor.srgb(0x5E5CE6), CGColor.srgb(0x0A84FF)] as CFArray,
                locations: nil)!
            context.saveGState()
            context.clip(to: CGRect(x: 440, y: 300, width: 340, height: 120))
            context.drawLinearGradient(gradient, start: CGPoint(x: 440, y: 0), end: CGPoint(x: 780, y: 0), options: [])
            context.restoreGState()
        }
        let labels = texts.enumerated().map { scene.block([$1], id: $0) }
        return (scene, labels + [scene.block(paragraph, id: labels.count)])
    }

    @Test("place：单行标签、多行段落；draw：整个选区")
    func placeAndDraw() throws {
        let (scene, blocks) = scene()
        let label = blocks[0]
        let paragraph = blocks[blocks.count - 1]
        let labelTime = best { _ = TranslationPlacer.place(label, translation: hans, in: scene.frame) }
        let paragraphTime = best {
            _ = TranslationPlacer.place(paragraph, translation: String(repeating: hans, count: 12), in: scene.frame)
        }
        let placed = blocks.map { TranslationPlacer.place($0, translation: hans, in: scene.frame) }
        let context = try #require(
            CGContext(
                data: nil, width: 1600, height: 1000, bitsPerComponent: 8, bytesPerRow: 0, space: TestCanvas.colorSpace,
                bitmapInfo: TestCanvas.bitmapInfo))
        let environment = RenderEnvironment(
            origin: .zero, scale: 2, targetPixelSize: CGSize(width: 1600, height: 1000), pixelatedFrame: nil,
            frameOrigin: .zero)
        let drawTime = best { TranslationPainter.draw(placed, in: context, environment: environment) }
        let banner = TranslationTestScene.Text(
            string: "Get 2 TB free", origin: CGPoint(x: 460, y: 360), size: 20, weight: .bold, color: .srgb(0xFFFFFF))
        let plateScene = TranslationTestScene(
            size: CGSize(width: 800, height: 500), scale: 2,
            background: .gradient(.srgb(0x5E5CE6), .srgb(0x0A84FF)), texts: [banner])
        let plateBlock = plateScene.block([banner])
        let plateTime = best { _ = TranslationPlacer.place(plateBlock, translation: hans, in: plateScene.frame) }
        print("TranslationBenchmark place(plate)=\(plateTime)")
        #expect(plateTime < .milliseconds(5))
        print(
            "TranslationBenchmark place(label)=\(labelTime) place(paragraph)=\(paragraphTime) draw(\(placed.count) blocks)=\(drawTime)"
        )
        #expect(labelTime < .milliseconds(5))
        #expect(paragraphTime < .milliseconds(5))
        #expect(drawTime < .milliseconds(8))
    }

    @Test("place：40 行长段落（2x）——逐像素去重必须接近线性")
    func longParagraph() {
        let lines = (0..<40).map { index in
            TranslationTestScene.Text(
                string: "Optimize storage to free up space automatically by removing old items \(index)",
                origin: CGPoint(x: 30, y: 30 + 19 * CGFloat(index)))
        }
        let scene = TranslationTestScene(
            size: CGSize(width: 560, height: 820), scale: 2, background: .solid(.srgb(0xFFFFFF)), texts: lines)
        let block = scene.block(lines)
        let time = best(of: 3) {
            _ = TranslationPlacer.place(block, translation: String(repeating: hans, count: 150), in: scene.frame)
        }
        print("TranslationBenchmark place(40-line paragraph)=\(time)")
        #expect(time < .milliseconds(40))
    }
}
