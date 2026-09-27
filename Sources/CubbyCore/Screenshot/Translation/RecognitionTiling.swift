import CoreGraphics

/// 大选区分片识别（§3.1：超过约 3840×2160 像素时整张识别会出现乱码行）。
/// 实测（合成 5K 语料，稀疏的 17 pt 标签）：3840×2160 的分片仍漏掉 20/65 块，2560×1600 的分片全部识别，故取后者
///
/// 每个轴上用尽量少、尽量大的分片均匀铺满，相邻分片至少重叠 minimumOverlap；
/// 每个分片的 core 是它「负责」的区域（相邻分片以重叠带中线为界，互不重叠且铺满整张图）：
/// 一行只从中心落在其 core 内的分片里取，由此去重。
public struct RecognitionTile: Equatable, Sendable {
    /// 分片在整张图中的像素矩形（左上原点）
    public let rect: CGRect
    /// 该分片负责的区域
    public let core: CGRect

    public init(rect: CGRect, core: CGRect) {
        self.rect = rect
        self.core = core
    }
}

public enum RecognitionTiling {
    /// 横向图的分片上限（纵向图宽高互换）
    public static let maximumSize = CGSize(width: 2560, height: 1600)
    /// 相邻分片的最小重叠（像素）：远大于 2 × 常见行高
    public static let minimumOverlap: CGFloat = 256

    /// size 为整张图的像素尺寸；不超过上限时只有一个分片
    public static func tiles(for size: CGSize) -> [RecognitionTile] {
        let limit =
            size.width >= size.height
            ? maximumSize : CGSize(width: maximumSize.height, height: maximumSize.width)
        let columns = spans(length: size.width, maximum: limit.width)
        let rows = spans(length: size.height, maximum: limit.height)
        return rows.flatMap { row in
            columns.map { column in
                RecognitionTile(
                    rect: CGRect(x: column.start, y: row.start, width: column.length, height: row.length),
                    core: CGRect(
                        x: column.coreStart, y: row.coreStart, width: column.coreEnd - column.coreStart,
                        height: row.coreEnd - row.coreStart))
            }
        }
    }

    private struct Span {
        let start: CGFloat
        let length: CGFloat
        let coreStart: CGFloat
        let coreEnd: CGFloat
    }

    /// 一个轴上的分片：数量 n = ⌈(L − 重叠) / (上限 − 重叠)⌉，起点均匀分布
    private static func spans(length: CGFloat, maximum: CGFloat) -> [Span] {
        guard length > maximum else { return [Span(start: 0, length: length, coreStart: 0, coreEnd: length)] }
        let count = Int(((length - minimumOverlap) / (maximum - minimumOverlap)).rounded(.up))
        let step = ((length - maximum) / CGFloat(count - 1)).rounded(.down)
        let starts = (0..<count).map { index in index == count - 1 ? length - maximum : CGFloat(index) * step }
        let boundaries = zip(starts.dropFirst(), starts).map { next, start in ((next + start + maximum) / 2).rounded() }
        let edges = [0] + boundaries + [length]
        return starts.enumerated().map { index, start in
            Span(start: start, length: maximum, coreStart: edges[index], coreEnd: edges[index + 1])
        }
    }
}
