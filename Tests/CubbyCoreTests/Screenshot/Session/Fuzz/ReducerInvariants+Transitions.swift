import CoreGraphics
@testable import CubbyCore

/// 前后两个会话之间的关系
extension ReducerInvariantChecks {
    private static let hint = ScreenshotEffect.showHint(.pressEscapeAgainToDiscard)

    static func escapeAndRightClick(_ step: FuzzStep) -> String? {
        let previous = step.previous
        let session = step.session
        switch step.event {
        case .command(.escape):
            switch previous.phase {
            case .editingText:
                return !step.finished && session.phase != .editingText && step.effects.contains(.endTextEditing)
                    ? nil : "Esc while editing text must commit, not exit"
            case .selecting:
                return abandonedSelection(step)
            case .hovering, .adjusting, .annotating:
                return escapedTranslation(step) ?? armOrCancel(step)
            }
        case .rightMouseDown:
            switch previous.phase {
            case .hovering:
                return armOrCancel(step)
            case .selecting:
                return abandonedSelection(step)
            case .adjusting, .annotating, .editingText:
                // 清选区回 hovering，标注保留（拖动标注途中则回到按下前的文档）
                guard !step.finished, session.phase == .hovering, session.selection == nil else {
                    return "right click with a selection must return to hovering"
                }
                let kept = previous.phase == .editingText ? nil : (previous.press?.document ?? previous.document)
                if let kept, session.document.annotations != kept.annotations {
                    return "right click did not keep the annotations"
                }
                return nil
            }
        default:
            return nil
        }
    }

    /// selecting 中 Esc / 右键：放弃本次拖拽，有原选区则恢复，不结束会话
    private static func abandonedSelection(_ step: FuzzStep) -> String? {
        guard !step.finished, step.session.phase != .selecting else {
            return "abandoning a drag must not finish and must leave selecting"
        }
        if case .creatingSelection(_, let previous?) = step.previous.drag, step.session.selection != previous {
            return "previous selection \(previous) not restored (got \(String(describing: step.session.selection)))"
        }
        return nil
    }

    /// 翻译进行中的 Esc 只取消翻译，失败状态的 Esc 只关闭翻译条：都不结束会话、译文层回到上一次；
    /// 重试部分失败时的 Esc 只停掉重试（这次翻译保留）；其余情况返回 nil（照常二次确认或取消）
    private static func escapedTranslation(_ step: FuzzStep) -> String?? {
        guard let run = step.previous.translation, run.status.isBusy || run.isDismissible else { return nil }
        let session = step.session
        if run.status.isBusy && run.isRetrying {
            let kept = session.translation?.id == run.id && session.translation?.status.isBusy == false
            let stopped = !step.finished && !session.isTranslating && step.effects.contains(.translation(.cancel))
            return .some(kept && stopped ? nil : "Esc during a retry did not only stop the retry")
        }
        guard !step.finished, !session.isTranslating, session.document.translation == run.parent,
            session.translationRuns[run.id] == nil, !session.isDiscardArmed
        else { return .some("Esc did not only cancel the translation") }
        let cancels = step.effects.contains(.translation(.cancel))
        return .some(cancels == run.status.isBusy ? nil : "cancel effect does not match a busy translation")
    }

    /// 有标注或译文且未待确认：只进入待确认并提示；否则直接取消（PM Q1）
    private static func armOrCancel(_ step: FuzzStep) -> String? {
        let previous = step.previous
        if previous.hasDiscardableContent && !previous.isDiscardArmed {
            let armed = step.effects == [hint] && step.session.isDiscardArmed
            return armed && step.session.document == previous.document ? nil : "first press must only arm discard"
        }
        return step.effects == [.finish(.cancel)] ? nil : "second press / no annotations must cancel: \(step.effects)"
    }

    static func windowCaptureMode(_ step: FuzzStep) -> String? {
        let session = step.session
        guard session.isWindowCaptureMode else { return nil }
        if session.phase != .hovering {
            return "window capture mode in \(session.phase)"
        }
        if session.isMagnifierVisible {
            return "magnifier visible in window capture mode"
        }
        if !step.previous.isWindowCaptureMode {
            guard case .modifiersChanged(let modifiers) = step.event, !modifiers.contains(.space) else {
                return "window capture mode entered by \(step.event)"
            }
            return session.hover?.windowID == nil ? "entered window capture mode on a screen target" : nil
        }
        // §9.3：Tab / 滚轮切到整屏时自动退出。只看真正换了层的切换；移动到桌面（hover 变为整屏或空隙中为 nil）
        // 时模式保留，这是既有测试 ReducerWindowModeTests.desktopInWindowMode 固定的行为
        switch step.event {
        case .command(.cycleHover), .scrolled:
            guard session.hoverDepth != step.previous.hoverDepth, case .screen = session.hover else { return nil }
            return "cycled to the screen target but stayed in window mode"
        default:
            return nil
        }
    }

