import CoreGraphics
import Testing
@testable import CubbyCore

@Suite("AlphaBounds 按透明像素裁剪")
struct AlphaBoundsTests {
    /// 透明画布上在 (x, y)（左上原点）处放若干像素
    private func canvas(width: Int, height: Int, pixels: [(Int, Int, Pixel)]) -> CGImage {
        let canvas = TestCanvas(width: width, height: height, fill: .clear)
        for (x, y, pixel) in pixels {
            canvas.setPixel(pixel, x: x, y: y)
        }
        return canvas.makeImage()
    }

    @Test("整张透明：nil")
    func fullyTransparent() {
        let image = canvas(width: 8, height: 6, pixels: [])
        #expect(AlphaBounds.bounds(of: image) == nil)
        #expect(AlphaBounds.cropped(image) == nil)
    }

    @Test("不透明矩形：外接矩形即该矩形（左上原点像素坐标）")
    func opaqueBlock() {
        let block = (2...5).flatMap { x in (1...3).map { y in (x, y, Pixel.black) } }
        let image = canvas(width: 10, height: 8, pixels: block)
        #expect(AlphaBounds.bounds(of: image) == CGRect(x: 2, y: 1, width: 4, height: 3))
    }

    @Test("半透明像素（如阴影边缘）也算在内")
    func translucentCounts() {
        let image = canvas(
            width: 12, height: 10,
            pixels: [(1, 8, Pixel(0, 0, 0, 1)), (10, 2, Pixel(0, 0, 0, 30)), (5, 5, .black)])
        #expect(AlphaBounds.bounds(of: image) == CGRect(x: 1, y: 2, width: 10, height: 7))
    }

    @Test("单个像素贴右下角")
    func cornerPixel() {
        let image = canvas(width: 5, height: 4, pixels: [(4, 3, .white)])
        #expect(AlphaBounds.bounds(of: image) == CGRect(x: 4, y: 3, width: 1, height: 1))
    }

    @Test("没有透明边：外接矩形为整张图，裁剪后尺寸不变")
    func noTransparentMargin() throws {
        let image = TestCanvas(width: 7, height: 3, fill: .white).makeImage()
        #expect(AlphaBounds.bounds(of: image) == CGRect(x: 0, y: 0, width: 7, height: 3))
        let cropped = try #require(AlphaBounds.cropped(image))
        #expect(cropped.width == 7 && cropped.height == 3)
    }

    @Test("裁剪结果尺寸与内容正确")
    func croppedContent() throws {
        let image = canvas(width: 20, height: 12, pixels: [(3, 4, .black), (8, 9, Pixel(255, 0, 0))])
        let cropped = try #require(AlphaBounds.cropped(image))
        #expect(cropped.width == 6 && cropped.height == 6)
        let readBack = TestCanvas(image: cropped)
        #expect(readBack.pixel(x: 0, y: 0) == .black)
        #expect(readBack.pixel(x: 5, y: 5) == Pixel(255, 0, 0))
        #expect(readBack.pixel(x: 3, y: 3).alpha == 0)
    }
}
