import CoreGraphics
import Foundation
import Testing
@testable import CubbyCore

/// 8 位 RGBA 像素（sRGB，预乘 alpha；不透明像素与直通值相同）
struct Pixel: Equatable, CustomStringConvertible {
    let red: UInt8
    let green: UInt8
    let blue: UInt8
    let alpha: UInt8

    init(_ red: UInt8, _ green: UInt8, _ blue: UInt8, _ alpha: UInt8 = 255) {
        self.red = red
        self.green = green
        self.blue = blue
        self.alpha = alpha
    }

    static let white = Pixel(255, 255, 255)
    static let black = Pixel(0, 0, 0)
    static let clear = Pixel(0, 0, 0, 0)

    var description: String { "(\(red), \(green), \(blue), \(alpha))" }

    var isWhite: Bool { self == .white }

    /// 各分量差值都不超过 tolerance
    func isClose(to other: Pixel, tolerance: Int = 2) -> Bool {
        abs(Int(red) - Int(other.red)) <= tolerance
            && abs(Int(green) - Int(other.green)) <= tolerance
            && abs(Int(blue) - Int(other.blue)) <= tolerance
            && abs(Int(alpha) - Int(other.alpha)) <= tolerance
    }

    /// 由 0...1 的 RGBAColor 换算（仅用于不透明颜色的断言）
    init(_ color: RGBAColor) {
        self.init(
            UInt8((color.red * 255).rounded()),
            UInt8((color.green * 255).rounded()),
            UInt8((color.blue * 255).rounded()),
            UInt8((color.alpha * 255).rounded())
        )
    }
}

/// 可读写的 RGBA 位图：既用来生成测试图，也用来读回渲染结果
/// 内存行 0 即视觉上的第一行，因此 pixel(x:y:) 使用左上原点、y 向下的像素坐标
final class TestCanvas {
    let width: Int
    let height: Int
    let context: CGContext

    static var colorSpace: CGColorSpace { CGColorSpace(name: CGColorSpace.sRGB)! }
    static let bitmapInfo = CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue

    init(width: Int, height: Int, fill: Pixel? = .white) {
        self.width = width
        self.height = height
        guard
            let context = CGContext(
                data: nil,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: 0,
                space: Self.colorSpace,
                bitmapInfo: Self.bitmapInfo
            )
        else { preconditionFailure("cannot create test canvas") }
        self.context = context
        if let fill {
            context.setFillColor(fill.cgColor)
            context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        }
    }

    /// 把现有图片按原尺寸画进新画布，便于读取像素
    convenience init(image: CGImage) {
        self.init(width: image.width, height: image.height, fill: nil)
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
    }

    private var bytes: UnsafeMutablePointer<UInt8> {
        context.data!.assumingMemoryBound(to: UInt8.self)
    }

    /// 左上原点、y 向下的像素坐标
    func pixel(x: Int, y: Int) -> Pixel {
        precondition(x >= 0 && x < width && y >= 0 && y < height, "pixel out of range")
        let offset = y * context.bytesPerRow + x * 4
        return Pixel(bytes[offset], bytes[offset + 1], bytes[offset + 2], bytes[offset + 3])
    }

    func setPixel(_ pixel: Pixel, x: Int, y: Int) {
        let offset = y * context.bytesPerRow + x * 4
        bytes[offset] = pixel.red
        bytes[offset + 1] = pixel.green
        bytes[offset + 2] = pixel.blue
        bytes[offset + 3] = pixel.alpha
    }

    func makeImage() -> CGImage {
        guard let image = context.makeImage() else { preconditionFailure("cannot make image") }
        return image
    }

    /// 某一行中满足条件的像素个数
    func countPixels(inRow y: Int, where predicate: (Pixel) -> Bool) -> Int {
        (0..<width).filter { predicate(pixel(x: $0, y: y)) }.count
    }

    /// 某一列中满足条件的像素个数
    func countPixels(inColumn x: Int, where predicate: (Pixel) -> Bool) -> Int {
        (0..<height).filter { predicate(pixel(x: x, y: $0)) }.count
    }

    /// 整张图中满足条件的像素个数
    func countPixels(where predicate: (Pixel) -> Bool) -> Int {
        var count = 0
        for y in 0..<height {
            for x in 0..<width where predicate(pixel(x: x, y: y)) {
                count += 1
            }
        }
        return count
    }
}

extension Pixel {
    var cgColor: CGColor {
        CGColor(
            srgbRed: CGFloat(red) / 255,
            green: CGFloat(green) / 255,
            blue: CGFloat(blue) / 255,
            alpha: CGFloat(alpha) / 255
        )
    }
}

/// 程序生成的测试图（像素精确，不经过插值）
enum TestImage {
    static func solid(width: Int, height: Int, _ pixel: Pixel) -> CGImage {
        TestCanvas(width: width, height: height, fill: pixel).makeImage()
    }

    /// 棋盘：cell × cell 像素一格，左上格为 first
    static func checkerboard(
        width: Int,
        height: Int,
        cell: Int,
        first: Pixel = .black,
        second: Pixel = .white
    ) -> CGImage {
        let canvas = TestCanvas(width: width, height: height, fill: nil)
        for y in 0..<height {
            for x in 0..<width {
                let isFirst = (x / cell + y / cell).isMultiple(of: 2)
                canvas.setPixel(isFirst ? first : second, x: x, y: y)
            }
        }
        return canvas.makeImage()
    }

    /// 每个像素颜色唯一：R = x、G = y（均取低 8 位），B = 128
    static func coordinates(width: Int, height: Int) -> CGImage {
        let canvas = TestCanvas(width: width, height: height, fill: nil)
        for y in 0..<height {
            for x in 0..<width {
                canvas.setPixel(Pixel(UInt8(x & 0xFF), UInt8(y & 0xFF), 128), x: x, y: y)
            }
        }
        return canvas.makeImage()
    }
}
