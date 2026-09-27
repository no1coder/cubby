#if DEBUG
import AppKit
import CoreGraphics
import CubbyCore
import ImageIO
import UniformTypeIdentifiers

/// 验收图：左右对比、识别框调试图、PNG 写出
enum TranslationQAImages {
    static func context(width: Int, height: Int) -> CGContext? {
        guard let space = CGColorSpace(name: CGColorSpace.sRGB) else { return nil }
        return CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0, space: space,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
    }

    /// 原图 | 译文，中间 12 像素深色间隔
    static func sideBySide(_ left: CGImage, _ right: CGImage) -> CGImage? {
        let gap = 12
        let width = left.width + gap + right.width
        let height = max(left.height, right.height)
        guard let context = context(width: width, height: height) else { return nil }
        context.setFillColor(CGColor(srgbRed: 0.15, green: 0.15, blue: 0.17, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        context.draw(left, in: CGRect(x: 0, y: height - left.height, width: left.width, height: left.height))
        context.draw(
            right, in: CGRect(x: left.width + gap, y: height - right.height, width: right.width, height: right.height))
        return context.makeImage()
    }

    /// 原图上画识别行框（青）、块外框（橙，带 id）、跳过的块（灰）、译文排版框（品红）
    static func debug(_ result: TranslationQARunner.SceneResult) -> CGImage? {
        let image = result.before
        let scale = result.scene.scale ?? 2
        guard let context = context(width: image.width, height: image.height) else { return nil }
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        context.translateBy(x: 0, y: CGFloat(image.height))
        context.scaleBy(x: scale, y: -scale)
        for record in result.records {
            let skipped = record.skip != nil || record.placed == nil
            stroke(
                record.block.lines.map(\.frame), color: CGColor(srgbRed: 0.1, green: 0.8, blue: 0.95, alpha: 0.9),
                width: 0.5, in: context)
            let blockColor =
                skipped
                ? CGColor(srgbRed: 0.5, green: 0.5, blue: 0.5, alpha: 0.9)
                : CGColor(srgbRed: 1, green: 0.55, blue: 0, alpha: 0.95)
            stroke([record.block.frame.insetBy(dx: -2, dy: -2)], color: blockColor, width: 1, in: context)
            if let placed = record.placed {
                stroke(
                    [placed.textFrame], color: CGColor(srgbRed: 1, green: 0.2, blue: 0.6, alpha: 0.8), width: 0.5,
                    in: context)
            }
            label(
                "#\(record.block.id)", at: CGPoint(x: record.block.frame.minX - 2, y: record.block.frame.minY - 3),
                color: blockColor, in: context)
        }
        return context.makeImage()
    }

    static func writePNG(_ image: CGImage, to url: URL) throws {
        guard let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)
        else { throw CocoaError(.fileWriteUnknown) }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else { throw CocoaError(.fileWriteUnknown) }
    }

    private static func stroke(_ rects: [CGRect], color: CGColor, width: CGFloat, in context: CGContext) {
        context.setStrokeColor(color)
        context.setLineWidth(width)
        rects.forEach { context.stroke($0) }
    }

    private static func label(_ text: String, at point: CGPoint, color: CGColor, in context: CGContext) {
        let font = NSFont.monospacedSystemFont(ofSize: 7, weight: .semibold)
        let attributes: [NSAttributedString.Key: Any] = [
            NSAttributedString.Key(kCTFontAttributeName as String): font,
            NSAttributedString.Key(kCTForegroundColorAttributeName as String): color,
        ]
        let line = CTLineCreateWithAttributedString(NSAttributedString(string: text, attributes: attributes))
        context.saveGState()
        context.translateBy(x: point.x, y: point.y)
        context.scaleBy(x: 1, y: -1)
        context.textMatrix = .identity
        context.textPosition = .zero
        CTLineDraw(line, context)
        context.restoreGState()
    }
}
#endif
