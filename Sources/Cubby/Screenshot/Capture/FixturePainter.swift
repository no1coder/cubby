#if DEBUG
import CoreGraphics
import CubbyCore
import Foundation

/// 夹具画面的绘制：在「左上原点、y 向下、单位为点」的坐标系里画，输出 BGRA 位图（与真实采集一致）
enum FixturePainter {
    private static let windowRadius: CGFloat = 10
    private static let titleBarHeight: CGFloat = 28
    private static let shadowPadding: CGFloat = 40
    private static let palette: [(String, RGBAColor)] = AnnotationColor.allCases.map { ($0.hex, $0.rgba) }
    /// "截图测试"（转义写法：源码中不出现汉字字面量）
    private static let cjkSample = "\u{622A}\u{56FE}\u{6D4B}\u{8BD5} Cubby Fixture"
    private static let latinSample = "The quick brown fox jumps over the lazy dog 0123456789"

    /// 整块屏幕：背景、网格、色板、棋盘格、菜单栏、程序坞与假窗口
    static func desktop(for screen: CaptureScreen, windows: [FixtureWindow]) -> CGImage? {
        let size = screen.frame.size
        guard let context = makeContext(pointSize: size, scale: screen.scale) else { return nil }
        drawBackground(size: size, in: context)
        drawGrid(size: size, in: context)
        drawPalette(at: CGPoint(x: 24, y: size.height - 150), in: context)
        drawCheckerboard(CGRect(x: size.width - 300, y: size.height - 250, width: 240, height: 160), in: context)
        drawText(latinSample, at: CGPoint(x: 24, y: size.height - 200), size: 15, in: context)
        drawText(cjkSample, at: CGPoint(x: 24, y: size.height - 176), size: 15, in: context)
        for window in windows.reversed() {
            drawWindow(window, frame: window.frame, shadow: true, in: context)
        }
        drawChrome(size: size, in: context)
        return context.makeImage()
    }

    /// 单个窗口（纯净窗口截图的夹具）：圆角外透明；带阴影时四周留白
    static func window(_ window: FixtureWindow, scale: CGFloat, includeShadow: Bool) -> CGImage? {
        let padding = includeShadow ? shadowPadding : 0
        let size = CGSize(width: window.frame.width + padding * 2, height: window.frame.height + padding * 2)
        guard let context = makeContext(pointSize: size, scale: scale) else { return nil }
        let frame = CGRect(origin: CGPoint(x: padding, y: padding), size: window.frame.size)
        drawWindow(window, frame: frame, shadow: includeShadow, in: context)
        return context.makeImage()
    }

    // MARK: - 画布

    private static func makeContext(pointSize: CGSize, scale: CGFloat) -> CGContext? {
        let width = Int((pointSize.width * scale).rounded())
        let height = Int((pointSize.height * scale).rounded())
        guard
            let context = CGContext(
                data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
            )
        else { return nil }
        // 翻转为左上原点、y 向下，并按点绘制
        context.translateBy(x: 0, y: CGFloat(height))
        context.scaleBy(x: scale, y: -scale)
        return context
    }

    private static func color(_ value: RGBAColor, alpha: Double? = nil) -> CGColor {
        CGColor(
            srgbRed: CGFloat(value.red), green: CGFloat(value.green), blue: CGFloat(value.blue),
            alpha: CGFloat(alpha ?? value.alpha))
    }

    private static func gray(_ white: CGFloat, alpha: CGFloat = 1) -> CGColor {
        CGColor(srgbRed: white, green: white, blue: white, alpha: alpha)
    }

    // MARK: - 背景

    private static func drawBackground(size: CGSize, in context: CGContext) {
        let colors = [
            CGColor(srgbRed: 0.91, green: 0.93, blue: 0.97, alpha: 1),
            CGColor(srgbRed: 0.76, green: 0.82, blue: 0.92, alpha: 1),
        ]
        guard let gradient = CGGradient(colorsSpace: nil, colors: colors as CFArray, locations: nil) else { return }
        context.drawLinearGradient(gradient, start: .zero, end: CGPoint(x: 0, y: size.height), options: [])
    }

    /// 20 pt 细网格、100 pt 粗线与刻度数字（验证放大镜与尺寸标签）
    private static func drawGrid(size: CGSize, in context: CGContext) {
        for step in stride(from: CGFloat(20), to: max(size.width, size.height), by: 20) {
            let isMajor = step.truncatingRemainder(dividingBy: 100) == 0
            context.setStrokeColor(gray(0, alpha: isMajor ? 0.18 : 0.07))
            context.setLineWidth(isMajor ? 1 : 0.5)
            if step < size.width {
                context.strokeLineSegments(between: [CGPoint(x: step, y: 0), CGPoint(x: step, y: size.height)])
            }
            if step < size.height {
                context.strokeLineSegments(between: [CGPoint(x: 0, y: step), CGPoint(x: size.width, y: step)])
            }
            if isMajor {
                let label = String(Int(step))
                let dark = RGBAColor(red: 0.2, green: 0.24, blue: 0.3)
                if step < size.width {
                    drawText(
                        label, at: CGPoint(x: step + 3, y: FixtureLayout.menuBarHeight + 2), size: 10, color: dark,
                        in: context)
                }
                if step < size.height {
                    drawText(label, at: CGPoint(x: 3, y: step + 2), size: 10, color: dark, in: context)
                }
            }
        }
    }

