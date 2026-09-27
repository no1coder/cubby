import CoreGraphics

/// 不可变的标注文档：每个变更返回新值；撤销 / 重做以快照实现，撤销栈上限 100 步
///
/// 拖动标注只占一步撤销：reducer 在按下时保存文档快照，拖动的每一步都用
/// `pressSnapshot.replacing(移动后的标注)` 重建，因此一次撤销就回到拖动前。
///
/// 截图翻译（契约扩展）：快照里还记着当前应用的译文层 `translation`（一次翻译运行的 id）。
/// 译文内容放在会话里、按 id 原地更新，所以流式到达的每一块都不占撤销步；
/// 「应用翻译」「换语言重译」各是一次 `applyingTranslation`，即一步撤销。
public struct AnnotationDocument: Equatable, Sendable {
    /// 撤销栈上限
    public static let undoLimit = 100

    /// 没有任何标注与历史的文档
    public static let empty = AnnotationDocument(
        snapshot: Snapshot(annotations: [], translation: nil), undoStack: [], redoStack: [])

    /// 某一时刻的文档内容（撤销栈的元素）
    private struct Snapshot: Equatable, Sendable {
        let annotations: [Annotation]
        let translation: TranslationRunID?

        func with(translation: TranslationRunID?) -> Snapshot {
            Snapshot(annotations: annotations, translation: translation)
        }
    }

    private let snapshot: Snapshot
    private let undoStack: [Snapshot]
    private let redoStack: [Snapshot]

    private init(snapshot: Snapshot, undoStack: [Snapshot], redoStack: [Snapshot]) {
        self.snapshot = snapshot
        self.undoStack = undoStack
        self.redoStack = redoStack
    }

    /// 绘制顺序，先画的在下
    public var annotations: [Annotation] {
        snapshot.annotations
    }

    /// 当前应用的译文层（契约扩展）；nil = 没有译文
    public var translation: TranslationRunID? {
        snapshot.translation
    }

    public var canUndo: Bool {
        !undoStack.isEmpty
    }

    public var canRedo: Bool {
        !redoStack.isEmpty
    }

    // MARK: - 变更（每个都入一步撤销并清空重做）

    /// 追加到最上层
    public func adding(_ annotation: Annotation) -> AnnotationDocument {
        committing(annotations + [annotation])
    }

    /// 删除；id 不存在时原样返回
    public func removing(id: AnnotationID) -> AnnotationDocument {
        guard annotations.contains(where: { $0.id == id }) else { return self }
        return committing(annotations.filter { $0.id != id })
    }

    /// 同 id 原位替换；不存在或无变化时原样返回
    public func replacing(_ annotation: Annotation) -> AnnotationDocument {
        guard let updated = substituted(annotation) else { return self }
        return committing(updated)
    }

    /// 应用（或移除，nil）译文层：一步撤销；与当前相同时原样返回
    public func applyingTranslation(_ run: TranslationRunID?) -> AnnotationDocument {
        guard run != translation else { return self }
        return committing(snapshot.with(translation: run))
    }

    /// 取消一次翻译（翻译进行中按 Esc）：历史里所有指向 run 的快照改指 parent（重译前的译文，或 nil），
    /// 再合并因此变得相同的相邻快照——那一步撤销就像从没发生过；期间画的标注原样保留。不入撤销栈
    public func purgingTranslation(_ run: TranslationRunID, restoring parent: TranslationRunID?)
        -> AnnotationDocument
    {
        let timeline = undoStack + [snapshot] + redoStack.reversed()
        guard timeline.contains(where: { $0.translation == run }) else { return self }
        let replaced = timeline.map { $0.translation == run ? $0.with(translation: parent) : $0 }
        // 合并相邻重复；当前快照所在的那一段合并后仍是当前
        let currentIndex = undoStack.count
        var merged: [Snapshot] = []
        var mergedCurrent = 0
        for (index, item) in replaced.enumerated() {
            if merged.last != item {
                merged.append(item)
            }
            if index == currentIndex {
                mergedCurrent = merged.count - 1
            }
        }
        return AnnotationDocument(
            snapshot: merged[mergedCurrent],
            undoStack: Array(merged[..<mergedCurrent]),
            redoStack: Array(merged[(mergedCurrent + 1)...].reversed())
        )
    }

    // MARK: - 撤销 / 重做

    /// 回到上一步；无可撤销时原样返回
    public func undone() -> AnnotationDocument {
        guard let previous = undoStack.last else { return self }
        return AnnotationDocument(
            snapshot: previous,
            undoStack: Array(undoStack.dropLast()),
            redoStack: redoStack + [snapshot]
        )
    }

    /// 重做被撤销的一步；无可重做时原样返回
    public func redone() -> AnnotationDocument {
        guard let next = redoStack.last else { return self }
        return AnnotationDocument(
            snapshot: next,
            undoStack: undoStack + [snapshot],
            redoStack: Array(redoStack.dropLast())
        )
    }

    // MARK: - 查询

    public func annotation(id: AnnotationID) -> Annotation? {
        annotations.first { $0.id == id }
    }

    /// 命中的最上层（最后绘制的）标注
    public func topmost(at point: CGPoint, tolerance: CGFloat) -> Annotation? {
        annotations.last { $0.hitTest(point, tolerance: tolerance) }
    }

    /// 序号标注的显示编号（1 起，= 在序号类标注中的位置 + 1）；非序号或不存在返回 nil
    public func numberLabel(for id: AnnotationID) -> Int? {
        let numbers = annotations.filter { $0.tool == .number }
        return numbers.firstIndex { $0.id == id }.map { $0 + 1 }
    }

    /// 下一个新序号标注将显示的编号
    public var nextNumber: Int {
        annotations.filter { $0.tool == .number }.count + 1
    }

    // MARK: - 内部

    /// 标注变化：译文层保持不变
    private func committing(_ updated: [Annotation]) -> AnnotationDocument {
        committing(Snapshot(annotations: updated, translation: translation))
    }

    /// 以当前状态为快照入撤销栈（超出上限丢最早），清空重做栈
    private func committing(_ updated: Snapshot) -> AnnotationDocument {
        let history = (undoStack + [snapshot]).suffix(Self.undoLimit)
        return AnnotationDocument(snapshot: updated, undoStack: Array(history), redoStack: [])
    }

    /// 替换后的标注列表；id 不存在或内容相同返回 nil
    private func substituted(_ replacement: Annotation) -> [Annotation]? {
        guard let existing = annotation(id: replacement.id), existing != replacement else { return nil }
        return annotations.map { $0.id == replacement.id ? replacement : $0 }
    }
}