    static func discardArmed(_ step: FuzzStep) -> String? {
        let session = step.session
        if session.isDiscardArmed && !session.hasDiscardableContent {
            return "discard armed with an empty document"
        }
        if step.effects.contains(hint) != (session.isDiscardArmed && !step.previous.isDiscardArmed) {
            return "hint effect does not match arming"
        }
        guard step.previous.isDiscardArmed, session.isDiscardArmed, !step.finished else { return nil }
        switch step.event {
        case .mouseMoved, .modifiersChanged:
            return nil
        case .translation(let translation) where translation.isPipelineReport:
            return nil
        default:
            return "\(step.event) did not disarm the pending discard"
        }
    }

    static func effectsConsistency(_ step: FuzzStep) -> String? {
        let previous = step.previous
        let session = step.session
        let begins = step.effects.compactMap { effect -> (TextEditingState, String)? in
            if case .beginTextEditing(let state, let initial) = effect { (state, initial) } else { nil }
        }
        let entered = previous.phase != .editingText && session.phase == .editingText
        if entered != !begins.isEmpty {
            return "beginTextEditing effect does not match entering editingText"
        }
        if let (state, initial) = begins.first, state != session.textEditing || initial != state.text {
            return "beginTextEditing state differs from session.textEditing"
        }
        let left = previous.phase == .editingText && session.phase != .editingText
        if left != step.effects.contains(.endTextEditing) {
            return "endTextEditing effect does not match leaving editingText"
        }
        let styles = step.effects.compactMap { effect -> ToolStyles? in
            if case .stylesChanged(let styles) = effect { styles } else { nil }
        }
        let expected = session.styles == previous.styles ? [] : [session.styles]
        return styles == expected ? nil : "stylesChanged effects \(styles.count) do not match style change"
    }

    static func passiveEvents(_ step: FuzzStep) -> String? {
        let previous = step.previous
        let session = step.session
        let keepsSelectionAndPhase: Bool
        switch step.event {
        case .mouseMoved, .scrolled, .textChanged:
            keepsSelectionAndPhase = true
        case .modifiersChanged:
            // 拖拽中按 ⇧ / ⌥ / 空格会重算选区；空格单击会切换窗口模式，但都不改文档与阶段
            keepsSelectionAndPhase = false
        case .command(.cycleHover), .command(.copyColor), .styleChanged:
            guard previous.phase != .editingText else { return nil }
            keepsSelectionAndPhase = true
        case .translation(let translation) where translation.isPipelineReport:
            // 流水线回报只更新译文内容，不碰文档、选区与阶段
            keepsSelectionAndPhase = true
        default:
            return nil
        }
        if case .styleChanged = step.event {
            // 样式条可以改选中标注的样式，只检查选区与阶段
        } else if session.document != previous.document && !reappliedAnnotationMove(step) && !reappliedArrowEnd(step) {
            return "\(step.event) changed the document"
        }
        if session.phase != previous.phase {
            return "\(step.event) changed the phase \(previous.phase) → \(session.phase)"
        }
        if keepsSelectionAndPhase && session.selection != previous.selection {
            return "\(step.event) changed the selection"
        }
        return nil
    }

    /// 修饰键变化会按当前光标重算进行中的拖拽（§2.3 ⇧ 约束即时生效）。拖动标注时文档因此可以变，
    /// 但只能变成「从按下点拖到当前光标」的结果。只有非物理序列（按住时收到 mouseMoved）才会让光标领先于拖拽
    private static func reappliedAnnotationMove(_ step: FuzzStep) -> Bool {
        guard case .modifiersChanged = step.event, case .movingAnnotation(let id, _) = step.previous.drag,
            let press = step.previous.press, let original = press.document.annotation(id: id)
        else { return false }
        let cursor = step.session.cursor
        let moved = original.translated(by: CGVector(dx: cursor.x - press.location.x, dy: cursor.y - press.location.y))
        return step.session.document == press.document.replacing(moved)
    }