    /// 8 色色板 + HEX（验证取色）
    private static func drawPalette(at origin: CGPoint, in context: CGContext) {
        let side: CGFloat = 40
        for (index, entry) in palette.enumerated() {
            let rect = CGRect(x: origin.x + CGFloat(index) * (side + 12), y: origin.y, width: side, height: side)
            context.setFillColor(color(entry.1))
            context.fill(rect)
            context.setStrokeColor(gray(0, alpha: 0.25))
            context.stroke(rect, width: 1)
            drawText(entry.0, at: CGPoint(x: rect.minX, y: rect.maxY + 4), size: 10, in: context)
        }
    }

    /// 8 pt 黑白棋盘格（马赛克前后对比明显）
    private static func drawCheckerboard(_ rect: CGRect, in context: CGContext) {
        let cell: CGFloat = 8
        for row in 0..<Int(rect.height / cell) {
            for column in 0..<Int(rect.width / cell) {
                context.setFillColor(gray((row + column).isMultiple(of: 2) ? 0.1 : 0.95))
                context.fill(
                    CGRect(
                        x: rect.minX + CGFloat(column) * cell, y: rect.minY + CGFloat(row) * cell, width: cell,
                        height: cell))
            }
        }
        drawText("Mosaic test", at: CGPoint(x: rect.minX, y: rect.maxY + 4), size: 11, in: context)
    }

    // MARK: - 菜单栏与程序坞

    private static func drawChrome(size: CGSize, in context: CGContext) {
        for item in FixtureLayout.all(screenSize: size) where item.layer != 0 {
            let path = CGPath(
                roundedRect: item.frame, cornerWidth: item.layer == 20 ? 16 : 0,
                cornerHeight: item.layer == 20 ? 16 : 0,
                transform: nil)
            context.addPath(path)
            context.setFillColor(color(item.tint, alpha: 0.92))
            context.fillPath()
            drawText(item.title, at: CGPoint(x: item.frame.minX + 12, y: item.frame.minY + 4), size: 12, in: context)
        }
    }

    // MARK: - 窗口

    private static func drawWindow(_ window: FixtureWindow, frame: CGRect, shadow: Bool, in context: CGContext) {
        let shape = CGPath(roundedRect: frame, cornerWidth: windowRadius, cornerHeight: windowRadius, transform: nil)
        context.saveGState()
        if shadow {
            // 阴影偏移在设备空间（y 向上）：负值向下
            context.setShadow(offset: CGSize(width: 0, height: -10), blur: 24, color: gray(0, alpha: 0.35))
        }
        context.addPath(shape)
        context.setFillColor(gray(0.99))
        context.fillPath()
        context.restoreGState()

        context.saveGState()
        context.addPath(shape)
        context.clip()
        context.setFillColor(color(window.tint, alpha: 0.28))
        context.fill(CGRect(x: frame.minX, y: frame.minY, width: frame.width, height: titleBarHeight))
        drawTrafficLights(at: CGPoint(x: frame.minX + 14, y: frame.minY + 8), in: context)
        drawText(window.title, at: CGPoint(x: frame.minX + 76, y: frame.minY + 6), size: 13, in: context)
        drawContent(of: window, in: frame, context: context)
        context.restoreGState()

        context.addPath(shape)
        context.setStrokeColor(gray(0, alpha: 0.25))
        context.setLineWidth(0.5)
        context.strokePath()
    }

    private static func drawTrafficLights(at origin: CGPoint, in context: CGContext) {
        let colors = [
            CGColor(srgbRed: 1, green: 0.37, blue: 0.34, alpha: 1),
            CGColor(srgbRed: 1, green: 0.74, blue: 0.18, alpha: 1),
            CGColor(srgbRed: 0.16, green: 0.79, blue: 0.25, alpha: 1),
        ]
        for (index, fill) in colors.enumerated() {
            context.setFillColor(fill)
            context.fillEllipse(in: CGRect(x: origin.x + CGFloat(index) * 20, y: origin.y, width: 12, height: 12))
        }
    }

    private static func drawContent(of window: FixtureWindow, in frame: CGRect, context: CGContext) {
        let top = frame.minY + titleBarHeight + 16
        context.setFillColor(color(window.tint))
        context.fill(CGRect(x: frame.minX + 16, y: top, width: 120, height: 80))
        let textX = frame.minX + 152
        let width = frame.maxX - textX - 16
        drawText("Window \(window.id)", at: CGPoint(x: textX, y: top), size: 15, maxWidth: width, in: context)
        drawText(latinSample, at: CGPoint(x: textX, y: top + 26), size: 12, maxWidth: width, in: context)
        drawText(
            cjkSample, at: CGPoint(x: frame.minX + 16, y: top + 100), size: 13, maxWidth: frame.width - 32, in: context)
    }

    private static func drawText(
        _ text: String,
        at origin: CGPoint,
        size: CGFloat,
        maxWidth: CGFloat = .infinity,
        color: RGBAColor = RGBAColor(red: 0.1, green: 0.1, blue: 0.12),
        in context: CGContext
    ) {
        TextLayout.draw(text, at: origin, fontSize: size, maxWidth: maxWidth, color: color, in: context)
    }
}
#endif
