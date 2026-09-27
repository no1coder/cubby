import CoreGraphics
@testable import CubbyCore

/// 按设计文档 §2.3 / §2.11 表格逐行归纳的语义：在任意交错的事件序列中，每条命令与点击仍按规格生效
extension ReducerInvariantChecks {
    /// 命令语义（editingText 中命令先提交文字再处理，由 textCommit / effectsConsistency 覆盖）
    static func commandSemantics(_ step: FuzzStep) -> String? {
        guard case .command(let command) = step.event, step.previous.phase != .editingText else { return nil }
        let previous = step.previous
        let idle = !previous.isPointerBusy
        let editable = isSelectionPhase(previous.phase) && idle
        switch command {
        case .selectTool(let tool):
            return toolSwitch(step, tool: tool)
        case .nudge(let direction, let large):
            guard editable else { return unchangedEdits(step) }
            if ScreenshotReducer.nudgingWipe(previous, direction, large: large) != nil {
                // 分隔线有焦点：← / → 只移动分隔线
                return unchangedEdits(step)
            }
            return nudge(step, direction: direction, step: large ? 10 : 1)
        case .deleteAnnotation:
            guard editable, let id = previous.selectedAnnotation else { return unchangedEdits(step) }
            let expected = previous.document.annotations.filter { $0.id != id }
            let deleted = step.session.document.annotations == expected && step.session.selectedAnnotation == nil
            return deleted ? nil : "delete did not remove exactly the selected annotation"
        case .undo, .redo:
            guard editable, !previous.isTranslating else { return unchangedEdits(step) }
            let expected = command == .undo ? previous.document.undone() : previous.document.redone()
            return step.session.document == expected ? nil : "\(command) did not apply to the document"
        case .selectAll:
            return selectAll(step, idle: idle)
        case .selectColor, .adjustWeight:
            // 键盘选色 / 调粗细：不能编辑时什么都不改；能编辑时只改样式（选区与阶段不变）
            guard editable else { return unchangedEdits(step) }
            let session = step.session
            return session.selection == previous.selection && session.phase == previous.phase
                && session.document.annotations.map(\.shape) == previous.document.annotations.map(\.shape)
                ? nil : "\(command) changed more than styles"
        case .cycleHover(let forward):
            guard previous.phase == .hovering, !previous.hoverCandidates.isEmpty else {
                let unchanged = step.session.hoverDepth == previous.hoverDepth
                return unchanged ? nil : "cycleHover changed depth outside hovering"
            }
            let last = previous.hoverCandidates.count - 1
            let expected = forward ? min(previous.hoverDepth + 1, last) : max(previous.hoverDepth - 1, 0)
            return step.session.hoverDepth == expected ? nil : "depth \(step.session.hoverDepth), expected \(expected)"
        default:
            return nil
        }
    }

    /// 工具键：adjusting 选工具 → annotating；annotating 再按同一工具 / V → adjusting，按其他工具切换；保留选中
    private static func toolSwitch(_ step: FuzzStep, tool: ScreenshotTool) -> String? {
        let previous = step.previous
        let session = step.session
        let expected: (ScreenshotPhase, ScreenshotTool)
        switch previous.phase {
        case .adjusting where tool != .pointer:
            expected = (.annotating, tool)
        case .annotating where tool == .pointer || tool == previous.tool:
            expected = (.adjusting, .pointer)
        case .annotating:
            expected = (.annotating, tool)
        default:
            expected = (previous.phase, previous.tool)
        }
        guard session.phase == expected.0, session.tool == expected.1 else {
            return "selectTool(\(tool)) in \(previous.phase)/\(previous.tool) → \(session.phase)/\(session.tool)"
        }
        return session.selectedAnnotation == previous.selectedAnnotation ? nil : "switching tools dropped the selection"
    }

    /// 方向键：选中标注时移动标注，否则移动选区（夹紧在所在屏幕）
    private static func nudge(_ step: FuzzStep, direction: NudgeDirection, step size: CGFloat) -> String? {
        let previous = step.previous
        let session = step.session
        let vector = CGVector(dx: direction.vector.dx * size, dy: direction.vector.dy * size)
        if let selected = previous.selectedAnnotationValue {
            let moved = session.document.annotation(id: selected.id)?.shape == selected.translated(by: vector).shape
            return moved && session.selection == previous.selection ? nil : "nudge did not move the selected annotation"
        }
        guard let selection = previous.selection, let id = previous.screenID, let screen = step.topology.screen(id: id)
        else { return nil }
        let expected = SelectionGeometry.nudged(selection, direction, step: size, bounds: screen.frame)
        guard session.selection == expected, session.document == previous.document else {
            return "nudge moved the selection to \(String(describing: session.selection)), expected \(expected)"
        }
        return nil
    }

