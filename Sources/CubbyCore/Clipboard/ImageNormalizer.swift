import AppKit

/// 图片内容无法入库的原因
public enum ImageCaptureError: LocalizedError, Equatable, Sendable {
    /// 数据无法解码或无法转为 PNG
    case undecodable
    /// 超过采集上限（转码前的原始数据超过 maxTIFFBytes，或转码后的 PNG 超过 maxImageBytes）
    case tooLarge(bytes: Int)

    /// 只用于日志（不显示给用户），不需要本地化
    public var errorDescription: String? {
        switch self {
        case .undecodable: "Image data could not be decoded"
        case .tooLarge(let bytes): "Image exceeds the capture limit (\(bytes) bytes)"
        }
    }
}

/// 转码后的 PNG 及其像素尺寸
struct NormalizedImage: Equatable, Sendable {
    let png: Data
    let width: Int
    let height: Int

    var content: ClipContent {
        .image(png: png, width: width, height: height)
    }
}

/// 把剪贴板上的原始图片规范化为 PNG（在后台执行，见 ClipStore.prepare）
enum ImageNormalizer {
    /// 与此前在主线程转码的写法完全相同（NSBitmapImageRep → PNG），同一张图得到逐字节相同的 PNG，去重哈希不变。
    /// 每次调用使用独立的位图对象，可在任意线程执行。
    static func normalize(_ raw: RawImage, maxPNGBytes: Int = CaptureLimits.maxImageBytes) throws -> NormalizedImage {
        // 读取时已拦截；这里再查一次，覆盖不经读取直接构造的原始图片
        guard raw.data.count <= CaptureLimits.maxTIFFBytes else {
            throw ImageCaptureError.tooLarge(bytes: raw.data.count)
        }
        guard let rep = NSBitmapImageRep(data: raw.data),
            let png = rep.representation(using: .png, properties: [:])
        else { throw ImageCaptureError.undecodable }
        guard png.count <= maxPNGBytes else { throw ImageCaptureError.tooLarge(bytes: png.count) }
        return NormalizedImage(png: png, width: rep.pixelsWide, height: rep.pixelsHigh)
    }
}
