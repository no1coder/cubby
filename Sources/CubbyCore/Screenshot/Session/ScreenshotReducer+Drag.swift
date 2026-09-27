import CoreGraphics

/// 拖拽：超过阈值后开始，按按下时的快照 + 总位移计算（夹紧后往回拖不会漂移）
extension ScreenshotReducer {
    static func mouseDragged(_ session: ScreenshotSession, to point: CGPoint, topology: ScreenTopology)
        -> ScreenshotSession
    {
        let moved = movingPointer(session, to: point, topology: topology)
        guard let press = session.press else { return moved }
        if session.drag == .none {
            // 只按距离判定拖拽（≥ 4 pt）；§2.3 的「300 ms 内松开」不判断，因为 reducer 是纯函数、不读时间
            let distance = hypot(point.x - press.location.x, point.y - press.location.y)
            guard distance >= SelectionGeometry.dragThreshold else { return moved }
            return beginningDrag(moved, press: press, at: point, topology: topology)
        }
        return continuingDrag(moved, press: press, at: point, previousCursor: session.cursor, topology: topology)
    }

    /// 按下时的意图决定拖拽类型；无法开始的拖拽把按下作废（松开时不再当作单击）
    private static func beginningDrag(
        _ session: ScreenshotSession,
        press: PointerPress,
        at point: CGPoint,
        topology: ScreenTopology
    ) -> ScreenshotSession {
        let started: ScreenshotSession?
        switch press.intent {
        case .selectHover, .newSelection:
            started = startingSelection(session, press: press, topology: topology)
        case .moveSelection:
            started = session.updating { $0.drag = .movingSelection(last: point) }
        case .resize(let handle):
            started = session.updating { $0.drag = .resizing(handle) }
        case .moveAnnotation(let id):
            started = session.updating { $0.drag = .movingAnnotation(id, last: point) }
        case .moveArrowEnd(let id, let end):
            started = session.updating { $0.drag = .movingArrowEnd(id, end: end) }
        case .draw:
            started = startingDrawing(session, press: press, at: point)
        case .captureWindow, .none:
            started = nil
        }
        guard let started else {
            return session.updating { $0.press = press.with(intent: .none) }
        }
        return continuingDrag(started, press: press, at: point, previousCursor: point, topology: topology)
    }

    private static func startingSelection(
        _ session: ScreenshotSession,
        press: PointerPress,
        topology: ScreenTopology
    ) -> ScreenshotSession? {
        guard let screen = topology.screen(containing: press.location) else { return nil }
        let previous = press.intent == .newSelection ? press.selection : nil
        return session.updating {
            $0.phase = .selecting
            $0.drag = .creatingSelection(anchor: press.location, previous: previous)
            // 旧选区只保存在 previous 里，避免按住空格时平移的是旧选区
            $0.selection = nil
            $0.screenID = screen.id
            $0.hover = nil
            $0.selectedAnnotation = nil
            $0.isWindowCaptureMode = false
        }
    }

    private static func startingDrawing(_ session: ScreenshotSession, press: PointerPress, at point: CGPoint)
        -> ScreenshotSession?
    {
        guard
            let shape = AnnotationDrafting.shape(
                for: session.tool, from: press.location, to: point, constrained: false, previous: nil)
        else { return nil }
        let annotation = Annotation(
            id: AnnotationDrafting.annotationID(serial: session.annotationSerial),
            shape: shape,
            style: session.styles.style(for: session.tool)
        )
        return session.updating {
            $0.drag = .drawing(annotation)
            $0.annotationSerial = session.annotationSerial + 1
            $0.selectedAnnotation = nil
        }
    }

    /// 拖拽进行中（含修饰键变化时以当前光标重算）
    static func continuingDrag(
        _ session: ScreenshotSession,
        press: PointerPress,
        at point: CGPoint,
        previousCursor: CGPoint,
        topology: ScreenTopology
    ) -> ScreenshotSession {
        let shift = session.modifiers.contains(.shift)
        let delta = delta(from: press.location, to: point)
        switch session.drag {
        case .none:
            return session
        case .creatingSelection(let anchor, let previous):
            return creatingSelection(
                session, anchor: anchor, previous: previous, at: point, previousCursor: previousCursor,
                topology: topology)
        case .movingSelection:
            guard let start = press.selection, let bounds = selectionBounds(session, topology: topology) else {
                return session
            }
            let moved = SelectionGeometry.moved(start, by: delta, bounds: bounds)
            let magnetized = magnetGuides(session, topology: topology).map {
                SelectionGeometry.moved(SelectionMagnet.snappedOffset(moved, guides: $0), by: .zero, bounds: bounds)
            }
            return session.updating {
                $0.selection = magnetized ?? moved
                $0.drag = .movingSelection(last: point)
            }
        case .resizing(let handle):
            guard let start = press.selection, let bounds = selectionBounds(session, topology: topology) else {
                return session
            }
            let target = offset(handle.center(in: start), by: delta)
            let raw = SelectionGeometry.resizing(
                start, handle: handle, to: target, constrainSquare: shift, bounds: bounds)
            // ⇧ 正方形约束时不吸附（吸附会破坏正方形）
            let resized =
                (shift ? nil : magnetGuides(session, topology: topology)).map {
                    SelectionGeometry.clamped(
                        SelectionMagnet.snappedEdges(
                            raw, handle: handle, minSize: SelectionGeometry.minSize, guides: $0),
                        to: bounds)
                } ?? raw
            // 对边固定（§2.3）：吸附像素网格时保持固定边不动，只移动被拖的边
            let anchored = (x: handle.movesLeftEdge, y: handle.movesTopEdge)
            let snapped =
                session.screenID.flatMap { topology.screen(id: $0) }
                .map { snappedToPixelGrid(resized, screen: $0, anchoredHigh: anchored) } ?? resized
            return session.updating { $0.selection = snapped }
        case .drawing(let annotation):
            return session.updating {
                $0.drag = .drawing(
                    AnnotationDrafting.updated(annotation, anchor: press.location, to: point, constrained: shift))
            }
        case .movingAnnotation(let id, _):
            guard let original = press.document.annotation(id: id) else { return session }
            return session.updating {
                $0.document = press.document.replacing(original.translated(by: delta))
                $0.drag = .movingAnnotation(id, last: point)
            }
        case .movingArrowEnd(let id, let end):
            return movingArrowEnd(session, press: press, id: id, end: end, delta: delta, constrained: shift)
        }
    }

