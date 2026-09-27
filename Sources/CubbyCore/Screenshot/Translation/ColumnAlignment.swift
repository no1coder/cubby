import CoreGraphics

/// 单行块的对齐：单独一行看不出对齐，借同一列里上下相邻的块推断（表格的数值列、表单右对齐的标签、居中的标题与按钮）
enum ColumnAlignment {
    /// 相邻块的竖直距离上限：行高的这么多倍
    static let neighborReach: CGFloat = 8

    /// 右对齐 / 居中至少要这么多个相邻块佐证（一个块碰巧与另一块右缘齐很常见）
    static let minimumVotes = 2

    /// frames 为各块外框，heights 为各块中位行高；返回第 index 块的对齐，没有证据时为 nil。
    /// 只与另一块左缘齐（右缘、中线不齐）记一票 leading，只右缘齐记 trailing，只中线齐记 center；
    /// 票多者胜（平票取 leading），trailing / center 至少 2 票
    static func alignment(of index: Int, frames: [CGRect], heights: [CGFloat]) -> TextBlockAlignment? {
        let frame = frames[index]
        var votes: [TextBlockAlignment: Int] = [:]
        for other in frames.indices where other != index && isNeighbor(frame, frames[other], height: heights[index]) {
            let tolerance = 0.5 * min(heights[index], heights[other])
            if let vote = exclusiveAlignment(frame, frames[other], tolerance: tolerance) {
                votes[vote, default: 0] += 1
            }
        }
        guard let best = votes.values.max() else { return nil }
        let order: [TextBlockAlignment] = [.leading, .trailing, .center]
        let winner = order.first { votes[$0] == best }
        return winner == .leading || best >= minimumVotes ? winner : nil
    }

    /// 上下相邻（不在同一行、竖直距离不超过 8 行高）且水平有重叠
    private static func isNeighbor(_ frame: CGRect, _ other: CGRect, height: CGFloat) -> Bool {
        let verticalGap = max(other.minY - frame.maxY, frame.minY - other.maxY)
        let overlapsHorizontally = other.maxX > frame.minX && other.minX < frame.maxX
        return verticalGap >= 0 && verticalGap <= neighborReach * height && overlapsHorizontally
    }

    private static func exclusiveAlignment(_ frame: CGRect, _ other: CGRect, tolerance: CGFloat)
        -> TextBlockAlignment?
    {
        let left = abs(frame.minX - other.minX) <= tolerance
        let right = abs(frame.maxX - other.maxX) <= tolerance
        let center = abs(frame.midX - other.midX) <= tolerance
        switch (left, right, center) {
        case (true, false, _): return .leading
        case (false, true, _): return .trailing
        case (false, false, true): return .center
        default: return nil
        }
    }
}
