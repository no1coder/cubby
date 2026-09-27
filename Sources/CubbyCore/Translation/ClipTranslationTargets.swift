import Foundation

/// 剪贴板翻译的语言对（docs/CLIP-TRANSLATION-DESIGN.md §0.1 A8、§7，纯函数）。优先级：
/// 1. 翻译卡上明确选定的目标语言；
/// 2. 粘贴目标应用记住的目标语言（A8）——与检测到的源语言相同时不用（例如为 Slack 记住英语，复制的就是英文）；
/// 3. 与截图翻译共享的目标语言（设置 › 翻译，nil = 自动）；
/// 4. 自动规则（TranslationTargetResolver：首选语言中第一个与原文不同的，否则英语）。
///
/// 自动规则也找不到不同的语言时（系统语言为英语、原文也是英语），目标取源语言本身：
/// 界面据 `ClipLanguageMatch.isSameLanguage(source, target)` 显示「原文已是 <语言>」，让用户选择目标语言
public enum ClipTranslationTargets {
    /// 检测源语言的取样上限（字符）：足够判断，又不让长文拖慢
    public static let sampleLimit = 4000

    public static func languages(
        explicit: String?, remembered: String?, shared: String?, preferred: [String], sample: String
    ) -> TranslationLanguages {
        let source = TranslationTargetResolver.detectSource(String(sample.prefix(sampleLimit)))
        if let target = explicit.flatMap(TranslationLanguageCatalog.normalize) {
            return TranslationLanguages(source: source, target: target)
        }
        if let target = remembered.flatMap(TranslationLanguageCatalog.normalize),
            !(source.map { ClipLanguageMatch.isSameLanguage($0, target) } ?? false)
        {
            return TranslationLanguages(source: source, target: target)
        }
        if let target = shared.flatMap(TranslationLanguageCatalog.normalize) {
            return TranslationLanguages(source: source, target: target)
        }
        let target = TranslationTargetResolver.automaticTarget(source: source, preferred: preferred)
        return TranslationLanguages(source: source, target: target ?? source ?? "en")
    }
}

/// 按粘贴目标应用记住的目标语言（A8，bundle id → BCP-47）。不可变值：每次修改返回新值
public struct ClipPasteTargetLanguages: Equatable, Sendable {
    public let languages: [String: String]

    /// 丢弃空 bundle id 与无法识别的语言，语言规范化（en-US → en）
    public init(_ languages: [String: String]) {
        self.languages = languages.reduce(into: [:]) { result, entry in
            let bundleID = entry.key.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !bundleID.isEmpty, let language = TranslationLanguageCatalog.normalize(entry.value) else { return }
            result[bundleID] = language
        }
    }

    public func language(for bundleID: String) -> String? {
        languages[bundleID]
    }

    /// 记住（language 非 nil）或忘记（nil）该应用的目标语言
    public func setting(_ language: String?, for bundleID: String) -> ClipPasteTargetLanguages {
        var updated = languages
        updated[bundleID] = language
        return ClipPasteTargetLanguages(updated)
    }

    /// 设置页列表：按 bundle id 排序，显示顺序稳定
    public var sortedEntries: [(bundleID: String, language: String)] {
        languages.sorted { $0.key < $1.key }.map { (bundleID: $0.key, language: $0.value) }
    }
}
