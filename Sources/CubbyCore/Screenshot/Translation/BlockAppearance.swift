import CoreGraphics
import Foundation

/// 从冻结帧采样得到的原文外观（§3.5）：按墨迹收紧的几何、背景色与纯色 / 复杂判定、文字色、粗细、
/// 原文字号与行位置、周围的同色空白
struct BlockAppearance: Equatable {
    /// 环带宽度（像素）
    static let ringWidth = 3
    /// 粗体判定：(笔画宽度 − 抗锯齿展宽 0.1 px) / 字号像素 超过阈值即 semibold 及以上。合成语料标定（1x / 2x、11–22 pt）：
    /// SF 常规 ≈ 0.066、medium 0.075–0.080、semibold 0.083–0.090、bold 0.098–0.103；
    /// 苹方常规 ≈ 0.060、medium 0.069–0.075、semibold 0.075–0.088、bold 0.085–0.104
    static let antialiasSpread = 0.1
    static let latinBoldRatio = 0.08
    static let ideographicBoldRatio = 0.075
    /// 文字与背景的最低对比度
    static let minimumContrast = 3.0

    /// 行框按墨迹收紧后的几何（抹除、环带采样、扩展都以它为准）
    let geometry: BlockGeometry
    let background: PixelColor
    let isSolid: Bool
    let textColor: PixelColor
    let isBold: Bool
    /// 由墨迹量出的原文字号、首行视觉中线与行距
    let source: SourceText
    /// 原文（未经对比度修正的）文字色与背景色构成的覆盖度模型
    let inkModel: InkModel
    /// 纯色背景下，原文抹除区（外框外扩 pad）左 / 右 / 下方连续的同色空白（点，从外框算起，不超过扫描范围）；
    /// 复杂背景为 0。…AtEdge：挡住空白的是控件边框 / 分隔线（可以贴得更近）而不是别的内容
    let freeLeft: CGFloat
    let freeRight: CGFloat
    let freeBelow: CGFloat
    let leftAtEdge: Bool
    let rightAtEdge: Bool
    let belowAtEdge: Bool

    /// 扫描同色空白的范围（点）
    struct Reach {
        let horizontal: CGFloat
        let below: CGFloat
    }

    /// 读取块周围的小块像素并采样；读不到像素（块在帧外）时按白底黑字处理。
    /// 两遍：先用 Vision 行框粗采背景与文字色、按墨迹收紧行框，再以收紧的行框重新采样
    static func sample(_ geometry: BlockGeometry, frame: FrozenFrame, reach: Reach, limit: CGRect?) -> BlockAppearance {
        let ring = CGFloat(ringWidth) / frame.screen.scale
        let margin = geometry.pad + ring + geometry.lineHeight * InkMetrics.searchRatio
        let region = geometry.frame.insetBy(dx: -(margin + reach.horizontal), dy: -(margin + reach.below))
        guard let patch = PixelPatch(frame: frame, region: region),
            let rough = roughModel(for: geometry, patch: patch)
        else { return fallback(geometry) }
        let roughLines = InkMetrics.lines(geometry, patch: patch, model: rough)
        let tight = geometry.tightened(to: roughLines.map { $0.map(inkFrame) })
        guard let model = model(for: tight, patch: patch) else { return fallback(geometry) }
        // 两遍的模型相同（常见：纯色背景）时第一遍量出的墨迹就是最终结果
        let lines = model == rough ? roughLines : InkMetrics.lines(tight, patch: patch, model: model)
        let source = InkMetrics.source(tight, lines: lines)
        let stroke = patch.strokeWidth(in: tight.lineFrames.compactMap(patch.box), model: model) ?? 0
        let background = model.background.pixelColor
        let free = FreeSpace(patch: patch, geometry: tight, model: model, reach: reach, limit: limit)
        return BlockAppearance(
            geometry: tight, background: background, isSolid: model.isSolid,
            textColor: model.ink.pixelColor.ensuringContrast(minimumContrast, against: background),
            isBold: isBold(
                stroke: stroke, fontSize: source.fontSize, ideographic: tight.isIdeographic, scale: frame.screen.scale),
            source: source, inkModel: model, freeLeft: free.left, freeRight: free.right, freeBelow: free.below,
            leftAtEdge: free.leftAtEdge, rightAtEdge: free.rightAtEdge, belowAtEdge: free.belowAtEdge)
    }

    static func isBold(stroke: Double, fontSize: CGFloat, ideographic: Bool, scale: CGFloat) -> Bool {
        let threshold = ideographic ? ideographicBoldRatio : latinBoldRatio
        return (stroke - antialiasSpread) / Double(fontSize * scale) > threshold
    }

    // MARK: - 内部

