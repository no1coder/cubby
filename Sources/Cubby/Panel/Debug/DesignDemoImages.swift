#if DEBUG
import AppKit
import ImageIO
import UniformTypeIdentifiers

/// 设计稿走查用的演示图片（`--demo-history`）：照着 docs/design/ui-upgrade 里的图片卡画的六种场景，
/// 全部用 CoreGraphics 现画，不读任何真实图片
enum DesignDemoImages {
    enum Scene: CaseIterable {
        /// 紫色夜空、橙色太阳与两道山丘（Keynote 幻灯片）
        case sunset
        /// 浅色应用窗口截图
        case window
        /// 深绿底的柱状图（Numbers 表格）
        case chart
        /// 浅蓝底的人像照片
        case photo
        /// 深色终端截图
        case terminal
        /// 棕色底的两个圆角色块（设计稿）
        case design
    }

    static let pixelSize = CGSize(width: 1600, height: 1000)

    static func png(_ scene: Scene) throws -> Data {
        let width = Int(pixelSize.width)
        let height = Int(pixelSize.height)
        guard
            let context = CGContext(
                data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { throw DemoImageError.drawingFailed }
        // 以左上角为原点作画，与设计稿的坐标一致
        context.translateBy(x: 0, y: pixelSize.height)
        context.scaleBy(x: 1, y: -1)
        draw(scene, in: context)
        guard let image = context.makeImage() else { throw DemoImageError.drawingFailed }
        return try encode(image)
    }

    private static func encode(_ image: CGImage) throws -> Data {
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil)
        else { throw DemoImageError.drawingFailed }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else { throw DemoImageError.drawingFailed }
        return data as Data
    }

    private static func draw(_ scene: Scene, in context: CGContext) {
        switch scene {
        case .sunset: drawSunset(context)
        case .window: drawWindow(context)
        case .chart: drawChart(context)
        case .photo: drawPhoto(context)
        case .terminal: drawTerminal(context)
        case .design: drawDesign(context)
        }
    }

    private static func drawSunset(_ context: CGContext) {
        fill(context, hex: 0x2C2257)
        ellipse(context, CGRect(x: 640, y: 180, width: 320, height: 320), hex: 0xF8C48A)
        ellipse(context, CGRect(x: -500, y: 620, width: 2400, height: 1000), hex: 0x7B4FBF)
        ellipse(context, CGRect(x: 500, y: 760, width: 1800, height: 900), hex: 0x5A3A9A)
    }

    private static func drawWindow(_ context: CGContext) {
        fill(context, hex: 0xF3F3F5)
        rect(context, CGRect(x: 0, y: 0, width: 1600, height: 110), hex: 0xE4E4E8)
        for (index, color) in [0xFF5F57, 0xFEBC2E, 0x28C840].enumerated() {
            ellipse(context, CGRect(x: 40 + index * 56, y: 38, width: 34, height: 34), hex: color)
        }
        for row in 0..<4 {
            let color = row == 2 ? 0x0A84FF : 0xD6D6DC
            rounded(context, CGRect(x: 60, y: 200 + row * 70, width: 260, height: 26), hex: color)
        }
        rounded(context, CGRect(x: 420, y: 190, width: 460, height: 56), hex: 0x2C2C30)
        rounded(context, CGRect(x: 420, y: 300, width: 1000, height: 28), hex: 0xDDDDE2)
        rounded(context, CGRect(x: 420, y: 370, width: 760, height: 28), hex: 0xDDDDE2)
        rounded(context, CGRect(x: 420, y: 460, width: 1000, height: 300), hex: 0xDCE6FF)
    }

    private static func drawChart(_ context: CGContext) {
        fill(context, hex: 0x1F2A24)
        let heights: [CGFloat] = [260, 480, 360, 680, 560]
        for (index, height) in heights.enumerated() {
            let color = index == 3 ? 0x5EDB9A : 0x3BB273
            rect(
                context, CGRect(x: 160 + CGFloat(index) * 270, y: 900 - height, width: 170, height: height), hex: color)
        }
    }

    private static func drawPhoto(_ context: CGContext) {
        fill(context, hex: 0xC9DBE8)
        ellipse(context, CGRect(x: 260, y: 170, width: 460, height: 460), hex: 0xF5F7FA)
        ellipse(context, CGRect(x: 380, y: 520, width: 1500, height: 1100), hex: 0x6E8FA6)
    }

    private static func drawTerminal(_ context: CGContext) {
        fill(context, hex: 0x232325)
        let lines: [(width: CGFloat, color: Int)] = [
            (900, 0xFF9F43), (1180, 0x6B6B70), (620, 0x6B6B70), (1000, 0x6B6B70), (780, 0x4DA3FF),
        ]
        for (index, line) in lines.enumerated() {
            rounded(
                context, CGRect(x: 110, y: 150 + CGFloat(index) * 150, width: line.width, height: 44), hex: line.color)
        }
    }

    private static func drawDesign(_ context: CGContext) {
        fill(context, hex: 0x4A3226)
        rounded(context, CGRect(x: 280, y: 260, width: 520, height: 760), hex: 0xD9895B, radius: 220)
        rounded(context, CGRect(x: 900, y: 420, width: 420, height: 600), hex: 0xA8643F, radius: 200)
    }

    // MARK: - 画笔

    private static func color(_ hex: Int) -> CGColor {
        CGColor(
            srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255, alpha: 1)
    }

    private static func fill(_ context: CGContext, hex: Int) {
        rect(context, CGRect(origin: .zero, size: pixelSize), hex: hex)
    }

    private static func rect(_ context: CGContext, _ frame: CGRect, hex: Int) {
        context.setFillColor(color(hex))
        context.fill(frame)
    }

    private static func ellipse(_ context: CGContext, _ frame: CGRect, hex: Int) {
        context.setFillColor(color(hex))
        context.fillEllipse(in: frame)
    }

    private static func rounded(_ context: CGContext, _ frame: CGRect, hex: Int, radius: CGFloat = 14) {
        // CGPath 要求圆角不超过短边的一半
        let corner = min(radius, min(frame.width, frame.height) / 2)
        context.setFillColor(color(hex))
        context.addPath(CGPath(roundedRect: frame, cornerWidth: corner, cornerHeight: corner, transform: nil))
        context.fillPath()
    }

    enum DemoImageError: Error {
        case drawingFailed
    }
}
#endif
