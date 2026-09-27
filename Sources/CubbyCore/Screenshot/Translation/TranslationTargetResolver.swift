import Foundation
import NaturalLanguage

// 目标语言的解析（实现线 T2 拥有，docs/TRANSLATION-DESIGN.md §3.4）。签名是契约。

public enum TranslationTargetResolver {
    /// 源语言检测的最低置信度：低于它视为无法判断（大模型自动识别；系统翻译改用候选列表）
    static let minimumSourceConfidence = 0.5
    /// 少于这么多个字母时不做语言判断（过短的文本检测结果不可靠，与候选过滤 §3.3 一致）
    static let minimumLettersForDetection = 4

    /// chosen：用户选定的目标（nil = 自动）；preferred：系统首选语言（SystemLanguages.preferred，不受界面语言影响）；
    /// sample：选区原文（用于检测源语言）。返回 nil 表示自动模式下找不到与原文不同的目标语言
    public static func languages(chosen: String?, preferred: [String], sample: String) -> TranslationLanguages? {
        let source = detectSource(sample)
        if let target = chosen.flatMap(TranslationLanguageCatalog.normalize) {
            return TranslationLanguages(source: source, target: target)
        }
        return automaticTarget(source: source, preferred: preferred).map {
            TranslationLanguages(source: source, target: $0)
        }
    }

    /// 自动目标：首选语言中第一个与源语言不同的；都相同则英语；源语言本身就是英语时返回 nil
    static func automaticTarget(source: String?, preferred: [String]) -> String? {
        let normalized = preferred.compactMap(TranslationLanguageCatalog.normalize)
        if let first = normalized.first(where: { $0 != source }) { return first }
        return source == "en" ? nil : "en"
    }

    /// 源语言：主语言的置信度足够高时返回规范化的 BCP-47 标识，否则 nil
    public static func detectSource(_ sample: String) -> String? {
        guard let best = sourceCandidates(sample, maximum: 1).first,
            best.confidence >= minimumSourceConfidence
        else { return nil }
        return best.language
    }

    /// 源语言候选（置信度从高到低，已规范化并去重）：系统翻译在源语言无法判断时逐个尝试
    public static func sourceCandidates(_ sample: String, maximum: Int = 3) -> [SourceLanguageCandidate] {
        guard maximum > 0, sample.lazy.filter(\.isLetter).count >= minimumLettersForDetection else { return [] }
        let recognizer = NLLanguageRecognizer()
        recognizer.processString(sample)
        let hypotheses = recognizer.languageHypotheses(withMaximum: maximum).sorted { $0.value > $1.value }
        return hypotheses.reduce(into: []) { result, hypothesis in
            guard let code = TranslationLanguageCatalog.normalize(hypothesis.key.rawValue),
                !result.contains(where: { $0.language == code })
            else { return }
            result.append(SourceLanguageCandidate(language: code, confidence: hypothesis.value))
        }
    }
}

/// 源语言候选：BCP-47 标识与置信度（0–1）
public struct SourceLanguageCandidate: Equatable, Sendable {
    public let language: String
    public let confidence: Double
}
