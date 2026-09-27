#if DEBUG
import AppKit
import CoreGraphics
import CoreText

/// 视觉验收语料（JSON，见 Tests/TranslationQA/corpus.json）：每个场景是一张合成截图 + 每段文字的预置译文
struct TranslationQACorpus: Decodable {
    let scenes: [TranslationQAScene]
}

struct TranslationQAScene: Decodable {
    let id: String
    let title: String
    let width: CGFloat
    let height: CGFloat
    /// 点 → 像素，默认 2
    let scale: CGFloat?
    /// 目标语言（BCP-47）
    let target: String
    let background: Paint
    let shapes: [Shape]?
    let texts: [Text]

    /// 纯色 color、水平渐变 gradient（两色）或平滑彩色噪点 noise（种子）
    struct Paint: Decodable {
        let color: String?
        let gradient: [String]?
        let noise: UInt64?
    }

    /// 点坐标矩形 [x, y, w, h]；可圆角、描边；oval 为椭圆
    struct Shape: Decodable {
        let rect: [CGFloat]
        let fill: Paint?
        let radius: CGFloat?
        let stroke: String?
        let oval: Bool?
    }

    /// 一段文字：y 为首行行框顶；x 按 align 为左缘 / 中线 / 右缘；width 为折行宽度（缺省不折行）
    struct Text: Decodable {
        let text: String
        let x: CGFloat
        let y: CGFloat
        let size: CGFloat?
        let weight: String?
        let color: String?
        let width: CGFloat?
        let lineHeight: CGFloat?
        let align: String?
        let lang: String?
        /// 预置译文；nil 表示预期不翻译（数字、代码等）
        let translation: String?
        /// 列表符号（画在正文左侧 marker 缩进处）
        let marker: String?
    }
}

/// 渲染后的场景：位图 + 每段文字的真值外框（点）
struct TranslationQARendering {
    let image: CGImage
    /// 与 scene.texts 一一对应
    let textFrames: [CGRect]
}

enum TranslationQARenderer {
    private static let markerGap: CGFloat = 8

    static func render(_ scene: TranslationQAScene) -> TranslationQARendering? {
        let scale = scene.scale ?? 2
        let width = Int((scene.width * scale).rounded())
        let height = Int((scene.height * scale).rounded())
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
            let context = CGContext(
                data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0, space: space,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return nil }
        let bounds = CGRect(x: 0, y: 0, width: scene.width, height: scene.height)
        context.translateBy(x: 0, y: CGFloat(height))
        context.scaleBy(x: scale, y: -scale)
        context.setShouldSmoothFonts(false)
        fill(bounds, with: scene.background, in: context, scale: scale)
        for shape in scene.shapes ?? [] { draw(shape, in: context, scale: scale) }
        let frames = scene.texts.map { draw($0, in: context) }
        guard let image = context.makeImage() else { return nil }
        return TranslationQARendering(image: image, textFrames: frames)
    }

    // MARK: - 背景与形状

    private static func fill(
        _ rect: CGRect, with paint: TranslationQAScene.Paint, in context: CGContext, scale: CGFloat
    ) {
        if let colors = paint.gradient, colors.count == 2,
            let gradient = CGGradient(
                colorsSpace: CGColorSpace(name: CGColorSpace.sRGB),
                colors: colors.map(color) as CFArray, locations: nil)
        {
            context.saveGState()
            context.clip(to: rect)
            context.drawLinearGradient(
                gradient, start: CGPoint(x: rect.minX, y: rect.minY), end: CGPoint(x: rect.maxX, y: rect.maxY),
                options: [])
            context.restoreGState()
        } else if let seed = paint.noise {
            let pixels = CGSize(width: (rect.width * scale).rounded(), height: (rect.height * scale).rounded())
            if let noise = TranslationQANoise.image(size: pixels, seed: seed) {
                context.saveGState()
                context.translateBy(x: rect.minX, y: rect.maxY)
                context.scaleBy(x: 1, y: -1)
                context.draw(noise, in: CGRect(origin: .zero, size: rect.size))
                context.restoreGState()
            }
        } else {
            context.setFillColor(color(paint.color ?? "#FFFFFF"))
            context.fill(rect)
        }
    }

