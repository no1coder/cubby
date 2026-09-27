import CoreGraphics
import Foundation

/// 背景采样结果
struct BackgroundSample: Equatable {
    /// 环带像素的逐通道中位数
    let color: RGB
    /// 环带内与 color 足够接近的像素占比 ≥ 阈值
    let isSolid: Bool
}

extension PixelPatch {
    /// 「同色」的 RGB 欧氏距离上限（0…255 口径，§3.5：12/255）
    static let sameColorTolerance = 12
    /// 纯色判定：环带内同色像素占比下限
    static let solidFraction = 0.9
    /// 文字色：取与背景距离不小于「第 99 百分位距离 × 此比例」的像素
    static let inkDistanceRatio = 0.9

    /// 外框 box 外侧 width 像素宽的环带：逐通道中位数 = 背景色；同色占比 ≥ 90% → 纯色（§3.5）
    func background(around box: PixelBox, ringWidth: Int) -> BackgroundSample? {
        backgroundSample(in: box.insetBy(-ringWidth), excluding: box)
    }

    /// 外框 box 内侧 width 像素宽的环带（即将被填色替换、紧挨着未改动像素的那一圈）
    func background(inside box: PixelBox, bandWidth: Int) -> BackgroundSample? {
        backgroundSample(in: box, excluding: box.insetBy(bandWidth))
    }

    private func backgroundSample(in region: PixelBox, excluding hole: PixelBox) -> BackgroundSample? {
        var histograms = ChannelHistograms()
        var colors: [RGB] = []
        for y in max(region.minY, bounds.minY)..<min(region.maxY, bounds.maxY) {
            for x in max(region.minX, bounds.minX)..<min(region.maxX, bounds.maxX) where !hole.contains(x: x, y: y) {
                let pixel = color(x: x, y: y)
                histograms.add(pixel)
                colors.append(pixel)
            }
        }
        guard let median = histograms.median() else { return nil }
        let limit = Self.sameColorTolerance * Self.sameColorTolerance
        let same = colors.filter { $0.distanceSquared(to: median) < limit }.count
        return BackgroundSample(color: median, isSolid: Double(same) >= Double(colors.count) * Self.solidFraction)
    }

    /// 文字色：boxes 内离背景最远的像素（距离 ≥ 0.9 × 第 99 百分位距离）的逐通道中位数；没有像素时为 nil。
    /// 标定：§3.5 的「最远 25%」在 ≤ 13 pt 时混入大量抗锯齿半覆盖像素，黑字会被估成 #2C2C2C～#525252
    func inkColor(in boxes: [PixelBox], background: RGB) -> RGB? {
        // 距离（0…441）直方图求第 99 百分位，避免对全部像素排序
        var counts = [Int](repeating: 0, count: 442)
        var total = 0
        forEachPixel(in: boxes) { _, _, color in
            counts[Self.distance(color, background)] += 1
            total += 1
        }
        guard total > 0 else { return nil }
        var reference = 0
        var seen = 0
        for distance in stride(from: counts.count - 1, through: 0, by: -1) {
            seen += counts[distance]
            if seen > total / 100 {
                reference = distance
                break
            }
        }
        let threshold = Int((Double(reference) * Self.inkDistanceRatio).rounded(.up))
        var histograms = ChannelHistograms()
        forEachPixel(in: boxes) { _, _, color in
            if Self.distance(color, background) >= threshold { histograms.add(color) }
        }
        return histograms.median()
    }

    /// 欧氏距离取整（0…441）
    private static func distance(_ color: RGB, _ background: RGB) -> Int {
        Int(Double(color.distanceSquared(to: background)).squareRoot())
    }

    /// 笔画宽度（像素）≈ 2 × 墨迹面积 / 墨迹轮廓长度；没有墨迹时为 nil
    func strokeWidth(in boxes: [PixelBox], model: InkModel) -> Double? {
        var area = 0.0
        var edges = 0
        for box in boxes {
            var previousRow = [Bool](repeating: false, count: box.width)
            for y in box.minY..<box.maxY {
                var previous = false
                for x in box.minX..<box.maxX {
                    let value = model.coverage(color(x: x, y: y))
                    let isInk = value >= 0.5
                    area += value
                    edges += (isInk != previous ? 1 : 0) + (isInk != previousRow[x - box.minX] ? 1 : 0)
                    previous = isInk
                    previousRow[x - box.minX] = isInk
                }
                edges += previous ? 1 : 0
            }
            edges += previousRow.filter { $0 }.count
        }
        return edges > 0 ? 2 * area / Double(edges) : nil
    }

    /// 连续同色空白的长度（像素），以及挡住它的是不是一条贯通的边（控件边框、分隔线：该列 / 行 ≥ 80% 的像素不同色；
    /// 扫到范围尽头——选区边缘或扫描上限——也算，那里是容器的边界）
    struct FreeRun: Equatable {
        let length: Int
        let endsAtEdge: Bool
    }

    /// 贯通边：挡住空白的那一列 / 行中不同色像素的最低占比
    static let edgeFraction = 0.8

