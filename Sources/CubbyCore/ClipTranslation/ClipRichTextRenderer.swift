import Foundation

/// 段落结构 → 显示与粘贴用的形式（纯函数）：
/// - AttributedString：段落样式写入 presentationIntent（标题、列表项、代码块），行内样式写入
///   inlinePresentationIntent（粗体 stronglyEmphasized、代码 code）与 link；用 `paragraphStyle(of:)` 读回段落样式；
/// - 纯文本：段落间空一行，相邻列表项之间只换行，列表项带「• 」或「N. 」前缀。
/// 粘贴用的 RTF / HTML 由剪贴板写入端（RichTextExport）从 AttributedString 生成
public enum ClipRichTextRenderer {
    /// 列表嵌套的最大层数（更深的按该层处理）
    static let maxListDepth = 8

    // MARK: - AttributedString

    /// 一个段落（翻译卡「对照」的一段）
    public static func attributed(_ paragraph: ClipRichParagraph, identity: Int = 1) -> AttributedString {
        let intent = presentationIntent(for: paragraph.style, identity: identity)
        return paragraph.runs.reduce(into: AttributedString()) { output, run in
            var piece = AttributedString(run.text)
            piece.presentationIntent = intent
            piece.link = run.link
            let inline: InlinePresentationIntent = [
                run.isBold ? .stronglyEmphasized : [], run.isCode ? .code : [],
            ]
            piece.inlinePresentationIntent = inline.isEmpty ? nil : inline
            output += piece
        }
    }

    /// 整篇：段落之间以换行分隔（换行带前一段的段落样式）
    public static func attributed(_ document: ClipRichDocument) -> AttributedString {
        document.paragraphs.enumerated().reduce(into: AttributedString()) { output, element in
            let (index, paragraph) = element
            if index > 0 {
                var separator = AttributedString("\n")
                separator.presentationIntent = output.runs.last?.presentationIntent
                output += separator
            }
            output += attributed(paragraph, identity: index + 1)
        }
    }

    /// 从 AttributedString（本类型生成的）读回段落样式：取第一段文字的 presentationIntent
    public static func paragraphStyle(of text: AttributedString) -> ClipParagraphStyle {
        guard let components = text.runs.first?.presentationIntent?.components else { return .body }
        let level = components.filter { $0.kind == .unorderedList || $0.kind == .orderedList }.count
        for component in components {
            switch component.kind {
            case .header(let level): return .heading(level: level)
            case .codeBlock: return .preformatted
            case .listItem(let ordinal):
                let ordered =
                    components.first { $0.kind == .orderedList || $0.kind == .unorderedList }?.kind == .orderedList
                return .listItem(ordinal: ordered ? ordinal : nil, level: max(level, 1))
            default: continue
            }
        }
        return .body
    }

    /// 段落样式 → presentationIntent。列表项按层级嵌套在列表之内（最内层列表的有序 / 无序取自本项）
    static func presentationIntent(for style: ClipParagraphStyle, identity: Int) -> PresentationIntent {
        let base = identity * 32
        switch style {
        case .body:
            return PresentationIntent(.paragraph, identity: base)
        case .heading(let level):
            return PresentationIntent(.header(level: level), identity: base)
        case .preformatted:
            return PresentationIntent(.codeBlock(languageHint: nil), identity: base)
        case .listItem(let ordinal, let level):
            let depth = min(max(level, 1), maxListDepth)
            let outer = (1..<depth).reduce(nil as PresentationIntent?) { parent, step in
                let list = PresentationIntent(.unorderedList, identity: base + step * 2, parent: parent)
                return PresentationIntent(.listItem(ordinal: 1), identity: base + step * 2 + 1, parent: list)
            }
            let list = PresentationIntent(
                ordinal == nil ? .unorderedList : .orderedList, identity: base + 30, parent: outer)
            return PresentationIntent(.listItem(ordinal: ordinal ?? 1), identity: base + 31, parent: list)
        }
    }

    // MARK: - 纯文本

    public static func plainText(_ document: ClipRichDocument) -> String {
        document.paragraphs.enumerated().reduce(into: "") { output, element in
            let (index, paragraph) = element
            if index > 0 {
                let previous = document.paragraphs[index - 1].style
                output += isListItem(previous) && isListItem(paragraph.style) ? "\n" : "\n\n"
            }
            output += marker(for: paragraph.style) + paragraph.text
        }
    }

    /// 列表项的纯文本前缀：每深一层缩进一个制表符
    static func marker(for style: ClipParagraphStyle) -> String {
        guard case .listItem(let ordinal, let level) = style else { return "" }
        let indent = String(repeating: "\t", count: max(level - 1, 0))
        return indent + (ordinal.map { "\($0). " } ?? "\u{2022} ")
    }

    static func isListItem(_ style: ClipParagraphStyle) -> Bool {
        if case .listItem = style { true } else { false }
    }
}
