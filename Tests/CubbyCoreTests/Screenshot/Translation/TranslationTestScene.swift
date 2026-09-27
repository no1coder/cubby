import AppKit
import CoreGraphics
import CoreText
@testable import CubbyCore

/// 翻译版面测试用的合成截图：在给定背景上按点坐标画文字，并给出与 Vision 行框口径相近的行框
struct TranslationTestScene {
    struct Text {
        var string: String
        /// 基线左端（点，左上原点）
        var origin: CGPoint
        var size: CGFloat = 13
        var weight: NSFont.Weight = .regular
        var color: CGColor = CGColor(srgbRed: 0, green: 0, blue: 0, alpha: 1)
    }

    enum Background {
        case solid(CGColor)
        /// 水平渐变
        case gradient(CGColor, CGColor)
        /// 棋盘格（cell 点）
        case checker(CGColor, CGColor, cell: CGFloat)
    }

    let screen: CaptureScreen
    let frame: FrozenFrame

    /// size 为点尺寸；extra 在文字之后再画（例如按钮边框），坐标为点
    init(
        size: CGSize, scale: CGFloat = 2, origin: CGPoint = .zero, background: Background, texts: [Text],
        extra: ((CGContext) -> Void)? = nil
    ) {
        screen = CaptureScreen(id: 1, frame: CGRect(origin: origin, size: size), scale: scale)
        let canvas = TestCanvas(
            width: Int((size.width * scale).rounded()), height: Int((size.height * scale).rounded()), fill: nil)
        let context = canvas.context
        context.saveGState()
        // 左上原点、单位为点
        context.translateBy(x: 0, y: CGFloat(canvas.height))
        context.scaleBy(x: scale, y: -scale)
        Self.paint(background, size: size, in: context)
        extra?(context)
        context.setShouldSmoothFonts(false)
        for text in texts {
            context.saveGState()
            context.translateBy(x: text.origin.x, y: text.origin.y)
            context.scaleBy(x: 1, y: -1)
            context.textMatrix = .identity
            context.textPosition = .zero
            CTLineDraw(Self.line(text), context)
            context.restoreGState()
        }
        context.restoreGState()
        frame = FrozenFrame(screen: screen, image: canvas.makeImage())
    }

    /// 与 Vision 行框口径相近：基线上 0.77 em 到基线下 0.28 em（拉丁），CJK 为 0.86 / 0.36 em；宽度为字形外框外扩 0.08 em
    static func lineFrame(_ text: Text, ideographic: Bool = false) -> CGRect {
        let ink = CTLineGetBoundsWithOptions(line(text), .useGlyphPathBounds)
        let top = (ideographic ? 0.86 : 0.77) * text.size
        let bottom = (ideographic ? 0.36 : 0.28) * text.size
        let margin = 0.08 * text.size
        return CGRect(
            x: text.origin.x + ink.minX - margin, y: text.origin.y - top, width: ink.width + 2 * margin,
            height: top + bottom)
    }

    /// 由若干行文字组成的块（行框按 Vision 口径，全局点 = 场景坐标 + 屏幕原点）
    func block(_ texts: [Text], id: Int = 0, alignment: TextBlockAlignment = .leading, ideographic: Bool = false)
        -> TextBlock
    {
        let lines = texts.map { text in
            RecognizedLine(
                text: text.string,
                frame: Self.lineFrame(text, ideographic: ideographic).offsetBy(
                    dx: screen.frame.minX, dy: screen.frame.minY))
        }
        return TextBlock(id: id, lines: lines, alignment: alignment, text: TextBlockBuilder.joined(texts.map(\.string)))
    }

    static func line(_ text: Text) -> CTLine {
        let font = NSFont.systemFont(ofSize: text.size, weight: text.weight)
        let attributes: [NSAttributedString.Key: Any] = [
            NSAttributedString.Key(kCTFontAttributeName as String): font,
            NSAttributedString.Key(kCTForegroundColorAttributeName as String): text.color,
        ]
        return CTLineCreateWithAttributedString(NSAttributedString(string: text.string, attributes: attributes))
    }

    private static func paint(_ background: Background, size: CGSize, in context: CGContext) {
        let bounds = CGRect(origin: .zero, size: size)
        switch background {
        case .solid(let color):
            context.setFillColor(color)
            context.fill(bounds)
        case .gradient(let start, let end):
            let gradient = CGGradient(
                colorsSpace: TestCanvas.colorSpace, colors: [start, end] as CFArray, locations: nil)!
            context.drawLinearGradient(gradient, start: .zero, end: CGPoint(x: size.width, y: 0), options: [])
        case .checker(let first, let second, let cell):
            for row in 0..<Int((size.height / cell).rounded(.up)) {
                for column in 0..<Int((size.width / cell).rounded(.up)) {
                    context.setFillColor((row + column).isMultiple(of: 2) ? first : second)
                    context.fill(CGRect(x: CGFloat(column) * cell, y: CGFloat(row) * cell, width: cell, height: cell))
                }
            }
        }
    }
}

extension CGColor {
    static func srgb(_ hex: UInt32) -> CGColor {
        CGColor(
            srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255, alpha: 1)
    }
}
