import CoreGraphics

/// 键盘命令、工具栏按钮、样式条（§2.3 / §2.6 / §2.11）
extension ScreenshotReducer {
    static func reduceCommand(_ session: ScreenshotSession, _ command: ScreenshotCommand, topology: ScreenTopology)
        -> Result
    {
        switch command {
        case .escape:
            return escape(session, topology: topology)
        case .confirm:
            return confirm(session)
        case .save:
            return finishingWithSelection(session, .save)
        case .pin:
            return finishingWithSelection(session, .pin)
        case .extractText:
            return finishingWithSelection(session, .extractText)
        case .selectAll:
            return (selectAll(session, topology: topology), [])
        case .undo, .redo:
            return (history(session, undo: command == .undo), [])
        case .selectTool(let tool):
            return (selectTool(session, tool), [])
        case .nudge(let direction, let large):
            return (nudge(session, direction, large: large, topology: topology), [])
        case .deleteAnnotation:
            return (deleteAnnotation(session), [])
        case .cycleHover(let forward):
            return (cyclingHover(session, forward: forward), [])
        case .selectColor(let color):
            return styleShortcut(session) { tool, style in tool.usesColor ? style.withColor(color) : nil }
        case .adjustWeight(let heavier):
            return styleShortcut(session) { _, style in
                let weights = StrokeWeight.allCases
                guard let index = weights.firstIndex(of: style.weight) else { return nil }
                let next = min(max(index + (heavier ? 1 : -1), 0), weights.count - 1)
                return next == index ? nil : style.withWeight(weights[next])
            }
        case .translate:
            return reduceTranslation(session, .start, topology: topology)
        case .copyColor, .commitText:
            // copyColor 需要读数，由覆盖层发 .toolbarAction(.copyColor(读数))；commitText 只在 editingText 有意义
            return (session, [])
        }
    }

    /// Esc：selecting 放弃拖拽；翻译进行中只取消翻译（失败时关闭翻译条）；
    /// 其余阶段取消会话，但有标注或译文时第一次只进入待确认（PM Q1）
    private static func escape(_ session: ScreenshotSession, topology: ScreenTopology) -> Result {
        if session.phase == .selecting {
            return (abandoningSelection(session, topology: topology), [])
        }
        if let translation = escapingTranslation(session) {
            return translation
        }
        return cancellingOrArmingDiscard(session)
    }

    /// 取消会话；但有标注或译文且尚未待确认时，只进入待确认并提示（PM Q1，Esc 与 hovering 的右键共用）
    static func cancellingOrArmingDiscard(_ session: ScreenshotSession) -> Result {
        if session.hasDiscardableContent && !session.isDiscardArmed {
            return (session.updating { $0.isDiscardArmed = true }, [.showHint(.pressEscapeAgainToDiscard)])
        }
        return (session, [.finish(.cancel)])
    }

    /// ↩ / ⌘C：hovering 截悬停目标（窗口模式截窗口）；有选区时完成
    private static func confirm(_ session: ScreenshotSession) -> Result {
        guard session.phase == .hovering else { return finishingWithSelection(session, .copy) }
        if session.isWindowCaptureMode {
            return capturingWindow(session, includeShadow: true)
        }
        let selected = selectingHoverTarget(session)
        return selected.selection == nil ? (session, []) : (selected, [.finish(.copy)])
    }

    /// 有选区（adjusting / annotating）时以 outcome 结束
    private static func finishingWithSelection(_ session: ScreenshotSession, _ outcome: ScreenshotOutcome) -> Result {
        let hasSelection = session.phase == .adjusting || session.phase == .annotating
        guard hasSelection, session.selection != nil else { return (session, []) }
        return (session, [.finish(outcome)])
    }

    /// ⌘A：hovering 选光标所在整屏；有选区时扩为所在整屏；鼠标按下期间忽略
    private static func selectAll(_ session: ScreenshotSession, topology: ScreenTopology) -> ScreenshotSession {
        guard !session.isPointerBusy else { return session }
        switch session.phase {
        case .hovering:
            guard let screen = session.hover?.screen ?? topology.screen(containing: session.cursor) else {
                return session
            }
            return session.updating {
                $0.phase = session.selectionPhase
                $0.selection = screen.frame
                $0.screenID = screen.id
                leavingHover(&$0)
            }
        case .adjusting, .annotating:
            guard let bounds = selectionBounds(session, topology: topology) else { return session }
            return session.updating { $0.selection = bounds }
        case .selecting, .editingText:
            return session
        }
    }

