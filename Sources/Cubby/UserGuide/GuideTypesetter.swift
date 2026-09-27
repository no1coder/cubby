import AppKit

/// 排版结果：NSTextView 显示的富文本，以及各标题在全文中的位置（目录、锚点跳转、搜索归属）
struct GuideRendering {
    let text: NSAttributedString
    let headings: [GuideRenderedHeading]
}

struct GuideRenderedHeading: Equatable {
    let heading: GuideHeading
    /// 标题段落在全文中的字符位置（UTF-16）
    let location: Int
}

/// 把 GuideDocument 排成 NSAttributedString（TextKit 1）：列表用缩进与制表位，
/// 引用、代码块与表格用 NSTextBlock / NSTextTable；键帽与行内代码标记 guideInlineBox，由 GuideLayoutManager 绘制。
/// 只在一次 render 内部使用。
@MainActor
final class GuideTypesetter {
    /// 块内片段的公共属性
    private struct BlockContext {
        let font: NSFont
        let color: NSColor
        /// 标题与代码块里的行内代码不画底框
        let allowsBoxes: Bool
    }

    private static let lineBreaks: Set<Character> = ["\n", "\t", "\u{2028}"]
    private static let textVariationSelector: Unicode.Scalar = "\u{FE0E}"
    /// 菜单路径的分隔符
    private static let pathSeparator: Character = "›"

    private let output = NSMutableAttributedString()
    private var headings: [GuideRenderedHeading] = []
    private var tables: [Int: NSTextTable] = [:]
    private var quotes: [Int: NSTextBlock] = [:]

    private init() {}

    static func render(_ document: GuideDocument) -> GuideRendering {
        let typesetter = GuideTypesetter()
        let blocks = document.blocks
        for (index, block) in blocks.enumerated() {
            typesetter.append(block, next: blocks.indices.contains(index + 1) ? blocks[index + 1] : nil)
        }
        let text = NSAttributedString(attributedString: typesetter.output)
        return GuideRendering(text: text, headings: typesetter.headings)
    }

    private func append(_ block: GuideBlock, next: GuideBlock?) {
        let start = output.length
        let context = Self.context(for: block.kind)
        switch block.kind {
        case .heading(let heading):
            headings.append(GuideRenderedHeading(heading: heading, location: start))
        case .listItem(let marker?, _):
            output.append(
                NSAttributedString(
                    string: marker + "\t",
                    attributes: [.font: GuideTypography.listMarker, .foregroundColor: GuideTypography.secondaryText]
                ))
        default:
            break
        }
        for run in block.runs {
            append(run, context: context)
        }
        output.append(NSAttributedString(string: "\n", attributes: [.font: context.font]))
        let style = paragraphStyle(for: block.kind, next: next?.kind)
        // 段首就是底框时首行右移留白的宽度，框的左边与正文对齐
        if let first = block.runs.first, context.allowsBoxes, let box = Self.box(for: first.style),
            style.firstLineHeadIndent == style.headIndent
        {
            style.firstLineHeadIndent += box.horizontalPadding
        }
        output.addAttribute(
            .paragraphStyle, value: style, range: NSRange(location: start, length: output.length - start))
    }

    private static func context(for kind: GuideBlock.Kind) -> BlockContext {
        switch kind {
        case .heading(let heading):
            BlockContext(
                font: GuideTypography.heading(level: heading.level), color: GuideTypography.text, allowsBoxes: false)
        case .code:
            BlockContext(font: GuideTypography.codeBlock, color: GuideTypography.text, allowsBoxes: false)
        case .tableCell(let cell) where cell.isHeader:
            BlockContext(font: GuideTypography.bodyBold, color: GuideTypography.text, allowsBoxes: true)
        case .paragraph, .listItem, .quote, .tableCell:
            BlockContext(font: GuideTypography.body, color: GuideTypography.text, allowsBoxes: true)
        }
    }

    // MARK: - 行内

    private func append(_ run: GuideRun, context: BlockContext) {
        let box = context.allowsBoxes ? Self.box(for: run.style) : nil
        var attributes: [NSAttributedString.Key: Any] = [
            .font: Self.font(for: run.style, context: context, text: run.text),
            .foregroundColor: context.color,
        ]
        if let link = run.link { attributes[.link] = link }
        if let box {
            attributes[.guideInlineBox] = box.rawValue
            addKernToLastCharacter(box.outerKern, unlessLineStart: true)
        }
        let text = box == .key ? Self.textPresentation(run.text) : run.text
        output.append(NSAttributedString(string: text, attributes: attributes))
        if let box {
            addKernToLastCharacter(box.outerKern, unlessLineStart: false)
        }
    }

    private static func box(for style: GuideRun.Style) -> GuideInlineBox? {
        if style.contains(.key) { return .key }
        if style.contains(.code) { return .code }
        return nil
    }

    /// 圆体没有 ↩ 等符号，AppKit 回退时会取到彩色 Emoji：在可显示为 Emoji 的符号后加文本样式选择符 U+FE0E
    private static func textPresentation(_ text: String) -> String {
        var scalars = String.UnicodeScalarView()
        for scalar in text.unicodeScalars {
            scalars.append(scalar)
            if !scalar.isASCII, scalar.properties.isEmoji, !scalar.properties.isEmojiPresentation {
                scalars.append(Self.textVariationSelector)
            }
        }
        return String(scalars)
    }

