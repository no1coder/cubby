import CoreGraphics
import Foundation

/// 锥形箭头（macOS 标记同款）的几何；角度吸附见 ArrowGeometry+Snapping.swift
///
/// 形状（lineWidth = w）：尾宽 w × 0.5，箭杆两侧微凹地渐宽到颈部 w × 1.2；
/// 箭头长 clamp(w × 6, 10, 28)，翼宽（两翼之间的总宽）= 箭头长 × 0.8，两翼略向后掠。
/// 整个箭头是一条闭合的填充路径。
public enum ArrowGeometry {
    private static let tailWidthRatio: CGFloat = 0.5
    private static let neckWidthRatio: CGFloat = 1.2
    private static let headLengthRatio: CGFloat = 6
    private static let minHeadLength: CGFloat = 10
    private static let maxHeadLength: CGFloat = 28
    private static let headWidthRatio: CGFloat = 0.8
    /// 颈部位于距箭尖 箭头长 × 0.85 处，比两翼更靠前，形成后掠
    private static let neckPositionRatio: CGFloat = 0.85
    /// 箭杆侧边二次曲线控制点的半宽插值比例（< 0.5 即内凹）
    private static let concavity: CGFloat = 0.3
    /// 首尾重合时视为零长度
    private static let degenerateLength: CGFloat = 0.001

    /// 箭头长 = clamp(线宽 × 6, 10, 28)
    public static func headLength(for lineWidth: CGFloat) -> CGFloat {
        min(max(lineWidth * headLengthRatio, minHeadLength), maxHeadLength)
    }

    /// 两翼之间的总宽 = 箭头长 × 0.8
    public static func headWidth(for lineWidth: CGFloat) -> CGFloat {
        headLength(for: lineWidth) * headWidthRatio
    }

    /// 从尾（tail）到头（head）的锥形箭头填充路径
    /// - 长度短于箭头长时只画按比例缩小的箭头三角；零长度时为直径 = 线宽的圆点
    public static func taperedPath(from tail: CGPoint, to head: CGPoint, lineWidth: CGFloat) -> CGPath {
        let dx = head.x - tail.x
        let dy = head.y - tail.y
        let length = hypot(dx, dy)
        guard length > degenerateLength else {
            let radius = max(lineWidth, 1) / 2
            return CGPath(
                ellipseIn: CGRect(x: head.x - radius, y: head.y - radius, width: radius * 2, height: radius * 2),
                transform: nil
            )
        }
        let frame = ArrowFrame(tail: tail, direction: CGVector(dx: dx / length, dy: dy / length))
        let headLength = headLength(for: lineWidth)
        if length < headLength {
            return headOnlyPath(
                frame: frame, length: length, halfWidth: headWidth(for: lineWidth) / 2 * length / headLength)
        }
        return fullPath(frame: frame, length: length, lineWidth: lineWidth)
    }

    // MARK: - 路径构造

    private static func headOnlyPath(frame: ArrowFrame, length: CGFloat, halfWidth: CGFloat) -> CGPath {
        let path = CGMutablePath()
        path.move(to: frame.point(along: length, across: 0))
        path.addLine(to: frame.point(along: 0, across: halfWidth))
        path.addLine(to: frame.point(along: 0, across: -halfWidth))
        path.closeSubpath()
        return path
    }

    private static func fullPath(frame: ArrowFrame, length: CGFloat, lineWidth: CGFloat) -> CGPath {
        let headLength = headLength(for: lineWidth)
        let wingHalf = headWidth(for: lineWidth) / 2
        let tailHalf = lineWidth * tailWidthRatio / 2
        let neckHalf = lineWidth * neckWidthRatio / 2
        let baseAlong = length - headLength
        let neckAlong = length - headLength * neckPositionRatio
        let controlHalf = tailHalf + (neckHalf - tailHalf) * concavity
        let controlAlong = neckAlong / 2

        let path = CGMutablePath()
        path.move(to: frame.point(along: 0, across: tailHalf))
        path.addQuadCurve(
            to: frame.point(along: neckAlong, across: neckHalf),
            control: frame.point(along: controlAlong, across: controlHalf)
        )
        path.addLine(to: frame.point(along: baseAlong, across: wingHalf))
        path.addLine(to: frame.point(along: length, across: 0))
        path.addLine(to: frame.point(along: baseAlong, across: -wingHalf))
        path.addLine(to: frame.point(along: neckAlong, across: -neckHalf))
        path.addQuadCurve(
            to: frame.point(along: 0, across: -tailHalf),
            control: frame.point(along: controlAlong, across: -controlHalf)
        )
        path.closeSubpath()
        return path
    }
}

/// 以箭尾为原点、箭头方向为轴的局部坐标
private struct ArrowFrame {
    let tail: CGPoint
    let direction: CGVector

    /// along：沿箭头方向的距离；across：垂直方向的偏移（左手侧为正）
    func point(along: CGFloat, across: CGFloat) -> CGPoint {
        CGPoint(
            x: tail.x + direction.dx * along - direction.dy * across,
            y: tail.y + direction.dy * along + direction.dx * across
        )
    }
}
