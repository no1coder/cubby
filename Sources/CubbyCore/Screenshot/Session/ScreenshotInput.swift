import CoreGraphics

/// 覆盖层输入换算中不依赖 AppKit 事件对象的部分
public enum ScreenshotInput {
    /// 滚轮 → `.scrolled(deltaY:)` 的点数：触控板 / 妙控鼠标直接用 scrollingDeltaY，惯性阶段丢弃（nil）；
    /// 行式滚轮每行换算 `ScreenshotReducer.scrollPointsPerLine` 点
    public static func scrollDelta(scrollingDeltaY: CGFloat, isPrecise: Bool, isMomentum: Bool) -> CGFloat? {
        guard !isMomentum else { return nil }
        return isPrecise ? scrollingDeltaY : scrollingDeltaY * ScreenshotReducer.scrollPointsPerLine
    }
}
