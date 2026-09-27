import CoreGraphics

/// 截图会话状态机（§2.2 / §2.3）：纯函数，不依赖时间、随机数或任何全局状态
///
/// 分文件：+Pointer（鼠标按下 / 松开 / 右键）、+Drag（拖拽）、+Commands（键盘与工具栏）、
/// +Text（文字编辑）、+Hover（悬停、逐层切换、窗口模式）、+Translation / +TranslationReports（截图翻译）。
public enum ScreenshotReducer {
    /// reduce 的返回值
    typealias Result = (session: ScreenshotSession, effects: [ScreenshotEffect])

    /// 滚轮累积到该值（点）才切换一层（契约扩展）
    ///
    /// 取 40 pt 的理由：触控板上约 1 cm 的有意滑动，手指搭在板上的抖动远小于它；
    /// 与 `scrollPointsPerLine` 相同，保证老式滚轮一格恰好一层。每个事件最多走一层且余量清零，
    /// 因此单个大增量（快速甩动）也只跳一层；惯性阶段的事件应由覆盖层过滤（见 `scrollPointsPerLine`）。
    public static let scrollStepThreshold: CGFloat = 40

    /// 行式滚轮（`hasPreciseScrollingDeltas == false`）每行换算的点数：覆盖层发送 `scrollingDeltaY × 该值`。
    /// 触控板 / 妙控鼠标直接发送 `scrollingDeltaY`，并且不转发 `momentumPhase` 非空的惯性事件。
    public static let scrollPointsPerLine: CGFloat = 40

    /// 单击选中标注的容差（§2.3）；覆盖层按同一容差决定悬停光标（契约扩展：公开）
    public static let annotationHitTolerance: CGFloat = 6
    /// 方向键小步 / 大步（§2.3）
    static let smallNudge: CGFloat = 1
    static let largeNudge: CGFloat = 10

    /// 纯函数：所有阶段转换、选区几何、标注增删改、撤销 / 重做都在这里
    public static func reduce(
        _ session: ScreenshotSession,
        event: ScreenshotEvent,
        topology: ScreenTopology
    ) -> (session: ScreenshotSession, effects: [ScreenshotEffect]) {
        let prepared = preparing(session, for: event)
        let result =
            prepared.phase == .editingText
            ? reduceEditingText(prepared, event: event, topology: topology)
            : dispatch(prepared, event: event, topology: topology)
        let snapped = snappingSelection(result.session, topology: topology)
        return (settlingTranslationView(snapped, previous: session), result.effects)
    }

    /// 所有写入 selection 的路径（创建、缩放、移动、微调、单击窗口 / 整屏、⌘A）在这里统一吸附到所在屏幕的
    /// 像素网格：原点取最近的像素，尺寸四舍五入到整像素（⇧ 正方形保持正方形），再夹回屏幕内。
    /// 这样尺寸标签与导出（`CaptureScreen.pixelRect` 的 integral）得到同一个像素尺寸。
    /// 缩放手柄在 +Drag 里先按固定边吸附过（见 `snappedToPixelGrid(_:screen:anchoredHigh:)`），这里对它是恒等变换
    private static func snappingSelection(_ session: ScreenshotSession, topology: ScreenTopology)
        -> ScreenshotSession
    {
        guard let selection = session.selection,
            let screen = session.screenID.flatMap({ topology.screen(id: $0) })
        else { return session }
        let snapped = snappedToPixelGrid(selection, screen: screen)
        return snapped == selection ? session : session.updating { $0.selection = snapped }
    }

    /// 吸附到像素网格。anchoredHigh：该轴上高端（右 / 下边）是缩放时的固定边，吸附时保持它不动、只移动起点；
    /// 否则原点与尺寸分别取整，固定边会漂移半个像素（@1x 上 .5 坐标甚至一整个点）
    static func snappedToPixelGrid(
        _ rect: CGRect,
        screen: CaptureScreen,
        anchoredHigh: (x: Bool, y: Bool) = (false, false)
    ) -> CGRect {
        let scale = screen.scale
        let box = rect.standardized
        let origin = screen.frame.origin
        let nearest = { (value: CGFloat, base: CGFloat) in base + ((value - base) * scale).rounded() / scale }
        let width = (box.width * scale).rounded() / scale
        let height = (box.height * scale).rounded() / scale
        let snapped = CGRect(
            x: anchoredHigh.x ? nearest(box.maxX, origin.x) - width : nearest(box.minX, origin.x),
            y: anchoredHigh.y ? nearest(box.maxY, origin.y) - height : nearest(box.minY, origin.y),
            width: width,
            height: height
        )
        return SelectionGeometry.clamped(snapped, to: screen.frame)
    }

