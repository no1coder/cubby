import AppKit
import SwiftUI

/// 圆角令牌：所有圆角只从这里取值，保证嵌套元素的层级关系一致（见 docs/DESIGN.md）
enum Radius {
    /// 面板：macOS 26 Liquid Glass 为 22，更早系统为 14
    static var panel: CGFloat {
        if #available(macOS 26, *) { return 22 }
        return 14
    }
    /// 卡片、面板内横幅、帮助浮层、引导步骤卡
    static let card: CGFloat = 15
    /// 卡片内的图片缩略图（内缩 cardImageInset 后与卡片圆角同心）
    static let cardImage: CGFloat = 11
    /// 搜索框（36 高）与分类分段控件的底槽
    static let field: CGFloat = 12
    /// 顶栏图标按钮（34 见方）
    static let iconButton: CGFloat = 11
    /// 分段控件里浮起的选中胶囊、悬停工具条
    static let segment: CGFloat = 9
    /// 悬停工具条里的按钮（26 × 24）
    static let toolbarButton: CGFloat = 7
    /// 设置页分组（与系统 Form 分组一致）
    static let group: CGFloat = 10
    /// 输入框、图标按钮、录制框、预览中的块
    static let control: CGFloat = 8
    /// 卡片内缩略图、来源图标底板
    static let thumb: CGFloat = 6
    /// 键帽
    static let key: CGFloat = 5
    /// 图标底板圆角与边长之比（与 macOS 应用图标一致）
    static let iconRatio: CGFloat = 0.225
}

/// 字号阶梯：10 / 11 / 12 / 13 / 14 / 15 / 18 / 22，禁止使用其他字号
enum FontSize {
    /// 键帽
    static let caption2: CGFloat = 10
    /// 元信息、卡片头部、底栏
    static let caption: CGFloat = 11
    /// 分类、代码、次级按钮
    static let footnote: CGFloat = 12
    /// 链接标题、预览与设置里的正文
    static let body: CGFloat = 13
    /// 卡片正文（行高 1.5）、搜索
    static let callout: CGFloat = 14
    /// 标题
    static let title: CGFloat = 15
    /// 颜色卡的 HEX 值（等宽）
    static let display: CGFloat = 18
    /// 底部横条颜色方卡里居中的 HEX（等宽）
    static let shelfHex: CGFloat = 22
}

/// 面板布局常量
enum PanelMetrics {
    /// 面板内边距
    static let inset: CGFloat = 12
    /// 卡片间距
    static let cardSpacing: CGFloat = 8
    /// 卡片内边距：上下 12、左右 13
    static let cardPadding = EdgeInsets(top: 12, leading: 13, bottom: 12, trailing: 13)
    /// 颜色卡：左侧色块离边缘更近
    static let colorCardPadding = EdgeInsets(top: 10, leading: 10, bottom: 10, trailing: 13)
    /// 图片卡缩略图下方说明行的上下留白
    static let imageCaptionPadding = (top: CGFloat(9), bottom: CGFloat(10))
    /// 卡片头部一行与正文之间、正文各行块之间的间距
    static let cardRowSpacing: CGFloat = 7
    /// 图片卡的缩略图：距卡片上、左、右边缘 6，高 128
    static let cardImageInset: CGFloat = 6
    static let cardImageHeight: CGFloat = 128
    /// 主面板与预览面板的底栏高度（并排时分割线对齐）
    static let footerHeight: CGFloat = 38
    /// 搜索框高度
    static let controlHeight: CGFloat = 36
    /// 顶栏图标按钮边长
    static let iconButtonSize: CGFloat = 34
}

extension PanelMetrics {
    /// 来源应用图标边长（卡片头部一行）
    static let sourceIconSize: CGFloat = 18
    /// 固定右侧侧栏的宽度（高度为可见区域高度减去上下留白）
    static let sidebarWidth: CGFloat = 400
    /// 固定底部横条的高度（宽度为可见区域宽度减去左右留白）
    static let shelfHeight: CGFloat = 304
    /// 横条里的单行提醒：高 36，与上方间隔 6；横条每多一条提醒长高 42
    static let compactBannerHeight: CGFloat = 36
    static let compactBannerSpacing: CGFloat = 6
    static let shelfBannerHeight: CGFloat = compactBannerHeight + compactBannerSpacing
}

/// 预览面板布局常量
enum PreviewMetrics {
    static let width: CGFloat = 440
    /// 底部横条上方的详情区：与横条的间距、最大高度（还受横条上方剩余空间限制）
    static let shelfGap: CGFloat = 18
    static let shelfMaxHeight: CGFloat = 620
    /// 单个文件 / 短文本的内容高度（头 48 + 一行文件 60 + 脚 36 + 内边距 16），不留大片空白
    static let minHeight: CGFloat = 160
    /// 头部（来源 + 时间 + 类型徽标）高度
    static let headerHeight: CGFloat = 48
    /// 图片四周留白
    static let imageInset: CGFloat = 18
}

/// 动效令牌（见 docs/DESIGN.md「动效」）。开启「减弱动态效果」时去掉位移与滑动，只保留短淡入
enum Motion {
    /// 面板入场：透明度 0→1 并下落 entranceOffset
    static let panelEntrance: TimeInterval = 0.16
    static let entranceOffset: CGFloat = 8
    /// 停靠排布的入场：侧栏从右侧滑入、横条从底部升起这么远
    static let dockEntranceOffset: CGFloat = 24
    /// 面板关闭淡出；减弱动态效果时的入场淡入也用这个时长（不位移）
    static let fade: TimeInterval = 0.1
    /// 预览面板淡入与高度调整
    static let previewFade: TimeInterval = 0.14
    static let previewResize: TimeInterval = 0.16
    /// 帮助浮层淡入淡出、列表滚动到选中项
    static let overlayFade: TimeInterval = 0.15
    /// 横幅出现 / 消失、底栏轻提示切换
    static let layoutChange: TimeInterval = 0.2
    /// 分类胶囊滑动
    static let tabSlide: TimeInterval = 0.22
    /// 卡片选中态切换
    static let selection: TimeInterval = 0.12

    /// 减弱动态效果时返回 nil（状态直接切换，不做动画）
    static func animation(_ animation: Animation, reduceMotion: Bool) -> Animation? {
        reduceMotion ? nil : animation
    }

    /// AppKit 侧读取系统「减弱动态效果」
    @MainActor static var prefersReducedMotion: Bool {
        NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    }
}
