import Foundation

// 剪贴板条目翻译的数据契约（docs/CLIP-TRANSLATION-DESIGN.md §2）。修改需经协调者同意。

/// 一个条目在一种目标语言下的译文缓存
public struct ClipTranslation: Codable, Equatable, Sendable {
    /// BCP-47 目标语言，缓存键
    public let target: String
    /// 检测到的源语言（BCP-47），未知为 nil
    public let source: String?
    /// 引擎显示名（翻译卡徽标、「译」角标的悬停说明）
    public let engineName: String
    public let isOnDevice: Bool
    public let createdAt: Date
    /// 分段算法版本；与当前版本不一致时「对照」退化为原文、译文上下两整段
    public let segmentation: Int
    /// 文本：与原文分段一一对应，nil = 该段未翻译（显示与粘贴时用原文）；图片：按块 id 顺序的译文
    public let segments: [String?]
    /// 段内是否含行内标记（大模型保留的粗体、链接、行内代码，受限 Markdown 子集）；nil 视为 false
    public let usesInlineMarkup: Bool?
    /// 图片：译后 PNG 的 blob 名；文本为 nil
    public let imageName: String?

    public init(
        target: String, source: String?, engineName: String, isOnDevice: Bool, createdAt: Date,
        segmentation: Int, segments: [String?], usesInlineMarkup: Bool? = nil, imageName: String? = nil
    ) {
        self.target = target
        self.source = source
        self.engineName = engineName
        self.isOnDevice = isOnDevice
        self.createdAt = createdAt
        self.segmentation = segmentation
        self.segments = segments
        self.usesInlineMarkup = usesInlineMarkup
        self.imageName = imageName
    }
}

/// 条目上的全部译文。**解码容错**：任何一项损坏只丢弃该项、整体损坏则为空，
/// 绝不向上抛错——否则整份历史解码失败会被备份后清空（ClipStoreLoading）
public struct ClipTranslations: Codable, Equatable, Sendable {
    public let entries: [ClipTranslation]

    public init(_ entries: [ClipTranslation]) {
        self.entries = entries
    }

    public init(from decoder: any Decoder) throws {
        guard var container = try? decoder.unkeyedContainer() else {
            self.entries = []
            return
        }
        var decoded: [ClipTranslation] = []
        while !container.isAtEnd {
            if let entry = try? container.decode(ClipTranslation.self) {
                decoded.append(entry)
            } else if (try? container.decode(Skipped.self)) == nil {
                break
            }
        }
        self.entries = decoded
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.unkeyedContainer()
        try container.encode(contentsOf: entries)
    }

    /// 指定目标语言的译文
    public func entry(for target: String) -> ClipTranslation? {
        entries.first { $0.target == target }
    }

    /// 跳过一项无法解码的元素（任何 JSON 值都能「解码」成它）
    private struct Skipped: Decodable {
        init(from decoder: any Decoder) throws {}
    }
}
