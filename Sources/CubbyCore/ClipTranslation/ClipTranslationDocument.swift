import Foundation

/// 一个文本条目的「翻译文档」（纯函数、值类型，可在任意线程构造与使用）：把纯文本或富文本条目统一成若干段，
/// 引擎按段翻译、缓存按段对齐（ClipTranslation.segments 与 segments 一一对应），翻译卡按段显示「对照」。
///
/// - 纯文本：按 ClipTextSegmenter 分段，译文按原文的分隔符拼回；
/// - 富文本（§0.1 A2）：按段落分段并保留段落样式（标题、列表、代码块）。系统翻译发送 `plainText`、只保留段落样式；
///   大模型发送 `markup`（受限 Markdown，行内代码与链接地址都换成占位符、不发送），返回后解析回粗体、链接与行内代码。
///   两种发送形式都不含链接地址；实际发送的文字见 `sentTexts(markup:)`（疑似密钥检查应扫描它）。
///
/// 参数 `markup` 表示译文是否为受限 Markdown（大模型翻译富文本时为 true），与缓存里的 usesInlineMarkup 一致；
/// 纯文本文档忽略它
public struct ClipTranslationDocument: Equatable, Sendable {
    /// 一个翻译单元
    public struct Segment: Equatable, Sendable {
        public let index: Int
        /// 代码、网址、代码块等不翻译的段：不送引擎，缓存里为 nil，显示与粘贴用原文
        public let isTranslatable: Bool
        /// 送给系统翻译的纯文本（硬换行已合并为一行；富文本为段落文字，不含行内样式与链接地址）
        public let plainText: String
        /// 送给大模型的文字：富文本为受限 Markdown（行内代码为占位符 `c1`…，链接地址为占位符 `L1`…），
        /// 纯文本与 plainText 相同
        public let markup: String
    }

    private enum Body: Equatable, Sendable {
        case plain(original: String, segments: [ClipTextSegment])
        case rich(ClipRichDocument)
    }

    private let body: Body
    public let segments: [Segment]

    /// 纯文本条目
    public static func plain(_ text: String) -> ClipTranslationDocument {
        let pieces = ClipTextSegmenter.segments(of: text)
        let segments = pieces.map {
            Segment(index: $0.index, isTranslatable: $0.isTranslatable, plainText: $0.source, markup: $0.source)
        }
        return ClipTranslationDocument(body: .plain(original: text, segments: pieces), segments: segments)
    }

    /// 富文本条目：格式能解析出有结构（标题、列表、代码块、行内样式）且有可翻译段落时按富文本，否则按纯文本分段
    public static func make(text: String, formats: [String: Data]) -> ClipTranslationDocument {
        guard let rich = ClipRichTextParser.document(from: formats), rich.hasStructure,
            rich.paragraphs.contains(where: \.isTranslatable)
        else { return plain(text) }
        return ClipTranslationDocument(rich: rich)
    }

    public init(rich document: ClipRichDocument) {
        body = .rich(document)
        segments = document.paragraphs.enumerated().map { index, paragraph in
            Segment(
                index: index, isTranslatable: paragraph.isTranslatable, plainText: paragraph.text,
                markup: ClipInlineMarkup.serialize(paragraph.runs, placeholders: true))
        }
    }

    private init(body: Body, segments: [Segment]) {
        self.body = body
        self.segments = segments
    }

    public var isRich: Bool {
        if case .rich = body { true } else { false }
    }

    /// 需要送去翻译的段
    public var translatableSegments: [Segment] {
        segments.filter(\.isTranslatable)
    }

    /// 实际送给引擎的全部文字（每个可翻译段一条，按段顺序）：markup 为 true 时是大模型收到的受限 Markdown，
    /// 否则是系统翻译收到的纯文本（系统翻译可能再把行内代码换成占位符，发送的只会更少）。疑似密钥检查应扫描这些文字
    public func sentTexts(markup: Bool) -> [String] {
        translatableSegments.map { markup ? $0.markup : $0.plainText }
    }

    // MARK: - 单段

    /// 第 index 段原文（「对照」视图）：富文本保留段落样式与行内样式；越界时为空
    public func original(at index: Int) -> AttributedString {
        switch body {
        case .plain(_, let pieces):
            return pieces.indices.contains(index) ? AttributedString(pieces[index].original) : AttributedString()
        case .rich(let document):
            guard document.paragraphs.indices.contains(index) else { return AttributedString() }
            return ClipRichTextRenderer.attributed(document.paragraphs[index], identity: index + 1)
        }
    }

