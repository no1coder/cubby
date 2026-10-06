import AppKit
import CubbyCore

/// 拆词卡的版式常量（docs/TEXT-PICK-DESIGN.md §3，与原型 docs/prototypes/text-pick.html 一致）
enum TextPickMetrics {
    // MARK: 卡片

    /// 头部高度：来源图标 ·「拆词」· 副标题 · 「全选」
    static let headerHeight: CGFloat = 56
    /// 卡片最小高度（最大与主面板等高，超出时词块区滚动）
    static let minHeight: CGFloat = 236
    /// 头部 + 底栏 + 两条 0.5pt 分割线
    static var chromeHeight: CGFloat {
        headerHeight + PanelMetrics.footerHeight + 1
    }
    /// 头部与底栏的左右内边距
    static let barInset: CGFloat = 14
    /// 头部右侧的文字按钮「全选」：12pt，内边距 4 × 10，悬停 primary 0.08；置灰与胶囊按钮一致（0.5）
    static let textButtonVertical: CGFloat = 4
    static let textButtonHorizontal: CGFloat = 10
    static let textButtonHover: CGFloat = 0.08
    static let disabledOpacity: CGFloat = 0.5

    // MARK: 词块区

    /// 词块区内边距：上下 12、左右 14
    static let contentVertical: CGFloat = 12
    static let contentHorizontal: CGFloat = 14
    /// 排版宽度（详情区宽 440 减去左右内边距；滚动条为浮动样式，不占宽度）
    static var contentWidth: CGFloat {
        PreviewMetrics.width - contentHorizontal * 2
    }
    /// 块与块的横距、行距、空行多留的段距
    static let layout = TextPickLayout.Metrics(itemSpacing: 4, lineSpacing: 6, paragraphSpacing: 8)

    // MARK: 词块

    /// 词 13pt、标点 12pt
    static let wordFontSize = FontSize.body
    static let punctuationFontSize = FontSize.footnote
    /// 内边距：上下 3；词左右 7、标点左右 4
    static let chipVertical: CGFloat = 3
    static let wordHorizontal: CGFloat = 7
    static let punctuationHorizontal: CGFloat = 4
    static let chipRadius = Radius.thumb
    /// 底色 primary 0.07，悬停 0.13
    static let chipFill: CGFloat = 0.07
    static let chipHoverFill: CGFloat = 0.13
    /// 增强对比度：块加 1pt primary 0.25 描边（与卡片描边的 0.25 一致）
    static let contrastStrokeOpacity: CGFloat = 0.25
    static let contrastStrokeWidth: CGFloat = 1

    // MARK: 结果条

    /// 11pt，内边距 7 × 10，圆角 8，底色 primary 0.05，最多 2 行；与卡片左右各留 14、与底栏留 10
    static let resultFontSize = FontSize.caption
    static let resultVertical: CGFloat = 7
    static let resultHorizontal: CGFloat = 10
    static let resultRadius = Radius.control
    static let resultFill: CGFloat = 0.05
    static let resultMaxLines = 2
    static let resultBottom: CGFloat = 10
    /// 高度按两行预留：选取出现 / 消失时窗口不跳动
    static var resultReservedHeight: CGFloat {
        let font = NSFont.systemFont(ofSize: resultFontSize)
        let line = font.ascender - font.descender + font.leading
        return (line * CGFloat(resultMaxLines) + resultVertical * 2 + resultBottom).rounded(.up)
    }

    // MARK: 动效

    /// 打开动画：词块按行依次淡入并从 0.92 放大到 1，总时长不超过 0.3 秒（减弱动态效果时不做）
    static let openingDuration: TimeInterval = 0.3
    static let rowFadeDuration: TimeInterval = 0.16
    static let openingScale: CGFloat = 0.92
    /// 拖到上下边缘这么近时开始自动滚动；每帧最多滚这么多
    static let autoScrollEdge: CGFloat = 24
    static let autoScrollMaxStep: CGFloat = 14
    static let animationInterval: TimeInterval = 1.0 / 60

    // MARK: 卡片上的长按

    /// 长按 0.45 秒打开拆词卡；移动超过 4pt 取消（交给拖出）；按下时卡片缩到 0.985（P2、§2）
    static let longPressDuration: TimeInterval = 0.45
    static let longPressMaxDistance: CGFloat = 4
    static let pressedScale: CGFloat = 0.985

    // MARK: 后台分词

    /// 长文本在后台分词前先等这么久：按住方向键扫过多条长文本时，只拆停下的那条
    static let backgroundTokenizeDelay: Duration = .milliseconds(80)
}
