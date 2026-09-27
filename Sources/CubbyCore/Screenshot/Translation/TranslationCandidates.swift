import CoreGraphics
import Foundation
import NaturalLanguage

// 哪些块需要翻译（实现线 T3 拥有，docs/TRANSLATION-DESIGN.md §3.3）。

public enum TranslationCandidates {
    /// 不翻译的原因（调试与验收工具展示用）
    public enum SkipReason: String, Equatable, Sendable {
        /// 被遮挡（马赛克等）的面积 ≥ 块面积的 20%
        case hidden
        /// 疑似密钥
        case secret
        /// 没有字母（数字、符号、价格、时间），或只是数字加短单位
        case noLetters
        /// 代码、路径、URL、邮箱、命令行
        case code
        /// 已是目标语言
        case targetLanguage
    }

    /// 被遮挡面积占比的下限
    static let hiddenAreaFraction: CGFloat = 0.2
    /// 语言判断的置信度下限
    static let languageConfidence = 0.8
    /// 少于这么多个字母的块不做语言判断（交给引擎）
    static let minimumLettersForLanguage = 4

    /// 需要翻译的块，其余保持原图像素：被遮挡（hidden，例如马赛克区域，全局点）、疑似密钥、
    /// 没有字母、已是目标语言的块都不翻译，也不发送给引擎
    public static func translatable(_ blocks: [TextBlock], target: String, hidden: [CGRect]) -> [TextBlock] {
        blocks.filter { skipReason(for: $0, target: target, hidden: hidden) == nil }
    }

    /// 某块不翻译的原因；nil 表示需要翻译
    public static func skipReason(for block: TextBlock, target: String, hidden: [CGRect]) -> SkipReason? {
        if isHidden(block.frame, by: hidden) { return .hidden }
        if SecretDetector.containsSecret(block.text) { return .secret }
        if NonTranslatableText.isNumeric(block.text) { return .noLetters }
        if NonTranslatableText.isCodeLike(block.text) { return .code }
        if isAlready(block.text, in: target) { return .targetLanguage }
        return nil
    }

    // MARK: - 内部

    static func isHidden(_ frame: CGRect, by hidden: [CGRect]) -> Bool {
        let area = frame.width * frame.height
        guard area > 0 else { return false }
        let covered = hidden.reduce(CGFloat(0)) { sum, rect in
            let overlap = rect.intersection(frame)
            return overlap.isNull ? sum : sum + overlap.width * overlap.height
        }
        return covered >= area * hiddenAreaFraction
    }

    private static func isAlready(_ text: String, in target: String) -> Bool {
        let letters = text.unicodeScalars.filter { $0.properties.isAlphabetic }.count
        guard letters >= minimumLettersForLanguage else { return false }
        let recognizer = NLLanguageRecognizer()
        recognizer.processString(text)
        guard let (language, confidence) = recognizer.languageHypotheses(withMaximum: 1).first,
            confidence >= languageConfidence
        else { return false }
        return normalized(language.rawValue) == normalized(target)
    }

    /// 语言比较口径：中文按字形（zh-Hans / zh-Hant），其他语言只看语言代码
    static func normalized(_ identifier: String) -> String {
        let components = Locale.Language(identifier: identifier)
        let code = components.languageCode?.identifier ?? identifier.lowercased()
        guard code == "zh" else { return code }
        let script = components.script?.identifier
        let region = components.region?.identifier
        let traditional = script == "Hant" || (script == nil && ["TW", "HK", "MO"].contains(region ?? ""))
        return traditional ? "zh-Hant" : "zh-Hans"
    }
}
