#!/usr/bin/env swift
// 生成应用图标 Resources/AppIcon.icns
//
// 用法：swift scripts/make-icon.swift
// 设计：macOS 图标网格（1024 画布内 824 圆角方形，四周留 100 安全边距）、
//       紫色渐变底板上的「小格子」储物柜：糖果色储物盒 + 从格子里抽出的卡片。
// 另输出 docs/assets/icon.png（512px）供 README 使用。
import AppKit
import CoreGraphics
import Foundation

let canvas: CGFloat = 1024
let plateInset: CGFloat = 100
let plateRadius: CGFloat = 184
let colorSpace = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()

// MARK: - 工具

func color(_ red: CGFloat, _ green: CGFloat, _ blue: CGFloat, _ alpha: CGFloat = 1) -> CGColor {
    CGColor(colorSpace: colorSpace, components: [red, green, blue, alpha]) ?? CGColor(gray: 0, alpha: alpha)
}

/// 以「距顶部」坐标描述矩形，转换为 CoreGraphics 的左下角原点坐标
func rect(x: CGFloat, top: CGFloat, width: CGFloat, height: CGFloat) -> CGRect {
    CGRect(x: x, y: canvas - top - height, width: width, height: height)
}

/// 连续曲率圆角矩形（与系统图标一致的平滑圆角，而非普通圆弧）
func continuousRoundedRect(_ rect: CGRect, radius: CGFloat) -> CGPath {
    let r = min(radius, min(rect.width, rect.height) / 2 / 1.528665)
    let (c1, c2, c3, c4) = (1.528665 * r, 1.088493 * r, 0.868407 * r, 0.631494 * r)
    let (c5, c6, c7, c8) = (0.074911 * r, 0.372824 * r, 0.169060 * r, 0.029567 * r)
    let (minX, minY, maxX, maxY) = (rect.minX, rect.minY, rect.maxX, rect.maxY)
    let path = CGMutablePath()

    path.move(to: CGPoint(x: minX + c1, y: minY))
    path.addLine(to: CGPoint(x: maxX - c1, y: minY))
    path.addCurve(to: CGPoint(x: maxX - c4, y: minY + c5), control1: CGPoint(x: maxX - c2, y: minY), control2: CGPoint(x: maxX - c3, y: minY + c8))
    path.addCurve(to: CGPoint(x: maxX - c5, y: minY + c4), control1: CGPoint(x: maxX - c6, y: minY + c7), control2: CGPoint(x: maxX - c7, y: minY + c6))
    path.addCurve(to: CGPoint(x: maxX, y: minY + c1), control1: CGPoint(x: maxX - c8, y: minY + c3), control2: CGPoint(x: maxX, y: minY + c2))

    path.addLine(to: CGPoint(x: maxX, y: maxY - c1))
    path.addCurve(to: CGPoint(x: maxX - c5, y: maxY - c4), control1: CGPoint(x: maxX, y: maxY - c2), control2: CGPoint(x: maxX - c8, y: maxY - c3))
    path.addCurve(to: CGPoint(x: maxX - c4, y: maxY - c5), control1: CGPoint(x: maxX - c7, y: maxY - c6), control2: CGPoint(x: maxX - c6, y: maxY - c7))
    path.addCurve(to: CGPoint(x: maxX - c1, y: maxY), control1: CGPoint(x: maxX - c3, y: maxY - c8), control2: CGPoint(x: maxX - c2, y: maxY))

    path.addLine(to: CGPoint(x: minX + c1, y: maxY))
    path.addCurve(to: CGPoint(x: minX + c4, y: maxY - c5), control1: CGPoint(x: minX + c2, y: maxY), control2: CGPoint(x: minX + c3, y: maxY - c8))
    path.addCurve(to: CGPoint(x: minX + c5, y: maxY - c4), control1: CGPoint(x: minX + c6, y: maxY - c7), control2: CGPoint(x: minX + c7, y: maxY - c6))
    path.addCurve(to: CGPoint(x: minX, y: maxY - c1), control1: CGPoint(x: minX + c8, y: maxY - c3), control2: CGPoint(x: minX, y: maxY - c2))

    path.addLine(to: CGPoint(x: minX, y: minY + c1))
    path.addCurve(to: CGPoint(x: minX + c5, y: minY + c4), control1: CGPoint(x: minX, y: minY + c2), control2: CGPoint(x: minX + c8, y: minY + c3))
    path.addCurve(to: CGPoint(x: minX + c4, y: minY + c5), control1: CGPoint(x: minX + c7, y: minY + c6), control2: CGPoint(x: minX + c6, y: minY + c7))
    path.addCurve(to: CGPoint(x: minX + c1, y: minY), control1: CGPoint(x: minX + c3, y: minY + c8), control2: CGPoint(x: minX + c2, y: minY))
    path.closeSubpath()
    return path
}

