import CoreGraphics

/// 鼠标按下 / 松开 / 右键（§2.3）。拖拽统一在超过阈值后才开始，见 +Drag
extension ScreenshotReducer {
    static func mouseDown(
        _ session: ScreenshotSession,
        at point: CGPoint,
        clickCount: Int,
        topology: ScreenTopology
    ) -> Result {
        switch session.phase {
        case .hovering:
            let refreshed = refreshingHover(session, at: point, topology: topology)
            let intent: PointerPress.Intent = session.isWindowCaptureMode ? .captureWindow : .selectHover
            return (pressing(refreshed, at: point, intent: intent), [])
        case .adjusting, .annotating:
            let moved = session.updating { $0.cursor = point }
            return selectionMouseDown(moved, at: point, clickCount: clickCount, topology: topology)
        case .selecting, .editingText:
            // selecting 时按钮已按下，不会再收到按下；editingText 由 +Text 处理
            return (session.updating { $0.cursor = point }, [])
        }
    }

    /// 有选区时的按下：双击完成 > 手柄 > （annotating：按工具）/（adjusting：标注 > 选区内 / 外）
    private static func selectionMouseDown(
        _ session: ScreenshotSession,
        at point: CGPoint,
        clickCount: Int,
        topology: ScreenTopology
    ) -> Result {
        guard let selection = session.selection else { return (session, []) }
        if clickCount >= 2 && selection.contains(point) {
            return (session, [.finish(.copy)])
        }
        // 选中箭头的端点手柄优先（annotating 时也是重新指向而不是新画一支）
        if let (id, end) = arrowEndHit(session, at: point) {
            return (pressing(session, at: point, intent: .moveArrowEnd(id, end)), [])
        }
        let region = SelectionGeometry.hitRegion(at: point, in: selection)
        if case .handle(let handle) = region {
            return (pressing(session, at: point, intent: .resize(handle)), [])
        }
        if session.phase == .annotating {
            return annotatingMouseDown(session, at: point, topology: topology)
        }
        if let hit = session.document.topmost(at: point, tolerance: annotationHitTolerance) {
            let selected = session.updating { $0.selectedAnnotation = hit.id }
            return (pressing(selected, at: point, intent: .moveAnnotation(hit.id)), [])
        }
        let deselected = session.updating { $0.selectedAnnotation = nil }
        let intent: PointerPress.Intent = region == .inside ? .moveSelection : .newSelection
        return (pressing(deselected, at: point, intent: intent), [])
    }

    /// annotating：文字工具按下即打开编辑器；序号工具按下即放置；其余工具拖拽绘制
    private static func annotatingMouseDown(
        _ session: ScreenshotSession,
        at point: CGPoint,
        topology: ScreenTopology
    ) -> Result {
        switch session.tool {
        case .text:
            return beginningTextEditing(session, at: point, topology: topology)
        case .number:
            return (pressing(placingNumber(session, at: point), at: point, intent: .none), [])
        default:
            return (pressing(session, at: point, intent: .draw), [])
        }
    }

    static func mouseUp(_ session: ScreenshotSession, at point: CGPoint, topology: ScreenTopology) -> Result {
        let released = movingPointer(session.updating { $0.press = nil }, to: point, topology: topology)
        guard let press = session.press else { return (released, []) }
        if session.drag == .none {
            return clicked(released, press: press)
        }
        return (endingDrag(released, press: press, topology: topology), [])
    }

    /// 没有超过拖拽阈值的松开 = 单击
    private static func clicked(_ session: ScreenshotSession, press: PointerPress) -> Result {
        switch press.intent {
        case .selectHover:
            return (selectingHoverTarget(session), [])
        case .captureWindow:
            // 按下后若已退出窗口模式（Tab / 滚轮切到整屏时自动退出，§9.3），按当前模式当作普通单击
            guard session.isWindowCaptureMode else { return (selectingHoverTarget(session), []) }
            return capturingWindow(session, includeShadow: !session.modifiers.contains(.option))
        case .newSelection, .moveSelection, .resize, .moveAnnotation, .moveArrowEnd, .draw, .none:
            return (session, [])
        }
    }

    /// 右键：hovering 取消会话（有标注时与 Esc 一样需要按两次）；selecting 放弃拖拽；
    /// 有选区时清选区回 hovering（标注保留）
    static func rightMouseDown(_ session: ScreenshotSession, at point: CGPoint, topology: ScreenTopology) -> Result {
        switch session.phase {
        case .hovering:
            return cancellingOrArmingDiscard(session)
        case .selecting:
            return (abandoningSelection(session.updating { $0.cursor = point }, topology: topology), [])
        case .adjusting, .annotating, .editingText:
            // 拖动标注途中右键：回到按下前的文档
            let reverted = session.updating { $0.document = session.press?.document ?? session.document }
            return (returningToHover(reverted, at: point, topology: topology), [])
        }
    }

    /// 记录一次按下
    static func pressing(_ session: ScreenshotSession, at point: CGPoint, intent: PointerPress.Intent)
        -> ScreenshotSession
    {
        let press = PointerPress(
            location: point,
            intent: intent,
            selection: session.selection,
            screenID: session.screenID,
            document: session.document
        )
        return session.updating {
            $0.cursor = point
            $0.press = press
        }
    }

    /// 放置一个序号标注（中心 = 点击点）
    private static func placingNumber(_ session: ScreenshotSession, at point: CGPoint) -> ScreenshotSession {
        let annotation = Annotation(
            id: AnnotationDrafting.annotationID(serial: session.annotationSerial),
            shape: .number(center: point),
            style: session.styles.style(for: .number)
        )
        return session.updating {
            $0.document = session.document.adding(annotation)
            $0.annotationSerial = session.annotationSerial + 1
            $0.selectedAnnotation = nil
        }
    }
}
