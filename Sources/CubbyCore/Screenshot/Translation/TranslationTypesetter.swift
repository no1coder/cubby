import AppKit
import CoreGraphics
import CoreText

/// 译文的 CoreText 排版（placer 量尺寸与折行、painter 绘制共用同一套字体与属性，保证所见即导出）
///
/// 行的位置不交给 CTFrame（回退字体的行高随线程与缓存变化），由调用方按原文行距逐行给出基线。
enum TranslationTypesetter {
    /// 字体参数：系统字体，粗体用 semibold；language 写入 kCTLanguageAttributeName（决定中日文字形）
    struct Style: Equatable, Sendable {
        let fontSize: CGFloat
        let isBold: Bool
        let language: String?

        func resized(_ fontSize: CGFloat) -> Style {
            Style(fontSize: fontSize, isBold: isBold, language: language)
        }
    }

    /// 省略号
    static let ellipsis = "\u{2026}"

    static func font(_ style: Style) -> CTFont {
        NSFont.systemFont(ofSize: style.fontSize, weight: style.isBold ? .semibold : .regular) as CTFont
    }

    /// 基准字体（系统字体）的上 / 下伸，不受回退字体影响
    static func ascent(_ style: Style) -> CGFloat { CTFontGetAscent(font(style)) }
    static func descent(_ style: Style) -> CGFloat { CTFontGetDescent(font(style)) }

    static func line(_ text: String, style: Style, color: CGColor? = nil) -> CTLine {
        var attributes = stringAttributes(style)
        if let color {
            attributes[NSAttributedString.Key(kCTForegroundColorAttributeName as String)] = color
        }
        return CTLineCreateWithAttributedString(NSAttributedString(string: text, attributes: attributes))
    }

    /// 单行排版宽度（不含行尾空白）
    static func width(of text: String, style: Style) -> CGFloat {
        let ctLine = line(text, style: style)
        return CGFloat(CTLineGetTypographicBounds(ctLine, nil, nil, nil)) - CTLineGetTrailingWhitespaceWidth(ctLine)
    }

    /// 字形外框（相对基线左端，y 向上）
    static func inkBounds(of text: String, style: Style) -> CGRect {
        CTLineGetBoundsWithOptions(line(text, style: style), .useGlyphPathBounds)
    }

    /// 单个字符的左 / 右字形边距（笔位到墨迹的距离）；空白或没有字符时为 0
    static func bearings(of character: Character?, style: Style) -> (left: CGFloat, right: CGFloat) {
        guard let character, !character.isWhitespace else { return (0, 0) }
        let text = String(character)
        let ink = inkBounds(of: text, style: style)
        guard !ink.isEmpty else { return (0, 0) }
        return (ink.minX, width(of: text, style: style) - ink.maxX)
    }

    /// 视觉中线在基线上方的高度：拉丁文字取大写高的一半，CJK 取字形外框的中线
    static func centerHeight(of text: String, style: Style) -> CGFloat {
        guard TextScript.isMostlyIdeographic(text) else { return CTFontGetCapHeight(font(style)) / 2 }
        return inkBounds(of: text, style: style).midY
    }

    /// 按宽度折行（硬换行处也断开），各行去掉首尾空白；空串为空数组
    static func breakLines(_ text: String, style: Style, width: CGFloat) -> [String] {
        let string = text as NSString
        guard string.length > 0 else { return [] }
        let typesetter = CTTypesetterCreateWithAttributedString(
            NSAttributedString(string: text, attributes: stringAttributes(style)))
        var lines: [String] = []
        var start = 0
        while start < string.length {
            let count = max(CTTypesetterSuggestLineBreak(typesetter, start, Double(max(width, 1))), 1)
            let piece = string.substring(with: NSRange(location: start, length: count))
            lines.append(piece.trimmingCharacters(in: .whitespacesAndNewlines))
            start += count
        }
        return lines.filter { !$0.isEmpty }
    }

    /// 截断到 width 内并以省略号结尾（按字素簇二分）；本身放得下时原样返回
    static func truncated(_ text: String, style: Style, width: CGFloat) -> String {
        guard self.width(of: text, style: style) > width else { return text }
        let characters = Array(text)
        var low = 0
        var high = characters.count
        while low < high {
            let middle = (low + high + 1) / 2
            if self.width(of: candidate(characters, middle), style: style) <= width {
                low = middle
            } else {
                high = middle - 1
            }
        }
        return candidate(characters, low)
    }

    /// 在 frame 内自动换行（首行顶 = frame 顶，行高 = 字体行高），供没有原文行距可循的调用方使用
    static func wrap(_ text: String, style: Style, in frame: CGRect, alignment: TextBlockAlignment) -> [TranslatedLine]
    {
        let ascent = ascent(style)
        let pitch = ascent + descent(style) + CTFontGetLeading(font(style))
        return breakLines(text, style: style, width: frame.width).enumerated().map { index, text in
            let width = width(of: text, style: style)
            let x: CGFloat =
                switch alignment {
                case .leading: frame.minX
                case .center: frame.midX - width / 2
                case .trailing: frame.maxX - width
                }
            return TranslatedLine(text: text, origin: CGPoint(x: x, y: frame.minY + ascent + CGFloat(index) * pitch))
        }
    }

    // MARK: - 内部

    private static func stringAttributes(_ style: Style) -> [NSAttributedString.Key: Any] {
        var attributes: [NSAttributedString.Key: Any] = [
            NSAttributedString.Key(kCTFontAttributeName as String): font(style)
        ]
        if let language = style.language {
            attributes[NSAttributedString.Key(kCTLanguageAttributeName as String)] = language
        }
        return attributes
    }

    private static func candidate(_ characters: [Character], _ count: Int) -> String {
        String(characters.prefix(count)).trimmingCharacters(in: .whitespaces) + ellipsis
    }
}
