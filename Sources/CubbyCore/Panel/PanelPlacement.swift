import CoreGraphics

/// 计算面板位置（AppKit 坐标系，原点在左下角）。所有结果都完整位于可见区域内。
public enum PanelPlacement {
    /// 优先放在鼠标右下方；放不下时翻转到左侧 / 上方
    public static func frame(
        size: CGSize,
        mouse: CGPoint,
        visibleFrame: CGRect,
        offset: CGFloat = 12
    ) -> CGRect {
        let fitted = fit(size, in: visibleFrame)

        let preferredX = mouse.x + offset
        let x = preferredX + fitted.width > visibleFrame.maxX ? mouse.x - offset - fitted.width : preferredX

        let preferredY = mouse.y - offset - fitted.height
        let y = preferredY < visibleFrame.minY ? mouse.y + offset : preferredY

        return clamped(CGRect(origin: CGPoint(x: x, y: y), size: fitted), in: visibleFrame)
    }

    /// 放在锚点（如菜单栏图标）正下方并水平居中
    public static func frame(
        size: CGSize,
        below anchor: CGRect,
        visibleFrame: CGRect,
        gap: CGFloat = 6
    ) -> CGRect {
        let fitted = fit(size, in: visibleFrame)
        let origin = CGPoint(x: anchor.midX - fitted.width / 2, y: anchor.minY - gap - fitted.height)
        return clamped(CGRect(origin: origin, size: fitted), in: visibleFrame)
    }

    /// 在可见区域内居中（略偏上，符合视觉重心）
    public static func centered(size: CGSize, in visibleFrame: CGRect) -> CGRect {
        let fitted = fit(size, in: visibleFrame)
        let origin = CGPoint(
            x: visibleFrame.midX - fitted.width / 2,
            y: visibleFrame.midY - fitted.height / 2 + visibleFrame.height * 0.08
        )
        return clamped(CGRect(origin: origin, size: fitted), in: visibleFrame)
    }

    /// 放在已有面板旁边：优先左侧，放不下则右侧，顶部对齐
    public static func frame(
        size: CGSize,
        beside host: CGRect,
        visibleFrame: CGRect,
        gap: CGFloat = 8
    ) -> CGRect {
        let fitted = CGSize(width: min(size.width, visibleFrame.width), height: host.height)
        let leftX = host.minX - gap - fitted.width
        let x = leftX >= visibleFrame.minX ? leftX : host.maxX + gap
        return clamped(CGRect(origin: CGPoint(x: x, y: host.minY), size: fitted), in: visibleFrame)
    }

    private static func fit(_ size: CGSize, in visibleFrame: CGRect) -> CGSize {
        CGSize(width: min(size.width, visibleFrame.width), height: min(size.height, visibleFrame.height))
    }

    private static func clamped(_ rect: CGRect, in visibleFrame: CGRect) -> CGRect {
        CGRect(
            x: clamp(rect.minX, visibleFrame.minX, visibleFrame.maxX - rect.width),
            y: clamp(rect.minY, visibleFrame.minY, visibleFrame.maxY - rect.height),
            width: rect.width,
            height: rect.height
        )
    }

    private static func clamp(_ value: CGFloat, _ lower: CGFloat, _ upper: CGFloat) -> CGFloat {
        min(max(value, lower), upper)
    }
}
