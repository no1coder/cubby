import CoreGraphics
import CubbyCore
import Foundation
import ImageIO
import Vision

enum ImageTextRecognitionError: Error {
    /// 文件无法读取或不是可解码的图片
    case unreadable
}

/// ImageTextIndexer（Core）使用的本机识别（Vision，不联网）：语言与阅读顺序与截图「提取文字」一致
/// （复用 TextRecognizer.languages 与 TextReadingOrder），但在 utility 串行队列执行——
/// TextRecognizer 固定使用 userInitiated（用户正在等结果），不适合后台回填。
/// 串行队列同时保证：即使上一轮被取消，Vision 也不会有两张图片同时在识别。
struct VisionImageTextRecognizer: ImageTextRecognizing {
    private static let queue = DispatchQueue(label: "io.github.no1coder.Cubby.image-text", qos: .utility)

    /// 开始前检查取消；Vision 一旦开始便无法中断，完成后的结果照常返回，由索引器决定保留还是丢弃
    func recognizeText(at url: URL, maxPixelSize: Int?) async throws -> String {
        try Task.checkCancellation()
        let fragments = try await withCheckedThrowingContinuation { continuation in
            Self.queue.async {
                // 及时释放解码后的位图与 Vision 的中间结果，回填大量图片时内存不累积
                let result = Result { try autoreleasepool { try Self.fragments(at: url, maxPixelSize: maxPixelSize) } }
                continuation.resume(with: result)
            }
        }
        return TextReadingOrder.text(fragments)
    }

    private static func fragments(at url: URL, maxPixelSize: Int?) throws -> [TextReadingOrder.Fragment] {
        let image = try loadImage(at: url, maxPixelSize: maxPixelSize)
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.recognitionLanguages = TextRecognizer.languages
        request.usesLanguageCorrection = true
        try VNImageRequestHandler(cgImage: image, orientation: .up).perform([request])
        return (request.results ?? []).compactMap { observation in
            observation.topCandidates(1).first.map {
                TextReadingOrder.Fragment(text: $0.string, box: observation.boundingBox)
            }
        }
    }

    /// 需要缩放时用 ImageIO 直接解码出缩略图，避免先把超大原图完整解码进内存
    private static func loadImage(at url: URL, maxPixelSize: Int?) throws -> CGImage {
        let sourceOptions = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let source = CGImageSourceCreateWithURL(url as CFURL, sourceOptions) else {
            throw ImageTextRecognitionError.unreadable
        }
        let image: CGImage?
        if let maxPixelSize {
            let options: [CFString: Any] = [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
            ]
            image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
        } else {
            image = CGImageSourceCreateImageAtIndex(source, 0, nil)
        }
        guard let image else { throw ImageTextRecognitionError.unreadable }
        return image
    }
}
