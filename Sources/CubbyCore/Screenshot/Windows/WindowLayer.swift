import CoreGraphics

/// 窗口层级规则：截图覆盖层放多高，以及哪些层级的窗口可以被悬停选中
///
/// 数值与 CGWindowLevelKey 一致：普通 0、浮动 3、模态面板 8、Dock 20、菜单栏 24、状态栏 25、
/// 弹出菜单 101、工具提示 / 覆盖层 102、屏保 1000、屏蔽层 2147483628；
/// 第三方输入法候选窗（2147483629）与光标（2147483630）在屏蔽层之上。
public enum WindowLayer {
    /// 覆盖层层级：系统屏蔽层，一出现就压住所有应用窗口（例如 Telegram 101 级的全屏看图窗口）；
    /// 只有第三方输入法候选窗与光标在其上
    public static let overlay = Int(CGShieldingWindowLevel())
    /// Dock（20）到状态栏（25）：系统界面，悬停时不算窗口，落在其上等于选整屏
    static let systemChrome = 20...25

    /// 应用的窗口（含聊天软件的看图窗口、置顶小窗等浮动窗口）可以被悬停选中；
    /// 负层级（桌面、通知中心）、Dock / 菜单栏 / 状态栏，以及不低于覆盖层的窗口（输入法候选窗、光标）除外
    public static func isSelectable(_ layer: Int) -> Bool {
        layer >= 0 && layer < overlay && !systemChrome.contains(layer)
    }
}
