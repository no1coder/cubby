import CoreGraphics
@testable import CubbyCore

/// 放大镜测试用位图：按像素坐标生成已知颜色的 sRGB 图像（左上原点）
enum MagnifierTestImage {
    /// 一个像素的 8 位分量（非预乘）
    struct Pixel {
        let red: UInt8
        let green: UInt8
        let blue: UInt8
        let alpha: UInt8
    }

    /// 默认图案：red = x × 5，green = y × 5，blue = 100，不透明
    static func gradient(width: Int, height: Int) -> CGImage {
        make(width: width, height: height) { x, y in
            Pixel(red: UInt8(x * 5), green: UInt8(y * 5), blue: 100, alpha: 255)
        }
    }

    /// 期望颜色：与 gradient 一致
    static func gradientColor(x: Int, y: Int) -> RGBAColor {
        RGBAColor(red: Double(x * 5) / 255, green: Double(y * 5) / 255, blue: 100.0 / 255, alpha: 1)
    }

    static func make(width: Int, height: Int, pixel: (Int, Int) -> Pixel) -> CGImage {
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        for y in 0..<height {
            for x in 0..<width {
                let value = pixel(x, y)
                let index = (y * width + x) * 4
                // 预乘 alpha 存储
                bytes[index] = UInt8(Int(value.red) * Int(value.alpha) / 255)
                bytes[index + 1] = UInt8(Int(value.green) * Int(value.alpha) / 255)
                bytes[index + 2] = UInt8(Int(value.blue) * Int(value.alpha) / 255)
                bytes[index + 3] = value.alpha
            }
        }
        let space = CGColorSpace(name: CGColorSpace.sRGB)!
        let info = CGImageAlphaInfo.premultipliedLast.rawValue
        let context = bytes.withUnsafeMutableBytes { buffer in
            CGContext(
                data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8,
                bytesPerRow: width * 4, space: space, bitmapInfo: info)!
        }
        let image = context.makeImage()!
        return image
    }
}
