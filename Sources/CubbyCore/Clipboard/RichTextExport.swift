import AppKit

/// 把保留结构的译文（Foundation 的段落 / 行内意图，同 `AttributedString(markdown:)` 的表示）
/// 转成带 AppKit 字体、链接属性的 NSAttributedString，再导出 RTF / HTML（粘贴富文本条目的译文，
/// 设计文档 docs/CLIP-TRANSLATION-DESIGN.md §0.1 A2）。
///
/// - 段落意图：标题加粗放大；列表项加「• 」或序号；块与块之间补一个换行（Markdown 解析结果的块之间没有换行字符）
/// - 行内意图：粗体、斜体、行内代码（等宽）、删除线；`link` 转为 `.link`
public enum RichTextExport {
    /// 正文字号（与系统「文本编辑」的默认正文接近）
    public static let bodyFontSize: CGFloat = 13
    /// 一到三级标题的字号，更低级别沿用最后一档
    static let headingFontSizes: [CGFloat] = [20, 17, 15]
    static let bullet = "• "

    /// RTF 与 HTML 两种格式的数据
    public struct Output: Equatable, Sendable {
        public let rtf: Data
        public let html: Data
    }

    /// 导出 RTF 与 HTML；任一格式生成失败时为 nil
    public static func data(from text: AttributedString) -> Output? {
        let string = appKitString(from: text)
        let range = NSRange(location: 0, length: string.length)
        let rtfAttributes: [NSAttributedString.DocumentAttributeKey: Any] = [
            .documentType: NSAttributedString.DocumentType.rtf
        ]
        guard let rtf = string.rtf(from: range, documentAttributes: rtfAttributes),
            let html = try? string.data(
                from: range,
                documentAttributes: [
                    .documentType: NSAttributedString.DocumentType.html,
                    .characterEncoding: String.Encoding.utf8.rawValue,
                ])
        else { return nil }
        return Output(rtf: rtf, html: html)
    }

    /// 按块转换并拼接
    public static func appKitString(from text: AttributedString) -> NSAttributedString {
        let output = NSMutableAttributedString()
        var needsSeparator = false
        for block in text.runs[\.presentationIntent] {
            let content = text[block.1]
            if needsSeparator, !output.string.hasSuffix("\n") {
                output.append(NSAttributedString(string: "\n", attributes: [.font: font(size: bodyFontSize)]))
            }
            output.append(convert(content, intent: block.0))
            needsSeparator = block.0 != nil
        }
        return output
    }

    // MARK: - 块

    private static func convert(_ content: AttributedSubstring, intent: PresentationIntent?) -> NSAttributedString {
        let style = BlockStyle(intent)
        let result = NSMutableAttributedString()
        if let marker = style.marker, !String(content.characters).hasPrefix(bullet) {
            result.append(NSAttributedString(string: marker, attributes: [.font: font(size: style.fontSize)]))
        }
        for run in content.runs {
            let piece = String(content[run.range].characters)
            result.append(NSAttributedString(string: piece, attributes: attributes(for: run, style: style)))
        }
        return result
    }

    private static func attributes(
        for run: AttributedString.Runs.Run, style: BlockStyle
    ) -> [NSAttributedString.Key: Any] {
        let inline = run.inlinePresentationIntent ?? []
        var traits: NSFontDescriptor.SymbolicTraits = style.isBold ? .bold : []
        if inline.contains(.stronglyEmphasized) { traits.insert(.bold) }
        if inline.contains(.emphasized) { traits.insert(.italic) }
        var result: [NSAttributedString.Key: Any] = [
            .font: inline.contains(.code) || style.isCode
                ? NSFont.monospacedSystemFont(
                    ofSize: style.fontSize - 1, weight: traits.contains(.bold) ? .bold : .regular)
                : font(size: style.fontSize, traits: traits)
        ]
        if inline.contains(.strikethrough) {
            result[.strikethroughStyle] = NSUnderlineStyle.single.rawValue
        }
        if let link = run.link {
            result[.link] = link
        }
        return result
    }

    private static func font(size: CGFloat, traits: NSFontDescriptor.SymbolicTraits = []) -> NSFont {
        let base = NSFont.systemFont(ofSize: size)
        guard !traits.isEmpty else { return base }
        let descriptor = base.fontDescriptor.withSymbolicTraits(traits)
        return NSFont(descriptor: descriptor, size: size) ?? base
    }

    /// 由段落意图决定的块样式
    private struct BlockStyle {
        let fontSize: CGFloat
        let isBold: Bool
        /// 代码块：整块等宽
        let isCode: Bool
        let marker: String?

        init(_ intent: PresentationIntent?) {
            let kinds = intent?.components.map(\.kind) ?? []
            isCode = kinds.contains { if case .codeBlock = $0 { true } else { false } }
            if let level = kinds.lazy.compactMap(Self.headerLevel).first {
                let index = min(max(level, 1), RichTextExport.headingFontSizes.count) - 1
                fontSize = RichTextExport.headingFontSizes[index]
                isBold = true
                marker = nil
                return
            }
            fontSize = RichTextExport.bodyFontSize
            isBold = false
            marker = Self.listMarker(kinds)
        }

        private static func headerLevel(_ kind: PresentationIntent.Kind) -> Int? {
            if case .header(let level) = kind { return level }
            return nil
        }

        /// 列表项：紧邻的父级（意图由内向外排列）为有序列表时用序号，否则用项目符号；嵌套在有序列表里的无序项仍用符号
        private static func listMarker(_ kinds: [PresentationIntent.Kind]) -> String? {
            guard let index = kinds.firstIndex(where: { listOrdinal($0) != nil }),
                let ordinal = listOrdinal(kinds[index])
            else { return nil }
            let parent = kinds.indices.contains(index + 1) ? kinds[index + 1] : nil
            return parent == .orderedList ? "\(ordinal). " : RichTextExport.bullet
        }

        private static func listOrdinal(_ kind: PresentationIntent.Kind) -> Int? {
            if case .listItem(let ordinal) = kind { return ordinal }
            return nil
        }
    }
}
