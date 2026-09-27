import AppKit

extension NSAttributedString.Key {
    /// 行内底框（值为 GuideInlineBox.rawValue）：由 GuideLayoutManager 在文字下方绘制
    static let guideInlineBox = NSAttributedString.Key("CubbyGuideInlineBox")
}

/// 行内底框：键帽与行内代码。键帽与设置页的 ShortcutKeyCap 同一视觉语言
/// （Radius.key 圆角、0.5pt primary 0.1 描边、底部 1pt 投影；浅色白底，深色 white 0.14）
enum GuideInlineBox: Int {
    case code
    case key

    /// 两侧留白：排版时用字距在框外让出同样的空间（见 GuideTypesetter）
    var horizontalPadding: CGFloat {
        switch self {
        case .code: 3
        case .key: 5
        }
    }

    var verticalPadding: CGFloat {
        switch self {
        case .code: 1
        case .key: 2
        }
    }

    /// 框与相邻文字的间隙
    static let gap: CGFloat = 2

    /// 框两侧需要的字距：留白 + 间隙
    var outerKern: CGFloat {
        horizontalPadding + Self.gap
    }

    func draw(in rect: NSRect) {
        let radius = Radius.key
        let shape = NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius)
        switch self {
        case .code:
            GuideInlineBoxColors.codeFill.setFill()
            shape.fill()
        case .key:
            // 视图是翻转坐标：y 增大向下，投影画在下方 1pt
            GuideInlineBoxColors.keyShadow.setFill()
            NSBezierPath(roundedRect: rect.offsetBy(dx: 0, dy: 1), xRadius: radius, yRadius: radius).fill()
            GuideInlineBoxColors.keyFill.setFill()
            shape.fill()
            let outline = NSBezierPath(
                roundedRect: rect.insetBy(dx: 0.25, dy: 0.25), xRadius: radius, yRadius: radius)
            outline.lineWidth = 0.5
            GuideInlineBoxColors.keyStroke.setStroke()
            outline.stroke()
        }
    }
}

/// 随浅色 / 深色外观变化的底框颜色（绘制时按当前外观解析）
private enum GuideInlineBoxColors {
    static let keyFill = dynamic(light: .white, dark: NSColor.white.withAlphaComponent(0.14))
    static let keyShadow = dynamic(
        light: NSColor.black.withAlphaComponent(0.12), dark: NSColor.black.withAlphaComponent(0.35))
    static let keyStroke = dynamic(
        light: NSColor.black.withAlphaComponent(0.1), dark: NSColor.white.withAlphaComponent(0.1))
    static let codeFill = dynamic(
        light: NSColor.black.withAlphaComponent(0.05), dark: NSColor.white.withAlphaComponent(0.08))

    private static func dynamic(light: NSColor, dark: NSColor) -> NSColor {
        NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? dark : light
        }
    }
}

/// 在文字背景层画出行内底框：先画底框，再由系统画选区与搜索高亮，最后画文字
final class GuideLayoutManager: NSLayoutManager {
    override func drawBackground(forGlyphRange glyphsToShow: NSRange, at origin: NSPoint) {
        drawInlineBoxes(forGlyphRange: glyphsToShow, at: origin)
        super.drawBackground(forGlyphRange: glyphsToShow, at: origin)
    }

    private func drawInlineBoxes(forGlyphRange glyphsToShow: NSRange, at origin: NSPoint) {
        guard let storage = textStorage else { return }
        let characters = characterRange(forGlyphRange: glyphsToShow, actualGlyphRange: nil)
        storage.enumerateAttribute(.guideInlineBox, in: characters) { value, range, _ in
            guard let raw = value as? Int, let box = GuideInlineBox(rawValue: raw),
                let font = storage.attribute(.font, at: range.location, effectiveRange: nil) as? NSFont
            else { return }
            for rect in boxRects(forCharacters: range, box: box, font: font) {
                box.draw(in: rect.offsetBy(dx: origin.x, dy: origin.y))
            }
        }
    }

    /// 每行一个框（框很少跨行）：横向取字形范围，去掉末尾让出的字距；纵向按框内字体的上下伸部围绕基线
    private func boxRects(forCharacters range: NSRange, box: GuideInlineBox, font: NSFont) -> [NSRect] {
        let glyphs = glyphRange(forCharacterRange: range, actualCharacterRange: nil)
        var rects: [NSRect] = []
        enumerateLineFragments(forGlyphRange: glyphs) { lineRect, _, container, lineGlyphs, _ in
            let part = NSIntersectionRange(lineGlyphs, glyphs)
            guard part.length > 0 else { return }
            let bounds = self.boundingRect(forGlyphRange: part, in: container)
            let baseline = lineRect.minY + self.location(forGlyphAt: part.location).y
            let isLastPart = NSMaxRange(part) == NSMaxRange(glyphs)
            let trailing = isLastPart ? box.outerKern : 0
            rects.append(
                NSRect(
                    x: bounds.minX - box.horizontalPadding,
                    y: baseline - font.ascender - box.verticalPadding,
                    width: bounds.width - trailing + box.horizontalPadding * 2,
                    height: font.ascender - font.descender + box.verticalPadding * 2
                ))
        }
        return rects
    }
}