    private static func font(for style: GuideRun.Style, context: BlockContext, text: String) -> NSFont {
        if context.allowsBoxes, style.contains(.key) { return GuideTypography.key }
        // 界面路径（Settings › Privacy）与含中文的行内代码用正文字体：等宽字体的空格太宽，中文也没有等宽字形
        if context.allowsBoxes, style.contains(.code) {
            let isProse = text.contains(Self.pathSeparator) || GuideScript.containsCJK(text)
            return isProse ? GuideTypography.body : GuideTypography.code
        }
        var font = context.font
        if style.contains(.bold) {
            font = font == GuideTypography.body ? GuideTypography.bodyBold : GuideTypography.bold(font)
        }
        if style.contains(.italic) { font = GuideTypography.italic(font) }
        return font
    }

    /// 底框两侧用字距让出留白：框前加在前一个字符上（行首、制表符后不加），框后加在框内最后一个字符上
    private func addKernToLastCharacter(_ kern: CGFloat, unlessLineStart: Bool) {
        guard output.length > 0 else { return }
        let string = output.mutableString
        let range = string.rangeOfComposedCharacterSequence(at: output.length - 1)
        if unlessLineStart, let last = string.substring(with: range).first, Self.lineBreaks.contains(last) { return }
        let existing = output.attribute(.kern, at: range.location, effectiveRange: nil) as? CGFloat ?? 0
        output.addAttribute(.kern, value: existing + kern, range: range)
    }

    // MARK: - 段落

    private func paragraphStyle(for kind: GuideBlock.Kind, next: GuideBlock.Kind?) -> NSMutableParagraphStyle {
        let style = NSMutableParagraphStyle()
        style.lineSpacing = GuideTypography.lineSpacing
        style.paragraphSpacing = GuideTypography.paragraphSpacing
        switch kind {
        case .heading(let heading):
            let spacing = GuideTypography.headingSpacing(level: heading.level)
            style.paragraphSpacingBefore = spacing.before
            style.paragraphSpacing = spacing.after
        case .paragraph:
            break
        case .listItem(let marker, let depth):
            let indent = GuideTypography.listIndent * CGFloat(depth)
            style.headIndent = indent
            style.firstLineHeadIndent = marker == nil ? indent : indent - GuideTypography.markerWidth
            style.tabStops = [NSTextTab(textAlignment: .left, location: indent)]
            if case .listItem = next { style.paragraphSpacing = GuideTypography.listItemSpacing }
        case .quote(let group):
            style.textBlocks = [quoteBlock(group: group)]
            style.paragraphSpacing = next == kind ? GuideTypography.listItemSpacing : 0
        case .code:
            style.textBlocks = [Self.codeBlock()]
            style.paragraphSpacing = 0
        case .tableCell(let cell):
            style.textBlocks = [tableBlock(for: cell)]
            style.paragraphSpacing = 0
        }
        return style
    }
}

// MARK: - 文本块：引用、代码块、表格

extension GuideTypesetter {
    /// 同一引用的段落共用一个块：左侧强调色竖条 + 浅底
    private func quoteBlock(group: Int) -> NSTextBlock {
        if let block = quotes[group] { return block }
        let block = NSTextBlock()
        block.backgroundColor = GuideTypography.quoteBackground
        block.setWidth(GuideTypography.quoteBarWidth, type: .absoluteValueType, for: .border, edge: .minX)
        block.setBorderColor(GuideTypography.quoteBar, for: .minX)
        block.setWidth(GuideTypography.blockPadding, type: .absoluteValueType, for: .padding)
        block.setWidth(GuideTypography.quoteInset, type: .absoluteValueType, for: .padding, edge: .minX)
        block.setWidth(GuideTypography.paragraphSpacing, type: .absoluteValueType, for: .margin, edge: .maxY)
        quotes[group] = block
        return block
    }

    private static func codeBlock() -> NSTextBlock {
        let block = NSTextBlock()
        block.backgroundColor = GuideTypography.quoteBackground
        block.setWidth(GuideTypography.blockPadding, type: .absoluteValueType, for: .padding)
        block.setWidth(GuideTypography.paragraphSpacing, type: .absoluteValueType, for: .margin, edge: .maxY)
        return block
    }

    /// 表格占满正文宽度，列宽自动；行间细分隔线，表头浅底
    private func tableBlock(for cell: GuideTableCell) -> NSTextTableBlock {
        let table = tables[cell.table] ?? Self.makeTable(columns: cell.columns)
        tables[cell.table] = table
        let block = NSTextTableBlock(
            table: table, startingRow: cell.row, rowSpan: 1, startingColumn: cell.column, columnSpan: 1)
        block.setWidth(GuideTypography.tableCellPadding, type: .absoluteValueType, for: .padding)
        block.setWidth(0.5, type: .absoluteValueType, for: .border, edge: .maxY)
        block.setBorderColor(GuideTypography.separator, for: .maxY)
        if cell.isHeader { block.backgroundColor = GuideTypography.headerBackground }
        return block
    }

    private static func makeTable(columns: Int) -> NSTextTable {
        let table = NSTextTable()
        table.numberOfColumns = columns
        table.collapsesBorders = true
        table.hidesEmptyCells = false
        table.layoutAlgorithm = .automaticLayoutAlgorithm
        table.setContentWidth(100, type: .percentageValueType)
        table.setWidth(GuideTypography.paragraphSpacing, type: .absoluteValueType, for: .margin, edge: .maxY)
        return table
    }
}
