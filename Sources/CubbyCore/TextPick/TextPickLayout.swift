import CoreGraphics
import Foundation

/// 词块的流式排版（docs/TEXT-PICK-DESIGN.md §3）：给定每块的尺寸、换行数与容器宽度，从左到右排，放不下换行；
/// 换行另起一行，两个及以上换行（空行）多留段距；比一行还宽的块收窄到行宽（绘制时截断）。
/// 坐标以内容区左上角为原点、y 向下；每行按最高的块计行高，其余块垂直居中。
/// 命中与重绘范围先按行二分查找，上万块也只看一两行
public struct TextPickLayout: Equatable, Sendable {
    public struct Metrics: Equatable, Sendable {
        /// 同一行两块之间的横距
        public let itemSpacing: CGFloat
        /// 行与行之间的行距
        public let lineSpacing: CGFloat
        /// 空行（段落）额外多留的距离
        public let paragraphSpacing: CGFloat

        public init(itemSpacing: CGFloat, lineSpacing: CGFloat, paragraphSpacing: CGFloat) {
            self.itemSpacing = itemSpacing
            self.lineSpacing = lineSpacing
            self.paragraphSpacing = paragraphSpacing
        }
    }

    /// 一行：其中的块（序号范围）与纵向范围
    public struct Row: Equatable, Sendable {
        public let tokens: Range<Int>
        public let minY: CGFloat
        public let maxY: CGFloat

        public init(tokens: Range<Int>, minY: CGFloat, maxY: CGFloat) {
            self.tokens = tokens
            self.minY = minY
            self.maxY = maxY
        }
    }

    public let frames: [CGRect]
    public let rows: [Row]
    /// 内容总高度（最后一行的底边）
    public let height: CGFloat

    public init(frames: [CGRect], rows: [Row], height: CGFloat) {
        self.frames = frames
        self.rows = rows
        self.height = height
    }

    /// - Parameters:
    ///   - sizes: 每块的尺寸（宽度超过容器时收窄到容器宽）
    ///   - lineBreaks: 每块之前的换行数（缺少的按 0；首块前的换行不留空）
    ///   - width: 容器宽度（不为正时按 1）
    public static func make(sizes: [CGSize], lineBreaks: [Int], width: CGFloat, metrics: Metrics) -> TextPickLayout {
        let lineWidth = max(width, 1)
        var builder = RowBuilder(metrics: metrics)
        for (index, size) in sizes.enumerated() {
            let breaks = index < lineBreaks.count ? lineBreaks[index] : 0
            let clamped = CGSize(width: min(size.width, lineWidth), height: size.height)
            builder.place(clamped, breaks: index == 0 ? 0 : breaks, lineWidth: lineWidth)
        }
        return builder.finish()
    }

    // MARK: - 查找

    /// 点所在的块（只在块内命中）
    public func index(at point: CGPoint) -> Int? {
        guard let row = rowIndex(at: point.y) else { return nil }
        return rows[row].tokens.first { frames[$0].contains(point) }
    }

    /// 离点最近的块（拖选用）：先取纵向最近的行（上方取首行、下方取末行、行间取较近的一行），再取行内横向最近的块
    public func nearestIndex(to point: CGPoint) -> Int? {
        guard !rows.isEmpty else { return nil }
        let row = rowIndex(at: point.y) ?? nearestRow(to: point.y)
        return rows[row].tokens.min { distance(point.x, to: frames[$0]) < distance(point.x, to: frames[$1]) }
    }

    /// 与矩形纵向相交的行（序号范围）
    public func rowRange(intersecting rect: CGRect) -> Range<Int> {
        let first = firstRow { $0.maxY > rect.minY }
        let last = firstRow { $0.minY >= rect.maxY }
        return first < last ? first..<last : first..<first
    }

    /// 与矩形相交的行里的全部块（绘制脏区）
    public func indices(intersecting rect: CGRect) -> Range<Int> {
        let range = rowRange(intersecting: rect)
        guard let first = range.first, let last = range.last else { return 0..<0 }
        return rows[first].tokens.lowerBound..<rows[last].tokens.upperBound
    }

    /// 某块所在的行
    public func row(containing token: Int) -> Int? {
        guard frames.indices.contains(token) else { return nil }
        let row = firstRow { $0.tokens.upperBound > token }
        return rows.indices.contains(row) ? row : nil
    }

    private func rowIndex(at y: CGFloat) -> Int? {
        let row = firstRow { $0.maxY > y }
        return rows.indices.contains(row) && rows[row].minY <= y ? row : nil
    }

    private func nearestRow(to y: CGFloat) -> Int {
        let below = firstRow { $0.minY > y }
        guard below > 0 else { return 0 }
        guard below < rows.count else { return rows.count - 1 }
        return y - rows[below - 1].maxY <= rows[below].minY - y ? below - 1 : below
    }

    /// 第一个满足条件的行（条件对行单调：前面为假、后面为真）；都不满足时为 rows.count
    private func firstRow(where predicate: (Row) -> Bool) -> Int {
        var low = 0
        var high = rows.count
        while low < high {
            let middle = (low + high) / 2
            if predicate(rows[middle]) {
                high = middle
            } else {
                low = middle + 1
            }
        }
        return low
    }

    private func distance(_ x: CGFloat, to frame: CGRect) -> CGFloat {
        x < frame.minX ? frame.minX - x : max(x - frame.maxX, 0)
    }
}

/// 逐块放进当前行，换行或放不下时收尾当前行（块在行内垂直居中）
private struct RowBuilder {
    let metrics: TextPickLayout.Metrics
    private var frames: [CGRect] = []
    private var rows: [TextPickLayout.Row] = []
    /// 当前行的起始块、顶边、已用宽度与行高
    private var rowStart = 0
    private var rowY: CGFloat = 0
    private var cursorX: CGFloat = 0
    private var rowHeight: CGFloat = 0

    init(metrics: TextPickLayout.Metrics) {
        self.metrics = metrics
    }

    mutating func place(_ size: CGSize, breaks: Int, lineWidth: CGFloat) {
        let isRowEmpty = frames.count == rowStart
        let fits = cursorX + (isRowEmpty ? 0 : metrics.itemSpacing) + size.width <= lineWidth
        if !isRowEmpty, breaks > 0 || !fits {
            closeRow(extra: breaks >= 2 ? metrics.paragraphSpacing : 0)
        }
        let x = frames.count == rowStart ? 0 : cursorX + metrics.itemSpacing
        frames.append(CGRect(x: x, y: rowY, width: size.width, height: size.height))
        cursorX = x + size.width
        rowHeight = max(rowHeight, size.height)
    }

    mutating func finish() -> TextPickLayout {
        guard frames.count > rowStart else { return TextPickLayout(frames: frames, rows: rows, height: 0) }
        let bottom = rowY + rowHeight
        closeRow(extra: 0)
        return TextPickLayout(frames: frames, rows: rows, height: bottom)
    }

    private mutating func closeRow(extra: CGFloat) {
        for index in rowStart..<frames.count {
            frames[index].origin.y = rowY + (rowHeight - frames[index].height) / 2
        }
        rows.append(TextPickLayout.Row(tokens: rowStart..<frames.count, minY: rowY, maxY: rowY + rowHeight))
        rowY += rowHeight + metrics.lineSpacing + extra
        rowStart = frames.count
        cursorX = 0
        rowHeight = 0
    }
}
