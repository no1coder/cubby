#!/usr/bin/env swift
// 生成 DMG 安装窗口背景 packaging/dmg/background.png（1x）与 background@2x.png（Retina）
//
// 用法：swift scripts/make-dmg-background.swift
// 布局：窗口尺寸、图标尺寸与位置取自 packaging/dmg/layout.json（dmgbuild 配置读同一份文件）。
// 设计：深靛紫渐变底（与应用图标同色系）+ 两个磨砂玻璃「小格子」分别托住 Cubby 与「应用程序」，
//       中间一支箭头，顶部品牌字标，底部中英双语安装提示。
// 标签可读性：图标名称由 Finder 绘制，颜色不受背景控制（macOS 26 实测浅色、深色模式下都是黑字，
//       较早的系统在深色模式下可能用白字）。因此格子底部（标签所在区域）的亮度取黑白两色
//       对比度都足够的中间值；脚本会实测该区域对比度，低于 minContrast 时报错退出。
// 改动 layout.json 或本脚本后重新运行，并提交生成的两张 PNG。
import AppKit
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

// MARK: - 布局（与 packaging/dmg/layout.json 对应）

struct Layout: Decodable {
    /// 窗口：width × height 为内容区（即背景 1x 尺寸）；bleed 为背景图底部多画的出血，
    /// 用来吸收不同 macOS 版本标题栏高度的差异（titleBarHeight 只由 dmgbuild 配置使用）
    struct Window: Decodable {
        let width: CGFloat
        let height: CGFloat
        let bleed: CGFloat
    }
    struct Point: Decodable {
        let x: CGFloat
        let y: CGFloat
    }
    let window: Window
    let iconSize: CGFloat
    let textSize: CGFloat
    let app: Point
    let applications: Point
}

let colorSpace = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()
/// 标签区域与黑字、白字的最低对比度（WCAG 相对亮度公式）
let minContrast: CGFloat = 4.0

/// 格子（磨砂玻璃卡片）相对图标中心的范围：上方留白、下方容纳 Finder 绘制的图标名称
let cellWidth: CGFloat = 184
let cellTopInset: CGFloat = 84
let cellBottomInset: CGFloat = 102
let cellRadius: CGFloat = 30
/// Finder 标签大致所在的纵向范围（相对图标中心），用于对比度自检
let labelTop: CGFloat = 68
let labelBottom: CGFloat = 94
let labelHalfWidth: CGFloat = 56

func color(_ red: CGFloat, _ green: CGFloat, _ blue: CGFloat, _ alpha: CGFloat = 1) -> CGColor {
    CGColor(colorSpace: colorSpace, components: [red, green, blue, alpha]) ?? CGColor(gray: 0, alpha: alpha)
}

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data("生成 DMG 背景失败：\(message)\n".utf8))
    exit(1)
}

// MARK: - 绘制

/// 以「距顶部」坐标绘制（与 Finder 图标坐标一致），内部换算为 CoreGraphics 左下角原点
struct Canvas {
    let context: CGContext
    let layout: Layout

    var width: CGFloat { layout.window.width }
    /// 窗口内容区高度（文字、图标都排在这个范围内）
    var height: CGFloat { layout.window.height }
    /// 背景图高度 = 内容区 + 底部出血
    var imageHeight: CGFloat { layout.window.height + layout.window.bleed }

    func point(_ x: CGFloat, _ top: CGFloat) -> CGPoint { CGPoint(x: x, y: imageHeight - top) }

    func rect(x: CGFloat, top: CGFloat, width: CGFloat, height rectHeight: CGFloat) -> CGRect {
        CGRect(x: x, y: imageHeight - top - rectHeight, width: width, height: rectHeight)
    }

    func gradient(_ colors: [CGColor], _ locations: [CGFloat]) -> CGGradient {
        guard let gradient = CGGradient(colorsSpace: colorSpace, colors: colors as CFArray, locations: locations) else {
            fail("无法创建渐变")
        }
        return gradient
    }

    /// 底色：上浅下深的靛紫渐变 + 顶部柔光 + 右下角一抹品红，与图标底板同色系
    func drawBackdrop() {
        let base = gradient(
            [color(0.36, 0.27, 0.86), color(0.24, 0.15, 0.64), color(0.13, 0.07, 0.40)],
            [0, 0.55, 1]
        )
        context.drawLinearGradient(base, start: point(0, 0), end: point(0, imageHeight), options: [])

        let glow = gradient([color(0.62, 0.52, 1.00, 0.55), color(0.62, 0.52, 1.00, 0)], [0, 1])
        context.drawRadialGradient(
            glow, startCenter: point(width / 2, -40), startRadius: 0,
            endCenter: point(width / 2, -40), endRadius: 320, options: []
        )
        let blush = gradient([color(0.95, 0.45, 0.85, 0.18), color(0.95, 0.45, 0.85, 0)], [0, 1])
        context.drawRadialGradient(
            blush, startCenter: point(width + 20, imageHeight + 20), startRadius: 0,
            endCenter: point(width + 20, imageHeight + 20), endRadius: 300, options: []
        )
    }