    /// 非编辑文字阶段的事件分发
    static func dispatch(_ session: ScreenshotSession, event: ScreenshotEvent, topology: ScreenTopology) -> Result {
        switch event {
        case .mouseMoved(let point):
            return (mouseMoved(session, to: point, topology: topology), [])
        case .mouseDown(let point, let clickCount):
            return mouseDown(session, at: point, clickCount: clickCount, topology: topology)
        case .mouseDragged(let point):
            return (mouseDragged(session, to: point, topology: topology), [])
        case .mouseUp(let point):
            return mouseUp(session, at: point, topology: topology)
        case .rightMouseDown(let point):
            return rightMouseDown(session, at: point, topology: topology)
        case .modifiersChanged(let modifiers):
            return (modifiersChanged(session, to: modifiers, topology: topology), [])
        case .command(let command):
            return reduceCommand(session, command, topology: topology)
        case .styleChanged(let style):
            return styleChanged(session, to: style)
        case .textChanged, .textCommitted:
            return (session, [])
        case .toolbarAction(let outcome):
            return toolbarAction(session, outcome, topology: topology)
        case .scrolled(let deltaY):
            return (scrolled(session, deltaY: deltaY, topology: topology), [])
        case .translation(let event):
            return reduceTranslation(session, event, topology: topology)
        }
    }

    /// 事件前置处理：
    /// - 除 Esc 与被动事件（鼠标移动、修饰键）外，任何事件都先解除「待确认放弃」（PM Q1）；
    /// - 除被动事件外，任何事件都让「单独按空格」失效（空格期间有其他操作就不是切换窗口模式）；
    /// - 按下鼠标让卷帘分隔线失去键盘焦点。翻译流水线的回报也是被动事件。
    private static func preparing(_ incoming: ScreenshotSession, for event: ScreenshotEvent) -> ScreenshotSession {
        let session = releasingWipeFocus(incoming, for: event)
        let isPassive: Bool
        switch event {
        case .mouseMoved, .modifiersChanged: isPassive = true
        case .translation(let translation): isPassive = translation.isPipelineReport
        default: isPassive = false
        }
        guard !isPassive, session.isDiscardArmed || session.isSpaceTapPending else { return session }
        // 再按一次 Esc（或 hovering 时再右键）就是确认放弃，不能先把待确认解除
        let keepsArmed: Bool
        switch event {
        case .command(.escape): keepsArmed = true
        case .rightMouseDown: keepsArmed = session.phase == .hovering
        default: keepsArmed = false
        }
        return session.updating {
            $0.isDiscardArmed = keepsArmed && session.isDiscardArmed
            $0.isSpaceTapPending = false
        }
    }

    // MARK: - 被动事件

    private static func mouseMoved(_ session: ScreenshotSession, to point: CGPoint, topology: ScreenTopology)
        -> ScreenshotSession
    {
        movingPointer(session, to: point, topology: topology)
    }

    /// ⇧ 决定颜色格式；hovering 的空格单击切换窗口模式；拖拽中按新的修饰键重算
    private static func modifiersChanged(
        _ session: ScreenshotSession,
        to modifiers: KeyModifiers,
        topology: ScreenTopology
    ) -> ScreenshotSession {
        let spacePressed = !session.modifiers.contains(.space) && modifiers.contains(.space)
        let spaceReleased = session.modifiers.contains(.space) && !modifiers.contains(.space)
        let updated = session.updating {
            $0.modifiers = modifiers
            $0.colorFormat = modifiers.contains(.shift) ? .rgb : .hex
            if spacePressed {
                $0.isSpaceTapPending = session.phase == .hovering && session.press == nil
            } else if spaceReleased {
                $0.isSpaceTapPending = false
            }
        }
        if spaceReleased && session.isSpaceTapPending && session.phase == .hovering {
            return togglingWindowCapture(updated)
        }
        guard updated.drag != .none, let press = updated.press else { return updated }
        return continuingDrag(
            updated, press: press, at: updated.cursor, previousCursor: updated.cursor, topology: topology)
    }

    // MARK: - 共用工具

    /// 选区所在屏幕的 frame（缩放 / 移动 / 微调的夹紧范围）
    static func selectionBounds(_ session: ScreenshotSession, topology: ScreenTopology) -> CGRect? {
        if let id = session.screenID, let screen = topology.screen(id: id) {
            return screen.frame
        }
        guard let selection = session.selection else { return nil }
        return topology.screen(containing: CGPoint(x: selection.midX, y: selection.midY))?.frame
    }

    static func offset(_ point: CGPoint, by delta: CGVector) -> CGPoint {
        CGPoint(x: point.x + delta.dx, y: point.y + delta.dy)
    }

    static func delta(from start: CGPoint, to end: CGPoint) -> CGVector {
        CGVector(dx: end.x - start.x, dy: end.y - start.y)
    }
}
