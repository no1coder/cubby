import CoreGraphics

/// hovering：悬停目标、重叠窗口逐层切换、纯净窗口截图模式（后两者为 PM 追加的契约扩展）
extension ScreenshotReducer {
    /// 按光标位置刷新悬停目标：候选栈与上次相同则保留 hoverDepth，否则归零（滚动累积同理）
    static func refreshingHover(_ session: ScreenshotSession, at point: CGPoint, topology: ScreenTopology)
        -> ScreenshotSession
    {
        let candidates = WindowHitTester.candidates(at: point, in: topology)
        let sameStack = candidates == session.hoverCandidates
        let depth = sameStack ? min(session.hoverDepth, max(candidates.count - 1, 0)) : 0
        return session.updating {
            $0.cursor = point
            $0.hoverCandidates = candidates
            $0.hoverDepth = depth
            $0.hover = candidates.isEmpty ? nil : candidates[depth]
            $0.scrollAccumulator = sameStack ? session.scrollAccumulator : 0
        }
    }

    /// 光标位置变化：hovering 时一律刷新悬停目标（含按钮按住时的拖动与松开），其他阶段只更新光标
    static func movingPointer(_ session: ScreenshotSession, to point: CGPoint, topology: ScreenTopology)
        -> ScreenshotSession
    {
        guard session.phase == .hovering else { return session.updating { $0.cursor = point } }
        return refreshingHover(session, at: point, topology: topology)
    }

    /// 离开 hovering 时清空悬停相关状态
    static func leavingHover(_ draft: inout ScreenshotSession.Draft) {
        draft.hover = nil
        draft.hoverCandidates = []
        draft.hoverDepth = 0
        draft.scrollAccumulator = 0
        draft.isWindowCaptureMode = false
        draft.isSpaceTapPending = false
    }

    /// Tab / 滚轮：depth ± 1，到整屏停住、到 0 停住，不循环；切到整屏时退出窗口模式
    static func cyclingHover(_ session: ScreenshotSession, forward: Bool) -> ScreenshotSession {
        let candidates = session.hoverCandidates
        guard session.phase == .hovering, !candidates.isEmpty else { return session }
        let depth = forward ? min(session.hoverDepth + 1, candidates.count - 1) : max(session.hoverDepth - 1, 0)
        let target = candidates[depth]
        return session.updating {
            $0.hoverDepth = depth
            $0.hover = target
            $0.scrollAccumulator = 0
            $0.isWindowCaptureMode = session.isWindowCaptureMode && target.windowID != nil
        }
    }

    /// 滚轮累积：同向累积到阈值走一层（每个事件最多一层，余量清零）；反向或 0（手势边界）清空累积
    static func scrolled(_ session: ScreenshotSession, deltaY: CGFloat, topology: ScreenTopology) -> ScreenshotSession {
        guard session.phase == .hovering else { return session }
        guard deltaY != 0 else { return session.updating { $0.scrollAccumulator = 0 } }
        let previous = session.scrollAccumulator
        let sameDirection = previous == 0 || (previous > 0) == (deltaY > 0)
        let accumulated = (sameDirection ? previous : 0) + deltaY
        guard abs(accumulated) >= scrollStepThreshold else {
            return session.updating { $0.scrollAccumulator = accumulated }
        }
        // AppKit 约定：deltaY < 0 为向下滚动 → 更深一层
        return cyclingHover(session, forward: accumulated < 0).updating { $0.scrollAccumulator = 0 }
    }

    /// 空格单击：在窗口目标上进入窗口模式；已在模式中则退出；整屏目标时不起作用
    static func togglingWindowCapture(_ session: ScreenshotSession) -> ScreenshotSession {
        if session.isWindowCaptureMode {
            return session.updating { $0.isWindowCaptureMode = false }
        }
        guard session.hover?.windowID != nil else { return session }
        return session.updating { $0.isWindowCaptureMode = true }
    }

    /// 选中当前悬停目标作为选区，进入 adjusting（单击 / ↩ / 过小的拖拽都走这里）。
    /// 跨屏窗口只有一条细边落在当前屏时，选区补足到 minSize 并留在屏幕内
    static func selectingHoverTarget(_ session: ScreenshotSession) -> ScreenshotSession {
        guard let target = session.hover else { return session }
        let rect = target.selectionRect
        let minimum = SelectionGeometry.minSize
        let size = CGSize(width: max(rect.width, minimum.width), height: max(rect.height, minimum.height))
        let selection = SelectionGeometry.clamped(CGRect(origin: rect.origin, size: size), to: target.screen.frame)
        return session.updating {
            $0.phase = session.selectionPhase
            $0.selection = selection
            $0.screenID = target.screen.id
            $0.drag = .none
            $0.press = nil
            leavingHover(&$0)
        }
    }

    /// 窗口模式下截取当前窗口；目标不是窗口时没有效果
    static func capturingWindow(_ session: ScreenshotSession, includeShadow: Bool) -> Result {
        guard let windowID = session.hover?.windowID else { return (session, []) }
        return (session, [.finish(.captureWindow(windowID: windowID, includeShadow: includeShadow))])
    }

    /// 回到 hovering（右键清选区、放弃拖拽）：depth 从 0 开始，工具复位为指针
    static func returningToHover(_ session: ScreenshotSession, at point: CGPoint, topology: ScreenTopology)
        -> ScreenshotSession
    {
        let cleared = session.updating {
            $0.phase = .hovering
            $0.selection = nil
            $0.screenID = nil
            $0.tool = .pointer
            $0.selectedAnnotation = nil
            $0.drag = .none
            $0.press = nil
            $0.textEditing = nil
            leavingHover(&$0)
        }
        return refreshingHover(cleared, at: point, topology: topology)
    }
}
