import CoreGraphics
import Foundation
import Testing
@testable import CubbyCore

/// 历史图片 → 合成冻结帧（docs/CLIP-TRANSLATION-DESIGN.md §5.1）：DPI → scale、整帧像素一致、按版面绘制译文
@Suite("HistoryImageFrame 合成屏幕")
struct HistoryImageFrameTests {
    @Test(
        "DPI → scale：DPI / 72 四舍五入并夹在 1…3；缺失或非法为 1",
        arguments: [
            (72.0, 1.0), (144, 2), (216, 3), (100, 1), (180, 3), (300, 3), (36, 1), (0, 1), (-72, 1), (.nan, 1),
            (.infinity, 1),
        ] as [(Double, CGFloat)])
    func scaleFromDPI(dpi: Double, expected: CGFloat) {
        #expect(HistoryImageFrame.scale(dpi: dpi) == expected)
    }

    @Test("没有 DPI 时 scale 为 1")
    func missingDPI() {
        #expect(HistoryImageFrame.scale(dpi: nil) == 1)
    }

    @Test("合成屏幕：原点 (0,0)、点尺寸 = 像素 / scale、选区为整帧；pixelSize 与图片尺寸严格相等（含奇数边）", arguments: [1.0, 2, 3] as [CGFloat])
    func syntheticScreen(scale: CGFloat) {
        let image = TestImage.coordinates(width: 101, height: 53)
        let (frame, selection) = HistoryImageFrame.make(image: image, scale: scale)
        #expect(frame.screen.id == 0)
        #expect(frame.screen.scale == scale)
        #expect(frame.screen.frame.origin == .zero)
        #expect(frame.screen.frame.width == 101 / scale)
        #expect(selection == frame.screen.frame)
        #expect(frame.screen.pixelSize == CGSize(width: 101, height: 53))
        #expect(frame.screen.pixelRect(selection) == CGRect(x: 0, y: 0, width: 101, height: 53))
    }

    @Test("整帧裁剪（识别用）逐像素等于原图", arguments: [1.0, 2] as [CGFloat])
    func cropMatchesOriginal(scale: CGFloat) throws {
        let image = TestImage.coordinates(width: 64, height: 31)
        let (frame, selection) = HistoryImageFrame.make(image: image, scale: scale)
        let cropped = try ScreenshotExporter.crop(frame: frame, selection: selection)
        let original = TestCanvas(image: image)
        let result = TestCanvas(image: cropped)
        #expect(cropped.width == 64 && cropped.height == 31)
        let mismatches = (0..<31).flatMap { y in
            (0..<64).filter { x in original.pixel(x: x, y: y) != result.pixel(x: x, y: y) }
        }
        #expect(mismatches.isEmpty)
    }

    @Test("渲染环境：一个用户单位 = 一个图片像素")
    func environment() {
        let (frame, _) = HistoryImageFrame.make(image: TestImage.solid(width: 40, height: 20, .white), scale: 2)
        let environment = HistoryImageFrame.environment(for: frame)
        #expect(environment.origin == .zero)
        #expect(environment.scale == 2)
        #expect(environment.targetPixelSize == CGSize(width: 40, height: 20))
        #expect(environment.pixelatedFrame == nil)
        #expect(environment.frameOrigin == .zero)
    }

    @Test("render：没有版面时与原图逐像素相同；有版面时按点坐标 × scale 抹除原文区域")
    func renderPaintsBlocks() throws {
        let image = TestImage.checkerboard(width: 40, height: 20, cell: 1)
        let (frame, _) = HistoryImageFrame.make(image: image, scale: 2)
        let untouched = TestCanvas(image: try HistoryImageFrame.render(frame, blocks: []))
        let original = TestCanvas(image: image)
        #expect(untouched.countPixels { _ in true } == 800)
        #expect(
            (0..<20).allSatisfy { y in
                (0..<40).allSatisfy { x in untouched.pixel(x: x, y: y) == original.pixel(x: x, y: y) }
            })

        let red = PixelColor(red: 1, green: 0, blue: 0)
        let block = TranslatedBlock(
            blockID: 0, eraseFrame: CGRect(x: 2, y: 3, width: 5, height: 4), backdrop: .solid(red), text: "",
            textFrame: CGRect(x: 2, y: 3, width: 5, height: 4), fontSize: 6, isBold: false, textColor: .black,
            alignment: .leading)
        let rendered = TestCanvas(image: try HistoryImageFrame.render(frame, blocks: [block]))

        let redPixel = Pixel(255, 0, 0)
        #expect(rendered.pixel(x: 4, y: 6) == redPixel)
        #expect(rendered.pixel(x: 13, y: 13) == redPixel)
        #expect(rendered.countPixels { $0 == redPixel } == 10 * 8)
        #expect(rendered.pixel(x: 3, y: 6) == original.pixel(x: 3, y: 6))
        #expect(rendered.pixel(x: 14, y: 13) == original.pixel(x: 14, y: 13))
        #expect(rendered.pixel(x: 4, y: 14) == original.pixel(x: 4, y: 14))
    }

    @Test("解码：取出位图与 DPI；无法解码为 nil")
    func decode() throws {
        let image = TestImage.solid(width: 12, height: 8, .black)
        let png = try #require(ScreenshotExporter.pngData(image, scale: 2))
        let decoded = try #require(HistoryImageFrame.decode(png))
        #expect(decoded.image.width == 12 && decoded.image.height == 8)
        #expect(decoded.dpi == 144)
        #expect(HistoryImageFrame.scale(dpi: decoded.dpi) == 2)
        #expect(HistoryImageFrame.decode(Data("not an image".utf8)) == nil)
    }
}
