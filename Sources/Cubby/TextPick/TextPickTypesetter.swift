import AppKit
import CoreText
import CubbyCore

/// 词块的字形与尺寸（docs/TEXT-PICK-DESIGN.md §3）：词 13pt、标点 12pt，所有块等高（按 13pt 行高 + 上下 3），
/// 文字颜色在绘制时由上下文填充色决定（同一条 CTLine 可画选中 / 未选中 / 实体等各种状态）
@MainActor
enum TextPickTypesetter {
    static let wordFont = NSFont.systemFont(ofSize: TextPickMetrics.wordFontSize)
    static let punctuationFont = NSFont.systemFont(ofSize: TextPickMetrics.punctuationFontSize)

    /// 所有块的高度
    static var chipHeight: CGFloat {
        (lineHeight(wordFont) + TextPickMetrics.chipVertical * 2).rounded(.up)
    }

    static func font(for kind: TextPickToken.Kind) -> NSFont {
        kind == .punctuation ? punctuationFont : wordFont
    }

    static func horizontalPadding(for kind: TextPickToken.Kind) -> CGFloat {
        kind == .punctuation ? TextPickMetrics.punctuationHorizontal : TextPickMetrics.wordHorizontal
    }

    /// 一块文字的字形（颜色取自绘制上下文）
    static func line(for token: TextPickToken) -> CTLine {
        line(token.text, kind: token.kind)
    }

    static func line(_ text: String, kind: TextPickToken.Kind) -> CTLine {
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font(for: kind),
            NSAttributedString.Key(kCTForegroundColorFromContextAttributeName as String): true,
        ]
        return CTLineCreateWithAttributedString(NSAttributedString(string: text, attributes: attributes))
    }

    /// 排版：块宽 = 文字宽 + 左右内边距（同一文字只量一次）
    static func layout(_ document: TextPickDocument, width: CGFloat) -> TextPickLayout {
        var widths: [String: CGFloat] = [:]
        let height = chipHeight
        let sizes = document.tokens.map { token in
            CGSize(width: chipWidth(of: token, cache: &widths), height: height)
        }
        return TextPickLayout.make(
            sizes: sizes, lineBreaks: document.tokens.map(\.lineBreaksBefore), width: width,
            metrics: TextPickMetrics.layout)
    }

    private static func chipWidth(of token: TextPickToken, cache: inout [String: CGFloat]) -> CGFloat {
        let key = (token.kind == .punctuation ? "p" : "w") + token.text
        let textWidth: CGFloat
        if let cached = cache[key] {
            textWidth = cached
        } else {
            textWidth = CGFloat(CTLineGetTypographicBounds(line(for: token), nil, nil, nil))
            cache[key] = textWidth
        }
        return (textWidth + horizontalPadding(for: token.kind) * 2).rounded(.up)
    }

    /// 词块区的内容高度（含上下内边距）
    static func contentHeight(of layout: TextPickLayout) -> CGFloat {
        layout.height + TextPickMetrics.contentVertical * 2
    }

    /// 文字在块内垂直居中时的基线（按字体而非字形计算，同一行各块基线一致）
    static func baseline(in frame: CGRect, kind: TextPickToken.Kind) -> CGFloat {
        let font = font(for: kind)
        return frame.minY + (frame.height - lineHeight(font)) / 2 + font.ascender
    }

    private static func lineHeight(_ font: NSFont) -> CGFloat {
        font.ascender - font.descender
    }
}
