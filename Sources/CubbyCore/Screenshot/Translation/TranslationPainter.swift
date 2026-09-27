import CoreGraphics
import CoreText

/// 把版面画进目标位图（约定同 AnnotationRenderer：一个用户单位 = 一个目标像素，左下原点）。
/// 覆盖层与导出共用，结果逐像素一致：填色对齐像素、不抗锯齿；衬底圆角与文字抗锯齿、不做字体平滑
public enum TranslationPainter {
    /// 衬底主色的不透明度与圆角（点）
    static let plateAlpha = 0.74
    static let plateRadius: CGFloat = 6

    public static func draw(_ blocks: [TranslatedBlock], in context: CGContext, environment: RenderEnvironment) {
        for block in blocks {
            context.saveGState()
            drawBackdrop(block, in: context, environment: environment)
            context.restoreGState()
            context.saveGState()
            drawLines(block, in: context, environment: environment)
            context.restoreGState()
        }
    }

    /// 全局点 → 目标位图像素（左下原点）
    static func pixelRect(_ rect: CGRect, _ environment: RenderEnvironment) -> CGRect {
        let x = (rect.minX - environment.origin.x) * environment.scale
        let top = (rect.minY - environment.origin.y) * environment.scale
        let height = rect.height * environment.scale
        return CGRect(
            x: x, y: environment.targetPixelSize.height - top - height, width: rect.width * environment.scale,
            height: height)
    }

    /// 像素矩形向外取整（容忍浮点误差）
    static func snapped(_ rect: CGRect) -> CGRect {
        let epsilon: CGFloat = 0.001
        let minX = (rect.minX + epsilon).rounded(.down)
        let minY = (rect.minY + epsilon).rounded(.down)
        let maxX = (rect.maxX - epsilon).rounded(.up)
        let maxY = (rect.maxY - epsilon).rounded(.up)
        return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }

    // MARK: - 内部

    private static func drawBackdrop(_ block: TranslatedBlock, in context: CGContext, environment: RenderEnvironment) {
        let rects = block.eraseRects.map { snapped(pixelRect($0, environment)) }
        switch block.backdrop {
        case .solid(let color):
            context.setShouldAntialias(false)
            context.setFillColor(color.cgColor)
            context.fill(rects)
        case .plate(let color):
            let radius = plateRadius * environment.scale
            for rect in rects {
                context.saveGState()
                context.addPath(CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil))
                context.clip()
                if let image = block.plateImage?.image {
                    context.interpolationQuality = .high
                    context.draw(image, in: rect)
                }
                let plate = PixelColor(
                    red: color.red, green: color.green, blue: color.blue, alpha: color.alpha * plateAlpha)
                context.setFillColor(plate.cgColor)
                context.fill(rect)
                context.restoreGState()
            }
        }
    }

    /// 进入「左上原点、y 向下、单位为全局点」的坐标系，逐行在基线处局部翻转后绘制
    private static func drawLines(_ block: TranslatedBlock, in context: CGContext, environment: RenderEnvironment) {
        context.translateBy(x: 0, y: environment.targetPixelSize.height)
        context.scaleBy(x: environment.scale, y: -environment.scale)
        context.translateBy(x: -environment.origin.x, y: -environment.origin.y)
        context.setShouldAntialias(true)
        context.setShouldSmoothFonts(false)
        let style = block.style
        let color = block.textColor.cgColor
        for line in block.lines {
            context.saveGState()
            context.translateBy(x: line.origin.x, y: line.origin.y)
            context.scaleBy(x: 1, y: -1)
            context.textMatrix = .identity
            context.textPosition = .zero
            CTLineDraw(TranslationTypesetter.line(line.text, style: style, color: color), context)
            context.restoreGState()
        }
    }
}