func fill(_ context: CGContext, _ path: CGPath, _ fillColor: CGColor) {
    context.addPath(path)
    context.setFillColor(fillColor)
    context.fillPath()
}

func linearGradient(_ colors: [CGColor], locations: [CGFloat]) -> CGGradient? {
    CGGradient(colorsSpace: colorSpace, colors: colors as CFArray, locations: locations)
}

// MARK: - 绘制

/// 储物柜网格：3 列 × 2 行，右上角的格子弹出一张卡片
let gridX: CGFloat = 196, gridTop: CGFloat = 392, gridWidth: CGFloat = 632, gridHeight: CGFloat = 404
let gridGap: CGFloat = 24, columns = 3, rows = 2
let cellWidth = (gridWidth - gridGap * CGFloat(columns - 1)) / CGFloat(columns)
let cellHeight = (gridHeight - gridGap * CGFloat(rows - 1)) / CGFloat(rows)
/// 糖果色储物盒（按行优先排列，弹出卡片的格子跳过）
let binColors: [CGColor] = [
    color(1.00, 0.42, 0.42), color(1.00, 0.79, 0.24),
    color(0.30, 0.76, 1.00), color(1.00, 0.56, 0.72), color(1.00, 0.64, 0.30),
]
let poppedCell = (column: 2, row: 0)

func cellRect(column: Int, row: Int) -> CGRect {
    rect(
        x: gridX + CGFloat(column) * (cellWidth + gridGap),
        top: gridTop + CGFloat(row) * (cellHeight + gridGap),
        width: cellWidth,
        height: cellHeight
    )
}

func roundedRect(_ rect: CGRect, _ radius: CGFloat) -> CGPath {
    CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil)
}

func drawPlate(in context: CGContext) {
    let plateRect = CGRect(x: plateInset, y: plateInset, width: canvas - plateInset * 2, height: canvas - plateInset * 2)
    let plate = continuousRoundedRect(plateRect, radius: plateRadius)

    context.saveGState()
    context.addPath(plate)
    context.clip()
    // 紫（左上）→ 深靛（右下）
    if let gradient = linearGradient([color(0.48, 0.38, 1.00), color(0.23, 0.11, 0.62)], locations: [0, 1]) {
        context.drawLinearGradient(
            gradient,
            start: CGPoint(x: plateRect.minX, y: plateRect.maxY),
            end: CGPoint(x: plateRect.maxX, y: plateRect.minY),
            options: []
        )
    }
    // 顶部柔光，增加层次
    if let sheen = linearGradient([color(1, 1, 1, 0.18), color(1, 1, 1, 0)], locations: [0, 1]) {
        context.drawLinearGradient(sheen, start: CGPoint(x: 0, y: plateRect.maxY), end: CGPoint(x: 0, y: plateRect.midY), options: [])
    }
    context.restoreGState()
}

