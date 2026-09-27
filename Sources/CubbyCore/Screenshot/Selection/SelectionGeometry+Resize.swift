import CoreGraphics

/// 手柄缩放（§2.5）
extension SelectionGeometry {
    /// 按手柄缩放，对边固定；不小于 minSize；不出 bounds
    ///
    /// 拖过对边时不翻转，而是停在 minSize（§5.1）。⇧（constrainSquare）：角手柄取两边中较小者、对角固定；
    /// 边手柄让另一边等长并以原中线居中，受该方向 bounds 空间限制。
    public static func resizing(
        _ rect: CGRect,
        handle: SelectionHandle,
        to point: CGPoint,
        constrainSquare: Bool,
        minSize: CGSize = SelectionGeometry.minSize,
        bounds: CGRect
    ) -> CGRect {
        let box = clamped(rect, to: bounds)
        let xSpan = Span(low: box.minX, high: box.maxX).resized(
            movesLow: handle.movesLeftEdge,
            movesHigh: handle.movesRightEdge,
            to: point.x,
            minLength: minSize.width,
            limit: Span(low: bounds.minX, high: bounds.maxX)
        )
        let ySpan = Span(low: box.minY, high: box.maxY).resized(
            movesLow: handle.movesTopEdge,
            movesHigh: handle.movesBottomEdge,
            to: point.y,
            minLength: minSize.height,
            limit: Span(low: bounds.minY, high: bounds.maxY)
        )
        let resized = CGRect(x: xSpan.low, y: ySpan.low, width: xSpan.length, height: ySpan.length)
        guard constrainSquare else { return resized }

        let minSide = max(minSize.width, minSize.height)
        if handle.isCorner {
            return squaredCorner(resized, handle: handle, minSide: minSide, bounds: bounds)
        }
        return squaredEdge(resized, original: box, handle: handle, minSide: minSide, bounds: bounds)
    }

    /// 从固定边朝拖动方向到 bounds 的可用空间。
    /// 输入比 minSize 还细且贴着 bounds 时，正方形边长不能超过它：与非 ⇧ 分支一致，「不出 bounds」优先于 minSize
    private static func room(_ rect: CGRect, handle: SelectionHandle, bounds: CGRect) -> (x: CGFloat, y: CGFloat) {
        (
            x: handle.movesLeftEdge ? rect.maxX - bounds.minX : bounds.maxX - rect.minX,
            y: handle.movesTopEdge ? rect.maxY - bounds.minY : bounds.maxY - rect.minY
        )
    }

    /// 角手柄正方形：边长取较小边，对角（固定角）不动
    private static func squaredCorner(_ rect: CGRect, handle: SelectionHandle, minSide: CGFloat, bounds: CGRect)
        -> CGRect
    {
        let limit = room(rect, handle: handle, bounds: bounds)
        let side = min(max(min(rect.width, rect.height), minSide), limit.x, limit.y)
        let x = handle.movesLeftEdge ? rect.maxX - side : rect.minX
        let y = handle.movesTopEdge ? rect.maxY - side : rect.minY
        return CGRect(x: x, y: y, width: side, height: side)
    }

    /// 边手柄正方形：另一边等长，以原矩形在该方向的中线居中
    private static func squaredEdge(
        _ rect: CGRect,
        original: CGRect,
        handle: SelectionHandle,
        minSide: CGFloat,
        bounds: CGRect
    ) -> CGRect {
        let horizontal = handle.movesLeftEdge || handle.movesRightEdge
        let dragged = horizontal ? rect.width : rect.height
        let middle = horizontal ? original.midY : original.midX
        let perpendicular =
            horizontal ? Span(low: bounds.minY, high: bounds.maxY) : Span(low: bounds.minX, high: bounds.maxX)
        let available = 2 * min(middle - perpendicular.low, perpendicular.high - middle)
        let limit = room(rect, handle: handle, bounds: bounds)
        let side = min(max(min(dragged, available), minSide), available, horizontal ? limit.x : limit.y)

        if horizontal {
            let x = handle.movesLeftEdge ? rect.maxX - side : rect.minX
            return CGRect(x: x, y: middle - side / 2, width: side, height: side)
        }
        let y = handle.movesTopEdge ? rect.maxY - side : rect.minY
        return CGRect(x: middle - side / 2, y: y, width: side, height: side)
    }
}

/// 一维区间 [low, high]
private struct Span {
    let low: CGFloat
    let high: CGFloat

    var length: CGFloat { high - low }

    /// 移动 low 或 high 到 value：另一端固定，长度不小于 minLength，不超出 limit
    func resized(movesLow: Bool, movesHigh: Bool, to value: CGFloat, minLength: CGFloat, limit: Span) -> Span {
        if movesLow {
            return Span(low: max(limit.low, min(value, high - minLength)), high: high)
        }
        if movesHigh {
            return Span(low: low, high: min(limit.high, max(value, low + minLength)))
        }
        return self
    }
}