    private static func draw(_ shape: TranslationQAScene.Shape, in context: CGContext, scale: CGFloat) {
        guard shape.rect.count == 4 else { return }
        let rect = CGRect(x: shape.rect[0], y: shape.rect[1], width: shape.rect[2], height: shape.rect[3])
        let radius = min(shape.radius ?? 0, rect.width / 2, rect.height / 2)
        let path =
            shape.oval == true
            ? CGPath(ellipseIn: rect, transform: nil)
            : CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil)
        if let paint = shape.fill {
            context.saveGState()
            context.addPath(path)
            context.clip()
            fill(rect, with: paint, in: context, scale: scale)
            context.restoreGState()
        }
        if let stroke = shape.stroke {
            context.setStrokeColor(color(stroke))
            context.setLineWidth(1)
            context.addPath(
                CGPath(
                    roundedRect: rect.insetBy(dx: 0.5, dy: 0.5), cornerWidth: radius, cornerHeight: radius,
                    transform: nil))
            context.strokePath()
        }
    }

    // MARK: - 文字

    /// 画一段文字，返回各行排版框的并集（点）
    private static func draw(_ text: TranslationQAScene.Text, in context: CGContext) -> CGRect {
        let size = text.size ?? 13
        let font = NSFont.systemFont(ofSize: size, weight: weight(text.weight))
        let lineHeight = text.lineHeight ?? (size * 1.35).rounded()
        let lines = wrap(text, font: font)
        let ascent = CTFontGetAscent(font)
        let descent = CTFontGetDescent(font)
        var frame = CGRect.null
        for (index, line) in lines.enumerated() {
            let width =
                CGFloat(CTLineGetTypographicBounds(line, nil, nil, nil)) - CTLineGetTrailingWhitespaceWidth(line)
            let left: CGFloat =
                switch text.align {
                case "center": text.x - width / 2
                case "right": text.x - width
                default: text.x
                }
            let top = text.y + CGFloat(index) * lineHeight
            let baseline = top + (lineHeight - (ascent + descent)) / 2 + ascent
            drawLine(line, at: CGPoint(x: left, y: baseline), in: context)
            frame = frame.union(CGRect(x: left, y: baseline - ascent, width: width, height: ascent + descent))
            if index == 0, let marker = text.marker {
                let markerLine = ctLine(marker, font: font, color: color(text.color ?? "#000000"), lang: nil)
                let markerWidth = CGFloat(CTLineGetTypographicBounds(markerLine, nil, nil, nil))
                drawLine(markerLine, at: CGPoint(x: left - markerGap - markerWidth, y: baseline), in: context)
            }
        }
        return frame
    }

    private static func wrap(_ text: TranslationQAScene.Text, font: NSFont) -> [CTLine] {
        let color = color(text.color ?? "#000000")
        guard let width = text.width else { return [ctLine(text.text, font: font, color: color, lang: text.lang)] }
        let string = attributed(text.text, font: font, color: color, lang: text.lang)
        let typesetter = CTTypesetterCreateWithAttributedString(string)
        var lines: [CTLine] = []
        var start = 0
        while start < string.length {
            let count = max(CTTypesetterSuggestLineBreak(typesetter, start, Double(width)), 1)
            lines.append(CTTypesetterCreateLine(typesetter, CFRange(location: start, length: count)))
            start += count
        }
        return lines
    }

    private static func drawLine(_ line: CTLine, at origin: CGPoint, in context: CGContext) {
        context.saveGState()
        context.translateBy(x: origin.x, y: origin.y)
        context.scaleBy(x: 1, y: -1)
        context.textMatrix = .identity
        context.textPosition = .zero
        CTLineDraw(line, context)
        context.restoreGState()
    }

    private static func ctLine(_ string: String, font: NSFont, color: CGColor, lang: String?) -> CTLine {
        CTLineCreateWithAttributedString(attributed(string, font: font, color: color, lang: lang))
    }

    private static func attributed(_ string: String, font: NSFont, color: CGColor, lang: String?) -> NSAttributedString
    {
        var attributes: [NSAttributedString.Key: Any] = [
            NSAttributedString.Key(kCTFontAttributeName as String): font,
            NSAttributedString.Key(kCTForegroundColorAttributeName as String): color,
        ]
        if let lang { attributes[NSAttributedString.Key(kCTLanguageAttributeName as String)] = lang }
        return NSAttributedString(string: string, attributes: attributes)
    }

    private static func weight(_ name: String?) -> NSFont.Weight {
        switch name {
        case "medium": .medium
        case "semibold": .semibold
        case "bold": .bold
        default: .regular
        }
    }

    /// "#RRGGBB" → sRGB
    static func color(_ hex: String) -> CGColor {
        let value = UInt32(hex.trimmingCharacters(in: CharacterSet(charactersIn: "#")), radix: 16) ?? 0
        return CGColor(
            srgbRed: CGFloat((value >> 16) & 0xFF) / 255, green: CGFloat((value >> 8) & 0xFF) / 255,
            blue: CGFloat(value & 0xFF) / 255, alpha: 1)
    }
}
#endif