func drawCabinet(in context: CGContext) {
    // 半透明柜体
    let frame = CGRect(x: gridX - 30, y: canvas - gridTop - gridHeight - 30, width: gridWidth + 60, height: gridHeight + 60)
    context.saveGState()
    context.setShadow(offset: CGSize(width: 0, height: -16), blur: 36, color: color(0, 0, 0, 0.28))
    fill(context, roundedRect(frame, 64), color(1, 1, 1, 0.14))
    context.restoreGState()

    var binIndex = 0
    for row in 0..<rows {
        for column in 0..<columns {
            let hole = cellRect(column: column, row: row)
            fillVertical(context, roundedRect(hole, 34), top: color(0.12, 0.06, 0.38), bottom: color(0.12, 0.06, 0.38, 0.75), in: hole)
            guard (column, row) != poppedCell else { continue }
            drawBin(in: context, hole: hole, fillColor: binColors[binIndex % binColors.count])
            binIndex += 1
        }
    }
}

/// 储物盒：从格子底部露出，顶部浅色边沿 + 把手槽
func drawBin(in context: CGContext, hole: CGRect, fillColor: CGColor) {
    let bin = CGRect(x: hole.minX + 14, y: hole.minY + 14, width: hole.width - 28, height: hole.height * 0.74)
    let binPath = roundedRect(bin, 30)
    context.saveGState()
    context.setShadow(offset: CGSize(width: 0, height: -6), blur: 14, color: color(0, 0, 0, 0.25))
    fill(context, binPath, fillColor)
    context.restoreGState()

    context.saveGState()
    context.addPath(binPath)
    context.clip()
    fill(context, CGPath(rect: CGRect(x: bin.minX, y: bin.maxY - 30, width: bin.width, height: 30), transform: nil), color(1, 1, 1, 0.28))
    context.restoreGState()

    fill(context, roundedRect(CGRect(x: bin.midX - 34, y: bin.maxY - 76, width: 68, height: 22), 11), color(0, 0, 0, 0.22))
}

/// 从格子里抽出的卡片：下半截被格子前沿遮住
func drawCard(in context: CGContext) {
    let hole = cellRect(column: poppedCell.column, row: poppedCell.row)
    let frontEdge = hole.minY + hole.height * 0.55

    context.saveGState()
    let visible = CGMutablePath()
    visible.addRect(CGRect(x: 0, y: 0, width: canvas, height: canvas))
    visible.addRect(CGRect(x: hole.minX - 40, y: hole.minY - 40, width: hole.width + 80, height: frontEdge - hole.minY + 40))
    context.addPath(visible)
    context.clip(using: .evenOdd)

    context.translateBy(x: hole.midX, y: frontEdge + 96)
    context.rotate(by: -0.10)
    let card = CGRect(x: -92, y: -150, width: 184, height: 250)
    context.setShadow(offset: CGSize(width: 0, height: -12), blur: 26, color: color(0, 0, 0, 0.35))
    fill(context, roundedRect(card, 30), color(1, 1, 1))
    context.setShadow(offset: .zero, blur: 0, color: nil)
    // 卡片上的「文字行」
    fill(context, roundedRect(CGRect(x: card.minX + 28, y: card.maxY - 62, width: 92, height: 26), 13), binColors[0])
    for (index, width) in [128.0, 128.0, 84.0].enumerated() {
        let line = CGRect(x: card.minX + 28, y: card.maxY - 108 - CGFloat(index) * 38, width: width, height: 20)
        fill(context, roundedRect(line, 10), color(0.85, 0.86, 0.91))
    }
    context.restoreGState()

    // 格子前沿高光，强化「插在格子里」的层次
    let lip = CGRect(x: hole.minX + 10, y: frontEdge - 3, width: hole.width - 20, height: 6)
    fill(context, roundedRect(lip, 3), color(1, 1, 1, 0.22))
}

