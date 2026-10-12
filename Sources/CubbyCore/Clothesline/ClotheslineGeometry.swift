import Foundation
import CoreGraphics

/// 晾衣绳的几何（纯函数，便于测试）：绳子是一条两端固定、中间下垂的抛物线，
/// 照片按宽度均匀分布在绳上，夹子夹在绳子与照片顶边相交处
public enum ClotheslineGeometry {
    /// 两端固定点离窗口左右边缘的距离
    public static let anchorInset: CGFloat = 28
    /// 照片之间的最小间距
    public static let minimumGap: CGFloat = 18

    /// 绳子在 x 处的 y（向下为正，0 = 两端固定点的高度）：y = sag × (1 − (2t − 1)²)，t = x 在两端之间的比例
    public static func ropeDrop(at x: CGFloat, width: CGFloat, sag: CGFloat) -> CGFloat {
        let span = width - anchorInset * 2
        guard span > 0 else { return 0 }
        let t = min(max((x - anchorInset) / span, 0), 1)
        let u = 2 * t - 1
        return sag * (1 - u * u)
    }

    /// 各张照片中心的 x：在两端之间等分成 count 段，每张居中于自己那段。
    /// 段宽小于 photoWidth + minimumGap 时照片会重叠，调用方先用 photoWidth(count:width:maxWidth:) 缩小照片
    public static func centers(count: Int, width: CGFloat) -> [CGFloat] {
        guard count > 0 else { return [] }
        let span = max(width - anchorInset * 2, 0)
        let slot = span / CGFloat(count)
        return (0..<count).map { anchorInset + slot * (CGFloat($0) + 0.5) }
    }

    /// 每张照片的最大宽度：放得下时取 maxWidth，否则按段宽减去间距缩小（不小于 minimumWidth）
    public static func photoWidth(count: Int, width: CGFloat, maxWidth: CGFloat, minimumWidth: CGFloat = 56) -> CGFloat
    {
        guard count > 0 else { return maxWidth }
        let slot = max(width - anchorInset * 2, 0) / CGFloat(count)
        return max(min(maxWidth, slot - minimumGap), minimumWidth)
    }

    /// 照片按原始宽高比放进 maxWidth × maxHeight 的框内（不放大到超过框）
    public static func photoSize(pixelWidth: Int, pixelHeight: Int, maxWidth: CGFloat, maxHeight: CGFloat) -> CGSize {
        guard pixelWidth > 0, pixelHeight > 0 else { return CGSize(width: maxWidth, height: maxWidth * 0.75) }
        let ratio = CGFloat(pixelWidth) / CGFloat(pixelHeight)
        let width = min(maxWidth, maxHeight * ratio)
        return CGSize(width: width.rounded(), height: (width / ratio).rounded())
    }

    /// 每张照片的静止倾角（度）：由序号决定、左右交替，看起来像随手夹上去的，而且每次显示都一样
    public static func restingTilt(index: Int, maxDegrees: Double = 2.5) -> Double {
        let pattern: [Double] = [-0.6, 0.8, -0.3, 1.0, -0.9, 0.4, -0.7, 0.2]
        let wrapped = (index % pattern.count + pattern.count) % pattern.count
        return pattern[wrapped] * maxDegrees
    }

    /// 微风摆动（度）：每张照片相位不同的正弦；刚挂上的照片额外摆动，振幅按指数衰减
    public static func swing(time: Double, index: Int, sinceHung: Double?, amplitude: Double = 1.2) -> Double {
        let phase = Double(index) * 1.7
        let breeze = sin(time * 1.1 + phase) * amplitude
        guard let sinceHung, sinceHung >= 0 else { return breeze }
        let settle = 9 * exp(-sinceHung * 2.2) * sin(sinceHung * 9)
        return breeze + settle
    }
}
