import CoreGraphics
import CubbyCore
import Foundation
import Vision

/// 本机文字识别（Vision），不联网。Vision 适配在这里，阅读顺序在 Core 的 TextReadingOrder（可测）；
/// 没有文字时返回空串
struct TextRecognizer: Sendable {
    /// 识别语言：简体中文 + 英文（中英混排是最常见的截图场景）
    static let languages = ["zh-Hans", "en-US"]

    /// Vision 同步识别较慢（大图可达数秒），放到全局队列执行，不占用 Swift 并发的协作线程；
    /// 开始前与完成后检查任务取消，取消时抛出 CancellationError
    func recognize(_ image: CGImage) async throws -> String {
        try Task.checkCancellation()
        let fragments = try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                continuation.resume(with: Result { try Self.fragments(in: image) })
            }
        }
        try Task.checkCancellation()
        return TextReadingOrder.text(fragments)
    }

    private static func fragments(in image: CGImage) throws -> [TextReadingOrder.Fragment] {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.recognitionLanguages = languages
        request.usesLanguageCorrection = true
        try VNImageRequestHandler(cgImage: image, orientation: .up).perform([request])
        return (request.results ?? []).compactMap { observation in
            observation.topCandidates(1).first.map {
                TextReadingOrder.Fragment(text: $0.string, box: observation.boundingBox)
            }
        }
    }
}