    /// 环带背景（外框外扩 pad 之外 3 像素）+ 行框内的文字色。外侧环带碰到了紧挨着的控件边框而不是纯色、
    /// 但抹除区内侧一圈是纯色时，仍按纯色处理：接缝只出现在填色区与未改动像素的交界，那一圈与填色一致即无接缝
    private static func model(for geometry: BlockGeometry, patch: PixelPatch) -> InkModel? {
        guard let outer = patch.box(geometry.frame.insetBy(dx: -geometry.pad, dy: -geometry.pad)),
            let ring = patch.background(around: outer, ringWidth: ringWidth)
        else { return nil }
        let band = Int((geometry.pad * patch.screen.scale).rounded(.down))
        let inner = ring.isSolid || band < 1 ? nil : patch.background(inside: outer, bandWidth: min(band, ringWidth))
        let background = inner?.isSolid == true ? inner ?? ring : ring
        let boxes = geometry.lineFrames.compactMap(patch.box)
        let ink = patch.inkColor(in: boxes, background: background.color) ?? background.color
        return InkModel(background: background.color, ink: ink, isSolid: background.isSolid)
    }

    /// 粗采：环带不是纯色时（Vision 行框比按钮还高，环带落到了按钮外面），改用行框内的主色作背景
    private static func roughModel(for geometry: BlockGeometry, patch: PixelPatch) -> InkModel? {
        guard let ring = model(for: geometry, patch: patch) else { return nil }
        let boxes = geometry.lineFrames.compactMap(patch.box)
        guard !ring.isSolid, let inside = patch.medianColor(in: boxes) else { return ring }
        let ink = patch.inkColor(in: boxes, background: inside) ?? inside
        return InkModel(background: inside, ink: ink, isSolid: true)
    }

    /// 一行墨迹的外框
    private static func inkFrame(_ ink: LineInk) -> CGRect {
        CGRect(x: ink.minX, y: ink.top, width: ink.maxX - ink.minX, height: ink.bottom - ink.top)
    }

    private static func fallback(_ geometry: BlockGeometry) -> BlockAppearance {
        let white = RGB(red: 255, green: 255, blue: 255)
        return BlockAppearance(
            geometry: geometry, background: .white, isSolid: true, textColor: .black, isBold: false,
            source: SourceText(
                fontSize: geometry.fontSize, firstCenter: geometry.visualCenter(ofLine: 0), pitch: geometry.pitch),
            inkModel: InkModel(background: white, ink: RGB(red: 0, green: 0, blue: 0), isSolid: true),
            freeLeft: 0, freeRight: 0, freeBelow: 0, leftAtEdge: false, rightAtEdge: false, belowAtEdge: false)
    }
}

/// 抹除区（外框外扩 pad）外连续的同色空白（点，含 pad）；只在纯色背景上扫描，且不越过 limit（选区）。
/// 从抹除区边缘起扫，跳过紧贴墨迹的抗锯齿边
private struct FreeSpace {
    let left: CGFloat
    let right: CGFloat
    let below: CGFloat
    let leftAtEdge: Bool
    let rightAtEdge: Bool
    let belowAtEdge: Bool

    init(patch: PixelPatch, geometry: BlockGeometry, model: InkModel, reach: BlockAppearance.Reach, limit: CGRect?) {
        guard model.isSolid, let box = patch.box(geometry.frame) else {
            (left, right, below, leftAtEdge, rightAtEdge, belowAtEdge) = (0, 0, 0, false, false, false)
            return
        }
        let scale = patch.screen.scale
        let bounds = limit.flatMap(patch.box) ?? patch.bounds
        let pad = Int((geometry.pad * scale).rounded(.up))
        let reachX = Int((reach.horizontal * scale).rounded(.up))
        let rows = box.minY..<box.maxY
        let color = model.background
        let rightRun = patch.freeColumns(
            from: box.maxX + pad, step: 1, limit: min(box.maxX + reachX, bounds.maxX), rows: rows, background: color)
        let leftRun = patch.freeColumns(
            from: box.minX - 1 - pad, step: -1, limit: max(box.minX - 1 - reachX, bounds.minX - 1), rows: rows,
            background: color)
        let start = box.maxY + pad
        let belowRun = patch.freeRows(
            from: start, limit: min(start + Int((reach.below * scale).rounded(.up)), bounds.maxY),
            columns: box.minX..<box.maxX, background: color)
        func points(_ run: PixelPatch.FreeRun) -> CGFloat { CGFloat(run.length + pad) / scale }
        (left, right, below) = (points(leftRun), points(rightRun), points(belowRun))
        (leftAtEdge, rightAtEdge, belowAtEdge) = (leftRun.endsAtEdge, rightRun.endsAtEdge, belowRun.endsAtEdge)
    }
}
