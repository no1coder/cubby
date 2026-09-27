import CoreGraphics
import Foundation

/// 原文的字号、首行视觉中线（全局 y）与行距（点）
struct SourceText: Equatable {
    let fontSize: CGFloat
    let firstCenter: CGFloat
    let pitch: CGFloat
}

/// 从墨迹量出的一行文字的位置（全局点）
struct LineInk: Equatable {
    /// 墨迹外沿（含很淡的抗锯齿），用于收紧行框
    let minX: CGFloat
    let maxX: CGFloat
    let top: CGFloat
    let bottom: CGFloat
    /// 主体墨迹（覆盖度 ≥ 峰值 4% 的行），用于估字号与视觉中线
    let bodyTop: CGFloat
    let bodyBottom: CGFloat
    let baseline: CGFloat
}

/// 由墨迹估计行的真实范围、原文字号与各行视觉中线。
/// Vision 文档识别的行框高波动很大（无下伸字母的标签只有字号的 0.8–0.9，按钮里的行框可达 1.8 倍），
/// 行框只用来定位，范围与字号以墨迹为准，行框只作兜底
enum InkMetrics {
    /// 拉丁文字：基线到主体墨迹顶 / 字号（含大写、数字或上伸字母时取大写高附近，否则取 x 高）
    static let latinCapRatio: CGFloat = 0.72
    static let latinXHeightRatio: CGFloat = 0.53
    /// CJK：主体墨迹高 / 字号（汉字；以假名为主时更矮）
    static let ideographicInkRatio: CGFloat = 0.86
    static let kanaInkRatio: CGFloat = 0.80
    /// 主体墨迹行 / 墨迹外沿行：该行覆盖度 ≥ 峰值的这一比例
    static let bodyThreshold = 0.04
    static let edgeThreshold = 0.005
    /// 量行范围时忽略的弱覆盖（很淡的起伏在长行上累加起来会像一行墨迹）
    static let gridFloor = 0.25
    /// 几乎贯通整列（≥ 85% 的行）的竖边是控件边框，不是文字
    static let ruleFraction = 0.85
    /// 在行框上下各外扩行框高的 30% 找墨迹；墨迹行之间允许的空隙（i 的点、重音）≤ 行框高的 15%
    static let searchRatio: CGFloat = 0.3
    static let gapRatio: CGFloat = 0.15

    /// 量一行：以行框中线所在的连续墨迹为准（不会并入上下相邻的文字、控件边框与分隔线）；limits 为允许的行范围
    static func measure(_ box: PixelBox, within limits: ClosedRange<Int>, patch: PixelPatch, model: InkModel)
        -> LineInk?
    {
        let extra = Int((CGFloat(box.height) * searchRatio).rounded())
        let window = PixelBox(
            minX: max(box.minX - 2 * extra, patch.bounds.minX),
            minY: max(box.minY - extra, limits.lowerBound, patch.bounds.minY),
            maxX: min(box.maxX + 2 * extra, patch.bounds.maxX),
            maxY: min(box.maxY + extra, limits.upperBound, patch.bounds.maxY))
        guard !window.isEmpty else { return nil }
        // 窗口被相邻行截断的上 / 下边不做连通剔除（那里可能正好是本行的下伸 / 上伸字母）
        let grid = CoverageGrid(
            window, patch: patch, model: model,
            openEdges: (top: window.minY > limits.lowerBound, bottom: window.maxY < limits.upperBound))
        let gap = max(1, Int((CGFloat(box.height) * gapRatio).rounded()))
        let rows = grid.rowSums(columns: (box.minX - window.minX)..<(box.maxX - window.minX))
        guard let run = inkRun(rows, around: (box.minY + box.maxY) / 2 - window.minY, maxGap: gap),
            let peak = rows[run].max(),
            let bodyFirst = run.first(where: { rows[$0] >= peak * bodyThreshold }),
            let bodyLast = run.last(where: { rows[$0] >= peak * bodyThreshold })
        else { return nil }
        let columns = grid.columnSums(rows: run)
        let seed = (box.minX - window.minX)..<(box.maxX - window.minX)
        guard let span = inkSpan(columns, seed: seed, maxGap: gap) else { return nil }
        return LineInk(
            minX: patch.globalX(window.minX + span.lowerBound), maxX: patch.globalX(window.minX + span.upperBound + 1),
            top: patch.globalY(window.minY + run.lowerBound), bottom: patch.globalY(window.minY + run.upperBound + 1),
            bodyTop: patch.globalY(window.minY + bodyFirst), bodyBottom: patch.globalY(window.minY + bodyLast + 1),
            baseline: patch.globalY(window.minY + baselineRow(rows, first: bodyFirst, last: bodyLast)))
    }

