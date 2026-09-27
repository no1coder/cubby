import AppKit
import CoreGraphics
import CoreText

/// 文字标注的 CoreText 排版，与覆盖层的 `NSTextView`（TextKit 2）逐行对齐
///
/// 约定（编辑器需与之一致，否则提交后文字会跳动）：
/// - 字体 = `NSFont.systemFont(ofSize:weight: .semibold)`，段落样式为默认；
/// - `origin` 是第一行行框的左上角（不含编辑框内边距），`maxWidth` 是文字可用宽度；
/// - `NSTextView` 需设置 `textContainer.lineFragmentPadding = 0`，`textContainerInset` 放在 origin 之外；
/// - 编辑器使用 TextKit 2（`NSTextView` 默认；不要访问 `layoutManager`，否则回退 TextKit 1，纯中文行高会变）。
///
/// 换行由 CTTypesetter 决定；行的位置不交给 CTFrame（它对回退字体行高的处理随线程与缓存状态变化），
/// 而是按 TextKit 2 的实测口径固定：行高 = round(ascent) + round(descent) + round(leading)，
/// 基线距行顶 = round(ascent)，与回退字体（中文、emoji 等）无关。
public enum TextLayout {
    /// maxWidth 为无穷或过大时使用的有限排版宽度
    private static let unboundedWidth: CGFloat = 1_000_000

    /// 系统字体 semibold
    public static func font(size: CGFloat) -> CTFont {
        NSFont.systemFont(ofSize: size, weight: .semibold) as CTFont
    }

    /// 在 maxWidth 内换行后的排版尺寸（向上取整到点）；空串为 `.zero`
    /// - 宽度：各行排版宽度（含行尾空白）的最大值，不超过 maxWidth；高度：行数 × 行高（末尾换行符另占一行）
    public static func size(of text: String, fontSize: CGFloat, maxWidth: CGFloat) -> CGSize {
        guard !text.isEmpty else { return .zero }
        let width = layoutWidth(maxWidth)
        let lines = makeLines(text, fontSize: fontSize, color: nil, width: width)
        let metrics = LineMetrics(font: font(size: fontSize))
        let lineCount = lines.count + (text.hasSuffix("\n") ? 1 : 0)
        let usedWidth = lines.map { CGFloat(CTLineGetTypographicBounds($0, nil, nil, nil)) }.max() ?? 0
        return CGSize(
            width: min(usedWidth, width).rounded(.up),
            height: CGFloat(lineCount) * metrics.lineHeight
        )
    }

    /// 在左上原点、y 向下的 context 中从 origin 开始绘制
    public static func draw(
        _ text: String,
        at origin: CGPoint,
        fontSize: CGFloat,
        maxWidth: CGFloat,
        color: RGBAColor,
        in context: CGContext
    ) {
        guard !text.isEmpty else { return }
        let lines = makeLines(text, fontSize: fontSize, color: color.srgbCGColor, width: layoutWidth(maxWidth))
        let metrics = LineMetrics(font: font(size: fontSize))
        for (index, line) in lines.enumerated() {
            let baseline = origin.y + metrics.baseline + CGFloat(index) * metrics.lineHeight
            context.saveGState()
            // CoreText 以 y 向上绘制：移到基线后局部翻转
            context.translateBy(x: origin.x, y: baseline)
            context.scaleBy(x: 1, y: -1)
            context.textMatrix = .identity
            context.textPosition = .zero
            CTLineDraw(line, context)
            context.restoreGState()
        }
    }

    // MARK: - 内部

    /// 单行行高（TextKit 2 口径）
    static func lineHeight(fontSize: CGFloat) -> CGFloat {
        LineMetrics(font: font(size: fontSize)).lineHeight
    }

    /// TextKit 2 的行框口径
    private struct LineMetrics {
        let baseline: CGFloat
        let lineHeight: CGFloat

        init(font: CTFont) {
            baseline = CTFontGetAscent(font).rounded()
            lineHeight = baseline + CTFontGetDescent(font).rounded() + CTFontGetLeading(font).rounded()
        }
    }

    /// maxWidth 非正时按 1 pt 处理，非有限值或过大时按 `unboundedWidth` 处理
    private static func layoutWidth(_ maxWidth: CGFloat) -> CGFloat {
        guard maxWidth.isFinite else { return unboundedWidth }
        return min(max(maxWidth, 1), unboundedWidth)
    }

    /// 用 CTTypesetter 按宽度断行（硬换行符处也断开）
    private static func makeLines(_ text: String, fontSize: CGFloat, color: CGColor?, width: CGFloat) -> [CTLine] {
        var attributes: [NSAttributedString.Key: Any] = [
            NSAttributedString.Key(kCTFontAttributeName as String): font(size: fontSize),
            .paragraphStyle: NSParagraphStyle.default,
        ]
        if let color {
            attributes[NSAttributedString.Key(kCTForegroundColorAttributeName as String)] = color
        }
        let string = NSAttributedString(string: text, attributes: attributes)
        let typesetter = CTTypesetterCreateWithAttributedString(string as CFAttributedString)
        var lines: [CTLine] = []
        var start = 0
        while start < string.length {
            let count = max(CTTypesetterSuggestLineBreak(typesetter, start, Double(width)), 1)
            lines.append(CTTypesetterCreateLine(typesetter, CFRange(location: start, length: count)))
            start += count
        }
        return lines
    }
}

extension RGBAColor {
    /// sRGB CGColor
    var srgbCGColor: CGColor {
        CGColor(srgbRed: CGFloat(red), green: CGFloat(green), blue: CGFloat(blue), alpha: CGFloat(alpha))
    }
}
