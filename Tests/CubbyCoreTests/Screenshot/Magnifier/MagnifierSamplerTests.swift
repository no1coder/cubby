import CoreGraphics
import Testing
@testable import CubbyCore

@Suite("MagnifierSampler 像素网格采样")
struct MagnifierSamplerTests {
    private let image = MagnifierTestImage.gradient(width: 40, height: 30)

    @Test("帧内采样：中心像素与角落像素正确")
    func samplesInsideFrame() {
        let grid = MagnifierSampler.sample(frame: image, centerPixel: CGPoint(x: 20, y: 15), radius: 8)
        #expect(grid.radius == 8)
        #expect(grid.side == 17)
        #expect(grid.colors.count == 17 * 17)
        #expect(grid.center == MagnifierTestImage.gradientColor(x: 20, y: 15))
        #expect(grid.color(dx: -8, dy: -8) == MagnifierTestImage.gradientColor(x: 12, y: 7))
        #expect(grid.color(dx: 8, dy: 8) == MagnifierTestImage.gradientColor(x: 28, y: 23))
        #expect(grid.color(dx: 3, dy: -2) == MagnifierTestImage.gradientColor(x: 23, y: 13))
    }

    @Test("小数坐标向下取整到像素")
    func floorsFractionalCenter() {
        let grid = MagnifierSampler.sample(frame: image, centerPixel: CGPoint(x: 20.7, y: 15.2), radius: 1)
        #expect(grid.center == MagnifierTestImage.gradientColor(x: 20, y: 15))
    }

    @Test("帧边缘：越界格子为 nil，帧内格子正常")
    func edgeCellsAreNil() {
        let grid = MagnifierSampler.sample(frame: image, centerPixel: CGPoint(x: 0, y: 0), radius: 2)
        #expect(grid.center == MagnifierTestImage.gradientColor(x: 0, y: 0))
        #expect(grid.color(dx: -1, dy: 0) == nil)
        #expect(grid.color(dx: 0, dy: -2) == nil)
        #expect(grid.color(dx: 1, dy: 1) == MagnifierTestImage.gradientColor(x: 1, y: 1))
        let bottomRight = MagnifierSampler.sample(frame: image, centerPixel: CGPoint(x: 39, y: 29), radius: 2)
        #expect(bottomRight.center == MagnifierTestImage.gradientColor(x: 39, y: 29))
        #expect(bottomRight.color(dx: 1, dy: 0) == nil)
        #expect(bottomRight.color(dx: -2, dy: -2) == MagnifierTestImage.gradientColor(x: 37, y: 27))
    }

    @Test("中心在帧外：中心为 nil，全部格子为 nil")
    func centerOutsideFrame() {
        let far = MagnifierSampler.sample(frame: image, centerPixel: CGPoint(x: 100, y: 100), radius: 8)
        #expect(far.center == nil)
        #expect(far.colors.allSatisfy { $0 == nil })
        let negative = MagnifierSampler.sample(frame: image, centerPixel: CGPoint(x: -0.5, y: 3), radius: 0)
        #expect(negative.center == nil)
    }

    @Test("中心刚好在帧外一格时，相邻帧内格子仍有颜色")
    func centerJustOutside() {
        let grid = MagnifierSampler.sample(frame: image, centerPixel: CGPoint(x: 40, y: 10), radius: 1)
        #expect(grid.center == nil)
        #expect(grid.color(dx: -1, dy: 0) == MagnifierTestImage.gradientColor(x: 39, y: 10))
    }

    @Test("半径 0 为单像素；负半径按 0 处理")
    func zeroAndNegativeRadius() {
        let single = MagnifierSampler.sample(frame: image, centerPixel: CGPoint(x: 5, y: 5), radius: 0)
        #expect(single.side == 1)
        #expect(single.colors == [MagnifierTestImage.gradientColor(x: 5, y: 5)])
        let negative = MagnifierSampler.sample(frame: image, centerPixel: CGPoint(x: 5, y: 5), radius: -3)
        #expect(negative.radius == 0)
        #expect(negative.side == 1)
    }

    @Test("半透明像素读出非预乘颜色")
    func unpremultipliesAlpha() throws {
        let translucent = MagnifierTestImage.make(width: 2, height: 2) { _, _ in
            MagnifierTestImage.Pixel(red: 255, green: 0, blue: 0, alpha: 128)
        }
        let grid = MagnifierSampler.sample(frame: translucent, centerPixel: CGPoint(x: 1, y: 1), radius: 0)
        let center = try #require(grid.center)
        #expect(abs(center.red - 1) < 0.01)
        #expect(abs(center.alpha - 128.0 / 255) < 0.01)
    }

    @Test("完全透明像素读出透明黑")
    func transparentPixel() {
        let clear = MagnifierTestImage.make(width: 1, height: 1) { _, _ in
            MagnifierTestImage.Pixel(red: 0, green: 0, blue: 0, alpha: 0)
        }
        let grid = MagnifierSampler.sample(frame: clear, centerPixel: .zero, radius: 0)
        #expect(grid.center == RGBAColor(red: 0, green: 0, blue: 0, alpha: 0))
    }
}

@Suite("PixelGrid 网格访问")
struct PixelGridTests {
    @Test("按 dx / dy 行优先访问，越界返回 nil")
    func accessesRowMajor() {
        let red = RGBAColor(red: 1, green: 0, blue: 0)
        let blue = RGBAColor(red: 0, green: 0, blue: 1)
        let grid = PixelGrid(radius: 1, colors: [nil, red, nil, nil, blue, nil, nil, nil, red])
        #expect(grid.side == 3)
        #expect(grid.center == blue)
        #expect(grid.color(dx: 0, dy: -1) == red)
        #expect(grid.color(dx: 1, dy: 1) == red)
        #expect(grid.color(dx: 2, dy: 0) == nil)
        #expect(grid.color(dx: 0, dy: -2) == nil)
    }

    @Test("颜色数量不足时缺失格子为 nil")
    func shortColorsArray() {
        let grid = PixelGrid(radius: 1, colors: [])
        #expect(grid.center == nil)
    }
}
