#if DEBUG
import AppKit
import CubbyCore

/// 展示场景的画面：渐变壁纸、发布说明窗口与天气窗口。
/// 在「左上原点、y 向下、单位为点、全局坐标」的坐标系里画，输出 BGRA 位图（与真实采集一致）
enum ShowcasePainter {
    private static let windowRadius: CGFloat = 12
    private static let shadowPadding: CGFloat = 48

    // MARK: - 配色

    private static let ink = color(0x1C1C1E)
    private static let body = color(0x3A3A3C)
    private static let secondary = color(0x8E8E93)
    private static let hairline = color(0xE5E5EA)
    private static let brand = color(0x5F2EEA)
    /// 天气窗口的暖色说明文字（晴、紫外线强）
    private static let warm = color(0xC2570C)

    /// 整块屏幕；layout 为 nil 时只有壁纸（其他屏幕）
    static func desktop(for screen: CaptureScreen, layout: ShowcaseLayout?, copy: ShowcaseCopy) -> CGImage? {
        guard let context = makeContext(pointSize: screen.frame.size, scale: screen.scale) else { return nil }
        context.translateBy(x: -screen.frame.minX, y: -screen.frame.minY)
        drawWallpaper(screen.frame, scene: layout ?? ShowcaseLayout(screen: screen), in: context)
        if let layout {
            drawWeather(layout, copy: copy, shadow: true, in: context)
            drawNotes(layout, copy: copy, shadow: true, in: context)
        }
        return context.makeImage()
    }

    /// 单个窗口（纯净窗口截图）：圆角外透明；带阴影时四周留白
    static func window(id: UInt32, layout: ShowcaseLayout, copy: ShowcaseCopy, scale: CGFloat, includeShadow: Bool)
        -> CGImage?
    {
        let frame = id == ShowcaseLayout.notesID ? layout.notes : layout.weather
        let padding = includeShadow ? shadowPadding : 0
        let size = CGSize(width: frame.width + padding * 2, height: frame.height + padding * 2)
        guard let context = makeContext(pointSize: size, scale: scale) else { return nil }
        context.translateBy(x: padding - frame.minX, y: padding - frame.minY)
        if id == ShowcaseLayout.notesID {
            drawNotes(layout, copy: copy, shadow: includeShadow, in: context)
        } else {
            drawWeather(layout, copy: copy, shadow: includeShadow, in: context)
        }
        return context.makeImage()
    }

    // MARK: - 画布与颜色

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

    private static func color(_ hex: UInt32, alpha: CGFloat = 1) -> CGColor {
        CGColor(
            srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255, alpha: alpha)
    }

    private static func gradient(_ stops: [(CGFloat, CGColor)]) -> CGGradient? {
        CGGradient(
            colorsSpace: CGColorSpace(name: CGColorSpace.sRGB), colors: stops.map(\.1) as CFArray,
            locations: stops.map(\.0))
    }

    // MARK: - 壁纸

