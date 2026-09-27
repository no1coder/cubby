import CoreGraphics
import Foundation
import ImageIO

/// 把一张历史图片伪装成「原点在 (0,0) 的一块屏幕」（docs/CLIP-TRANSLATION-DESIGN.md §5.1，纯函数）：
/// 截图翻译的识别 / 版面 / 绘制契约都以「冻结帧 + 全局点」为坐标系，合成帧让它们原样作用于历史图片，
/// 不改截图翻译的任何契约。整数 scale 下 `screen.pixelSize` 与图片像素尺寸严格相等，整帧裁剪取到整张图
public enum HistoryImageFrame {
    /// 图片 DPI 的基准（72 DPI 即 1 像素 = 1 点）
    public static let baseDPI = 72.0
    public static let scaleRange: ClosedRange<CGFloat> = 1...3

    /// 渲染失败的原因
    public enum RenderError: Error, Equatable, Sendable {
        /// 无法创建位图 context 或生成位图
        case contextUnavailable
    }

    /// 解码结果：位图与 PNG 里记录的 DPI（没有时为 nil）
    ///
    /// `@unchecked Sendable` 的理由：CGImage 不可变，可以安全地跨线程读取
    public struct Decoded: @unchecked Sendable {
        public let image: CGImage
        public let dpi: Double?
    }

    /// 解码历史图片（取第一帧与 DPI）；无法解码时为 nil。整图解码，调用方应在后台线程调用
    public static func decode(_ data: Data) -> Decoded? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
            let image = CGImageSourceCreateImageAtIndex(
                source, 0, [kCGImageSourceShouldCacheImmediately: true] as CFDictionary)
        else { return nil }
        let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
        let dpi = (properties?[kCGImagePropertyDPIWidth] as? NSNumber)?.doubleValue
        return Decoded(image: image, dpi: dpi)
    }

    /// DPI → 点到像素的缩放：DPI / 72 四舍五入并夹在 1…3（与贴图的倍率一致）；没有或非法时为 1
    public static func scale(dpi: Double?) -> CGFloat {
        guard let dpi, dpi.isFinite, dpi > 0 else { return 1 }
        let rounded = CGFloat((dpi / baseDPI).rounded())
        return min(max(rounded, scaleRange.lowerBound), scaleRange.upperBound)
    }

    /// 合成屏幕：CaptureScreen(id: 0, frame: (0, 0, 像素宽 / scale, 像素高 / scale), scale)；选区为整个 frame
    public static func make(image: CGImage, scale: CGFloat) -> (frame: FrozenFrame, selection: CGRect) {
        let points = CGRect(
            x: 0, y: 0, width: CGFloat(image.width) / scale, height: CGFloat(image.height) / scale)
        let screen = CaptureScreen(id: 0, frame: points, scale: scale)
        return (FrozenFrame(screen: screen, image: image), points)
    }

    /// 整帧的渲染环境：一个用户单位 = 图片的一个像素
    public static func environment(for frame: FrozenFrame) -> RenderEnvironment {
        RenderEnvironment(
            origin: .zero, scale: frame.screen.scale,
            targetPixelSize: CGSize(width: frame.image.width, height: frame.image.height), pixelatedFrame: nil,
            frameOrigin: .zero)
    }

    /// 原图 + 译文版面 → 译后成图（与原图同尺寸，sRGB）
    public static func render(_ frame: FrozenFrame, blocks: [TranslatedBlock]) throws(RenderError) -> CGImage {
        let width = frame.image.width
        let height = frame.image.height
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
            let context = CGContext(
                data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0, space: space,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue)
        else { throw .contextUnavailable }
        context.interpolationQuality = .none
        context.draw(frame.image, in: CGRect(x: 0, y: 0, width: width, height: height))
        TranslationPainter.draw(blocks, in: context, environment: environment(for: frame))
        guard let image = context.makeImage() else { throw .contextUnavailable }
        return image
    }
}
