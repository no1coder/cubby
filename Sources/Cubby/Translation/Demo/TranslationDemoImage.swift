#if DEBUG
import AppKit
import ImageIO
import UniformTypeIdentifiers

/// 剪贴板翻译演示的图片：一个虚构旅行应用的英文欢迎页（800 × 500 点，144 DPI）。
/// 上方是没有文字的风景横幅，下方是标题、说明、三项功能与两个按钮；文字都在纯色底上，
/// 译后图片由真实的识别、排版与绘制流程生成。原文与 DemoTranslationTable 中的条目一致
enum TranslationDemoImage {
    static let pointSize = CGSize(width: 800, height: 500)
    static let scale: CGFloat = 2
    static var pixelSize: CGSize {
        CGSize(width: pointSize.width * scale, height: pointSize.height * scale)
    }

    static let title = "Plan trips together"
    static let body =
        "Share an itinerary with friends, vote on places to visit, and keep every booking in one place, even offline."
    static let features: [(label: String, color: UInt32)] = [
        ("Shared itineraries", 0x2F7FE0), ("Offline maps", 0x34A853), ("Price alerts", 0xF29D38),
    ]
    static let secondaryButton = "Not Now"
    static let primaryButton = "Get Started"

    /// 图中的全部文字：写进条目的 recognizedText，与真实历史一样（按图中文字搜索的本机识别早已完成），
    /// 翻译卡据此判断源语言（没有它时显示「自动检测」）
    static var allText: String {
        ([title, body] + features.map(\.label) + [secondaryButton, primaryButton]).joined(separator: "\n")
    }

    enum DrawingError: Error {
        case failed
    }

    static func png() throws -> Data {
        guard let image = draw() else { throw DrawingError.failed }
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil)
        else { throw DrawingError.failed }
        let dpi = 72 * scale
        CGImageDestinationAddImage(
            destination, image, [kCGImagePropertyDPIWidth: dpi, kCGImagePropertyDPIHeight: dpi] as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { throw DrawingError.failed }
        return data as Data
    }

    // MARK: - 绘制（左上原点、y 向下、单位为点）

