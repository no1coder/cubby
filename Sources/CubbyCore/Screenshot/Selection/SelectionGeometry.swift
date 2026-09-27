import CoreGraphics

/// 选区几何：归一化、移动、微调、夹紧、命中（全局点坐标，y 向下）。缩放见 SelectionGeometry+Resize.swift
public enum SelectionGeometry {
    /// 选区最小尺寸（§2.5）
    public static let minSize = CGSize(width: 4, height: 4)
    /// 按下后移动不足该距离视为单击（§2.3）
    public static let dragThreshold: CGFloat = 4

    /// 短边小于该值时不画手柄（边带仍可拖）
    private static let noHandlesBelow: CGFloat = 16
    /// 短边小于该值时只画四角手柄
    private static let cornerHandlesOnlyBelow: CGFloat = 40

    /// 拖拽归一化；constrainSquare = ⇧，fromCenter = ⌥；结果夹紧到 bounds
    ///
    /// 正方形取两边中较小者、方向跟随光标象限；夹紧先于取较小边，因此夹紧后仍是正方形。
    public static func normalized(
        from anchor: CGPoint,
        to point: CGPoint,
        constrainSquare: Bool,
        fromCenter: Bool,
        bounds: CGRect
    ) -> CGRect {
        let start = clampedPoint(anchor, to: bounds)
        let delta = CGVector(dx: point.x - start.x, dy: point.y - start.y)
        if fromCenter {
            return centeredRect(around: start, delta: delta, square: constrainSquare, bounds: bounds)
        }
        return cornerRect(from: start, delta: delta, square: constrainSquare, bounds: bounds)
    }

    /// 平移后夹紧到 bounds
    public static func moved(_ rect: CGRect, by delta: CGVector, bounds: CGRect) -> CGRect {
        clamped(rect.offsetBy(dx: delta.dx, dy: delta.dy), to: bounds)
    }

    /// 方向键微调 step 个点，夹紧到 bounds
    public static func nudged(_ rect: CGRect, _ direction: NudgeDirection, step: CGFloat, bounds: CGRect) -> CGRect {
        let unit = direction.vector
        return moved(rect, by: CGVector(dx: unit.dx * step, dy: unit.dy * step), bounds: bounds)
    }

    /// 平移（必要时缩小）使矩形完整位于 bounds 内；比 bounds 大时贴左上
    public static func clamped(_ rect: CGRect, to bounds: CGRect) -> CGRect {
        let box = rect.standardized
        let width = min(box.width, bounds.width)
        let height = min(box.height, bounds.height)
        let x = min(max(box.minX, bounds.minX), bounds.maxX - width)
        let y = min(max(box.minY, bounds.minY), bounds.maxY - height)
        return CGRect(x: x, y: y, width: width, height: height)
    }

    /// 手柄中心 ±handleTolerance 优先，其次边带 edgeBand，再判断内 / 外
    ///
    /// 只有 `visibleHandles(for:)` 返回的手柄参与命中；边带宽度以边线为中心，角落处两条边带相交映射为角手柄。
    public static func hitRegion(
        at point: CGPoint,
        in rect: CGRect,
        handleTolerance: CGFloat = 8,
        edgeBand: CGFloat = 6
    ) -> SelectionHitRegion {
        let box = rect.standardized
        if let handle = nearestHandle(to: point, in: box, tolerance: handleTolerance) {
            return .handle(handle)
        }
        if let handle = bandHandle(at: point, in: box, halfWidth: edgeBand / 2) {
            return .handle(handle)
        }
        return box.contains(point) ? .inside : .outside
    }

    /// 小选区退化：返回应绘制的手柄集合（<16 pt 空集，<40 pt 只有四角）
    public static func visibleHandles(for rect: CGRect) -> [SelectionHandle] {
        let shortest = min(abs(rect.width), abs(rect.height))
        if shortest < noHandlesBelow {
            return []
        }
        if shortest < cornerHandlesOnlyBelow {
            return SelectionHandle.allCases.filter(\.isCorner)
        }
        return SelectionHandle.allCases
    }

