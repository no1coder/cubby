import Foundation

// MARK: - 译文缓存的查询与搜索（docs/CLIP-TRANSLATION-DESIGN.md §2、§3）

public extension ClipItem {
    /// 指定目标语言的缓存译文
    func translation(for target: String) -> ClipTranslation? {
        translations?.entry(for: target)
    }

    /// 有至少一种语言的译文（卡片上的「译」角标）
    var hasTranslations: Bool {
        translations?.entries.isEmpty == false
    }

    /// 参与搜索的译文：各语言的纯文本（去掉行内标记）按换行拼接；没有译文文字时为 nil
    var translationSearchText: String? {
        let texts = (translations?.entries ?? []).map(\.plainText).filter { !$0.isEmpty }
        return texts.isEmpty ? nil : texts.joined(separator: "\n")
    }

    /// 关键词是否命中译文（忽略大小写与变音符）
    func translationMatches(_ keyword: String) -> Bool {
        translations?.entries.contains { $0.plainText.localizedStandardContains(keyword) } == true
    }

    /// 需要借助译文才能命中时（有关键词在正文、元数据与图中文字里都找不到），返回第一个补上这些关键词的语言的译文，
    /// 卡片据此显示该译文的首行并高亮关键词；原文已能命中全部关键词、或译文也补不上时为 nil
    func translationMatch(keywords: [String]) -> ClipTranslation? {
        let entries = translations?.entries ?? []
        guard !entries.isEmpty else { return nil }
        let missing = keywords.filter { !matchesExcludingImageText($0) && !imageTextMatches($0) }
        guard !missing.isEmpty else { return nil }
        let texts = entries.map(\.plainText)
        guard missing.allSatisfy({ keyword in texts.contains { $0.localizedStandardContains(keyword) } }) else {
            return nil
        }
        return zip(entries, texts).first { _, text in
            missing.contains { text.localizedStandardContains($0) }
        }?.0
    }
}