    /// 撤销 / 重做作用于标注与译文层；选中的标注被撤销掉时清除选中。翻译进行中不可用（Esc 才是取消翻译）
    private static func history(_ session: ScreenshotSession, undo: Bool) -> ScreenshotSession {
        guard session.canEditSelection, !session.isTranslating else { return session }
        let document = undo ? session.document.undone() : session.document.redone()
        return session.updating {
            $0.document = document
            $0.selectedAnnotation = session.selectedAnnotation.flatMap { document.annotation(id: $0)?.id }
        }
    }

    /// 工具键：adjusting 选工具进入 annotating；annotating 再按同一工具 / V 回 adjusting，按其他工具切换
    private static func selectTool(_ session: ScreenshotSession, _ tool: ScreenshotTool) -> ScreenshotSession {
        switch session.phase {
        case .adjusting where tool != .pointer:
            return session.updating {
                $0.tool = tool
                $0.phase = .annotating
            }
        case .annotating where tool == .pointer || tool == session.tool:
            return session.updating {
                $0.tool = .pointer
                $0.phase = .adjusting
            }
        case .annotating:
            return session.updating { $0.tool = tool }
        default:
            return session
        }
    }

    /// 方向键：卷帘分隔线有焦点时 ← / → 微调它；选中标注时移动标注，否则移动选区（夹紧在所在屏幕）
    private static func nudge(
        _ session: ScreenshotSession,
        _ direction: NudgeDirection,
        large: Bool,
        topology: ScreenTopology
    ) -> ScreenshotSession {
        guard session.canEditSelection else { return session }
        if let wiped = nudgingWipe(session, direction, large: large) {
            return wiped
        }
        let step = large ? largeNudge : smallNudge
        if let annotation = session.selectedAnnotationValue {
            let vector = CGVector(dx: direction.vector.dx * step, dy: direction.vector.dy * step)
            return session.updating { $0.document = session.document.replacing(annotation.translated(by: vector)) }
        }
        guard let selection = session.selection, let bounds = selectionBounds(session, topology: topology) else {
            return session
        }
        return session.updating {
            $0.selection = SelectionGeometry.nudged(selection, direction, step: step, bounds: bounds)
        }
    }

    private static func deleteAnnotation(_ session: ScreenshotSession) -> ScreenshotSession {
        guard session.canEditSelection, let id = session.selectedAnnotation else { return session }
        return session.updating {
            $0.document = session.document.removing(id: id)
            $0.selectedAnnotation = nil
        }
    }

    /// 样式条：有选中标注时改它并更新其工具的默认样式；否则更新当前工具的默认样式；鼠标按下期间忽略
    static func styleChanged(_ session: ScreenshotSession, to style: AnnotationStyle) -> Result {
        let editable = [ScreenshotPhase.adjusting, .annotating, .editingText].contains(session.phase)
        guard editable, !session.isPointerBusy else { return (session, []) }
        let selected = session.selectedAnnotationValue
        guard let tool = selected?.tool ?? (session.tool == .pointer ? nil : session.tool) else { return (session, []) }
        let styles = session.styles.setting(style, for: tool)
        let updated = session.updating {
            $0.styles = styles
            if let selected {
                $0.document = session.document.replacing(selected.withStyle(style))
            }
        }
        return (updated, styles == session.styles ? [] : [.stylesChanged(styles)])
    }

    /// 键盘选色 / 调粗细：与样式条同一语义（选中标注优先，其次当前工具）；change 返回 nil 表示无变化
    private static func styleShortcut(
        _ session: ScreenshotSession,
        _ change: (ScreenshotTool, AnnotationStyle) -> AnnotationStyle?
    ) -> Result {
        guard session.canEditSelection else { return (session, []) }
        let tool = session.selectedAnnotationValue?.tool ?? (session.tool == .pointer ? nil : session.tool)
        guard let tool, let style = change(tool, session.activeStyle) else { return (session, []) }
        return styleChanged(session, to: style)
    }

    /// 工具栏出口：取色只在放大镜可见时有效；窗口截取只在窗口模式有效；✕ 总是直接取消
    static func toolbarAction(_ session: ScreenshotSession, _ outcome: ScreenshotOutcome, topology: ScreenTopology)
        -> Result
    {
        switch outcome {
        case .copyColor(let text):
            return session.isMagnifierVisible && !text.isEmpty ? (session, [.finish(outcome)]) : (session, [])
        case .captureWindow:
            return session.phase == .hovering && session.isWindowCaptureMode
                ? (session, [.finish(outcome)]) : (session, [])
        case .cancel:
            return (session, [.finish(.cancel)])
        case .copy, .save, .pin, .extractText:
            return finishingWithSelection(session, outcome)
        }
    }
}