    // MARK: - 私有

    /// 把点夹进 bounds（含右 / 下边缘）
    static func clampedPoint(_ point: CGPoint, to bounds: CGRect) -> CGPoint {
        CGPoint(
            x: min(max(point.x, bounds.minX), bounds.maxX),
            y: min(max(point.y, bounds.minY), bounds.maxY)
        )
    }

    /// 以 anchor 为一角：每个方向的长度不超过 anchor 到该方向 bounds 边缘的距离
    private static func cornerRect(from anchor: CGPoint, delta: CGVector, square: Bool, bounds: CGRect) -> CGRect {
        let availableWidth = delta.dx >= 0 ? bounds.maxX - anchor.x : anchor.x - bounds.minX
        let availableHeight = delta.dy >= 0 ? bounds.maxY - anchor.y : anchor.y - bounds.minY
        let rawWidth = min(abs(delta.dx), availableWidth)
        let rawHeight = min(abs(delta.dy), availableHeight)
        let side = min(rawWidth, rawHeight)
        let width = square ? side : rawWidth
        let height = square ? side : rawHeight
        let x = delta.dx >= 0 ? anchor.x : anchor.x - width
        let y = delta.dy >= 0 ? anchor.y : anchor.y - height
        return CGRect(x: x, y: y, width: width, height: height)
    }

    /// 以 center 为中心对称扩展：半宽 / 半高不超过 center 到最近 bounds 边缘的距离
    private static func centeredRect(around center: CGPoint, delta: CGVector, square: Bool, bounds: CGRect) -> CGRect {
        let rawHalfWidth = min(abs(delta.dx), center.x - bounds.minX, bounds.maxX - center.x)
        let rawHalfHeight = min(abs(delta.dy), center.y - bounds.minY, bounds.maxY - center.y)
        let side = min(rawHalfWidth, rawHalfHeight)
        let halfWidth = square ? side : rawHalfWidth
        let halfHeight = square ? side : rawHalfHeight
        return CGRect(
            x: center.x - halfWidth,
            y: center.y - halfHeight,
            width: halfWidth * 2,
            height: halfHeight * 2
        )
    }

    /// 命中容差内中心最近的可见手柄
    private static func nearestHandle(to point: CGPoint, in box: CGRect, tolerance: CGFloat) -> SelectionHandle? {
        let candidates = visibleHandles(for: box).compactMap { handle -> (SelectionHandle, CGFloat)? in
            let center = handle.center(in: box)
            let dx = abs(point.x - center.x)
            let dy = abs(point.y - center.y)
            guard dx <= tolerance, dy <= tolerance else { return nil }
            return (handle, dx * dx + dy * dy)
        }
        return candidates.min { $0.1 < $1.1 }?.0
    }

    /// 边带命中：以边线为中心、宽 2 × halfWidth 的带；两侧重叠时取较近的一侧
    private static func bandHandle(at point: CGPoint, in box: CGRect, halfWidth: CGFloat) -> SelectionHandle? {
        let withinX = point.x >= box.minX - halfWidth && point.x <= box.maxX + halfWidth
        let withinY = point.y >= box.minY - halfWidth && point.y <= box.maxY + halfWidth
        let xSide = withinY ? nearerEdge(point.x, low: box.minX, high: box.maxX, halfWidth: halfWidth) : nil
        let ySide = withinX ? nearerEdge(point.y, low: box.minY, high: box.maxY, halfWidth: halfWidth) : nil
        return SelectionHandle.from(x: xSide, y: ySide)
    }

    private static func nearerEdge(_ value: CGFloat, low: CGFloat, high: CGFloat, halfWidth: CGFloat) -> EdgeSide? {
        let toLow = abs(value - low)
        let toHigh = abs(value - high)
        guard min(toLow, toHigh) <= halfWidth else { return nil }
        return toLow <= toHigh ? .low : .high
    }
}
