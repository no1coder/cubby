import Foundation

/// 富文本条目的一段行内文字。只保留受限子集（docs/CLIP-TRANSLATION-DESIGN.md §0.1 A2）：粗体、链接、行内代码
public struct ClipRichRun: Equatable, Sendable {
    public let text: String
    public let isBold: Bool
    public let link: URL?
    public let isCode: Bool

    public init(_ text: String, isBold: Bool = false, link: URL? = nil, isCode: Bool = false) {
        self.text = text
        self.isBold = isBold
        self.link = link
        self.isCode = isCode
    }

    func hasSameStyle(as other: ClipRichRun) -> Bool {
        isBold == other.isBold && link == other.link && isCode == other.isCode
    }

    func withText(_ text: String) -> ClipRichRun {
        ClipRichRun(text, isBold: isBold, link: link, isCode: isCode)
    }

    /// 带样式（粗体、链接、代码）
    var isStyled: Bool {
        isBold || link != nil || isCode
    }
}

/// 段落级样式
public enum ClipParagraphStyle: Equatable, Sendable {
    case body
    /// 标题，level 为 1…6
    case heading(level: Int)
    /// 列表项：ordinal 为有序列表的序号（无序列表为 nil），level 为嵌套层级（从 1 开始）
    case listItem(ordinal: Int?, level: Int)
    /// 代码块等预排版文字：原样保留，不翻译
    case preformatted
}

/// 一个段落：译文按段落对齐，一段即一个翻译单元
public struct ClipRichParagraph: Equatable, Sendable {
    public let style: ClipParagraphStyle
    public let runs: [ClipRichRun]

    /// 相邻同样式的行内文字合并，空文字丢弃
    public init(style: ClipParagraphStyle, runs: [ClipRichRun]) {
        self.style = style
        self.runs = runs.filter { !$0.text.isEmpty }.reduce(into: [ClipRichRun]()) { merged, run in
            guard let last = merged.last, last.hasSameStyle(as: run) else { return merged.append(run) }
            merged[merged.count - 1] = last.withText(last.text + run.text)
        }
    }

    public var text: String {
        runs.map(\.text).joined()
    }

    /// 是否送去翻译：不是预排版文字，且行内代码以外的文字可翻译（含字母、不只是一个网址）
    public var isTranslatable: Bool {
        guard style != .preformatted else { return false }
        return ClipTextLine.isTranslatable(runs.filter { !$0.isCode }.map(\.text).joined()[...])
    }

    /// 段内出现过的链接（按出现顺序、去重）：大模型译文里只接受这些链接
    var links: [URL] {
        runs.compactMap(\.link).reduce(into: [URL]()) { unique, link in
            if !unique.contains(link) { unique.append(link) }
        }
    }

    func withRuns(_ runs: [ClipRichRun]) -> ClipRichParagraph {
        ClipRichParagraph(style: style, runs: runs)
    }
}

/// 富文本条目的段落结构（由 ClipRichTextParser 从 HTML / RTF 解析）
public struct ClipRichDocument: Equatable, Sendable {
    public let paragraphs: [ClipRichParagraph]

    /// 只含空白的段落丢弃
    public init(paragraphs: [ClipRichParagraph]) {
        self.paragraphs = paragraphs.filter { !$0.text.allSatisfy(\.isWhitespace) }
    }

    /// 有标题、列表、代码块或行内样式；否则与纯文本无异，按纯文本分段更好（能识别硬换行）
    public var hasStructure: Bool {
        paragraphs.contains { $0.style != .body || $0.runs.contains(where: \.isStyled) }
    }
}
