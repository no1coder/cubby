import CoreGraphics
import CoreImage
import CubbyCore
import Foundation
import ImageIO

/// 晾衣绳放大编辑的「冻结帧」：不截屏（不需要屏幕录制权限），用图片本身合成一整屏的背景
///
/// 自下而上：图片自身的模糊放大副本（铺满整屏）→ 黑色压暗 → 图片（带柔和投影）画在布局给出的位置。
/// 覆盖层还会在选区外再压一层 `OverlayTokens.dimAlpha`（0.45），两层合起来约 0.6，与设计稿的暗度一致，
/// 因此这里只压 0.3，避免叠加后过暗。
enum HistoryImageBackdrop {
    /// 背景自身的压暗
    static let darkening: CGFloat = 0.3
    /// 模糊副本的长边像素数：先缩到这么小再模糊，开销与屏幕大小无关
    private static let blurSourceLength: CGFloat = 96
    /// 模糊半径（模糊副本的像素）
    private static let blurRadius: Double = 6
    /// 图片投影（屏幕点）
    private static let shadowBlur: CGFloat = 40
    private static let shadowOffset: CGFloat = 12
    private static let shadowAlpha: CGFloat = 0.45
    private static let bitmapInfo = CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue

    /// 解码后的历史图片
    struct Decoded {
        let image: CGImage
        /// PNG 的 DPI 倍率（DPI / 72）；没有记录时为 1
        let dpiScale: CGFloat
    }

    /// 读取图片文件；无法解码时为 nil
    static func decode(_ url: URL) -> Decoded? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
            let image = CGImageSourceCreateImageAtIndex(
                source, 0, [kCGImageSourceShouldCacheImmediately: true] as CFDictionary),
            image.width > 0, image.height > 0
        else { return nil }
        let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
        let dpi = (properties?[kCGImagePropertyDPIWidth] as? NSNumber)?.doubleValue ?? 72
        let scale = dpi.isFinite && dpi >= 72 ? CGFloat(dpi) / 72 : 1
        return Decoded(image: image, dpiScale: min(scale, 4))
    }

    /// 合成整屏背景（屏幕像素尺寸）；无法创建位图时为 nil
    static func render(_ image: CGImage, layout: HistoryImageLayout, screen: CaptureScreen) -> CGImage? {
        let size = screen.pixelSize
        guard size.width >= 1, size.height >= 1,
            let space = CGColorSpace(name: CGColorSpace.sRGB),
            let context = CGContext(
                data: nil, width: Int(size.width), height: Int(size.height), bitsPerComponent: 8,
                bytesPerRow: 0, space: space, bitmapInfo: bitmapInfo)
        else { return nil }
        let bounds = CGRect(origin: .zero, size: size)
        context.setFillColor(CGColor(gray: 0, alpha: 1))
        context.fill(bounds)
        if let blurred = blurred(image) {
            context.interpolationQuality = .high
            context.draw(blurred, in: aspectFill(CGSize(width: blurred.width, height: blurred.height), in: bounds))
        }
        context.setFillColor(CGColor(gray: 0, alpha: darkening))
        context.fill(bounds)
        drawImage(image, at: layout.imageRect, screen: screen, into: context)
        return context.makeImage()
    }

    // MARK: - 私有

    /// 图片画在全局点 rect 处（CoreGraphics 左下原点：翻转 y），带柔和投影
    private static func drawImage(_ image: CGImage, at rect: CGRect, screen: CaptureScreen, into context: CGContext) {
        let scale = screen.scale
        let local = rect.offsetBy(dx: -screen.frame.minX, dy: -screen.frame.minY)
        let target = CGRect(
            x: local.minX * scale,
            y: CGFloat(context.height) - local.maxY * scale,
            width: local.width * scale,
            height: local.height * scale)
        context.saveGState()
        context.setShadow(
            offset: CGSize(width: 0, height: -shadowOffset * scale), blur: shadowBlur * scale,
            color: CGColor(gray: 0, alpha: shadowAlpha))
        context.setFillColor(CGColor(gray: 0, alpha: 1))
        context.fill(target)
        context.restoreGState()
        context.interpolationQuality = .high
        context.draw(image, in: target)
    }

    /// 缩小到长边 96 px 再高斯模糊（边缘夹取，不会出现暗边）
    private static func blurred(_ image: CGImage) -> CGImage? {
        let longest = CGFloat(max(image.width, image.height))
        let factor = min(blurSourceLength / longest, 1)
        let width = max(Int((CGFloat(image.width) * factor).rounded()), 1)
        let height = max(Int((CGFloat(image.height) * factor).rounded()), 1)
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
            let small = CGContext(
                data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0, space: space,
                bitmapInfo: bitmapInfo)
        else { return nil }
        small.interpolationQuality = .high
        small.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        guard let reduced = small.makeImage() else { return nil }
        let input = CIImage(cgImage: reduced)
        let output = input.clampedToExtent().applyingGaussianBlur(sigma: blurRadius).cropped(to: input.extent)
        return CIContext(options: [.cacheIntermediates: false]).createCGImage(output, from: input.extent)
    }

    /// 等比铺满 bounds 并居中（超出部分裁掉）
    private static func aspectFill(_ size: CGSize, in bounds: CGRect) -> CGRect {
        let factor = max(bounds.width / size.width, bounds.height / size.height)
        let width = size.width * factor
        let height = size.height * factor
        return CGRect(x: bounds.midX - width / 2, y: bounds.midY - height / 2, width: width, height: height)
    }
}