    func cellRect(center: Layout.Point) -> CGRect {
        rect(
            x: center.x - cellWidth / 2, top: center.y - cellTopInset,
            width: cellWidth, height: cellTopInset + cellBottomInset
        )
    }

    /// 磨砂玻璃格子：半透明白底、顶部高光、1pt 描边与轻微投影
    func drawCell(center: Layout.Point) {
        let frame = cellRect(center: center)
        let shape = CGPath(roundedRect: frame, cornerWidth: cellRadius, cornerHeight: cellRadius, transform: nil)

        context.saveGState()
        context.setShadow(offset: CGSize(width: 0, height: -8), blur: 24, color: color(0.05, 0.02, 0.20, 0.35))
        context.addPath(shape)
        context.setFillColor(color(1, 1, 1, 0.37))
        context.fillPath()
        context.restoreGState()

        context.saveGState()
        context.addPath(shape)
        context.clip()
        let sheen = gradient([color(1, 1, 1, 0.10), color(1, 1, 1, 0)], [0, 1])
        context.drawLinearGradient(
            sheen, start: CGPoint(x: 0, y: frame.maxY), end: CGPoint(x: 0, y: frame.midY), options: []
        )
        context.restoreGState()

        context.saveGState()
        let inset = frame.insetBy(dx: 0.5, dy: 0.5)
        context.addPath(CGPath(roundedRect: inset, cornerWidth: cellRadius - 0.5, cornerHeight: cellRadius - 0.5, transform: nil))
        context.replacePathWithStrokedPath()
        context.clip()
        let rim = gradient([color(1, 1, 1, 0.45), color(1, 1, 1, 0.10)], [0, 1])
        context.drawLinearGradient(rim, start: CGPoint(x: 0, y: frame.maxY), end: CGPoint(x: 0, y: frame.minY), options: [])
        context.restoreGState()
    }

    /// 两个格子之间的箭头：由淡到实的箭杆 + 圆角箭头
    func drawArrow() {
        let left = layout.app.x + cellWidth / 2 + 26
        let right = layout.applications.x - cellWidth / 2 - 26
        let y = layout.app.y
        let head: CGFloat = 11

        let path = CGMutablePath()
        path.move(to: point(left, y))
        path.addLine(to: point(right, y))
        path.move(to: point(right - head, y - head))
        path.addLine(to: point(right, y))
        path.addLine(to: point(right - head, y + head))

        context.saveGState()
        context.addPath(path)
        context.setLineWidth(3)
        context.setLineCap(.round)
        context.setLineJoin(.round)
        context.replacePathWithStrokedPath()
        context.clip()
        let fade = gradient([color(1, 1, 1, 0.15), color(1, 1, 1, 0.95)], [0, 1])
        context.drawLinearGradient(fade, start: point(left, y), end: point(right, y), options: [])
        context.restoreGState()
    }

    /// 以中心点居中绘制一行文字（AppKit 负责字体回退与字距）
    func drawText(_ text: NSAttributedString, centerX: CGFloat, centerY: CGFloat) {
        let size = text.size()
        text.draw(at: NSPoint(x: centerX - size.width / 2, y: imageHeight - centerY - size.height / 2))
    }

    func drawTexts() {
        let previous = NSGraphicsContext.current
        NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
        defer { NSGraphicsContext.current = previous }

        let wordmark = NSMutableAttributedString(
            string: "Cubby",
            attributes: [.font: roundedFont(size: 22, weight: .bold), .foregroundColor: NSColor.white]
        )
        wordmark.append(
            NSAttributedString(
                string: "  小格子",
                attributes: [.font: chineseFont(size: 14, weight: "Medium"), .foregroundColor: NSColor(white: 1, alpha: 0.72)]
            )
        )
        drawText(wordmark, centerX: width / 2, centerY: 52)

        let chinese = NSAttributedString(
            string: "拖到「应用程序」即可安装",
            attributes: [.font: chineseFont(size: 14, weight: "Medium"), .foregroundColor: NSColor(white: 1, alpha: 0.96)]
        )
        drawText(chinese, centerX: width / 2, centerY: height - 58)

        let english = NSAttributedString(
            string: "Drag Cubby to Applications to install",
            attributes: [.font: NSFont.systemFont(ofSize: 12, weight: .regular), .foregroundColor: NSColor(white: 1, alpha: 0.72)]
        )
        drawText(english, centerX: width / 2, centerY: height - 36)
    }

