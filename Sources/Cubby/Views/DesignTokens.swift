import AppKit
import SwiftUI

/// 圆角令牌：所有圆角只从这里取值，保证嵌套元素的层级关系一致（见 docs/DESIGN.md）
enum Radius {
    /// 面板：macOS 26 Liquid Glass 为 18，更早系统为 14
    static var panel: CGFloat {
        if #available(macOS 26, *) { return 18 }
        return 14
    }
    /// 卡片、面板内横幅、帮助浮层、引导步骤卡
    static let card: CGFloat = 12
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

/// 字号阶梯：10 / 11 / 12 / 13 / 14 / 15，禁止使用其他字号
enum FontSize {
    static let caption2: CGFloat = 10
    static let caption: CGFloat = 11
    static let footnote: CGFloat = 12
    static let body: CGFloat = 13
    static let callout: CGFloat = 14
    static let title: CGFloat = 15
}

/// 面板布局常量
enum PanelMetrics {
    /// 面板内边距
    static let inset: CGFloat = 12
    /// 卡片间距
    static let cardSpacing: CGFloat = 8
    /// 主面板与预览面板的底栏高度（并排时分割线对齐）
    static let footerHeight: CGFloat = 36
    /// 控件高度（搜索框、图标按钮）
    static let controlHeight: CGFloat = 32
}

extension PanelMetrics {
    /// 来源应用图标边长（卡片与预览头部一致）
    static let sourceIconSize: CGFloat = 20
}

/// 预览面板布局常量
enum PreviewMetrics {
    static let width: CGFloat = 440
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
