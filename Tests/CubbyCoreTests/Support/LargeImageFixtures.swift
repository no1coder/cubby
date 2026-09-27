import AppKit
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// 较大尺寸的测试图片：用 CGContext 整块填充生成（ImageFixtures 逐像素 setColor，大图太慢）
enum LargeImageFixtures {
    enum Fill {
        /// 完全不透明（带 alpha 通道但每个像素都不透明，像大多数截图 PNG）
        case opaque
        /// 右半边完全透明
        case halfTransparent
        /// 没有 alpha 通道
        case noAlpha
    }

    static func cgImage(width: Int, height: Int, fill: Fill = .opaque) -> CGImage {
        let alphaInfo: CGImageAlphaInfo = fill == .noAlpha ? .noneSkipLast : .premultipliedLast
        guard
            let context = CGContext(
                data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: alphaInfo.rawValue)
        else { preconditionFailure("无法创建测试位图") }
        context.setFillColor(red: 0.2, green: 0.5, blue: 0.9, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        // 左上角一块不同颜色，便于肉眼区分方向
        context.setFillColor(red: 1, green: 0.6, blue: 0, alpha: 1)
        context.fill(CGRect(x: 0, y: height / 2, width: width / 4, height: height / 2))
        if fill == .halfTransparent {
            context.clear(CGRect(x: width / 2, y: 0, width: width - width / 2, height: height))
        }
        guard let image = context.makeImage() else { preconditionFailure("无法生成测试图片") }
        return image
    }

    static func png(width: Int, height: Int, fill: Fill = .opaque) -> Data {
        encode(cgImage(width: width, height: height, fill: fill), type: .png)
    }

    static func tiff(width: Int, height: Int, fill: Fill = .opaque) -> Data {
        encode(cgImage(width: width, height: height, fill: fill), type: .tiff)
    }

    static func encode(_ image: CGImage, type: UTType) -> Data {
        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(output, type.identifier as CFString, 1, nil) else {
            preconditionFailure("无法创建编码器")
        }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else { preconditionFailure("编码失败") }
        return output as Data
    }

    /// 图片数据的类型与像素尺寸
    static func info(of data: Data) -> (type: String, width: Int, height: Int, hasAlpha: Bool)? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
            let type = CGImageSourceGetType(source) as String?,
            let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
            let width = properties[kCGImagePropertyPixelWidth] as? Int,
            let height = properties[kCGImagePropertyPixelHeight] as? Int
        else { return nil }
        let hasAlpha = properties[kCGImagePropertyHasAlpha] as? Bool ?? false
        return (type, width, height, hasAlpha)
    }

    /// 解码后的 alpha 最小值（255 表示完全不透明）
    static func minimumAlpha(of data: Data) -> UInt8? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
            let image = CGImageSourceCreateImageAtIndex(source, 0, nil)
        else { return nil }
        let width = image.width
        let height = image.height
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        let drawn = pixels.withUnsafeMutableBytes { buffer -> Bool in
            guard
                let context = CGContext(
                    data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8,
                    bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
            else { return false }
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        guard drawn else { return nil }
        return stride(from: 3, to: pixels.count, by: 4).map { pixels[$0] }.min()
    }

    static let jpegSignature = Data([0xFF, 0xD8, 0xFF])
}