    private static func draw() -> CGImage? {
        let pixels = pixelSize
        guard
            let context = CGContext(
                data: nil, width: Int(pixels.width), height: Int(pixels.height), bitsPerComponent: 8,
                bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return nil }
        context.translateBy(x: 0, y: pixels.height)
        context.scaleBy(x: scale, y: -scale)
        let previous = NSGraphicsContext.current
        NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: true)
        defer { NSGraphicsContext.current = previous }
        context.setFillColor(color(0xFFFFFF))
        context.fill(CGRect(origin: .zero, size: pointSize))
        drawBanner(in: context)
        drawBadge(in: context)
        drawText()
        drawFeatures(in: context)
        drawButtons(in: context)
        return context.makeImage()
    }

    /// 天空渐变、太阳、云与两层山
    private static func drawBanner(in context: CGContext) {
        let banner = CGRect(x: 0, y: 0, width: pointSize.width, height: 170)
        context.saveGState()
        context.clip(to: banner)
        fillGradient([0x3E8EF0, 0x8CCBFF, 0xFFE2B8], from: banner.minY, to: banner.maxY, in: context)
        context.setFillColor(color(0xFFF1C9, alpha: 0.35))
        context.fillEllipse(in: CGRect(x: 560, y: 22, width: 108, height: 108))
        context.setFillColor(color(0xFFD27A))
        context.fillEllipse(in: CGRect(x: 580, y: 42, width: 68, height: 68))
        for cloud in [CGRect(x: 120, y: 40, width: 96, height: 26), CGRect(x: 420, y: 70, width: 70, height: 20)] {
            context.setFillColor(color(0xFFFFFF, alpha: 0.85))
            context.addPath(CGPath(roundedRect: cloud, cornerWidth: 13, cornerHeight: 10, transform: nil))
            context.fillPath()
        }
        mountains([(0, 150), (140, 88), (260, 140), (390, 70), (540, 150), (680, 96), (800, 140)], 0x6FA7E0, context)
        mountains([(0, 170), (90, 120), (220, 170), (330, 112), (470, 170), (610, 124), (800, 170)], 0x2F6DB8, context)
        context.restoreGState()
    }

    private static func mountains(_ peaks: [(CGFloat, CGFloat)], _ hex: UInt32, _ context: CGContext) {
        let path = CGMutablePath()
        path.move(to: CGPoint(x: 0, y: 170))
        for (x, y) in peaks { path.addLine(to: CGPoint(x: x, y: y)) }
        path.addLine(to: CGPoint(x: pointSize.width, y: 170))
        path.closeSubpath()
        context.addPath(path)
        context.setFillColor(color(hex))
        context.fillPath()
    }

    /// 横幅下沿的应用图标（白底圆角方块 + 定位图钉）
    private static func drawBadge(in context: CGContext) {
        let badge = CGRect(x: 48, y: 136, width: 64, height: 64)
        context.saveGState()
        context.setShadow(offset: CGSize(width: 0, height: -2), blur: 8, color: color(0x000000, alpha: 0.18))
        context.addPath(CGPath(roundedRect: badge, cornerWidth: 15, cornerHeight: 15, transform: nil))
        context.setFillColor(color(0xFFFFFF))
        context.fillPath()
        context.restoreGState()
        let pin = CGMutablePath()
        pin.addArc(
            center: CGPoint(x: badge.midX, y: badge.minY + 27), radius: 14, startAngle: .pi * 0.8,
            endAngle: .pi * 0.2, clockwise: false)
        pin.addLine(to: CGPoint(x: badge.midX, y: badge.minY + 52))
        pin.closeSubpath()
        context.addPath(pin)
        context.setFillColor(color(0xFF5A3C))
        context.fillPath()
        context.setFillColor(color(0xFFFFFF))
        context.fillEllipse(in: CGRect(x: badge.midX - 5.5, y: badge.minY + 21.5, width: 11, height: 11))
    }

    private static func drawText() {
        text(title, size: 28, weight: .bold, hex: 0x1C1C1E).draw(at: CGPoint(x: 48, y: 222))
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineSpacing = 4
        let attributed = NSAttributedString(
            string: body,
            attributes: [
                .font: NSFont.systemFont(ofSize: 16), .foregroundColor: nsColor(0x48484A), .paragraphStyle: paragraph,
            ])
        attributed.draw(with: CGRect(x: 48, y: 268, width: 560, height: 60), options: [.usesLineFragmentOrigin])
    }

    /// 三项功能：彩色圆点 + 标签，横向排开
    private static func drawFeatures(in context: CGContext) {
        var x: CGFloat = 48
        for feature in features {
            context.setFillColor(color(feature.color))
            context.fillEllipse(in: CGRect(x: x, y: 350, width: 12, height: 12))
            let label = text(feature.label, size: 15, weight: .semibold, hex: 0x1C1C1E)
            label.draw(at: CGPoint(x: x + 20, y: 346))
            x += 20 + label.size().width + 36
        }
    }

    /// 右下角的两个按钮：浅灰「以后再说」、蓝色「开始使用」
    private static func drawButtons(in context: CGContext) {
        let secondary = CGRect(x: 474, y: 424, width: 120, height: 40)
        let primary = CGRect(x: 606, y: 424, width: 146, height: 40)
        for (rect, fill, label, textHex) in [
            (secondary, UInt32(0xEEEEF0), secondaryButton, UInt32(0x1C1C1E)),
            (primary, 0x0A7AFF, primaryButton, 0xFFFFFF),
        ] {
            context.addPath(CGPath(roundedRect: rect, cornerWidth: 10, cornerHeight: 10, transform: nil))
            context.setFillColor(color(fill))
            context.fillPath()
            let string = text(label, size: 15, weight: .semibold, hex: textHex)
            let size = string.size()
            string.draw(at: CGPoint(x: rect.midX - size.width / 2, y: rect.midY - size.height / 2))
        }
    }

    // MARK: - 工具

    private static func text(_ string: String, size: CGFloat, weight: NSFont.Weight, hex: UInt32) -> NSAttributedString
    {
        NSAttributedString(
            string: string,
            attributes: [.font: NSFont.systemFont(ofSize: size, weight: weight), .foregroundColor: nsColor(hex)])
    }

    private static func fillGradient(_ hexes: [UInt32], from top: CGFloat, to bottom: CGFloat, in context: CGContext) {
        let locations = hexes.indices.map { CGFloat($0) / CGFloat(max(hexes.count - 1, 1)) }
        guard
            let gradient = CGGradient(
                colorsSpace: CGColorSpace(name: CGColorSpace.sRGB), colors: hexes.map { color($0) } as CFArray,
                locations: locations)
        else { return }
        context.drawLinearGradient(gradient, start: CGPoint(x: 0, y: top), end: CGPoint(x: 0, y: bottom), options: [])
    }

    private static func color(_ hex: UInt32, alpha: CGFloat = 1) -> CGColor {
        CGColor(
            srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255, alpha: alpha)
    }

    private static func nsColor(_ hex: UInt32) -> NSColor {
        NSColor(cgColor: color(hex)) ?? .black
    }
}
#endif
