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

    /// 停靠的边缘
    public enum DockEdge: Sendable {
        case right
        case bottom
    }

    /// 详情区与主面板之间的默认间距
    public static let detailGap: CGFloat = 8

    /// 停靠面板与屏幕可见区域边缘的留白（面板悬在边缘，四周仍有圆角与阴影，不是贴死的抽屉）
    public static let dockMargin: CGFloat = 8

    /// 停靠排布：右侧为整高侧栏（宽度取 size.width），底部为整宽横条（高度取 size.height）
    public static func docked(
        _ edge: DockEdge,
        size: CGSize,
        visibleFrame: CGRect,
        margin: CGFloat = dockMargin
    ) -> CGRect {
        let available = visibleFrame.insetBy(dx: margin, dy: margin)
        guard available.width > 0, available.height > 0 else { return visibleFrame }
        switch edge {
        case .right:
            let width = min(size.width, available.width)
            return CGRect(x: available.maxX - width, y: available.minY, width: width, height: available.height)
        case .bottom:
            let height = min(size.height, available.height)
            return CGRect(x: available.minX, y: available.minY, width: available.width, height: height)
        }
    }

    /// 详情区（预览 / 翻译卡）的位置。
    /// 浮动面板与右侧侧栏：放在旁边（优先左侧），顶部对齐，最高不超过 maxHeight 与面板高度；
    /// 底部横条：放在横条正上方并水平居中于 anchorX（选中卡片的中心，nil 时为横条中心），底部对齐、向上长高
    public static func detailFrame(
        width: CGFloat,
        height: CGFloat,
        host: CGRect,
        layout: PanelLayout,
        visibleFrame: CGRect,
        maxHeight: CGFloat,
        anchorX: CGFloat? = nil,
        gap: CGFloat = detailGap
    ) -> CGRect {
        switch layout {
        case .floating, .sidebar:
            let beside = frame(
                size: CGSize(width: width, height: host.height), beside: host, visibleFrame: visibleFrame)
            let fitted = min(height, beside.height, maxHeight)
            return CGRect(x: beside.minX, y: beside.maxY - fitted, width: beside.width, height: fitted)
        case .shelf:
            let room = max(visibleFrame.maxY - host.maxY - gap, 0)
            let fitted = CGSize(width: min(width, visibleFrame.width), height: min(height, maxHeight, room))
            let origin = CGPoint(x: (anchorX ?? host.midX) - fitted.width / 2, y: host.maxY + gap)
            return clamped(CGRect(origin: origin, size: fitted), in: visibleFrame)
        }
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
