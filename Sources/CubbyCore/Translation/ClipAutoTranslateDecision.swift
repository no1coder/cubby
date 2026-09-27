import Foundation

/// 复制时自动翻译对一个条目的判定（docs/CLIP-TRANSLATION-DESIGN.md §6，纯函数，含一次源语言检测，宜在后台调用）：
/// 先做只看状态与内容的检查（ClipAutoTranslatePolicy.skipReason），再检测源语言、按「共享目标语言或自动规则」
/// 定出目标语言，最后检查置信度、是否同一语言与该语言的缓存。粘贴目标应用在复制时未知，不参与
public enum ClipAutoTranslateDecision: Equatable, Sendable {
    case skip(ClipAutoTranslatePolicy.Skip)
    case translate(TranslationLanguages)

    /// shared：与截图共享的目标语言（nil = 自动）；preferred：系统首选语言
    public static func decide(
        for item: ClipItem, shared: String?, preferred: [String], conditions: ClipAutoTranslatePolicy.Conditions
    ) -> ClipAutoTranslateDecision {
        if let skip = precheck(item, conditions: conditions) { return .skip(skip) }
        let chosen = shared.flatMap(TranslationLanguageCatalog.normalize)
        guard let text = item.text, let best = TranslationTargetResolver.sourceCandidates(text, maximum: 1).first
        else { return .skip(.uncertainLanguage) }
        guard
            let target = chosen
                ?? TranslationTargetResolver.automaticTarget(source: best.language, preferred: preferred)
        else { return .skip(.sameLanguage) }
        if let skip = ClipAutoTranslatePolicy.languageSkipReason(
            source: best.language, confidence: best.confidence, target: target)
        {
            return .skip(skip)
        }
        if item.translation(for: target) != nil { return .skip(.cached) }
        return .translate(TranslationLanguages(source: best.language, target: target))
    }

    /// 不检测语言的初筛（状态与内容）：复制后排队之前调用，不合格的条目不排队，以免顶掉排队中的合格条目。
    /// 缓存要等定下目标语言才能判断，这里不查
    public static func precheck(
        _ item: ClipItem, conditions: ClipAutoTranslatePolicy.Conditions
    ) -> ClipAutoTranslatePolicy.Skip? {
        // 目标语言只影响缓存检查；空目标语言不会命中任何缓存（ClipTranslationLimits 不接受空目标语言）
        ClipAutoTranslatePolicy.skipReason(for: item, target: "", conditions: conditions)
    }
}
