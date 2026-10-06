import Testing
@testable import CubbyCore

/// 不可变选取（docs/TEXT-PICK-DESIGN.md P7）：单击切换、拖过一串（起点未选 = 加选，已选 = 取消，往回拖收缩）、
/// ⇧单击从上次点击处连选、全选 / 已全选时清空
@Suite("TextPickSelection 拆词选取")
struct TextPickSelectionTests {
    @Test("初始为空")
    func startsEmpty() {
        let selection = TextPickSelection()
        #expect(selection.isEmpty)
        #expect(selection.count == 0)
        #expect(selection.anchor == nil)
        #expect(selection.sortedIndices.isEmpty)
    }

    @Test("toggling：未选中则加入，已选中则移除；锚点移到该块；原值不变")
    func toggling() {
        let empty = TextPickSelection()
        let one = empty.toggling(3)
        #expect(one.contains(3))
        #expect(one.anchor == 3)
        #expect(empty.isEmpty)
        let none = one.toggling(3)
        #expect(!none.contains(3))
        #expect(none.isEmpty)
        #expect(none.anchor == 3)
    }

    @Test("拖选从拖动前的选取计算：往回拖时范围收缩")
    func dragShrinksWhenMovingBack() {
        let base = TextPickSelection(indices: [0])
        let far = base.applying(range: 2...5, adding: true)
        #expect(far.sortedIndices == [0, 2, 3, 4, 5])
        let back = base.applying(range: 2...3, adding: true, anchor: 3)
        #expect(back.sortedIndices == [0, 2, 3])
        #expect(back.anchor == 3)
        #expect(far.anchor == nil)
    }

    @Test("起点已选中时拖过的块被取消")
    func dragFromSelectedRemoves() {
        let base = TextPickSelection(indices: [1, 2, 3, 4])
        let result = base.applying(range: 2...3, adding: false)
        #expect(result.sortedIndices == [1, 4])
    }

    @Test("⇧单击：从锚点连选到该块（两个方向都可以），锚点不变")
    func extending() {
        let clicked = TextPickSelection().toggling(5)
        let forward = clicked.extending(to: 8)
        #expect(forward.sortedIndices == [5, 6, 7, 8])
        #expect(forward.anchor == 5)
        let backward = clicked.extending(to: 2)
        #expect(backward.sortedIndices == [2, 3, 4, 5])
    }

    @Test("没有锚点时 ⇧单击等同单击")
    func extendingWithoutAnchor() {
        let result = TextPickSelection().extending(to: 4)
        #expect(result.sortedIndices == [4])
        #expect(result.anchor == 4)
    }

    @Test("全选：未全选时选中全部，已全选时清空；没有词块时为空")
    func togglingAll() {
        let partial = TextPickSelection(indices: [1])
        let all = partial.togglingAll(count: 4)
        #expect(all.sortedIndices == [0, 1, 2, 3])
        #expect(all.isAll(count: 4))
        #expect(!partial.isAll(count: 4))
        let cleared = all.togglingAll(count: 4)
        #expect(cleared.isEmpty)
        #expect(TextPickSelection().togglingAll(count: 0).isEmpty)
        #expect(!TextPickSelection().isAll(count: 0))
    }

    @Test("相等性只看选中的块与锚点")
    func equality() {
        #expect(TextPickSelection(indices: [1, 2]) == TextPickSelection(indices: [2, 1]))
        #expect(TextPickSelection(indices: [1]) != TextPickSelection(indices: [1]).toggling(2).toggling(2))
    }
}
