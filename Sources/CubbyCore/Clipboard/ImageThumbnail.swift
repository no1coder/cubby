import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// 图片条目的预生成缩略图：记录时（后台）按卡片需要的尺寸缩小一次存成小文件，面板卡片只解码它。
///
/// 5K 图的原图没有内嵌缩略图，每次冷缓存都要整张解码再缩放（72–149ms）；720px 的 JPEG 解码不到 1ms。
/// - 文件名由原图名推出（`<摘要>.thumb`），不写入历史：旧版本读到的历史不变，删除 / 撤销 / 清空 / 淘汰 /
///   孤儿清理按原图名一并处理（见 ClipStore 的 storedBlobNames）；
/// - 格式：不透明的图用 JPEG（体积小、解码最快、任何机器都能编码）；有透明像素的用 PNG，保留透明度。
///   不用 HEIC：编码依赖硬件 HEVC 编码器，部分机器（含虚拟机 / CI）不可用，解码也比 JPEG 慢（约 1.8ms 对 0.4ms）；
/// - 文件内容自带格式签名，读取时由 ImageIO 识别，因此不需要区分扩展名。
public enum ImageThumbnail {
    /// 卡片缩略图的最长边（像素）。面板卡片（CardContent）按 pixelSize(width:height:) 请求，尺寸规则只在这里定义
    public static let pixelSize = 720
    /// 高宽比超过它的竖长图（如长网页截图）按宽度保持清晰，长边相应放大
    static let tallRatio: CGFloat = 1.5
    /// 竖长图缩略图的长边上限：按宽度解码才清晰，但不为一张卡片解码整张超长图
    static let tallPixelLimit = 2_048
    /// 原图不超过这么多像素时不生成：剖析实测 2.5MP 以下的图直接解码原图中位只要 3–5ms，
    /// 这类图多是几十 KB 的界面截图，720px 的 JPEG 反而比原图大
    static let minimumPixels = 2_500_000
    static let jpegQuality = 0.8
    static let fileExtension = "thumb"

    /// 是否竖长图（高 / 宽超过 1.5）：卡片据此顶部对齐，缩略图按宽度保持清晰
    public static func isTall(width: Int, height: Int) -> Bool {
        aspectRatio(width: width, height: height) > tallRatio
    }

    /// 卡片请求、也是预生成的缩略图最长边：普通图 720；竖长图按宽度清晰、长边相应放大（不超过 2048）。
    /// 卡片与缩略图共用这一个计算，请求尺寸正好等于缩略图尺寸
    public static func pixelSize(width: Int, height: Int) -> Int {
        guard isTall(width: width, height: height) else { return pixelSize }
        return min(tallPixelLimit, Int(CGFloat(pixelSize) * aspectRatio(width: width, height: height)))
    }

    private static func aspectRatio(width: Int, height: Int) -> CGFloat {
        width > 0 ? CGFloat(height) / CGFloat(width) : 1
    }

    /// 只为解码慢的大图生成：原图超过 2.5MP，且比缩略图大
    public static func isNeeded(width: Int, height: Int) -> Bool {
        width * height > minimumPixels && max(width, height) > pixelSize(width: width, height: height)
    }

    public static func name(forImage imageName: String) -> String {
        (imageName as NSString).deletingPathExtension + "." + fileExtension
    }

    public static func url(forImageAt imageURL: URL) -> URL {
        imageURL.deletingLastPathComponent().appendingPathComponent(name(forImage: imageURL.lastPathComponent))
    }

    // MARK: - 生成

    /// 由原图数据（PNG，或转码前的 TIFF）生成缩略图文件内容；不需要（原图不大）或无法解码时返回 nil
    static func make(fromImageData data: Data, width: Int, height: Int) -> Data? {
        guard isNeeded(width: width, height: height),
            let source = CGImageSourceCreateWithData(data as CFData, nil)
        else { return nil }
        return make(from: source, width: width, height: height)
    }

    /// 由原图文件生成（回填旧条目时用，不把整张原图读进内存）
    static func make(fromImageAt url: URL, width: Int, height: Int) -> Data? {
        guard isNeeded(width: width, height: height),
            let source = CGImageSourceCreateWithURL(url as CFURL, nil)
        else { return nil }
        return make(from: source, width: width, height: height)
    }

    private static func make(from source: CGImageSource, width: Int, height: Int) -> Data? {
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: pixelSize(width: width, height: height),
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
        return encode(image)
    }

    /// 不透明 → JPEG；有透明像素 → PNG
    static func encode(_ image: CGImage) -> Data? {
        let output = NSMutableData()
        let isOpaque = !hasTransparentPixels(image)
        let type = isOpaque ? UTType.jpeg : UTType.png
        guard let destination = CGImageDestinationCreateWithData(output, type.identifier as CFString, 1, nil)
        else { return nil }
        let properties: [CFString: Any] = isOpaque ? [kCGImageDestinationLossyCompressionQuality: jpegQuality] : [:]
        CGImageDestinationAddImage(destination, image, properties as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return output as Data
    }

    /// 是否真的有不透明度低于 100% 的像素：截图 PNG 大多带 alpha 通道但全部不透明，这种仍可用 JPEG
    static func hasTransparentPixels(_ image: CGImage) -> Bool {
        switch image.alphaInfo {
        case .none, .noneSkipFirst, .noneSkipLast: return false
        default: break
        }
        let width = image.width
        let height = image.height
        let bytesPerRow = width * 4
        guard width > 0, height > 0,
            let context = CGContext(
                data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: bytesPerRow,
                space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue),
            let pixels = context.data
        else { return true }
        // 画进 RGBA 位图后检查每个像素的 alpha 字节（缩略图最大约 1.1MB，扫描不到 1ms）
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        let bytes = pixels.bindMemory(to: UInt8.self, capacity: context.bytesPerRow * height)
        for row in 0..<height {
            let start = bytes + row * context.bytesPerRow
            for offset in stride(from: 3, to: bytesPerRow, by: 4) where start[offset] != 255 {
                return true
            }
        }
        return false
    }

    // MARK: - 读取

    /// 面板卡片请求缩略图时先读预生成的小文件，返回已解码的位图。只服务卡片尺寸的请求：
    /// 恰好等于缩略图尺寸（卡片按同一规则请求），或不超过 720px。预览面板的 1600px 等更大的请求、
    /// 文件不存在或无法识别时返回 nil，调用方退回解码原图（竖长图的缩略图长边可达 2048，但宽度不够预览用）
    public static func decode(forImageAt imageURL: URL, maxPixelSize: Int) -> CGImage? {
        let url = url(forImageAt: imageURL)
        guard FileManager.default.fileExists(atPath: url.path),
            let source = CGImageSourceCreateWithURL(url as CFURL, nil),
            let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
            let width = properties[kCGImagePropertyPixelWidth] as? Int,
            let height = properties[kCGImagePropertyPixelHeight] as? Int
        else { return nil }
        let longEdge = max(width, height)
        guard maxPixelSize == longEdge || maxPixelSize <= min(pixelSize, longEdge) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
        ]
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
    }
}