func fillVertical(_ context: CGContext, _ path: CGPath, top: CGColor, bottom: CGColor, in rect: CGRect) {
    context.saveGState()
    context.addPath(path)
    context.clip()
    if let gradient = linearGradient([top, bottom], locations: [0, 1]) {
        context.drawLinearGradient(gradient, start: CGPoint(x: 0, y: rect.maxY), end: CGPoint(x: 0, y: rect.minY), options: [])
    }
    context.restoreGState()
}

func renderMaster() -> CGImage? {
    let size = Int(canvas)
    guard let context = CGContext(
        data: nil,
        width: size,
        height: size,
        bitsPerComponent: 8,
        bytesPerRow: 0,
        space: colorSpace,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ) else { return nil }
    context.setShouldAntialias(true)
    drawPlate(in: context)
    drawCabinet(in: context)
    drawCard(in: context)
    return context.makeImage()
}

func resized(_ image: CGImage, to pixels: Int) -> CGImage? {
    guard let context = CGContext(
        data: nil,
        width: pixels,
        height: pixels,
        bitsPerComponent: 8,
        bytesPerRow: 0,
        space: colorSpace,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ) else { return nil }
    context.interpolationQuality = .high
    context.draw(image, in: CGRect(x: 0, y: 0, width: pixels, height: pixels))
    return context.makeImage()
}

func writePNG(_ image: CGImage, to url: URL) throws {
    let rep = NSBitmapImageRep(cgImage: image)
    guard let data = rep.representation(using: .png, properties: [:]) else {
        throw NSError(domain: "make-icon", code: 1, userInfo: [NSLocalizedDescriptionKey: "PNG 编码失败"])
    }
    try data.write(to: url)
}

// MARK: - 输出

let scriptURL = URL(fileURLWithPath: CommandLine.arguments[0]).standardizedFileURL
let rootURL = scriptURL.deletingLastPathComponent().deletingLastPathComponent()
let outputURL = rootURL.appendingPathComponent("Resources/AppIcon.icns")
let iconsetURL = FileManager.default.temporaryDirectory.appendingPathComponent("AppIcon-\(UUID().uuidString).iconset")

/// iconutil 要求的文件名与像素尺寸
let variants: [(name: String, pixels: Int)] = [
    ("icon_16x16", 16), ("icon_16x16@2x", 32),
    ("icon_32x32", 32), ("icon_32x32@2x", 64),
    ("icon_128x128", 128), ("icon_128x128@2x", 256),
    ("icon_256x256", 256), ("icon_256x256@2x", 512),
    ("icon_512x512", 512), ("icon_512x512@2x", 1024),
]

do {
    guard let master = renderMaster() else {
        throw NSError(domain: "make-icon", code: 2, userInfo: [NSLocalizedDescriptionKey: "无法创建绘图上下文"])
    }
    try FileManager.default.createDirectory(at: iconsetURL, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: iconsetURL) }

    for variant in variants {
        let image = variant.pixels == Int(canvas) ? master : resized(master, to: variant.pixels)
        guard let image else {
            throw NSError(domain: "make-icon", code: 3, userInfo: [NSLocalizedDescriptionKey: "缩放 \(variant.pixels)px 失败"])
        }
        try writePNG(image, to: iconsetURL.appendingPathComponent("\(variant.name).png"))
    }

    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
    process.arguments = ["-c", "icns", "-o", outputURL.path, iconsetURL.path]
    try process.run()
    process.waitUntilExit()
    guard process.terminationStatus == 0 else {
        throw NSError(domain: "make-icon", code: 4, userInfo: [NSLocalizedDescriptionKey: "iconutil 退出码 \(process.terminationStatus)"])
    }
    let previewURL = rootURL.appendingPathComponent("docs/assets/icon.png")
    try FileManager.default.createDirectory(at: previewURL.deletingLastPathComponent(), withIntermediateDirectories: true)
    if let preview = resized(master, to: 512) {
        try writePNG(preview, to: previewURL)
    }
    print("已生成 \(outputURL.path)")
} catch {
    FileHandle.standardError.write(Data("生成图标失败：\(error.localizedDescription)\n".utf8))
    exit(1)
}
