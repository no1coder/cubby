import AppKit
import ImageIO

/// 从历史贴到屏幕上的图片：解码结果与摆放位置，交给 PinnedImageController.pin(image:pixelSize:scale:at:)
struct HistoryImagePin {
    let image: CGImage
    let pixelSize: CGSize
    /// 像素 / 点，决定贴图的点尺寸（pixelSize / scale）
    let scale: CGFloat
    /// AppKit 屏幕坐标下的中心点
    let center: CGPoint
}

/// 历史图片的贴图尺寸与解码
enum HistoryImagePinning {
    /// 贴图最多占可见区域的比例：大图等比缩小到放得下，四周留出拖动的余地
    static let maxScreenFraction: CGFloat = 0.8
    /// 图片 DPI 的基准（72 DPI 即 1 像素 = 1 点）
    private static let baseDPI: CGFloat = 72

    /// 贴图的点尺寸：按图片自身倍率换算为点，超出可见区域的 maxScreenFraction 时等比缩小
    static func pointSize(pixelSize: CGSize, imageScale: CGFloat, visibleSize: CGSize) -> CGSize {
        let scale = max(imageScale, 1)
        let natural = CGSize(width: pixelSize.width / scale, height: pixelSize.height / scale)
        guard natural.width > 0, natural.height > 0 else { return .zero }
        let fit = min(
            1,
            visibleSize.width * maxScreenFraction / natural.width,
            visibleSize.height * maxScreenFraction / natural.height
        )
        return CGSize(width: (natural.width * fit).rounded(), height: (natural.height * fit).rounded())
    }

    /// 在给定屏幕可见区域的中央贴图；解码在后台进行，大图按显示尺寸降采样（不会整张解码 7000×5000 的原图）
    @MainActor
    static func load(url: URL, on screen: NSScreen) async -> HistoryImagePin? {
        let visible = screen.visibleFrame
        let backingScale = screen.backingScaleFactor
        let decoded = await Task.detached(priority: .userInitiated) {
            decode(url: url, visibleSize: visible.size, backingScale: backingScale)
        }.value
        guard let decoded else { return nil }
        return HistoryImagePin(
            image: decoded.image,
            pixelSize: CGSize(width: decoded.image.width, height: decoded.image.height),
            scale: decoded.scale,
            center: CGPoint(x: visible.midX, y: visible.midY)
        )
    }

    private struct Decoded: @unchecked Sendable {
        let image: CGImage
        let scale: CGFloat
    }

    private static func decode(url: URL, visibleSize: CGSize, backingScale: CGFloat) -> Decoded? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
            let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
            let width = (properties[kCGImagePropertyPixelWidth] as? NSNumber)?.doubleValue,
            let height = (properties[kCGImagePropertyPixelHeight] as? NSNumber)?.doubleValue
        else { return nil }
        // 有 DPI 信息时按图片自身倍率（系统截图为 144 DPI，即 2 倍）；没有时按屏幕像素 1:1，与截图贴图一致
        let dpi = (properties[kCGImagePropertyDPIWidth] as? NSNumber)?.doubleValue
        let imageScale = dpi.map { CGFloat($0) / baseDPI } ?? backingScale
        let points = pointSize(
            pixelSize: CGSize(width: width, height: height),
            imageScale: imageScale,
            visibleSize: visibleSize
        )
        guard points.width > 0 else { return nil }
        let maxPixel = min(max(width, height), (max(points.width, points.height) * backingScale).rounded(.up))
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixel,
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            return nil
        }
        return Decoded(image: image, scale: CGFloat(image.width) / points.width)
    }
}