    /// 创建选区：普通 / ⇧ 正方形 / ⌥ 中心；按住空格时整体平移（起点随实际位移移动）
    private static func creatingSelection(
        _ session: ScreenshotSession,
        anchor: CGPoint,
        previous: CGRect?,
        at point: CGPoint,
        previousCursor: CGPoint,
        topology: ScreenTopology
    ) -> ScreenshotSession {
        guard let bounds = selectionBounds(session, topology: topology) else { return session }
        if session.modifiers.contains(.space), let current = session.selection {
            let shifted = SelectionGeometry.moved(current, by: delta(from: previousCursor, to: point), bounds: bounds)
            let applied = delta(from: current.origin, to: shifted.origin)
            return session.updating {
                $0.selection = shifted
                $0.drag = .creatingSelection(anchor: offset(anchor, by: applied), previous: previous)
            }
        }
        let fromCenter = session.modifiers.contains(.option)
        let corners =
            magnetGuides(session, topology: topology).map {
                SelectionMagnet.snappedCorners(anchor: anchor, cursor: point, fromCenter: fromCenter, guides: $0)
            } ?? (anchor: anchor, cursor: point)
        let rect = SelectionGeometry.normalized(
            from: corners.anchor,
            to: corners.cursor,
            constrainSquare: session.modifiers.contains(.shift),
            fromCenter: fromCenter,
            bounds: bounds
        )
        return session.updating { $0.selection = rect }
    }

    /// 松开：选区过小视为单击；绘制入文档；其余拖拽结束
    static func endingDrag(_ session: ScreenshotSession, press: PointerPress, topology: ScreenTopology)
        -> ScreenshotSession
    {
        switch session.drag {
        case .creatingSelection(_, let previous):
            let rect = session.selection ?? .zero
            if rect.width >= SelectionGeometry.minSize.width && rect.height >= SelectionGeometry.minSize.height {
                return session.updating {
                    $0.phase = session.selectionPhase
                    $0.drag = .none
                    leavingHover(&$0)
                }
            }
            if let previous {
                return restoringSelection(session, previous, screenID: press.screenID)
            }
            guard let target = currentHoverTarget(session) else {
                return abandoningSelection(session, topology: topology)
            }
            return selectingHoverTarget(session.updating { $0.hover = target })
        case .drawing(let annotation):
            return session.updating {
                $0.document = session.document.adding(annotation)
                $0.drag = .none
            }
        case .none, .movingSelection, .resizing, .movingAnnotation, .movingArrowEnd:
            return session.updating { $0.drag = .none }
        }
    }

    /// Esc / 右键放弃 selecting：有原选区则恢复，否则回 hovering（同一叠窗口内保留 depth）
    static func abandoningSelection(_ session: ScreenshotSession, topology: ScreenTopology) -> ScreenshotSession {
        guard case .creatingSelection(_, let previous) = session.drag else { return session }
        if let previous {
            return restoringSelection(session, previous, screenID: session.press?.screenID)
        }
        let cleared = session.updating {
            $0.phase = .hovering
            $0.selection = nil
            $0.screenID = nil
            $0.drag = .none
            $0.press = nil
        }
        return refreshingHover(cleared, at: session.cursor, topology: topology)
    }

    private static func restoringSelection(_ session: ScreenshotSession, _ previous: CGRect, screenID: UInt32?)
        -> ScreenshotSession
    {
        session.updating {
            $0.phase = session.selectionPhase
            $0.selection = previous
            $0.screenID = screenID ?? session.screenID
            $0.drag = .none
            $0.press = nil
        }
    }

    /// 候选栈中当前 depth 的目标（selecting 期间 hover 为 nil，栈与 depth 仍保留）
    private static func currentHoverTarget(_ session: ScreenshotSession) -> HoverTarget? {
        let candidates = session.hoverCandidates
        guard !candidates.isEmpty else { return nil }
        return candidates[min(session.hoverDepth, candidates.count - 1)]
    }
}
