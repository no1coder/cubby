import CoreGraphics
import Foundation

/// 箭头的角度吸附：⇧ 强制 45°；不按 ⇧ 时方向落在 0° / 45° / 90°（及对称方向）±3° 内自动磁吸（评审 §7）
///
/// 吸附后的终点用精确算术得到（水平 / 竖直方向不经过 cos / sin，对角方向按 (dx ± dy) / 2 投影），
/// 所以吸附结果恰好在该方向上，覆盖层据此判定是否显示辅助线。
extension ArrowGeometry {
    /// 自动磁吸的角度容差（度）
    public static let magnetToleranceDegrees: CGFloat = 3

    /// 以 anchor 为起点把 point 吸附到最近的 45° 方向；长度取 point 在该方向上的投影（负投影取 0）
    public static func snapped45(from anchor: CGPoint, to point: CGPoint) -> CGPoint {
        let dx = point.x - anchor.x
        let dy = point.y - anchor.y
        guard dx != 0 || dy != 0 else { return anchor }
        return projected(anchor: anchor, dx: dx, dy: dy, octant: nearestOctant(dx: dx, dy: dy))
    }

    /// 不按 ⇧ 时的磁吸：与最近的 45° 方向相差不超过 toleranceDegrees 才吸附，否则原样返回
    public static func magnetized(
        from anchor: CGPoint,
        to point: CGPoint,
        toleranceDegrees: CGFloat = magnetToleranceDegrees
    ) -> CGPoint {
        let dx = point.x - anchor.x
        let dy = point.y - anchor.y
        guard dx != 0 || dy != 0 else { return point }
        let octant = nearestOctant(dx: dx, dy: dy)
        let offset = abs(atan2(dy, dx) - CGFloat(octant) * .pi / 4)
        // 跨 ±180° 的环绕（例如 179° 与 −180°）
        let difference = min(offset, 2 * .pi - offset) * 180 / .pi
        guard difference <= toleranceDegrees else { return point }
        return projected(anchor: anchor, dx: dx, dy: dy, octant: octant)
    }

    /// 从 from 指向 to 的方向是否恰好是 45° 的倍数（容许浮点误差）；长度为 0 时为 false
    public static func isOnSnapAngle(from: CGPoint, to: CGPoint) -> Bool {
        let dx = to.x - from.x
        let dy = to.y - from.y
        let length = hypot(dx, dy)
        guard length > 0 else { return false }
        let epsilon = length * 1e-9
        return abs(dx) <= epsilon || abs(dy) <= epsilon || abs(abs(dx) - abs(dy)) <= epsilon
    }

    // MARK: - 内部

    /// 最近的 45° 方向编号：0 = 0°（向右），2 = 90°（向下，y 向下的坐标系），4 = 180°……取值 −4...4
    private static func nearestOctant(dx: CGFloat, dy: CGFloat) -> Int {
        Int((atan2(dy, dx) / (.pi / 4)).rounded())
    }

    /// 投影到第 octant 个方向上（精确算术）
    private static func projected(anchor: CGPoint, dx: CGFloat, dy: CGFloat, octant: Int) -> CGPoint {
        let index = ((octant % 8) + 8) % 8
        // 各方向的 (sx, sy)：轴向为单位向量，对角为 (±1, ±1)（未归一化）
        let signs: [(CGFloat, CGFloat)] = [(1, 0), (1, 1), (0, 1), (-1, 1), (-1, 0), (-1, -1), (0, -1), (1, -1)]
        let (sx, sy) = signs[index]
        let isDiagonal = sx != 0 && sy != 0
        // 对角方向：投影长度 / √2 = (dx·sx + dy·sy) / 2，直接得到沿两轴的位移
        let along = max((dx * sx + dy * sy) / (isDiagonal ? 2 : 1), 0)
        return CGPoint(x: anchor.x + sx * along, y: anchor.y + sy * along)
    }
}
