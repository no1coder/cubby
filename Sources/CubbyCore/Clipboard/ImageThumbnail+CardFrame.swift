import CoreGraphics

/// 列表卡片里图片框的宽高比：常见截图比例照原样，整张显示，不再裁成固定高度；
/// 过高（竖图、手机截图）或过扁（超宽横幅）的图，框夹在 4:3 到 3.5:1 之间，图片整张缩进框里
public extension ImageThumbnail {
    /// 框最高到 4:3（卡片宽约 348pt 时约 261pt 高）
    static let cardMinAspectRatio: CGFloat = 4.0 / 3.0
    /// 框最扁到 3.5:1（约 100pt 高）
    static let cardMaxAspectRatio: CGFloat = 3.5
    /// 尺寸无效时的框比例
    private static let fallbackAspectRatio: CGFloat = 1.6

    struct CardFrame: Equatable, Sendable {
        /// 框的宽 / 高
        public let aspectRatio: CGFloat
        /// 图片比例落在范围内：按 fill 铺满正好是整张图；否则按 fit 缩进框里
        public let showsWholeImageByFilling: Bool
    }

    static func cardFrame(width: Int, height: Int) -> CardFrame {
        guard width > 0, height > 0 else {
            return CardFrame(aspectRatio: fallbackAspectRatio, showsWholeImageByFilling: false)
        }
        let ratio = CGFloat(width) / CGFloat(height)
        let clamped = min(max(ratio, cardMinAspectRatio), cardMaxAspectRatio)
        return CardFrame(aspectRatio: clamped, showsWholeImageByFilling: clamped == ratio)
    }
}
