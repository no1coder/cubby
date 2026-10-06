import AppKit
import CubbyCore

// 词块区的鼠标操作（docs/TEXT-PICK-DESIGN.md P7）：单击切换一块；按住拖过一串连选（起点未选中 = 加选，
// 已选中 = 取消，从按下前的选取算起，往回拖收缩）；⇧单击从上次点击处连选；拖到上下边缘自动滚动。
// 详情区窗口不是 key：悬停靠 activeAlways 的跟踪区域，点击靠 acceptsFirstMouse

extension TextPickCanvasView {
    // MARK: - 点选与拖选

    override func mouseDown(with event: NSEvent) {
        guard let index = layout?.index(at: contentPoint(of: event.locationInWindow)) else { return }
        if event.modifierFlags.contains(.shift) {
            commit(selection.extending(to: index))
            return
        }
        let current = selection
        drag = Drag(base: current, start: index, adding: !current.contains(index))
        lastDragLocation = event.locationInWindow
        applyDrag(to: index)
    }

    override func mouseDragged(with event: NSEvent) {
        guard drag != nil else { return }
        lastDragLocation = event.locationInWindow
        dragToPointer()
        updateAutoScroll()
    }

    override func mouseUp(with event: NSEvent) {
        drag = nil
        lastDragLocation = nil
        stopAutoScroll()
    }

    /// 指针所在（或最近）的块作为拖选终点
    private func dragToPointer() {
        guard let location = lastDragLocation, let index = layout?.nearestIndex(to: contentPoint(of: location))
        else { return }
        applyDrag(to: index)
    }

    private func applyDrag(to index: Int) {
        guard let drag else { return }
        let range = min(drag.start, index)...max(drag.start, index)
        commit(drag.base.applying(range: range, adding: drag.adding, anchor: drag.start))
    }

    /// 先在本视图上立即重绘，再交给控制器（SwiftUI 随后同步回来，不会重复重绘）
    func commit(_ newSelection: TextPickSelection) {
        setSelection(newSelection)
        controller?.select(newSelection)
    }

    /// 窗口坐标 → 词块坐标（内容区左上角为原点）
    func contentPoint(of windowLocation: CGPoint) -> CGPoint {
        let point = convert(windowLocation, from: nil)
        return CGPoint(x: point.x - contentOrigin.x, y: point.y - contentOrigin.y)
    }

    // MARK: - 自动滚动

    /// 指针在可见区域上下边缘 autoScrollEdge 内（或已拖出）时，按越界的深度滚动，每帧重新取指针下的块
    private func updateAutoScroll() {
        guard autoScrollStep() != 0 else {
            stopAutoScroll()
            return
        }
        guard autoScrollTimer == nil else { return }
        autoScrollTimer = Self.repeatingTimer(interval: TextPickMetrics.animationInterval) { [weak self] in
            self?.autoScrollTick()
        }
    }

    private func autoScrollStep() -> CGFloat {
        guard let location = lastDragLocation else { return 0 }
        let point = convert(location, from: nil)
        let visible = visibleRect
        let edge = TextPickMetrics.autoScrollEdge
        let depth: CGFloat
        if point.y < visible.minY + edge {
            depth = point.y - (visible.minY + edge)
        } else if point.y > visible.maxY - edge {
            depth = point.y - (visible.maxY - edge)
        } else {
            return 0
        }
        let step = depth / edge * TextPickMetrics.autoScrollMaxStep
        return min(max(step, -TextPickMetrics.autoScrollMaxStep), TextPickMetrics.autoScrollMaxStep)
    }

    private func autoScrollTick() {
        let step = autoScrollStep()
        let maxY = max(bounds.height - visibleRect.height, 0)
        let targetY = min(max(visibleRect.minY + step, 0), maxY)
        guard step != 0, drag != nil, targetY != visibleRect.minY else {
            stopAutoScroll()
            return
        }
        scroll(CGPoint(x: visibleRect.minX, y: targetY))
        dragToPointer()
    }

    func stopAutoScroll() {
        autoScrollTimer?.invalidate()
        autoScrollTimer = nil
    }

    // MARK: - 悬停

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(
            NSTrackingArea(
                rect: .zero, options: [.activeAlways, .mouseMoved, .mouseEnteredAndExited, .inVisibleRect],
                owner: self))
    }

    override func mouseMoved(with event: NSEvent) {
        hover(atWindowPoint: event.locationInWindow)
    }

    override func mouseEntered(with event: NSEvent) {
        hover(atWindowPoint: event.locationInWindow)
    }

    /// 光标在窗口坐标里的位置 → 悬停的块（nil 表示离开）
    private func hover(atWindowPoint point: NSPoint?) {
        setHovered(point.flatMap { layout?.index(at: contentPoint(of: $0)) })
    }

    override func mouseExited(with event: NSEvent) {
        setHovered(nil)
    }

    func setHovered(_ index: Int?) {
        guard index != hovered else { return }
        let previous = hovered
        hovered = index
        redraw(previous)
        redraw(index)
    }

    #if DEBUG
    /// 面板 E2E：某块中心在屏幕上的位置（AppKit 坐标）；先滚到可见
    func debugScreenPoint(ofToken index: Int) -> CGPoint? {
        guard let frame = chipFrame(index), let window else { return nil }
        scrollToVisible(frame)
        let center = convert(CGPoint(x: frame.midX, y: frame.midY), to: nil)
        return window.convertPoint(toScreen: center)
    }

    /// 面板 E2E：合成的鼠标移动触发不了跟踪区域，脚本把窗口坐标交给与 mouseMoved 相同的命中判断
    func debugHover(atWindowPoint point: NSPoint?) {
        hover(atWindowPoint: point)
    }
    #endif
}
