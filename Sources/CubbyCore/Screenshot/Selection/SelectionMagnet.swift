import CoreGraphics

/// 选区边缘磁吸（评审 §7）：创建、缩放、移动选区时，边距离窗口边缘或屏幕边缘不超过 6 pt 就吸附过去。
/// 按住 ⌘ 临时关闭（由 reducer 判断，这里只做几何）。
///
/// 只吸附「在同一带内」的窗口边：竖直边只在窗口的纵向范围（外扩阈值）与选区的纵向范围重叠时参与，
/// 横向边同理——远处窗口的延长线不会把选区「吸」过去，避免黏滞感。屏幕四边总是参与。
public enum SelectionMagnet {
    /// 吸附距离（点）
    public static let threshold: CGFloat = 6

    /// 一条吸附线：位置 + 沿线方向的有效范围
    struct Guide: Equatable {
        let position: CGFloat
        let span: ClosedRange<CGFloat>
    }

    /// 某块屏幕上的全部吸附线：vertical 为竖直线（x 位置），horizontal 为横线（y 位置）
    struct Guides: Equatable {
        let vertical: [Guide]
        let horizontal: [Guide]

        /// 屏幕四边 + 与该屏相交的普通窗口的四边
        init(screen: CaptureScreen, topology: ScreenTopology) {
            let screenFrame = screen.frame
            var vertical = [
                Guide(position: screenFrame.minX, span: screenFrame.minY...screenFrame.maxY),
                Guide(position: screenFrame.maxX, span: screenFrame.minY...screenFrame.maxY),
            ]
            var horizontal = [
                Guide(position: screenFrame.minY, span: screenFrame.minX...screenFrame.maxX),
                Guide(position: screenFrame.maxY, span: screenFrame.minX...screenFrame.maxX),
            ]
            for window in WindowHitTester.eligibleWindows(in: topology) {
                let frame = window.frame.standardized.intersection(screenFrame)
                guard !frame.isNull, !frame.isEmpty else { continue }
                vertical += [frame.minX, frame.maxX].map { Guide(position: $0, span: frame.minY...frame.maxY) }
                horizontal += [frame.minY, frame.maxY].map { Guide(position: $0, span: frame.minX...frame.maxX) }
            }
            self.vertical = vertical
            self.horizontal = horizontal
        }
    }

    // MARK: - 吸附

    /// 创建选区：起点与光标分别吸附（fromCenter 时起点是中心，不吸附）；rect 为未吸附时的选区，用于判断同带
    static func snappedCorners(
        anchor: CGPoint,
        cursor: CGPoint,
        fromCenter: Bool,
        guides: Guides
    ) -> (anchor: CGPoint, cursor: CGPoint) {
        let rect = CGRect(
            x: min(anchor.x, cursor.x), y: min(anchor.y, cursor.y),
            width: abs(cursor.x - anchor.x), height: abs(cursor.y - anchor.y))
        let snap = { (point: CGPoint) in
            CGPoint(
                x: snapped(point.x, to: guides.vertical, band: rect.minY...rect.maxY),
                y: snapped(point.y, to: guides.horizontal, band: rect.minX...rect.maxX)
            )
        }
        let newAnchor = fromCenter ? anchor : snap(anchor)
        let snappedCursor = snap(cursor)
        // 两端吸到同一条线会把选区压扁（松开时变成「单击选中窗口」）：该轴上光标不吸附
        let minimum = SelectionGeometry.minSize
        let newCursor = CGPoint(
            x: abs(snappedCursor.x - newAnchor.x) < minimum.width ? cursor.x : snappedCursor.x,
            y: abs(snappedCursor.y - newAnchor.y) < minimum.height ? cursor.y : snappedCursor.y
        )
        return (newAnchor, newCursor)
    }

    /// 缩放：只吸附被拖动的边；吸附后仍不小于 minSize，否则该边保持原样
    static func snappedEdges(_ rect: CGRect, handle: SelectionHandle, minSize: CGSize, guides: Guides) -> CGRect {
        let box = rect.standardized
        var minX = box.minX
        var maxX = box.maxX
        var minY = box.minY
        var maxY = box.maxY
        let vertical = box.minY...box.maxY
        let horizontal = box.minX...box.maxX
        if handle.movesLeftEdge {
            minX = acceptable(snapped(minX, to: guides.vertical, band: vertical), fallback: minX) {
                maxX - $0 >= minSize.width
            }
        }
        if handle.movesRightEdge {
            maxX = acceptable(snapped(maxX, to: guides.vertical, band: vertical), fallback: maxX) {
                $0 - minX >= minSize.width
            }
        }
        if handle.movesTopEdge {
            minY = acceptable(snapped(minY, to: guides.horizontal, band: horizontal), fallback: minY) {
                maxY - $0 >= minSize.height
            }
        }
        if handle.movesBottomEdge {
            maxY = acceptable(snapped(maxY, to: guides.horizontal, band: horizontal), fallback: maxY) {
                $0 - minY >= minSize.height
            }
        }
        return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }

    /// 移动：两条竖直边中离吸附线最近的一条决定横向位移，横向边同理；尺寸不变
    static func snappedOffset(_ rect: CGRect, guides: Guides) -> CGRect {
        let box = rect.standardized
        let dx = nearestShift([box.minX, box.maxX], to: guides.vertical, band: box.minY...box.maxY)
        let dy = nearestShift([box.minY, box.maxY], to: guides.horizontal, band: box.minX...box.maxX)
        return box.offsetBy(dx: dx, dy: dy)
    }

    // MARK: - 内部

    /// 阈值内最近的同带吸附线位置；没有则原值
    static func snapped(_ value: CGFloat, to guides: [Guide], band: ClosedRange<CGFloat>) -> CGFloat {
        value + nearestShift([value], to: guides, band: band)
    }

    /// 若干条边到各自最近吸附线的位移中，绝对值最小的一个（阈值内）；没有则 0
    private static func nearestShift(_ edges: [CGFloat], to guides: [Guide], band: ClosedRange<CGFloat>) -> CGFloat {
        var best: CGFloat = 0
        var bestDistance = CGFloat.infinity
        for guide in guides where overlaps(guide.span, band) {
            for edge in edges {
                let shift = guide.position - edge
                if abs(shift) <= threshold && abs(shift) < bestDistance {
                    best = shift
                    bestDistance = abs(shift)
                }
            }
        }
        return best
    }

    /// 吸附线的有效范围外扩阈值后与选区的范围重叠
    private static func overlaps(_ span: ClosedRange<CGFloat>, _ band: ClosedRange<CGFloat>) -> Bool {
        span.lowerBound - threshold <= band.upperBound && band.lowerBound <= span.upperBound + threshold
    }

    private static func acceptable(_ value: CGFloat, fallback: CGFloat, _ isValid: (CGFloat) -> Bool) -> CGFloat {
        isValid(value) ? value : fallback
    }
}
