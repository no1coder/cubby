import AppKit

/// 菜单栏图标：design/cubby-logo/svg/MenuBarIconTemplate.svg（100 单位网格，y 向下）的代码版，模板图自动适配深浅色菜单栏。
/// 正常状态：U 形托盘 + 前卡（-5°）+ 半透明后卡（+11°）；暂停记录：托盘 + 空心前卡、没有后卡。
/// 有新版本时右上角留出一个圆形缺口，强调色蓝点由 StatusItemUpdateBadge 叠在缺口里（模板图只能是单色）
enum StatusBarIcon {
    static let size = NSSize(width: 18, height: 18)
    /// 蓝点圆心（图标坐标，左下原点）与直径：与原型一致，略超出图标右上角
    static let badgeCenter = CGPoint(x: 16.5, y: 15.5)
    static let badgeDiameter: CGFloat = 7
    /// 蓝点四周擦出的留白，让它在任何菜单栏底色上都与图标分开
    static let badgeGap: CGFloat = 1.5

    /// 设计稿网格（100 单位）到 18pt 的缩放
    private static let scale = size.width / 100
    /// 后卡的不透明度（设计稿 fill-opacity）
    private static let backCardOpacity: CGFloat = 0.45
    /// 暂停时空心前卡的描边宽度（网格单位）
    private static let pausedStroke: CGFloat = 6

    static func image(paused: Bool, badged: Bool = false) -> NSImage {
        // 翻转坐标与 SVG 一致（y 向下）；旋转角度的正负也随之与 SVG 相同
        let image = NSImage(size: size, flipped: true) { _ in
            draw(paused: paused)
            if badged { clearBadgeNotch() }
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = UpdateCopy.statusItemAccessibility(paused: paused, updateAvailable: badged)
        return image
    }

    /// 擦除蓝点及其留白所在的圆（badgeCenter 是左下原点坐标，换算到翻转坐标）
    private static func clearBadgeNotch() {
        guard let context = NSGraphicsContext.current else { return }
        let radius = badgeDiameter / 2 + badgeGap
        let center = CGPoint(x: badgeCenter.x, y: size.height - badgeCenter.y)
        let notch = NSBezierPath(
            ovalIn: NSRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2))
        context.saveGraphicsState()
        context.compositingOperation = .clear
        notch.fill()
        context.restoreGraphicsState()
    }

    private static func draw(paused: Bool) {
        guard let context = NSGraphicsContext.current else { return }
        context.saveGraphicsState()
        defer { context.restoreGraphicsState() }
        let transform = NSAffineTransform()
        transform.scale(by: scale)
        transform.concat()

        if !paused {
            NSColor.black.withAlphaComponent(backCardOpacity).setFill()
            card(NSRect(x: 52, y: 18, width: 22, height: 34), degrees: 11).fill()
        }
        NSColor.black.setFill()
        NSColor.black.setStroke()
        let front = card(NSRect(x: 33, y: 24, width: 28, height: 46), degrees: -5)
        if paused {
            // 描边向内收半个线宽，外轮廓与实心前卡一致
            let inset = card(
                NSRect(x: 33, y: 24, width: 28, height: 46).insetBy(dx: pausedStroke / 2, dy: pausedStroke / 2),
                degrees: -5, radius: 5 - pausedStroke / 2)
            inset.lineWidth = pausedStroke
            inset.stroke()
        } else {
            front.fill()
        }
        tray().fill()
    }

    /// 绕自身中心旋转的圆角卡片（设计稿 rotate(角度 中心x 中心y)）
    private static func card(_ rect: NSRect, degrees: CGFloat, radius: CGFloat = 5) -> NSBezierPath {
        let path = NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius)
        let transform = NSAffineTransform()
        transform.translateX(by: rect.midX, yBy: rect.midY)
        transform.rotate(byDegrees: degrees)
        transform.translateX(by: -rect.midX, yBy: -rect.midY)
        path.transform(using: transform as AffineTransform)
        return path
    }

    /// U 形托盘：外圆角 18、内圆角 6、壁厚 12（设计稿 path）
    private static func tray() -> NSBezierPath {
        let path = NSBezierPath()
        path.move(to: NSPoint(x: 14, y: 42))
        path.line(to: NSPoint(x: 14, y: 62))
        path.appendArc(from: NSPoint(x: 14, y: 80), to: NSPoint(x: 32, y: 80), radius: 18)
        path.line(to: NSPoint(x: 68, y: 80))
        path.appendArc(from: NSPoint(x: 86, y: 80), to: NSPoint(x: 86, y: 62), radius: 18)
        path.line(to: NSPoint(x: 86, y: 42))
        path.line(to: NSPoint(x: 74, y: 42))
        path.line(to: NSPoint(x: 74, y: 62))
        path.appendArc(from: NSPoint(x: 74, y: 68), to: NSPoint(x: 68, y: 68), radius: 6)
        path.line(to: NSPoint(x: 32, y: 68))
        path.appendArc(from: NSPoint(x: 26, y: 68), to: NSPoint(x: 26, y: 62), radius: 6)
        path.line(to: NSPoint(x: 26, y: 42))
        path.close()
        return path
    }
}
