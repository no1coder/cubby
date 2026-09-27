import AppKit
import CoreGraphics
import CoreText

/// 在「全局点、y 向下」的坐标系中绘制单个标注（由 `AnnotationRenderer` 建立坐标系后调用）
struct ShapePainter {
    let context: CGContext
    let environment: RenderEnvironment

    /// 荧光笔整层合成的 alpha：0.5 与微信、macOS 标记接近；multiply 保证深色文字不被盖住
    static let highlighterAlpha: CGFloat = 0.5
    /// 马赛克占位灰块（像素化副本未就绪时）
    static let mosaicPlaceholder = CGColor(srgbRed: 0.5, green: 0.5, blue: 0.5, alpha: 0.5)
    /// 箭头、矩形等的斜接上限
    private static let miterLimit: CGFloat = 10

    func paint(_ annotation: Annotation, numberLabel: Int?) {
        let color = annotation.style.color.rgba.srgbCGColor
        let width = annotation.lineWidth
        switch annotation.shape {
        case .rectangle(let rect):
            strokeShape(CGPath(rect: rect.standardized, transform: nil), color: color, width: width, join: .miter)
        case .ellipse(let rect):
            strokeShape(CGPath(ellipseIn: rect.standardized, transform: nil), color: color, width: width, join: .round)
        case .arrow(let from, let to):
            context.setFillColor(color)
            context.addPath(ArrowGeometry.taperedPath(from: from, to: to, lineWidth: width))
            context.fillPath()
        case .pen(let points):
            paintPen(points, color: color, width: width)
        case .highlighter(let points):
            paintHighlighter(points, color: color, width: width, bounds: annotation.bounds)
        case .mosaic(let points):
            paintMosaic(points, width: width)
        case .text(let text, let origin, let maxWidth):
            TextLayout.draw(
                text,
                at: origin,
                fontSize: annotation.fontSize,
                maxWidth: maxWidth,
                color: annotation.style.color.rgba,
                in: context
            )
        case .number(let center):
            NumberBadgePainter(context: context).paint(
                center: center,
                diameter: annotation.badgeDiameter,
                fontSize: annotation.fontSize,
                color: color,
                label: numberLabel
            )
        }
    }

    // MARK: - 线条

    private func strokeShape(_ path: CGPath, color: CGColor, width: CGFloat, join: CGLineJoin) {
        context.saveGState()
        context.setStrokeColor(color)
        context.setLineWidth(width)
        context.setLineJoin(join)
        context.setMiterLimit(Self.miterLimit)
        context.addPath(path)
        context.strokePath()
        context.restoreGState()
    }

    /// 自由笔迹的轮廓（圆角连接）；单点为直径 = 线宽的圆，空点列为 nil
    private func freehandOutline(_ points: [CGPoint], width: CGFloat, cap: CGLineCap) -> CGPath? {
        switch points.count {
        case 0:
            return nil
        case 1:
            return CGPath(ellipseIn: Annotation.square(center: points[0], side: width), transform: nil)
        default:
            return StrokeSmoothing.path(through: points)
                .copy(strokingWithWidth: width, lineCap: cap, lineJoin: .round, miterLimit: Self.miterLimit)
        }
    }

    private func paintPen(_ points: [CGPoint], color: CGColor, width: CGFloat) {
        guard let outline = freehandOutline(points, width: width, cap: .round) else { return }
        context.setFillColor(color)
        context.addPath(outline)
        context.fillPath()
    }

    /// 颜色以 alpha 1 画进透明层，整层以 0.5 alpha、multiply 合成：自交叉不加深、文字仍清晰
    private func paintHighlighter(_ points: [CGPoint], color: CGColor, width: CGFloat, bounds: CGRect) {
        guard let outline = freehandOutline(points, width: width, cap: .butt) else { return }
        context.saveGState()
        context.setAlpha(Self.highlighterAlpha)
        context.setBlendMode(.multiply)
        context.beginTransparencyLayer(in: bounds, auxiliaryInfo: nil)
        context.setFillColor(color)
        context.addPath(outline)
        context.fillPath()
        context.endTransparencyLayer()
        context.restoreGState()
    }

    // MARK: - 马赛克