    /// 对角渐变（深蓝 → 靛紫 → 品红 → 暖橙）+ 两团柔光 + 两条半透明光带；渐变以场景为基准铺满整块屏幕
    private static func drawWallpaper(_ frame: CGRect, scene: ShowcaseLayout, in context: CGContext) {
        let size = ShowcaseLayout.sceneSize
        let start = CGPoint(x: scene.origin.x - 160, y: scene.origin.y - 120)
        let end = CGPoint(x: scene.origin.x + size.width + 160, y: scene.origin.y + size.height + 120)
        let stops: [(CGFloat, CGColor)] = [
            (0, color(0x141B4D)), (0.3, color(0x33298F)), (0.55, color(0x7B3AB8)), (0.78, color(0xD9578F)),
            (1, color(0xFF9A5C)),
        ]
        if let base = gradient(stops) {
            context.drawLinearGradient(
                base, start: start, end: end, options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
        }
        glow(
            at: CGPoint(x: scene.origin.x + 720, y: scene.origin.y + 90), radius: 460, hex: 0x6F8CFF, alpha: 0.4,
            context)
        glow(
            at: CGPoint(x: scene.origin.x + 140, y: scene.origin.y + 600), radius: 420, hex: 0xFF7AB0, alpha: 0.3,
            context)
        ribbon(scene: scene, offset: 0, alpha: 0.1, context)
        ribbon(scene: scene, offset: 70, alpha: 0.07, context)
    }

    private static func glow(at center: CGPoint, radius: CGFloat, hex: UInt32, alpha: CGFloat, _ context: CGContext) {
        guard let glow = gradient([(0, color(hex, alpha: alpha)), (1, color(hex, alpha: 0))]) else { return }
        context.drawRadialGradient(
            glow, startCenter: center, startRadius: 0, endCenter: center, endRadius: radius, options: [])
    }

    /// 从左下斜穿到右上的柔和光带
    private static func ribbon(scene: ShowcaseLayout, offset: CGFloat, alpha: CGFloat, _ context: CGContext) {
        let o = scene.origin
        let path = CGMutablePath()
        path.move(to: CGPoint(x: o.x - 400, y: o.y + 700 + offset))
        path.addCurve(
            to: CGPoint(x: o.x + 1300, y: o.y - 60 + offset),
            control1: CGPoint(x: o.x + 250, y: o.y + 380 + offset),
            control2: CGPoint(x: o.x + 700, y: o.y + 560 + offset))
        path.addLine(to: CGPoint(x: o.x + 1300, y: o.y + 60 + offset))
        path.addCurve(
            to: CGPoint(x: o.x - 400, y: o.y + 820 + offset),
            control1: CGPoint(x: o.x + 720, y: o.y + 660 + offset),
            control2: CGPoint(x: o.x + 260, y: o.y + 480 + offset))
        path.closeSubpath()
        context.addPath(path)
        context.setFillColor(color(0xFFFFFF, alpha: alpha))
        context.fillPath()
    }

    // MARK: - 窗口外框

    /// 圆角白底 + 阴影 + 标题栏（红绿灯与居中标题）；返回前已把后续绘制裁剪到窗口内
    private static func beginWindow(_ frame: CGRect, title: String, shadow: Bool, in context: CGContext) {
        let shape = CGPath(roundedRect: frame, cornerWidth: windowRadius, cornerHeight: windowRadius, transform: nil)
        if shadow {
            context.saveGState()
            // 阴影偏移在设备空间（y 向上），单位为像素：负值向下
            let scale = context.ctm.a
            context.setShadow(
                offset: CGSize(width: 0, height: -14 * scale), blur: 40 * scale, color: color(0x000000, alpha: 0.42))
            context.addPath(shape)
            context.setFillColor(color(0xFFFFFF))
            context.fillPath()
            context.restoreGState()
        }
        context.saveGState()
        context.addPath(shape)
        context.clip()
        context.setFillColor(color(0xFFFFFF))
        context.fill(frame)
        let bar = CGRect(x: frame.minX, y: frame.minY, width: frame.width, height: ShowcaseLayout.titleBarHeight)
        context.setFillColor(color(0xF6F5F8))
        context.fill(bar)
        context.setFillColor(hairline)
        context.fill(CGRect(x: bar.minX, y: bar.maxY - 0.5, width: bar.width, height: 0.5))
        drawTrafficLights(at: CGPoint(x: frame.minX + 14, y: frame.minY + 8), in: context)
        let titleWidth = ShowcaseText.width(title, size: 13, weight: .semibold)
        ShowcaseText.draw(
            title, at: CGPoint(x: frame.midX - titleWidth / 2, y: frame.minY + 6), size: 13, weight: .semibold,
            color: color(0x4A4A4F), in: context)
    }

    /// 结束裁剪并描一圈细边
    private static func endWindow(_ frame: CGRect, in context: CGContext) {
        context.restoreGState()
        let shape = CGPath(roundedRect: frame, cornerWidth: windowRadius, cornerHeight: windowRadius, transform: nil)
        context.addPath(shape)
        context.setStrokeColor(color(0x000000, alpha: 0.18))
        context.setLineWidth(0.5)
        context.strokePath()
    }

    private static func drawTrafficLights(at origin: CGPoint, in context: CGContext) {
        for (index, hex) in [UInt32(0xFF5F57), 0xFEBC2E, 0x28C840].enumerated() {
            context.setFillColor(color(hex))
            context.fillEllipse(in: CGRect(x: origin.x + CGFloat(index) * 20, y: origin.y, width: 12, height: 12))
        }
    }

    // MARK: - 发布说明

    private static func drawNotes(_ layout: ShowcaseLayout, copy: ShowcaseCopy, shadow: Bool, in context: CGContext) {
        let frame = layout.notes
        beginWindow(frame, title: copy.notesTitle, shadow: shadow, in: context)
        let x = layout.notesTextX
        ShowcaseText.draw(
            copy.heading, at: CGPoint(x: x, y: frame.minY + 48), size: 26, weight: .bold, color: ink, in: context)
        ShowcaseText.draw(
            copy.subtitle, at: CGPoint(x: x, y: frame.minY + 84), size: 13, color: secondary, in: context)
        context.setFillColor(hairline)
        context.fill(CGRect(x: x, y: frame.minY + 114, width: frame.width - 56, height: 1))
        ShowcaseText.draw(
            copy.whatsNew, at: CGPoint(x: x, y: frame.minY + 128), size: 15, weight: .semibold, color: ink,
            in: context)
        for index in copy.bullets.indices {
            let line = layout.bulletLine(index, copy: copy)
            context.setFillColor(brand)
            context.fillEllipse(in: CGRect(x: frame.minX + 46, y: line.midY - 2.5, width: 5, height: 5))
            ShowcaseText.draw(
                copy.bullets[index], at: line.origin, size: ShowcaseLayout.bodySize, color: body, in: context)
        }
        ShowcaseText.draw(
            copy.feedback, at: CGPoint(x: x, y: frame.minY + 292), size: 15, weight: .semibold, color: ink,
            in: context)
        let email = layout.emailLine(copy: copy)
        ShowcaseText.draw(
            copy.contactPrefix, at: CGPoint(x: x, y: layout.contactTop), size: ShowcaseLayout.bodySize, color: body,
            in: context)
        ShowcaseText.draw(
            copy.email, at: email.origin, size: ShowcaseLayout.bodySize, color: color(0x0A64D6), in: context)
        endWindow(frame, in: context)
    }

    // MARK: - 天气窗口

    private static func drawWeather(
        _ layout: ShowcaseLayout, copy: ShowcaseCopy, shadow: Bool, in context: CGContext
    ) {
        let frame = layout.weather
        beginWindow(frame, title: copy.weatherTitle, shadow: shadow, in: context)
        let x = layout.weatherContentX
        ShowcaseText.draw(
            copy.city, at: CGPoint(x: x, y: frame.minY + 42), size: 18, weight: .bold, color: ink, in: context)
        ShowcaseText.draw(
            copy.outlook, at: CGPoint(x: x, y: frame.minY + 66), size: 12, color: secondary, in: context)
        for (index, tile) in copy.tiles.enumerated() {
            drawTile(tile, in: layout.tile(index), highlighted: index == 0, context: context)
        }
        drawForecast(layout, copy: copy, in: context)
        endWindow(frame, in: context)
    }

    private static func drawTile(_ tile: ShowcaseCopy.Tile, in rect: CGRect, highlighted: Bool, context: CGContext) {
        context.addPath(CGPath(roundedRect: rect, cornerWidth: 10, cornerHeight: 10, transform: nil))
        context.setFillColor(highlighted ? color(0xEAF3FF) : color(0xF4F5F7))
        context.fillPath()
        ShowcaseText.draw(
            tile.label, at: CGPoint(x: rect.minX + 12, y: rect.minY + 9), size: 11, color: secondary, in: context)
        ShowcaseText.draw(
            tile.value, at: CGPoint(x: rect.minX + 12, y: rect.minY + 26), size: 20, weight: .bold, color: ink,
            in: context)
        ShowcaseText.draw(
            tile.detail, at: CGPoint(x: rect.maxX - 10, y: rect.minY + 33), size: 11, weight: .semibold,
            color: warm, trailing: true, in: context)
    }

    /// 基线、七天最高气温的柱子（最后一天橙色）与首尾两天的标签
    private static func drawForecast(_ layout: ShowcaseLayout, copy: ShowcaseCopy, in context: CGContext) {
        let plot = layout.chartPlot
        context.setFillColor(hairline)
        context.fill(CGRect(x: plot.minX, y: plot.maxY, width: plot.width, height: 1))
        let sky = gradient([(0, color(0x7CC4FF)), (1, color(0x2F7FE0))])
        let sun = gradient([(0, color(0xFFB340)), (1, color(0xFF8A00))])
        for index in ShowcaseLayout.forecastHighs.indices {
            let bar = layout.barRect(index)
            context.saveGState()
            context.addPath(CGPath(roundedRect: bar, cornerWidth: 4, cornerHeight: 4, transform: nil))
            context.clip()
            if let fill = index == layout.lastBarIndex ? sun : sky {
                context.drawLinearGradient(
                    fill, start: CGPoint(x: bar.minX, y: bar.minY), end: CGPoint(x: bar.minX, y: bar.maxY), options: [])
            }
            context.restoreGState()
        }
        let first = layout.barRect(0)
        let final = layout.barRect(layout.lastBarIndex)
        ShowcaseText.draw(
            copy.firstDay, at: CGPoint(x: first.minX - 2, y: plot.maxY + 6), size: 10, color: secondary, in: context)
        ShowcaseText.draw(
            copy.lastDay, at: CGPoint(x: final.maxX + 2, y: plot.maxY + 6), size: 10, color: secondary,
            trailing: true, in: context)
    }
}
#endif
