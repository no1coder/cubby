import CubbyCore
import SwiftUI

/// 一段的块样式：由原文段落意图决定（译文沿用原文的结构：标题译文仍是标题）
enum SegmentStyle: Equatable {
    case paragraph
    case heading
    case listItem(marker: String)
    /// 代码块：等宽、不翻译
    case code

    init(_ original: AttributedString) {
        let kinds = original.runs.first?.presentationIntent?.components.map(\.kind) ?? []
        if kinds.contains(where: { if case .header = $0 { true } else { false } }) {
            self = .heading
        } else if let index = kinds.firstIndex(where: { Self.ordinal($0) != nil }),
            let ordinal = Self.ordinal(kinds[index])
        {
            // 意图由内向外排列：紧邻的父级是有序列表时用序号
            let parent = kinds.indices.contains(index + 1) ? kinds[index + 1] : nil
            self = .listItem(marker: parent == .orderedList ? "\(ordinal)." : "•")
        } else if kinds.contains(where: { if case .codeBlock = $0 { true } else { false } }) {
            self = .code
        } else {
            self = .paragraph
        }
    }

    private static func ordinal(_ kind: PresentationIntent.Kind) -> Int? {
        if case .listItem(let ordinal) = kind { return ordinal }
        return nil
    }

    /// 段后间距（原型：标题 8、段落 10、列表项 3）
    var spacingAfter: CGFloat {
        switch self {
        case .heading: 8
        case .listItem: 3
        case .paragraph, .code: 10
        }
    }
}

/// 译文 / 原文的行内样式：去掉段落意图，行内代码加底色，链接用浅强调色并加下划线
enum SegmentFormatting {
    static func display(_ text: AttributedString) -> AttributedString {
        var output = text
        output.presentationIntent = nil
        for run in output.runs {
            if run.inlinePresentationIntent?.contains(.code) == true {
                output[run.range].font = .system(size: FontSize.footnote, design: .monospaced)
                output[run.range].backgroundColor = Color.primary.opacity(0.08)
            }
            if run.link != nil {
                output[run.range].foregroundColor = TranslationPalette.link
                output[run.range].underlineStyle = Text.LineStyle(
                    pattern: .solid, color: TranslationPalette.link.opacity(0.4))
            }
        }
        return output
    }
}

/// 一段文字（原文或译文）按块样式排版；译文首次出现时逐字显现
struct SegmentText: View {
    let text: AttributedString
    let style: SegmentStyle
    /// 对照视图里的原文：12pt 次要色
    var isSecondary = false
    /// 标题字号（对照视图里的标题译文用 14）
    var headingSize = FontSize.title
    var animates = false

    var body: some View {
        switch style {
        case .listItem(let marker):
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(verbatim: marker)
                    .foregroundStyle(.secondary)
                    .frame(minWidth: 12, alignment: .trailing)
                content
            }
        default:
            content
        }
    }

    private var content: some View {
        RevealText(text: SegmentFormatting.display(text), animates: animates)
            .font(font)
            // 可选中文字（textSelection）不认层级样式 .secondary，这里用具体的颜色
            .foregroundStyle(isSecondary ? Color.primary.opacity(0.6) : Color.primary)
            .lineSpacing(isSecondary ? 4 : lineSpacing)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .textSelection(.enabled)
    }

    private var font: Font {
        switch style {
        case .heading:
            .system(size: isSecondary ? FontSize.footnote : headingSize, weight: .semibold)
        case .code:
            .system(size: FontSize.footnote, design: .monospaced)
        default:
            .system(size: isSecondary ? FontSize.footnote : FontSize.body)
        }
    }

    /// 行高：正文 20（13pt + 7）、标题 21
    private var lineSpacing: CGFloat {
        style == .heading ? 3 : 5
    }
}
