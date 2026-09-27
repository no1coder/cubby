import CoreGraphics
import Testing
@testable import CubbyCore

@Suite("AnnotationIndex 标注派生数据的增量更新")
struct AnnotationIndexTests {
    private let red = AnnotationStyle(color: .red, weight: .regular)

    /// 一条画笔：points 个点的折线（bounds 需要重建平滑路径，是索引要避免重复计算的开销）
    private func pen(_ index: Int, points: Int = 200) -> Annotation {
        let base = CGFloat(index * 10)
        let line = (0..<points).map { CGPoint(x: base + CGFloat($0) * 2, y: base + CGFloat($0 % 7)) }
        return Annotation(id: AnnotationDrafting.annotationID(serial: index + 1), shape: .pen(line), style: red)
    }

    private func document(_ annotations: [Annotation]) -> AnnotationDocument {
        annotations.reduce(AnnotationDocument.empty) { $0.adding($1) }
    }

    @Test("首次建立：每条标注计算一次 bounds；序号按文档顺序推导")
    func initialBuild() {
        let number = Annotation(shape: .number(center: CGPoint(x: 5, y: 5)), style: red)
        let index = AnnotationIndex(document: document([pen(0), number, pen(1)]))
        #expect(index.entries.count == 3)
        #expect(index.recomputedCount == 3)
        #expect(index.entries.map(\.numberLabel) == [nil, 1, nil])
        #expect(index.entries[0].bounds == pen(0).bounds)
    }

    @Test("文档不变：原样复用，不重算")
    func unchanged() {
        let doc = document((0..<5).map { pen($0) })
        let index = AnnotationIndex(document: doc)
        let again = index.updated(for: doc)
        #expect(again.recomputedCount == 0)
        #expect(again.entries == index.entries)
    }

    @Test("拖动一条标注（60 条中的 1 条）：每帧只重算被拖的那一条")
    func draggingOne() {
        var annotations = (0..<60).map { pen($0) }
        var index = AnnotationIndex(document: document(annotations))
        let start = document(annotations)
        for frame in 1...30 {
            annotations[17] = pen(17).translated(by: CGVector(dx: CGFloat(frame), dy: 0))
            let moved = start.replacing(annotations[17])
            index = index.updated(for: moved)
            #expect(index.recomputedCount == 1)
            #expect(index.entries[17].bounds == annotations[17].bounds)
            #expect(index.bounds(for: annotations[17].id) == annotations[17].bounds)
        }
    }

    @Test("增删改后与重新建立的结果一致")
    func matchesFreshBuild() {
        let base = document((0..<8).map { pen($0) })
        let index = AnnotationIndex(document: base)
        let edited = base.removing(id: pen(2).id).adding(pen(20)).replacing(pen(5).withStyle(red.withColor(.blue)))
        let updated = index.updated(for: edited)
        #expect(updated.entries == AnnotationIndex(document: edited).entries)
        // 只有新增与改样式的两条需要重算（改样式可能改变线宽 → bounds）
        #expect(updated.recomputedCount == 2)
    }
}
