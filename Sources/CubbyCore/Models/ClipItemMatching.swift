import Foundation

// MARK: - 关键词匹配（忽略大小写与变音符）

public extension ClipItem {
    /// 关键词是否命中正文、文件路径、来源应用名、图片中识别出的文字或译文。
    /// 超长文本只检索前 searchLimit 个字符，保证逐字搜索时的响应速度。
    func matches(keyword: String) -> Bool {
        matchesExcludingImageText(keyword) || imageTextMatches(keyword) || translationMatches(keyword)
    }

    /// 不看识别文字的匹配：来源应用名、图片类型名（先查这些短字段），再查正文或文件路径
    func matchesExcludingImageText(_ keyword: String) -> Bool {
        matchesMetadata(keyword) || searchableContent?.localizedStandardContains(keyword) == true
    }

    /// 关键词是否命中来源应用名；图片还可按类型名命中（不暴露内部 blob 文件名）
    func matchesMetadata(_ keyword: String) -> Bool {
        if source?.name?.localizedStandardContains(keyword) == true { return true }
        guard case .image = payload else { return false }
        return kind.displayName.localizedStandardContains(keyword)
    }

    /// 关键词是否命中图片中识别出的文字
    func imageTextMatches(_ keyword: String) -> Bool {
        recognizedText?.localizedStandardContains(keyword) == true
    }

    /// 有可搜索的识别文字（nil 与空串都没有）
    var hasImageText: Bool {
        recognizedText?.isEmpty == false
    }

    /// 参与相关度排序的正文：文本的前 searchLimit 个字符，或逐行拼接的文件路径；图片没有正文
    var searchableContent: Substring? {
        switch payload {
        case .text(let value):
            return value.prefix(Self.searchLimit)
        case .image:
            return nil
        case .files(let paths):
            return Substring(paths.joined(separator: "\n"))
        }
    }

    static let searchLimit = 200_000
}