    func drawAll() {
        drawBackdrop()
        drawCell(center: layout.app)
        drawCell(center: layout.applications)
        drawArrow()
        drawTexts()
    }
}

func roundedFont(size: CGFloat, weight: NSFont.Weight) -> NSFont {
    let base = NSFont.systemFont(ofSize: size, weight: weight)
    guard let descriptor = base.fontDescriptor.withDesign(.rounded) else { return base }
    return NSFont(descriptor: descriptor, size: size) ?? base
}

/// 中文固定用苹方（系统自带），避免不同语言环境下字体回退到日文字形
func chineseFont(size: CGFloat, weight: String) -> NSFont {
    NSFont(name: "PingFangSC-\(weight)", size: size) ?? NSFont.systemFont(ofSize: size, weight: .medium)
}

func render(layout: Layout, scale: CGFloat) -> CGImage {
    let pixelsWide = Int(layout.window.width * scale)
    let pixelsHigh = Int((layout.window.height + layout.window.bleed) * scale)
    guard let context = CGContext(
        data: nil, width: pixelsWide, height: pixelsHigh, bitsPerComponent: 8, bytesPerRow: 0,
        space: colorSpace, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
    ) else { fail("无法创建绘图上下文") }
    context.scaleBy(x: scale, y: scale)
    context.setShouldAntialias(true)
    Canvas(context: context, layout: layout).drawAll()
    guard let image = context.makeImage() else { fail("无法生成位图") }
    return image
}

// MARK: - 标签对比度自检

/// sRGB 分量 → 线性分量
func linear(_ component: CGFloat) -> CGFloat {
    component <= 0.04045 ? component / 12.92 : pow((component + 0.055) / 1.055, 2.4)
}

/// 统计标签区域的相对亮度范围（按 1x 图像素采样）
func labelLuminanceRange(_ image: CGImage, layout: Layout) -> (min: CGFloat, max: CGFloat) {
    guard let data = image.dataProvider?.data, let bytes = CFDataGetBytePtr(data) else { fail("无法读取像素") }
    let bytesPerRow = image.bytesPerRow
    var lowest: CGFloat = 1
    var highest: CGFloat = 0
    for center in [layout.app, layout.applications] {
        for y in Int(center.y + labelTop)..<Int(center.y + labelBottom) {
            for x in Int(center.x - labelHalfWidth)..<Int(center.x + labelHalfWidth) {
                let offset = y * bytesPerRow + x * 4
                let (red, green, blue) = (bytes[offset], bytes[offset + 1], bytes[offset + 2])
                let luminance = 0.2126 * linear(CGFloat(red) / 255) + 0.7152 * linear(CGFloat(green) / 255)
                    + 0.0722 * linear(CGFloat(blue) / 255)
                lowest = min(lowest, luminance)
                highest = max(highest, luminance)
            }
        }
    }
    return (lowest, highest)
}

// MARK: - 输出

func writePNG(_ image: CGImage, dpi: CGFloat, to url: URL) {
    guard let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) else {
        fail("无法写入 \(url.path)")
    }
    let properties: [CFString: Any] = [kCGImagePropertyDPIWidth: dpi, kCGImagePropertyDPIHeight: dpi]
    CGImageDestinationAddImage(destination, image, properties as CFDictionary)
    guard CGImageDestinationFinalize(destination) else { fail("PNG 编码失败：\(url.path)") }
}

let scriptURL = URL(fileURLWithPath: CommandLine.arguments[0]).standardizedFileURL
let rootURL = scriptURL.deletingLastPathComponent().deletingLastPathComponent()
let dmgURL = rootURL.appendingPathComponent("packaging/dmg")

let layout: Layout
do {
    layout = try JSONDecoder().decode(Layout.self, from: Data(contentsOf: dmgURL.appendingPathComponent("layout.json")))
} catch {
    fail("读取 layout.json 失败：\(error.localizedDescription)")
}

let standard = render(layout: layout, scale: 1)
let retina = render(layout: layout, scale: 2)

let range = labelLuminanceRange(standard, layout: layout)
let blackContrast = (range.min + 0.05) / 0.05
let whiteContrast = 1.05 / (range.max + 0.05)
print(String(format: "标签区域亮度 %.3f–%.3f：黑字对比度 ≥ %.2f，白字对比度 ≥ %.2f", range.min, range.max, blackContrast, whiteContrast))
guard blackContrast >= minContrast, whiteContrast >= minContrast else {
    fail(String(format: "标签区域对比度低于 %.1f，请调整格子或底色", minContrast))
}

writePNG(standard, dpi: 72, to: dmgURL.appendingPathComponent("background.png"))
writePNG(retina, dpi: 144, to: dmgURL.appendingPathComponent("background@2x.png"))
print("已生成 \(dmgURL.path)/background.png 与 background@2x.png")
