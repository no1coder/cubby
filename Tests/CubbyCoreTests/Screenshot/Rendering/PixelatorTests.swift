import CoreGraphics
import Foundation
import Testing
@testable import CubbyCore

@Suite("Pixelator 像素化")
struct PixelatorTests {
    @Test("逐像素棋盘按 2×2 取块平均得到中灰")
    func checkerboardAverages() throws {
        let image = TestImage.checkerboard(width: 8, height: 8, cell: 1)
        let result = TestCanvas(image: try #require(Pixelator.pixelated(image, blockSize: 2)))
        for y in 0..<8 {
            for x in 0..<8 {
                #expect(result.pixel(x: x, y: y).isClose(to: Pixel(128, 128, 128), tolerance: 1))
            }
        }
    }

    @Test("块内每个像素 = 该块的平均值（四舍五入），块与块互不影响")
    func blockAverageOfCoordinates() throws {
        // R = x、G = y：4×4 块 (0...3, 0...3) 的平均 = 1.5 → 2；块 (4...7, 0...3) 的 R 平均 = 5.5 → 6
        let image = TestImage.coordinates(width: 8, height: 8)
        let result = TestCanvas(image: try #require(Pixelator.pixelated(image, blockSize: 4)))
        #expect(result.pixel(x: 0, y: 0) == Pixel(2, 2, 128))
        #expect(result.pixel(x: 3, y: 3) == Pixel(2, 2, 128))
        #expect(result.pixel(x: 4, y: 0) == Pixel(6, 2, 128))
        #expect(result.pixel(x: 7, y: 7) == Pixel(6, 6, 128))
    }

    @Test("尺寸不整除时，边缘的不完整块按自身像素取平均")
    func partialEdgeBlocks() throws {
        let image = TestImage.coordinates(width: 10, height: 9)
        let pixelated = try #require(Pixelator.pixelated(image, blockSize: 4))
        #expect(pixelated.width == 10 && pixelated.height == 9)
        let result = TestCanvas(image: pixelated)
        // 右下角块：x ∈ 8...9（平均 8.5 → 9），y ∈ 8...8（平均 8）
        #expect(result.pixel(x: 9, y: 8) == Pixel(9, 8, 128))
        #expect(result.pixel(x: 8, y: 8) == Pixel(9, 8, 128))
        // 右侧块：x ∈ 8...9，y ∈ 4...7（平均 5.5 → 6）
        #expect(result.pixel(x: 8, y: 5) == Pixel(9, 6, 128))
    }

    @Test("blockSize = 1 返回原图")
    func blockSizeOneIsIdentity() throws {
        let image = TestImage.coordinates(width: 5, height: 5)
        let result = try #require(Pixelator.pixelated(image, blockSize: 1))
        #expect(result === image)
    }

    @Test("blockSize < 1 失败返回 nil")
    func invalidBlockSize() {
        let image = TestImage.solid(width: 4, height: 4, .white)
        #expect(Pixelator.pixelated(image, blockSize: 0) == nil)
        #expect(Pixelator.pixelated(image, blockSize: -3) == nil)
    }

    @Test("块比图大时整张图取一个平均色")
    func blockLargerThanImage() throws {
        let image = TestImage.checkerboard(width: 3, height: 3, cell: 1, first: .black, second: .white)
        let result = TestCanvas(image: try #require(Pixelator.pixelated(image, blockSize: 50)))
        // 5 黑 4 白：平均 4 × 255 / 9 = 113.3 → 113
        #expect(result.pixel(x: 0, y: 0) == Pixel(113, 113, 113))
        #expect(result.pixel(x: 2, y: 2) == Pixel(113, 113, 113))
    }

    @Test("半透明像素按预乘值平均，结果保持 alpha")
    func alphaIsAveraged() throws {
        let canvas = TestCanvas(width: 2, height: 1, fill: nil)
        canvas.setPixel(Pixel(0, 0, 0, 0), x: 0, y: 0)
        canvas.setPixel(Pixel(200, 0, 0, 200), x: 1, y: 0)
        let result = TestCanvas(image: try #require(Pixelator.pixelated(canvas.makeImage(), blockSize: 2)))
        #expect(result.pixel(x: 0, y: 0) == Pixel(100, 0, 0, 100))
    }

    @Test(
        "blockSize(forBrushWidth:scale:) = max(6, 宽 × scale / 2)",
        arguments: [
            (12.0, 1.0, 6),
            (24, 1, 12),
            (40, 1, 20),
            (12, 2, 12),
            (40, 2, 40),
            (4, 1, 6),
            (13, 1, 7),
        ]
    )
    func blockSizeForBrush(width: Double, scale: Double, expected: Int) {
        #expect(Pixelator.blockSize(forBrushWidth: width, scale: scale) == expected)
    }

    @Test(
        "性能：6K 帧像素化（设置 CUBBY_BENCH=1 时运行）",
        .enabled(if: ProcessInfo.processInfo.environment["CUBBY_BENCH"] != nil)
    )
    func benchmark6K() throws {
        let image = TestImage.solid(width: 6016, height: 3384, Pixel(10, 200, 30))
        let clock = ContinuousClock()
        var best = Duration.seconds(100)
        for _ in 0..<5 {
            let elapsed = clock.measure { _ = Pixelator.pixelated(image, blockSize: 20) }
            best = min(best, elapsed)
        }
        print("Pixelator 6016x3384 blockSize 20 best of 5: \(best)")
        #expect(best < .seconds(5))
    }
}
