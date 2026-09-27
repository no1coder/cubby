import AppKit

// MARK: - RTF

extension ClipRichTextParser {
    /// 标题判定：段落字号至少为正文字号的该倍数（RTF 没有语义标题，Safari / 备忘录的标题只是更大的粗体）
    static let headingSizeRatio: CGFloat = 1.15
    /// 超过该长度（UTF-16）的大字号段落不当作标题
    static let maxHeadingLength = 200
    private static let linkSchemes: Set<String> = ["http", "https", "mailto"]
    private static let orderedMarkers: Set<NSTextList.MarkerFormat> = [
        .decimal, .lowercaseAlpha, .uppercaseAlpha, .lowercaseRoman, .uppercaseRoman, .lowercaseLatin,
        .uppercaseLatin, .octal, .lowercaseHexadecimal, .uppercaseHexadecimal,
    ]

    /// RTF → 段落。整篇都是等宽字体（终端、代码编辑器复制的「富文本」）时为 nil，交给纯文本分段
    static func rtf(_ data: Data) -> ClipRichDocument? {
        guard
            let text = try? NSAttributedString(
                data: data, options: [.documentType: NSAttributedString.DocumentType.rtf], documentAttributes: nil),
            text.length > 0, !isEntirelyMonospaced(text)
        else { return nil }
        let bodySize = dominantFontSize(of: text)
        return ClipRichDocument(
            paragraphs: paragraphRanges(of: text).map { paragraph(in: text, range: $0, bodySize: bodySize) })
    }

    private static func paragraph(in text: NSAttributedString, range: NSRange, bodySize: CGFloat) -> ClipRichParagraph {
        let pieces = attributeRuns(of: text, in: range)
        let style = paragraphStyle(of: text, range: range, pieces: pieces, bodySize: bodySize)
        let isHeading = if case .heading = style { true } else { false }
        let runs = pieces.map { piece in
            ClipRichRun(
                piece.text, isBold: piece.isBold && !isHeading, link: piece.link,
                isCode: piece.isMonospaced && style != .preformatted)
        }
        return ClipRichParagraph(style: style, runs: runs)
    }

    private static func paragraphStyle(
        of text: NSAttributedString, range: NSRange, pieces: [AttributeRun], bodySize: CGFloat
    ) -> ClipParagraphStyle {
        let style = text.attribute(.paragraphStyle, at: range.location, effectiveRange: nil) as? NSParagraphStyle
        if let lists = style?.textLists, let list = lists.last {
            let start = min(max(list.startingItemNumber, 0), maxListOrdinal)
            let ordinal = start + text.itemNumber(in: list, at: range.location) - 1
            return .listItem(ordinal: orderedMarkers.contains(list.markerFormat) ? ordinal : nil, level: lists.count)
        }
        if let level = style?.headerLevel, level > 0 { return .heading(level: min(level, 6)) }
        let visible = pieces.filter { !$0.text.allSatisfy(\.isWhitespace) }
        if !visible.isEmpty, visible.allSatisfy(\.isMonospaced) { return .preformatted }
        let size = visible.map(\.fontSize).max() ?? bodySize
        guard size >= bodySize * headingSizeRatio, range.length <= maxHeadingLength else { return .body }
        let ratio = size / bodySize
        return .heading(level: ratio >= 1.75 ? 1 : ratio >= 1.35 ? 2 : 3)
    }

    // MARK: - 属性

    /// 一段属性一致的文字
    private struct AttributeRun {
        let text: String
        let isBold: Bool
        let isMonospaced: Bool
        let fontSize: CGFloat
        let link: URL?
    }

    private static func attributeRuns(of text: NSAttributedString, in range: NSRange) -> [AttributeRun] {
        var runs: [AttributeRun] = []
        text.enumerateAttributes(in: range) { attributes, subrange, _ in
            let font = attributes[.font] as? NSFont
            let traits = font?.fontDescriptor.symbolicTraits ?? []
            runs.append(
                AttributeRun(
                    text: text.attributedSubstring(from: subrange).string, isBold: traits.contains(.bold),
                    isMonospaced: traits.contains(.monoSpace), fontSize: font?.pointSize ?? 0,
                    link: link(from: attributes[.link])))
        }
        return runs
    }

    private static func link(from value: Any?) -> URL? {
        let url = (value as? URL) ?? (value as? String).flatMap { URL(string: $0) }
        guard let url, let scheme = url.scheme?.lowercased(), linkSchemes.contains(scheme) else { return nil }
        return url
    }

    private static func paragraphRanges(of text: NSAttributedString) -> [NSRange] {
        var ranges: [NSRange] = []
        let string = text.string as NSString
        string.enumerateSubstrings(
            in: NSRange(location: 0, length: string.length), options: [.byParagraphs, .substringNotRequired]
        ) { _, range, _, _ in
            if range.length > 0 { ranges.append(range) }
        }
        return ranges
    }

    /// 正文字号：按字符数加权出现最多的非等宽字号
    private static func dominantFontSize(of text: NSAttributedString) -> CGFloat {
        var weights: [CGFloat: Int] = [:]
        text.enumerateAttribute(.font, in: NSRange(location: 0, length: text.length)) { value, range, _ in
            guard let font = value as? NSFont, !font.fontDescriptor.symbolicTraits.contains(.monoSpace) else { return }
            weights[font.pointSize, default: 0] += range.length
        }
        return weights.max { $0.value < $1.value }?.key ?? NSFont.systemFontSize
    }

    private static func isEntirelyMonospaced(_ text: NSAttributedString) -> Bool {
        var monospaced = true
        text.enumerateAttribute(.font, in: NSRange(location: 0, length: text.length)) { value, range, stop in
            let font = value as? NSFont
            let visible = !text.attributedSubstring(from: range).string.allSatisfy(\.isWhitespace)
            if visible, font?.fontDescriptor.symbolicTraits.contains(.monoSpace) != true {
                monospaced = false
                stop.pointee = true
            }
        }
        return monospaced
    }
}