    /// 字号估计：拉丁文字按基线到主体墨迹顶，CJK 按主体墨迹高
    static func fontSize(_ ink: LineInk, text: String, ideographic: Bool) -> CGFloat {
        if ideographic {
            let kana = text.unicodeScalars.filter(TextScript.isKana).count
            let ratio = kana * 2 > text.unicodeScalars.count ? kanaInkRatio : ideographicInkRatio
            return (ink.bodyBottom - ink.bodyTop) / ratio
        }
        let tall = text.contains { $0.isUppercase || $0.isNumber || "bdfhklt".contains($0) }
        return (ink.baseline - ink.bodyTop) / (tall ? latinCapRatio : latinXHeightRatio)
    }

    /// 视觉中线：拉丁文字取主体墨迹顶与基线的中点，CJK 取主体墨迹上下的中点
    static func visualCenter(_ ink: LineInk, ideographic: Bool) -> CGFloat {
        ideographic ? (ink.bodyTop + ink.bodyBottom) / 2 : (ink.bodyTop + ink.baseline) / 2
    }

    /// 各行的墨迹（与 geometry.lineFrames 一一对应，量不到为 nil）；相邻行之间以行框间隙的中点为界
    static func lines(_ geometry: BlockGeometry, patch: PixelPatch, model: InkModel) -> [LineInk?] {
        let boxes = geometry.lineFrames.map { patch.box($0) }
        return boxes.indices.map { index in
            guard let box = boxes[index] else { return nil }
            let above = index > 0 ? boxes[index - 1].map { ($0.maxY + box.minY) / 2 } : nil
            let below = index + 1 < boxes.count ? boxes[index + 1].map { (box.maxY + $0.minY) / 2 } : nil
            let limits = (above ?? Int.min / 2)...(below ?? Int.max / 2)
            return measure(box, within: limits, patch: patch, model: model)
        }
    }

    /// 整块：字号取各行估计的中位数（0.5 pt 取整），首行视觉中线，行距取相邻行视觉中线间距的中位数；
    /// 量不到墨迹的行不参与，全都量不到时用行框推算的值
    static func source(_ geometry: BlockGeometry, lines: [LineInk?]) -> SourceText {
        let measured = zip(lines, geometry.lineTexts).map { line, text -> (center: CGFloat, size: CGFloat)? in
            guard let line else { return nil }
            let ideographic = TextScript.isMostlyIdeographic(text)
            return (visualCenter(line, ideographic: ideographic), fontSize(line, text: text, ideographic: ideographic))
        }
        let sizes = measured.compactMap { $0?.size }.filter { $0 > 0 }
        let gaps = zip(measured.dropFirst(), measured).compactMap { next, previous in
            next.flatMap { next in previous.map { next.center - $0.center } }
        }
        return SourceText(
            fontSize: sizes.isEmpty ? geometry.fontSize : max(1, (TranslationMath.median(sizes) * 2).rounded() / 2),
            firstCenter: measured.first.flatMap { $0?.center } ?? geometry.visualCenter(ofLine: 0),
            pitch: gaps.isEmpty ? geometry.pitch : TranslationMath.median(gaps))
    }

    // MARK: - 内部

    /// 从 center 附近的墨迹行出发，向上下扩展（容忍 ≤ maxGap 行的空隙），得到这一行文字的连续墨迹
    private static func inkRun(_ rows: [Double], around center: Int, maxGap: Int) -> ClosedRange<Int>? {
        guard let peak = rows.max(), peak > 0 else { return nil }
        let isInk = rows.map { $0 >= peak * edgeThreshold }
        let clamped = min(max(center, 0), rows.count - 1)
        guard let seed = rows.indices.filter({ isInk[$0] }).min(by: { abs($0 - clamped) < abs($1 - clamped) })
        else { return nil }
        return extend(seed...seed, isInk: isInk, maxGap: maxGap)
    }