    /// 从 start 起沿 step（±1）逐列检查 rows 行范围是否都与背景同色（遇到 limit 或块边界停止）
    func freeColumns(from start: Int, step: Int, limit: Int, rows: Range<Int>, background: RGB) -> FreeRun {
        var x = start
        while x != limit, x >= bounds.minX, x < bounds.maxX, rows.allSatisfy({ isSame(color(x: x, y: $0), background) })
        {
            x += step
        }
        let blocked = x != limit && x >= bounds.minX && x < bounds.maxX
        let edge =
            !blocked || fraction(of: rows.map { color(x: x, y: $0) }, differingFrom: background) >= Self.edgeFraction
        return FreeRun(length: abs(x - start), endsAtEdge: edge)
    }

    /// 从 start 起向下逐行检查 columns 列范围是否都与背景同色
    func freeRows(from start: Int, limit: Int, columns: Range<Int>, background: RGB) -> FreeRun {
        var y = start
        while y < limit, y >= bounds.minY, y < bounds.maxY,
            columns.allSatisfy({ isSame(color(x: $0, y: y), background) })
        {
            y += 1
        }
        let blocked = y < limit && y < bounds.maxY
        let edge =
            !blocked || fraction(of: columns.map { color(x: $0, y: y) }, differingFrom: background) >= Self.edgeFraction
        return FreeRun(length: y - start, endsAtEdge: edge)
    }

    /// boxes 内像素的逐通道中位数（行框里多数像素是背景）
    func medianColor(in boxes: [PixelBox]) -> RGB? {
        var histograms = ChannelHistograms()
        forEachPixel(in: boxes) { _, _, color in histograms.add(color) }
        return histograms.median()
    }

    private func fraction(of colors: [RGB], differingFrom background: RGB) -> Double {
        guard !colors.isEmpty else { return 0 }
        return Double(colors.filter { !isSame($0, background) }.count) / Double(colors.count)
    }

    private func isSame(_ color: RGB, _ background: RGB) -> Bool {
        color.distanceSquared(to: background) < Self.sameColorTolerance * Self.sameColorTolerance
    }
}

/// 墨迹覆盖度模型：像素在「背景 → 文字色」连线上的投影（0…1）。抗锯齿的文字像素都落在这条线上；
/// 离线太远的像素（控件边框外的别的颜色、照片噪点）不是这段文字的墨迹，记 0；复杂背景上低于 floor 的起伏也记 0
struct InkModel: Equatable {
    /// 复杂背景的覆盖度下限
    static let complexFloor = 0.3
    /// 离「背景 → 文字色」连线的最大距离（0…255 口径）
    static let lineTolerance = 16

    let background: RGB
    let ink: RGB
    /// 背景是否纯色（决定抹除方式与覆盖度下限）
    let isSolid: Bool
    let floor: Double
    /// 预先算好的「背景 → 文字色」向量与其长度的平方
    private let delta: (red: Int, green: Int, blue: Int)
    private let span: Double

    init(background: RGB, ink: RGB, isSolid: Bool) {
        self.background = background
        self.ink = ink
        self.isSolid = isSolid
        self.floor = isSolid ? 0 : Self.complexFloor
        self.delta = (ink.red - background.red, ink.green - background.green, ink.blue - background.blue)
        self.span = Double(ink.distanceSquared(to: background))
    }

    static func == (lhs: InkModel, rhs: InkModel) -> Bool {
        lhs.background == rhs.background && lhs.ink == rhs.ink && lhs.isSolid == rhs.isSolid
    }

    func coverage(_ color: RGB) -> Double {
        guard span > 0 else { return 0 }
        let red = color.red - background.red
        let green = color.green - background.green
        let blue = color.blue - background.blue
        let projection = Double(red * delta.red + green * delta.green + blue * delta.blue) / span
        let offLine = Double(red * red + green * green + blue * blue) - projection * projection * span
        guard offLine <= Double(Self.lineTolerance * Self.lineTolerance) else { return 0 }
        let value = min(max(projection, 0), 1)
        return value >= floor ? value : 0
    }
}

/// 逐通道 256 桶直方图，用于求中位数
struct ChannelHistograms {
    private var red = [Int](repeating: 0, count: 256)
    private var green = [Int](repeating: 0, count: 256)
    private var blue = [Int](repeating: 0, count: 256)
    private var count = 0

    mutating func add(_ color: RGB) {
        red[color.red] += 1
        green[color.green] += 1
        blue[color.blue] += 1
        count += 1
    }

    /// 逐通道中位数（下中位）；为空时 nil
    func median() -> RGB? {
        guard count > 0 else { return nil }
        return RGB(red: Self.median(red, count), green: Self.median(green, count), blue: Self.median(blue, count))
    }

    private static func median(_ histogram: [Int], _ count: Int) -> Int {
        let target = (count + 1) / 2
        var seen = 0
        return histogram.firstIndex { frequency in
            seen += frequency
            return seen >= target
        } ?? histogram.count - 1
    }
}
