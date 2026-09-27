import Foundation

/// 从系统剪贴板读取到的原始内容（尚未入库）
public enum ClipContent: Equatable, Sendable {
    case text(String)
    /// 带格式的文本：纯文本 + 其他表示（键为 UTI，如 public.rtf / public.html）
    case richText(String, formats: [String: Data])
    /// PNG 数据及像素尺寸
    case image(png: Data, width: Int, height: Int)
    case files([URL])
}

/// 尚未规范化的图片：剪贴板上只有 TIFF（系统截图工具、部分老应用）时取出的原始字节。
/// 5K 图的 TIFF→PNG 转码要 145–426ms，主线程只取字节；转码、尺寸解析与大小检查都在 ClipStore.prepare（后台）完成
public struct RawImage: Equatable, Sendable {
    /// NSBitmapImageRep 可读的图片数据（实际为 TIFF）
    public let data: Data

    public init(data: Data) {
        self.data = data
    }
}

/// 监听剪贴板时取出的一份内容：多数可以直接入库（ClipContent）；只有 TIFF 的图片先只取原始字节，入库前在后台转码。
/// 不在 ClipContent 里加一个「未规范化图片」case：ClipContent 被设置（密钥检测）、截图输出等多处按类型穷举，
/// 未规范化的图片只在「剪贴板监听 → 后台记录」这一条路径上存在，单独的类型让其他路径无从拿到未转码的数据
public enum PasteboardCapture: Equatable, Sendable {
    case content(ClipContent)
    case rawImage(RawImage)
}

/// 采集限制，过大的内容直接忽略，避免撑爆内存与磁盘
public enum CaptureLimits {
    public static let maxTextBytes = 2 * 1024 * 1024
    public static let maxImageBytes = 30 * 1024 * 1024
    /// TIFF 通常未压缩，允许更大，但仍需在解码前拦截
    public static let maxTIFFBytes = 150 * 1024 * 1024
    /// 单种富文本格式的上限
    public static let maxFormatBytes = 4 * 1024 * 1024
}

/// 富文本格式的编解码（二进制 plist，保存为单个 blob）
public enum RichFormats {
    /// 需要随文本一起保存的格式
    public static let supportedTypes = ["public.rtf", "public.html"]

    public static func encode(_ formats: [String: Data]) throws -> Data {
        let encoder = PropertyListEncoder()
        encoder.outputFormat = .binary
        return try encoder.encode(formats)
    }

    public static func decode(_ data: Data) throws -> [String: Data] {
        try PropertyListDecoder().decode([String: Data].self, from: data)
    }
}