    /// 端点拖动中修饰键变化（⇧ 切换强制 45°）会按当前光标重算：只能改被拖的箭头，且固定的一端不动
    private static func reappliedArrowEnd(_ step: FuzzStep) -> Bool {
        guard case .modifiersChanged = step.event, case .movingArrowEnd(let id, let end) = step.previous.drag,
            let press = step.previous.press, case .arrow(let from, let to) = press.document.annotation(id: id)?.shape,
            case .arrow(let newFrom, let newTo) = step.session.document.annotation(id: id)?.shape
        else { return false }
        let others = step.session.document.annotations.filter { $0.id != id }
        let fixedKept = end == .head ? newFrom == from : newTo == to
        return fixedKept && others == press.document.annotations.filter { $0.id != id }
    }

    static func selectionEdits(_ step: FuzzStep) -> String? {
        let session = step.session
        if case .command(.nudge) = step.event, isSelectionPhase(step.previous.phase),
            session.selection?.size != step.previous.selection?.size
        {
            return "nudge resized the selection"
        }
        guard let press = session.press, let start = press.selection, let current = session.selection else {
            return nil
        }
        switch session.drag {
        case .resizing(let handle) where !session.modifiers.contains(.shift):
            let fixed: [(Bool, CGFloat, CGFloat, String)] = [
                (handle.movesLeftEdge, start.minX, current.minX, "left"),
                (handle.movesRightEdge, start.maxX, current.maxX, "right"),
                (handle.movesTopEdge, start.minY, current.minY, "top"),
                (handle.movesBottomEdge, start.maxY, current.maxY, "bottom"),
            ]
            for (moves, before, after, edge) in fixed where !moves && before != after {
                return "resizing \(handle) moved the fixed \(edge) edge \(before) → \(after)"
            }
            return nil
        case .movingSelection:
            return current.size == start.size ? nil : "moving the selection changed its size \(start) → \(current)"
        default:
            return nil
        }
    }

    static func drawingAndMoving(_ step: FuzzStep) -> String? {
        let previous = step.previous
        let document = step.session.document
        if case .drawing(let annotation) = step.session.drag,
            [.pointer, .text, .number].contains(annotation.tool)
        {
            return "drawing a \(annotation.tool) annotation"
        }
        guard case .mouseUp = step.event, previous.press != nil else { return nil }
        switch previous.drag {
        case .drawing(let annotation):
            guard document.annotations == previous.document.annotations + [annotation] else {
                return "finished drawing was not appended to the document"
            }
            return document.undone().annotations == previous.document.annotations
                ? nil : "one undo does not remove the finished drawing"
        case .movingAnnotation, .movingArrowEnd:
            guard let before = previous.press?.document, document != before else { return nil }
            return document.undone().annotations == before.annotations
                ? nil : "moving an annotation (or an arrow end) took more than one undo step"
        default:
            return nil
        }
    }

    static func textCommit(_ step: FuzzStep) -> String? {
        let previous = step.previous
        guard previous.phase == .editingText, let editing = previous.textEditing else { return nil }
        let submitted: String?
        switch step.event {
        case .textCommitted(let text): submitted = text
        case .command(.escape), .command(.commitText), .mouseDown: submitted = editing.text
        default: return nil
        }
        let content = trimmedTrailingWhitespace(submitted ?? "")
        let before = previous.document.annotations
        let after = step.session.document.annotations
        if let id = editing.existing, let existing = previous.document.annotation(id: id) {
            let expected =
                content.isEmpty
                ? before.filter { $0.id != id } : before.map { $0.id == id ? existing.withText(content) : $0 }
            return after == expected ? nil : "re-edit commit of \(content.debugDescription) produced wrong document"
        }
        if content.isEmpty {
            return after == before ? nil : "blank text was not discarded"
        }
        guard after.count == before.count + 1, Array(after.dropLast()) == before, let added = after.last else {
            return "committed text was not appended"
        }
        let shape = AnnotationShape.text(content, origin: editing.origin, maxWidth: editing.maxWidth)
        guard added.shape == shape, added.style == previous.styles.style(for: .text) else {
            return "committed text annotation \(added.shape) != \(shape)"
        }
        return nil
    }

    /// 独立实现的「去掉末尾空白」，与 reducer 的实现互相校验
    static func trimmedTrailingWhitespace(_ text: String) -> String {
        var characters = Array(text)
        while let last = characters.last, last.isWhitespace {
            characters.removeLast()
        }
        return String(characters)
    }
}