    /// 引擎返回的一段 → 写入缓存的文字：去掉首尾空白；富文本译文按该段自己的代码与链接还原占位符
    /// （编号未知、重复的占位符与直接写出的地址都只保留文字）、丢弃不成对的标记，得到自成一体的规范形式
    public func storableTranslation(_ output: String, at index: Int, markup: Bool) -> String {
        let trimmed = output.trimmingCharacters(in: .whitespacesAndNewlines)
        guard markup, let paragraph = richParagraph(at: index) else { return trimmed }
        let runs = ClipInlineMarkup.parse(
            trimmed, codeSpans: ClipInlineMarkup.codeSpans(in: paragraph.runs),
            linkSlots: ClipInlineMarkup.linkSlots(in: paragraph.runs))
        return ClipInlineMarkup.serialize(runs, placeholders: false)
    }

    /// 缓存里的一段译文 → 显示用（流式到达的一段、「对照」的译文侧）：富文本带该段的段落样式，
    /// markup 为 true 时解析行内样式，否则只有段落样式
    public func translation(_ stored: String, at index: Int, markup: Bool) -> AttributedString {
        guard let paragraph = richParagraph(at: index) else { return AttributedString(stored) }
        return ClipRichTextRenderer.attributed(translated(paragraph, stored, markup: markup), identity: index + 1)
    }

    // MARK: - 整篇

    /// 完整译文的纯文本（⇧↩ 粘贴、存为新条目）：未翻译的段用原文；纯文本按原文的分隔符拼回
    public func plainText(translations: [String?], markup: Bool) -> String {
        switch body {
        case .plain(let original, let pieces):
            return ClipTextSegmenter.join(original: original, segments: pieces, translations: translations)
        case .rich(let document):
            return ClipRichTextRenderer.plainText(translatedDocument(document, translations, markup: markup))
        }
    }

    /// 富文本条目保留结构的完整译文（ClipTranslationResult.richText）；纯文本条目为 nil
    public func richText(translations: [String?], markup: Bool) -> AttributedString? {
        guard case .rich(let document) = body else { return nil }
        return ClipRichTextRenderer.attributed(translatedDocument(document, translations, markup: markup))
    }

    // MARK: - 缓存

    /// 一次完整翻译 → 缓存项：分段版本、段数与 usesInlineMarkup 都由本文档决定
    public func cacheEntry(
        target: String, source: String?, engineName: String, isOnDevice: Bool, createdAt: Date,
        translations: [String?], markup: Bool
    ) -> ClipTranslation {
        let aligned = segments.map { segment in
            segment.isTranslatable && translations.indices.contains(segment.index) ? translations[segment.index] : nil
        }
        return ClipTranslation(
            target: target, source: source, engineName: engineName, isOnDevice: isOnDevice, createdAt: createdAt,
            segmentation: ClipTextSegmenter.version, segments: aligned, usesInlineMarkup: isRich && markup ? true : nil)
    }

    /// 缓存的译文与本文档的分段一致（版本号与段数相同）；不一致时「对照」应退化为原文、译文上下两整段
    public func isAligned(with translation: ClipTranslation) -> Bool {
        translation.imageName == nil && translation.segmentation == ClipTextSegmenter.version
            && translation.segments.count == segments.count
    }

    // MARK: - 内部

    private func richParagraph(at index: Int) -> ClipRichParagraph? {
        guard case .rich(let document) = body, document.paragraphs.indices.contains(index) else { return nil }
        return document.paragraphs[index]
    }

    private func translatedDocument(_ document: ClipRichDocument, _ translations: [String?], markup: Bool)
        -> ClipRichDocument
    {
        ClipRichDocument(
            paragraphs: document.paragraphs.enumerated().map { index, paragraph in
                guard paragraph.isTranslatable, translations.indices.contains(index), let stored = translations[index]
                else { return paragraph }
                return translated(paragraph, stored, markup: markup)
            })
    }

    /// 段落换上译文：空译文保留原文；大模型的译文解析行内样式（只接受原文里的链接），系统翻译只保留段落样式
    private func translated(_ paragraph: ClipRichParagraph, _ stored: String, markup: Bool) -> ClipRichParagraph {
        guard !stored.isEmpty else { return paragraph }
        let runs = markup ? ClipInlineMarkup.parse(stored, allowedLinks: paragraph.links) : [ClipRichRun(stored)]
        return paragraph.withRuns(runs)
    }
}