    /// 以笔迹轮廓为裁剪，绘制整帧的像素化副本；副本未就绪时画半透明灰块
    private func paintMosaic(_ points: [CGPoint], width: CGFloat) {
        guard let outline = freehandOutline(points, width: width, cap: .round) else { return }
        context.saveGState()
        context.addPath(outline)
        context.clip()
        if let pixelated = environment.pixelatedFrame {
            let size = CGSize(
                width: CGFloat(pixelated.width) / environment.scale,
                height: CGFloat(pixelated.height) / environment.scale
            )
            drawUpright(pixelated, in: CGRect(origin: environment.frameOrigin, size: size))
        } else {
            context.setFillColor(Self.mosaicPlaceholder)
            context.fill(outline.boundingBoxOfPath)
        }
        context.restoreGState()
    }

    /// 在 y 向下的坐标系中正向绘制位图（CGContext.draw 默认按 y 向上放置），最近邻取样保持块边清晰
    private func drawUpright(_ image: CGImage, in rect: CGRect) {
        context.saveGState()
        context.interpolationQuality = .none
        context.translateBy(x: 0, y: rect.minY + rect.maxY)
        context.scaleBy(x: 1, y: -1)
        context.draw(image, in: rect)
        context.restoreGState()
    }
}

/// 序号徽标：实心圆（编号 ≥ 100 时加宽为胶囊）+ 外圈白色描边 + 居中的白色粗体数字
struct NumberBadgePainter {
    let context: CGContext

    /// 数字左右留白（占直径的比例），超出圆时加宽为胶囊
    private static let horizontalPaddingRatio: CGFloat = 0.45
    /// 数字颜色：白
    private static let labelColor = CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 1)
    /// 徽标外圈白色描边：压在彩色、深色内容上也能与底色分开（白底上看不出，不影响观感）
    private static let outlineWidth: CGFloat = 1.5
    private static let outlineColor = CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 0.9)

    /// fontSize 取 `ScreenshotTool.number.fontSize(for:)`（= 直径 × 0.6）
    func paint(center: CGPoint, diameter: CGFloat, fontSize: CGFloat, color: CGColor, label: Int?) {
        let line = label.map { makeLine(String($0), fontSize: fontSize) }
        let textWidth = line.map { CGFloat(CTLineGetTypographicBounds($0, nil, nil, nil)) } ?? 0
        let width = max(diameter, textWidth + diameter * Self.horizontalPaddingRatio)
        let badge = CGRect(x: center.x - width / 2, y: center.y - diameter / 2, width: width, height: diameter)
        let radius = diameter / 2
        // 描边整根画在徽标外侧：先画外扩半个线宽的描边，再盖上实心徽标
        let half = Self.outlineWidth / 2
        let ring = badge.insetBy(dx: -half, dy: -half)
        context.setStrokeColor(Self.outlineColor)
        context.setLineWidth(Self.outlineWidth)
        context.addPath(
            CGPath(roundedRect: ring, cornerWidth: radius + half, cornerHeight: radius + half, transform: nil))
        context.strokePath()
        context.setFillColor(color)
        context.addPath(CGPath(roundedRect: badge, cornerWidth: radius, cornerHeight: radius, transform: nil))
        context.fillPath()
        guard let line else { return }

        // 以字形轮廓的中心对准徽标中心；CoreText 以 y 向上绘制，因此局部翻转
        let glyphs = CTLineGetBoundsWithOptions(line, .useGlyphPathBounds)
        context.saveGState()
        context.translateBy(x: center.x, y: center.y)
        context.scaleBy(x: 1, y: -1)
        context.textMatrix = .identity
        context.textPosition = CGPoint(x: -glyphs.midX, y: -glyphs.midY)
        CTLineDraw(line, context)
        context.restoreGState()
    }

    private func makeLine(_ text: String, fontSize: CGFloat) -> CTLine {
        let font = NSFont.monospacedDigitSystemFont(ofSize: fontSize, weight: .bold) as CTFont
        let attributes: [NSAttributedString.Key: Any] = [
            NSAttributedString.Key(kCTFontAttributeName as String): font,
            NSAttributedString.Key(kCTForegroundColorAttributeName as String): Self.labelColor,
        ]
        return CTLineCreateWithAttributedString(NSAttributedString(string: text, attributes: attributes))
    }
}
