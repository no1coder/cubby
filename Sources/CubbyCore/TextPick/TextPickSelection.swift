import Foundation

/// 拆词卡的选取（不可变，每次操作返回新值；docs/TEXT-PICK-DESIGN.md P7）：
/// 单击切换一块；按住拖过一串连选（起点未选中 = 加选，已选中 = 取消），从按下前的选取算起，往回拖时收缩；
/// ⇧单击从上次点击处（锚点）连选；全选 / 已全选时清空
public struct TextPickSelection: Equatable, Sendable {
    public let indices: Set<Int>
    /// 上次单击或开始拖选的块：⇧单击从这里连选
    public let anchor: Int?

    public init(indices: Set<Int> = [], anchor: Int? = nil) {
        self.indices = indices
        self.anchor = anchor
    }

    public var isEmpty: Bool {
        indices.isEmpty
    }

    public var count: Int {
        indices.count
    }

    public var sortedIndices: [Int] {
        indices.sorted()
    }

    public func contains(_ index: Int) -> Bool {
        indices.contains(index)
    }

    /// 是否已全选（没有词块时为 false）
    public func isAll(count total: Int) -> Bool {
        total > 0 && indices.count == total && indices.allSatisfy { (0..<total).contains($0) }
    }

    /// 单击：切换一块，锚点移到这一块
    public func toggling(_ index: Int) -> TextPickSelection {
        let next = indices.contains(index) ? indices.subtracting([index]) : indices.union([index])
        return TextPickSelection(indices: next, anchor: index)
    }

    /// 拖选：在拖动开始前的选取（self）上加入或取消一段；newAnchor 为拖选的起点（nil 时锚点不变）
    public func applying(range: ClosedRange<Int>, adding: Bool, anchor newAnchor: Int? = nil) -> TextPickSelection {
        let span = Set(range)
        return TextPickSelection(
            indices: adding ? indices.union(span) : indices.subtracting(span), anchor: newAnchor ?? anchor)
    }

    /// ⇧单击：把锚点到 index 之间（含两端）加入选取，锚点不变；没有锚点时等同单击
    public func extending(to index: Int) -> TextPickSelection {
        guard let anchor else { return toggling(index) }
        let span = Set(min(anchor, index)...max(anchor, index))
        return TextPickSelection(indices: indices.union(span), anchor: anchor)
    }

    /// ⌘A / 「全选」：未全选时选中全部，已全选时清空
    public func togglingAll(count total: Int) -> TextPickSelection {
        guard total > 0, !isAll(count: total) else { return TextPickSelection(anchor: anchor) }
        return TextPickSelection(indices: Set(0..<total), anchor: anchor)
    }
}
