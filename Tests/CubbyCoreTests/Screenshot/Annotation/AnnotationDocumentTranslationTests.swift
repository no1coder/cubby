import CoreGraphics
import Testing
@testable import CubbyCore

@Suite("AnnotationDocument · 译文层的撤销 / 重做与取消")
struct AnnotationDocumentTranslationTests {
    private let first = TranslationRunID(rawValue: 1)
    private let second = TranslationRunID(rawValue: 2)

    private func rect(_ x: CGFloat) -> Annotation {
        AnnotationSamples.make(.rectangle(CGRect(x: x, y: 0, width: 50, height: 50)))
    }

    @Test("应用译文算一步撤销；撤销 / 重做往返；标注不受影响")
    func applyingIsOneUndoStep() {
        let base = AnnotationDocument.empty.adding(rect(0))
        let applied = base.applyingTranslation(first)
        #expect(applied.translation == first)
        #expect(applied.annotations == base.annotations)
        let undone = applied.undone()
        #expect(undone.translation == nil)
        #expect(undone.annotations == base.annotations)
        #expect(undone.redone().translation == first)
    }

    @Test("换语言重译是另一步撤销：撤销回到上一种语言")
    func retranslationIsAnotherStep() {
        let document = AnnotationDocument.empty.applyingTranslation(first).applyingTranslation(second)
        #expect(document.translation == second)
        #expect(document.undone().translation == first)
        #expect(document.undone().undone().translation == nil)
    }

    @Test("应用相同的译文不入撤销栈")
    func applyingSameIsNoOp() {
        let document = AnnotationDocument.empty.applyingTranslation(first)
        #expect(document.applyingTranslation(first) == document)
        #expect(AnnotationDocument.empty.applyingTranslation(nil) == .empty)
    }

    @Test("添加标注保留当前译文；撤销标注时译文仍在")
    func annotationsKeepTranslation() {
        let document = AnnotationDocument.empty.applyingTranslation(first).adding(rect(0))
        #expect(document.translation == first)
        #expect(document.undone().translation == first)
        #expect(document.undone().annotations.isEmpty)
    }

    @Test("取消译文：历史里的引用全部回到上一层，空的撤销步合并，期间画的标注保留")
    func purgingRemovesTheStep() {
        let drawn = rect(0)
        let document = AnnotationDocument.empty.applyingTranslation(first).adding(drawn)
        let purged = document.purgingTranslation(first, restoring: nil)
        #expect(purged.translation == nil)
        #expect(purged.annotations == [drawn])
        // 只剩「添加矩形」这一步：与没翻译过、直接画矩形的文档完全相同
        #expect(purged == AnnotationDocument.empty.adding(drawn))
    }

    @Test("取消重译：回到上一种语言，撤销栈与重译前一致")
    func purgingRestoresParent() {
        let before = AnnotationDocument.empty.applyingTranslation(first)
        let purged = before.applyingTranslation(second).purgingTranslation(second, restoring: first)
        #expect(purged == before)
    }

    @Test("取消的译文在重做栈里：一并清除，重做不会再带回来")
    func purgingCleansRedo() {
        let document = AnnotationDocument.empty.adding(rect(0)).applyingTranslation(first).undone()
        #expect(document.canRedo)
        let purged = document.purgingTranslation(first, restoring: nil)
        #expect(!purged.canRedo)
        #expect(purged.annotations == document.annotations)
        #expect(purged.canUndo)
    }

    @Test("取消与当前无关的译文不改变文档")
    func purgingUnknownIsNoOp() {
        let document = AnnotationDocument.empty.adding(rect(0)).applyingTranslation(first)
        #expect(document.purgingTranslation(second, restoring: nil) == document)
    }
}
