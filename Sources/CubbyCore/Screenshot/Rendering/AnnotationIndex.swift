import CoreGraphics

/// 文档标注的派生数据（序号、外接矩形），供覆盖层逐帧渲染使用
///
/// `Annotation.bounds` 对画笔要重建平滑路径、对文字要跑 CoreText 排版；拖动一条标注时文档每帧都变，
/// 但只有被拖的那一条变了。`updated(for:)` 按 id 复用内容没变的条目，只重算变化的条目，
/// 50 条以上的标注拖动也不会每帧重算全部 bounds。
public struct AnnotationIndex: Sendable {
    public struct Entry: Equatable, Sendable {
        public let annotation: Annotation
        /// 序号标注的编号（文档顺序推导），其他为 nil
        public let numberLabel: Int?
        public let bounds: CGRect
    }

    public static let empty = AnnotationIndex(entries: [], recomputedCount: 0)

    public let entries: [Entry]
    /// 最近一次建立 / 更新时重新计算 bounds 的条目数（测试用）
    let recomputedCount: Int

    private init(entries: [Entry], recomputedCount: Int) {
        self.entries = entries
        self.recomputedCount = recomputedCount
    }

    public init(document: AnnotationDocument) {
        self = Self.empty.updated(for: document)
    }

    /// 文档变化后的索引：内容相同的条目按 id 复用 bounds，其余重算；序号总是按新顺序推导
    public func updated(for document: AnnotationDocument) -> AnnotationIndex {
        let annotations = document.annotations
        if annotations.count == entries.count && zip(annotations, entries).allSatisfy({ $0 == $1.annotation }) {
            return AnnotationIndex(entries: entries, recomputedCount: 0)
        }
        let previous = Dictionary(entries.map { ($0.annotation.id, $0) }, uniquingKeysWith: { first, _ in first })
        var recomputed = 0
        var next = 1
        let rebuilt = annotations.map { annotation -> Entry in
            let label: Int?
            if annotation.tool == .number {
                label = next
                next += 1
            } else {
                label = nil
            }
            if let old = previous[annotation.id], old.annotation == annotation {
                return Entry(annotation: annotation, numberLabel: label, bounds: old.bounds)
            }
            recomputed += 1
            return Entry(annotation: annotation, numberLabel: label, bounds: annotation.bounds)
        }
        return AnnotationIndex(entries: rebuilt, recomputedCount: recomputed)
    }

    public func bounds(for id: AnnotationID) -> CGRect? {
        entries.first { $0.annotation.id == id }?.bounds
    }
}