    /// 行框内有墨迹的列，再向左右各自并入相隔 ≤ maxGap 的墨迹列（行框切掉的半个字形），但不跨过更宽的空隙（列表符号）
    private static func inkSpan(_ columns: [Double], seed: Range<Int>, maxGap: Int) -> ClosedRange<Int>? {
        let isInk = columns.map { $0 >= 0.5 }
        let inside = seed.clamped(to: 0..<columns.count).filter { isInk[$0] }
        guard let first = inside.first, let last = inside.last else { return nil }
        return extend(first...last, isInk: isInk, maxGap: maxGap)
    }

    /// 把 range 向两侧扩到相隔不超过 maxGap 的墨迹
    private static func extend(_ range: ClosedRange<Int>, isInk: [Bool], maxGap: Int) -> ClosedRange<Int> {
        func edge(_ start: Int, _ step: Int) -> Int {
            var edge = start
            var probe = start + step
            while probe >= 0, probe < isInk.count, abs(probe - edge) <= maxGap + 1 {
                if isInk[probe] { edge = probe }
                probe += step
            }
            return edge
        }
        return edge(range.lowerBound, -1)...edge(range.upperBound, 1)
    }

    /// 基线：主体墨迹下半部分里覆盖度下降最多的行界（下伸字母只贡献很少的墨迹）；返回基线下方第一行的下标
    private static func baselineRow(_ rows: [Double], first: Int, last: Int) -> Int {
        let start = (first + last) / 2
        guard start < last else { return last + 1 }
        var best = last + 1
        var bestDrop = rows[last]
        for row in start..<last where rows[row] - rows[row + 1] > bestDrop {
            bestDrop = rows[row] - rows[row + 1]
            best = row + 1
        }
        return best
    }
}

/// 一小块窗口内逐像素的墨迹覆盖度。不算墨迹的：与窗口边界连通的墨迹（窗口外的区域、相邻行、控件边框、
/// 分隔线——本行文字不会碰到窗口边界），以及没碰到边界但几乎贯通整列的竖边
private struct CoverageGrid {
    let width: Int
    let height: Int
    private let values: [Double]

    init(_ window: PixelBox, patch: PixelPatch, model: InkModel, openEdges: (top: Bool, bottom: Bool)) {
        let width = window.width
        let height = window.height
        var values = [Double](repeating: 0, count: width * height)
        for y in 0..<height {
            for x in 0..<width {
                let value = model.coverage(patch.color(x: window.minX + x, y: window.minY + y))
                values[y * width + x] = value >= InkMetrics.gridFloor ? value : 0
            }
        }
        Self.clearBorderComponents(&values, width: width, height: height, openEdges: openEdges)
        let limit = InkMetrics.ruleFraction
        for x in 0..<width {
            var strong = 0
            for y in 0..<height where values[y * width + x] >= 0.5 { strong += 1 }
            guard Double(strong) >= Double(height) * limit else { continue }
            for y in 0..<height { values[y * width + x] = 0 }
        }
        self.width = width
        self.height = height
        self.values = values
    }

    /// 从窗口边界出发，把与之 4 连通的墨迹像素清零
    private static func clearBorderComponents(
        _ values: inout [Double], width: Int, height: Int, openEdges: (top: Bool, bottom: Bool)
    ) {
        var seeds = (0..<height).flatMap { [$0 * width, $0 * width + width - 1] }
        if openEdges.top { seeds += (0..<width).map { $0 } }
        if openEdges.bottom { seeds += (0..<width).map { (height - 1) * width + $0 } }
        var stack = seeds.filter { values[$0] > 0 }
        while let index = stack.popLast() {
            guard values[index] > 0 else { continue }
            values[index] = 0
            let x = index % width
            let y = index / width
            if x > 0 { stack.append(index - 1) }
            if x + 1 < width { stack.append(index + 1) }
            if y > 0 { stack.append(index - width) }
            if y + 1 < height { stack.append(index + width) }
        }
    }

    /// 每行在 columns 列范围内的覆盖度之和
    func rowSums(columns: Range<Int>) -> [Double] {
        let clamped = columns.clamped(to: 0..<width)
        return (0..<height).map { y in clamped.reduce(0) { $0 + values[y * width + $1] } }
    }

    /// 每列在 rows 行范围内的覆盖度之和
    func columnSums(rows: ClosedRange<Int>) -> [Double] {
        (0..<width).map { x in rows.reduce(0) { $0 + values[$1 * width + x] } }
    }
}
