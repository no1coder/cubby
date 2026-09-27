import Foundation

/// 条目内容为何不能翻译。与 App 层 ClipTranslationUnsupportedReason 一一对应
/// （后者另有 unavailable：系统版本不支持，由 App 判定）
public enum ClipUntranslatableReason: Equatable, Sendable, CaseIterable {
    case link
    case file
    case color
    case code
    /// 没有可翻译的文字（空白、纯数字符号）
    case noText
    /// 原文超过 ClipTranslationEligibilityCheck.maxSourceLength
    case tooLong
    /// 图片超过 ClipTranslationEligibilityCheck.maxImageDimension / maxImagePixelArea
    case imageTooLarge
}

/// 翻译资格（docs/CLIP-TRANSLATION-DESIGN.md §2.3、§8，纯逻辑，只看内容；疑似密钥的确认按实际发送的文字判定，见 ClipTranslationDocument.sentTexts）
public enum ClipTranslationEligibilityCheck {
    /// 可翻译的原文长度上限（UTF-16 码元）：大模型约 2 批，与图片文字索引同级
    public static let maxSourceLength = 10_000
    /// 可翻译图片的最长边（像素）：需要整图解码后绘制
    public static let maxImageDimension = 8192
    /// 可翻译图片的面积上限（像素，8K）
    public static let maxImagePixelArea = 7680 * 4320

    /// 不能翻译的原因；可以翻译时为 nil。App 层据此映射出 ClipTranslationEligibility
    public static func unsupportedReason(for item: ClipItem) -> ClipUntranslatableReason? {
        switch item.payload {
        case .files:
            return .file
        case .image(let ref):
            return isImageTooLarge(width: ref.width, height: ref.height) ? .imageTooLarge : nil
        case .text(let text):
            switch item.kind {
            case .link: return .link
            case .color: return .color
            case .text, .image, .file: return textReason(text)
            }
        }
    }

    public static func isImageTooLarge(width: Int, height: Int) -> Bool {
        max(width, height) > maxImageDimension || width * height > maxImagePixelArea
    }

    private static func textReason(_ text: String) -> ClipUntranslatableReason? {
        guard text.contains(where: \.isLetter) else { return .noText }
        if TextHeuristics.looksLikeCode(text) { return .code }
        return text.utf16.count > maxSourceLength ? .tooLong : nil
    }
}
