import AppKit

/// 截图翻译的视觉常量（照搬原型 docs/prototypes/screenshot-translate.html 与设计文档 §1.1）
extension OverlayTokens {
    // MARK: - 译文层

    /// 每块译文到达时的淡入
    static let translationBlockFadeDuration: TimeInterval = 0.18
    /// 换语言时旧块在新块淡入结束后再移除
    static let translationReplaceDelay: Duration = .milliseconds(190)
    /// 整层显示 / 隐藏（按住空格、原文 | 译文）的淡变
    static let translationDisplayFadeDuration: TimeInterval = 0.12

    // MARK: - 流光（识别出的块在等译文）

    static let shimmerBaseAlpha: CGFloat = 0.07
    static let shimmerSweepAlpha: CGFloat = 0.38
    /// 扫光宽度占块宽的比例
    static let shimmerSweepWidth: CGFloat = 0.6
    static let shimmerCornerRadius: CGFloat = 3
    static let shimmerDuration: TimeInterval = 1.1
    /// 减弱动态效果时放慢
    static let shimmerReducedDuration: TimeInterval = 3

    // MARK: - 悬停看原文

    /// 停留多久出气泡
    static let translationHoverDelay: Duration = .milliseconds(400)
    /// 块描边：1.5 pt 强调色 0.65，与块留 1 pt
    static let translationOutlineWidth: CGFloat = 1.5
    static let translationOutlineOffset: CGFloat = 1
    static let translationOutlineAlpha: CGFloat = 0.65
    /// 气泡：最宽 360 pt，内边距 7 / 10 / 8，圆角 9，最多 6 行
    static let bubbleMaxWidth: CGFloat = 360
    static let bubbleTopPadding: CGFloat = 7
    static let bubbleHorizontalPadding: CGFloat = 10
    static let bubbleBottomPadding: CGFloat = 8
    static let bubbleCornerRadius: CGFloat = 9
    static let bubbleMaxLines = 6
    static let bubbleTitleSpacing: CGFloat = 2
    /// 与块的间距、与选区边缘的最小距离
    static let bubbleGap: CGFloat = 8
    static let bubbleMargin: CGFloat = 6
    static var bubbleBackground: NSColor {
        NSColor(srgbRed: 28 / 255, green: 28 / 255, blue: 32 / 255, alpha: 0.93)
    }
    static var bubbleText: NSColor {
        NSColor(srgbRed: 242 / 255, green: 242 / 255, blue: 244 / 255, alpha: 1)
    }
    static let bubbleTitleAlpha: CGFloat = 0.6
    static let bubbleShadowOpacity: Float = 0.4
    static let bubbleShadowRadius: CGFloat = 12

    // MARK: - 卷帘

    /// 2 pt 白线带阴影
    static let wipeLineWidth: CGFloat = 2
    static let wipeLineShadowOpacity: Float = 0.45
    static let wipeLineShadowRadius: CGFloat = 3
    /// 28 pt 圆形拖柄，命中区 36 pt；分隔线本身的命中带 18 pt
    static let wipeKnobDiameter: CGFloat = 28
    static let wipeKnobHitSize: CGFloat = 36
    static let wipeLineHitWidth: CGFloat = 18
    static let wipeKnobShadowOpacity: Float = 0.4
    static let wipeKnobShadowRadius: CGFloat = 2.5
    static var wipeKnobGlyph: NSColor {
        NSColor(srgbRed: 0.2, green: 0.2, blue: 0.2, alpha: 1)
    }
    static let wipeKnobGlyphWidth: CGFloat = 1.6
    /// 拖柄获得焦点时的强调色外环
    static let wipeFocusRingWidth: CGFloat = 3

    // MARK: - 小标签（卷帘两侧「原文」「译文」、按住空格时的「原文」）

    /// 11 pt semibold 白字，black 0.62 胶囊，内边距 4 × 8；距选区顶边 10 pt、距分隔线 10 pt
    static let chipBackgroundAlpha: CGFloat = 0.62
    static let chipHorizontalPadding: CGFloat = 8
    static let chipVerticalPadding: CGFloat = 4
    static let chipInset: CGFloat = 10
    /// 按住空格的提示距选区顶边
    static let peekChipTop: CGFloat = 12
}