    /// ⌘A：hovering 选光标所在整屏并进入 adjusting；有选区时扩为所在整屏；鼠标按下期间忽略
    private static func selectAll(_ step: FuzzStep, idle: Bool) -> String? {
        let previous = step.previous
        let session = step.session
        guard idle else { return session.selection == previous.selection ? nil : "⌘A applied while the mouse was busy" }
        let screen: CaptureScreen?
        switch previous.phase {
        case .hovering:
            screen = previous.hover?.screen ?? step.topology.screen(containing: previous.cursor)
            if screen != nil && session.phase != .adjusting {
                return "⌘A while hovering did not enter adjusting"
            }
        case .adjusting, .annotating:
            screen = previous.screenID.flatMap { step.topology.screen(id: $0) }
        case .selecting, .editingText:
            return session.selection == previous.selection ? nil : "⌘A changed the selection in \(previous.phase)"
        }
        guard let screen else { return nil }
        return session.selection == screen.frame && session.screenID == screen.id ? nil : "⌘A did not select the screen"
    }

    /// 不可编辑时（无选区阶段或鼠标按下中）编辑类命令不改文档与选区
    private static func unchangedEdits(_ step: FuzzStep) -> String? {
        step.session.document == step.previous.document && step.session.selection == step.previous.selection
            ? nil : "\(step.event) edited while not editable"
    }

    /// 点击语义：hovering 单击选中悬停目标；双击选区内完成复制；序号单击放置（中心 = 点击点）；
    /// 文字单击新建或重新编辑已有文字
    static func pointerSemantics(_ step: FuzzStep) -> String? {
        if case .mouseUp(let point) = step.event {
            return hoverClick(step, at: point)
        }
        guard case .mouseDown(let point, let count) = step.event, isSelectionPhase(step.previous.phase),
            let selection = step.previous.selection
        else { return nil }
        let previous = step.previous
        let session = step.session
        if count >= 2 && selection.contains(point) {
            return step.effects == [.finish(.copy)] ? nil : "double click inside the selection did not copy"
        }
        guard previous.phase == .annotating else { return nil }
        if case .handle = SelectionGeometry.hitRegion(at: point, in: selection) {
            return nil
        }
        // 选中箭头的端点手柄优先于工具（与选区手柄优先于绘制一致）：按下只开始重新指向
        if let arrow = previous.selectedAnnotationValue, case .arrow(let from, let to) = arrow.shape,
            min(hypot(point.x - from.x, point.y - from.y), hypot(point.x - to.x, point.y - to.y))
                <= ScreenshotReducer.arrowHandleTolerance
        {
            return session.document == previous.document && session.phase == previous.phase
                ? nil : "pressing a selected arrow's end handle ran the \(previous.tool) tool"
        }
        switch previous.tool {
        case .number:
            let added = session.document.annotations.last
            let placed =
                session.document.annotations.count == previous.document.annotations.count + 1
                && added?.shape == .number(center: point) && added?.style == previous.styles.style(for: .number)
            return placed ? nil : "number tool click did not place a badge at the click point"
        case .text:
            guard session.phase == .editingText, let editing = session.textEditing else {
                return "text tool click did not open the editor"
            }
            if let id = editing.existing {
                let hit = previous.document.annotation(id: id)?.hitTest(point, tolerance: 6) == true
                return hit ? nil : "re-edited a text annotation that was not clicked"
            }
            let texts = previous.document.annotations.filter { $0.tool == .text }
            if texts.contains(where: { $0.hitTest(point, tolerance: 6) }) {
                return "clicked an existing text annotation but opened a new editor"
            }
            return editing.origin == point && editing.text.isEmpty ? nil : "new text editor not at the click point"
        default:
            return nil
        }
    }

    /// hovering 单击（未超过拖拽阈值）：选区 = 松开处当前层的目标（窗口 ∩ 屏幕，或整屏），进入 adjusting（§2.3）。
    /// 允许吸附像素网格与补足 minSize 带来的最多一个像素（补足时更多）的差异
    private static func hoverClick(_ step: FuzzStep, at point: CGPoint) -> String? {
        let previous = step.previous
        guard previous.phase == .hovering, previous.drag == .none, let press = previous.press,
            press.intent == .selectHover
        else { return nil }
        let released = ScreenshotReducer.refreshingHover(
            previous.updating { $0.press = nil }, at: point, topology: step.topology)
        guard let target = released.hover else {
            return step.session.phase == .hovering ? nil : "click in a gap left hovering"
        }
        let session = step.session
        guard session.phase == .adjusting, session.screenID == target.screen.id, let selection = session.selection
        else { return "click did not select the hover target \(target)" }
        let expected = target.selectionRect
        let pixel = 1 / target.screen.scale + FuzzGeometry.tolerance
        let minimum = SelectionGeometry.minSize
        guard expected.width >= minimum.width, expected.height >= minimum.height else {
            return selection.intersects(expected) || selection.contains(point) ? nil : "tiny target not selected"
        }
        let edges = [
            selection.minX - expected.minX, selection.maxX - expected.maxX, selection.minY - expected.minY,
            selection.maxY - expected.maxY,
        ]
        return edges.allSatisfy { abs($0) <= pixel } ? nil : "selection \(selection) != target \(expected)"
    }
}
