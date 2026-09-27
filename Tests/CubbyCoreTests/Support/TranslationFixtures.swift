import Foundation
@testable import CubbyCore

/// 译文缓存的测试工厂：时间以 Fixtures.baseDate 为基准按秒偏移，便于断言「按时间淘汰最早的」
enum TranslationFixtures {
    static func text(
        _ target: String = "zh-Hans",
        segments: [String?] = ["\u{4F60}\u{597D}"],
        at offset: TimeInterval = 0,
        engine: String = "System",
        onDevice: Bool = true,
        markup: Bool? = nil
    ) -> ClipTranslation {
        ClipTranslation(
            target: target, source: "en", engineName: engine, isOnDevice: onDevice,
            createdAt: Fixtures.baseDate.addingTimeInterval(offset), segmentation: ClipTextSegmenter.version,
            segments: segments, usesInlineMarkup: markup)
    }

    static func image(
        _ target: String = "zh-Hans",
        blob: String,
        segments: [String?] = ["\u{8F6F}\u{4EF6}\u{66F4}\u{65B0}"],
        at offset: TimeInterval = 0
    ) -> ClipTranslation {
        ClipTranslation(
            target: target, source: "en", engineName: "System", isOnDevice: true,
            createdAt: Fixtures.baseDate.addingTimeInterval(offset), segmentation: ClipTextSegmenter.version,
            segments: segments, imageName: blob)
    }

    /// 指定长度（UTF-16 码元）的单段译文
    static func sized(_ target: String, length: Int, at offset: TimeInterval = 0) -> ClipTranslation {
        text(target, segments: [String(repeating: "a", count: length)], at: offset)
    }
}

extension ClipHistory {
    /// 测试用：全部译文的字符数（UTF-16 码元，同 ClipTranslationLimits）
    var translationLength: Int {
        items.reduce(0) { total, item in total + (item.translations?.entries.reduce(0) { $0 + $1.length } ?? 0) }
    }
}

extension ClipItem {
    /// 测试用：直接附上若干译文
    func translated(_ entries: ClipTranslation...) -> ClipItem {
        withTranslations(ClipTranslations(entries))
    }
}
