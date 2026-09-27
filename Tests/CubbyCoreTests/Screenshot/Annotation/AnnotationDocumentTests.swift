import CoreGraphics
import Testing
@testable import CubbyCore

@Suite("AnnotationDocument 不可变文档与撤销 / 重做")
struct AnnotationDocumentTests {
    private func rect(_ x: CGFloat) -> Annotation {
        AnnotationSamples.make(.rectangle(CGRect(x: x, y: 0, width: 50, height: 50)))
    }

    private func number(_ x: CGFloat) -> Annotation {
        AnnotationSamples.make(.number(center: CGPoint(x: x, y: 0)))
    }

    @Test("空文档：无标注、不可撤销 / 重做、下一个编号为 1")
    func emptyDocument() {
        let document = AnnotationDocument.empty
        #expect(document.annotations.isEmpty)
        #expect(!document.canUndo)
        #expect(!document.canRedo)
        #expect(document.nextNumber == 1)
    }

    @Test("adding 追加到末尾并入一步撤销；原文档不变")
    func addingPushesUndo() {
        let first = rect(0)
        let second = rect(100)
        let document = AnnotationDocument.empty.adding(first).adding(second)

        #expect(document.annotations == [first, second])
        #expect(document.canUndo)
        #expect(!document.canRedo)
        #expect(AnnotationDocument.empty.annotations.isEmpty)
    }

    @Test("undo / redo 往返")
    func undoRedoRoundTrip() {
        let first = rect(0)
        let second = rect(100)
        let document = AnnotationDocument.empty.adding(first).adding(second)

        let undone = document.undone()
        #expect(undone.annotations == [first])
        #expect(undone.canUndo && undone.canRedo)

        let undoneTwice = undone.undone()
        #expect(undoneTwice.annotations.isEmpty)
        #expect(!undoneTwice.canUndo)

        let redone = undoneTwice.redone().redone()
        #expect(redone.annotations == [first, second])
        #expect(!redone.canRedo)
    }

    @Test("边界：无可撤销时 undone、无可重做时 redone 原样返回")
    func boundaries() {
        #expect(AnnotationDocument.empty.undone() == .empty)
        #expect(AnnotationDocument.empty.redone() == .empty)
        let document = AnnotationDocument.empty.adding(rect(0))
        #expect(document.redone() == document)
    }

    @Test("新操作清空重做栈")
    func newChangeClearsRedo() {
        let document = AnnotationDocument.empty.adding(rect(0)).adding(rect(100)).undone()
        #expect(document.canRedo)
        let changed = document.adding(rect(200))
        #expect(!changed.canRedo)
        #expect(changed.annotations.count == 2)
    }

    @Test("removing 删除并入一步；未知 id 原样返回")
    func removing() {
        let first = rect(0)
        let second = rect(100)
        let document = AnnotationDocument.empty.adding(first).adding(second)

        let removed = document.removing(id: first.id)
        #expect(removed.annotations == [second])
        #expect(removed.undone().annotations == [first, second])
        #expect(document.removing(id: AnnotationID()) == document)
    }

    @Test("replacing 同 id 原位替换并入一步；未知 id 或无变化时原样返回")
    func replacing() {
        let first = rect(0)
        let second = rect(100)
        let document = AnnotationDocument.empty.adding(first).adding(second)
        let moved = first.translated(by: CGVector(dx: 5, dy: 5))

        let replaced = document.replacing(moved)
        #expect(replaced.annotations == [moved, second])
        #expect(replaced.undone().annotations == [first, second])
        #expect(document.replacing(rect(300)) == document)
        #expect(document.replacing(first) == document)
    }

    @Test("撤销栈上限 100：超出后丢弃最早的步骤")
    func undoLimit() {
        var document = AnnotationDocument.empty
        for index in 0..<105 {
            document = document.adding(rect(CGFloat(index)))
        }
        var undoCount = 0
        while document.canUndo {
            document = document.undone()
            undoCount += 1
        }
        #expect(undoCount == AnnotationDocument.undoLimit)
        #expect(AnnotationDocument.undoLimit == 100)
        #expect(document.annotations.count == 5)
    }

    @Test("annotation(id:) 查找")
    func lookup() {
        let first = rect(0)
        let document = AnnotationDocument.empty.adding(first)
        #expect(document.annotation(id: first.id) == first)
        #expect(document.annotation(id: AnnotationID()) == nil)
    }

    @Test("topmost 取最后画的命中标注；无命中为 nil")
    func topmost() {
        let lower = rect(0)
        let upper = rect(0).withStyle(AnnotationStyle(color: .blue, weight: .regular))
        let document = AnnotationDocument.empty.adding(lower).adding(upper)

        #expect(document.topmost(at: CGPoint(x: 25, y: 0), tolerance: 6)?.id == upper.id)
        #expect(document.topmost(at: CGPoint(x: 25, y: 25), tolerance: 6) == nil)
    }

    @Test("序号由顺序推导：删除中间一个，后面自动补位")
    func numberLabels() {
        let one = number(0)
        let shape = rect(0)
        let two = number(50)
        let three = number(100)
        let document = AnnotationDocument.empty.adding(one).adding(shape).adding(two).adding(three)

        #expect(document.numberLabel(for: one.id) == 1)
        #expect(document.numberLabel(for: two.id) == 2)
        #expect(document.numberLabel(for: three.id) == 3)
        #expect(document.numberLabel(for: shape.id) == nil)
        #expect(document.numberLabel(for: AnnotationID()) == nil)
        #expect(document.nextNumber == 4)

        let removed = document.removing(id: two.id)
        #expect(removed.numberLabel(for: three.id) == 2)
        #expect(removed.nextNumber == 3)
        #expect(removed.undone().numberLabel(for: three.id) == 3)
    }
}
