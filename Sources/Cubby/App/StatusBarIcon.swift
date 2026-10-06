import AppKit

/// 菜单栏图标：与 App 图标同构的「小格子」剪影（模板图，自动适配深浅色菜单栏）。
/// 正常状态：储物盒实心 + 右上格抽出卡片；暂停记录：储物盒空心、没有卡片。
/// 有新版本时右上角留出一个圆形缺口，强调色蓝点由 StatusItemUpdateBadge 叠在缺口里（模板图只能是单色）
enum StatusBarIcon {
    static let size = NSSize(width: 18, height: 18)
    /// 蓝点圆心（图标坐标，左下原点）与直径：与原型一致，略超出图标右上角
    static let badgeCenter = CGPoint(x: 16.5, y: 15.5)
    static let badgeDiameter: CGFloat = 7
    /// 蓝点四周擦出的留白，让它在任何菜单栏底色上都与图标分开
    static let badgeGap: CGFloat = 1.5

    static func image(paused: Bool, badged: Bool = false) -> NSImage {
        let image = NSImage(size: size, flipped: false) { _ in
            draw(paused: paused)
            if badged { clearBadgeNotch() }
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = UpdateCopy.statusItemAccessibility(paused: paused, updateAvailable: badged)
        return image
    }

    /// 擦除蓝点及其留白所在的圆
    private static func clearBadgeNotch() {
        guard let context = NSGraphicsContext.current else { return }
        let radius = badgeDiameter / 2 + badgeGap
        let notch = NSBezierPath(
            ovalIn: NSRect(
                x: badgeCenter.x - radius, y: badgeCenter.y - radius, width: radius * 2, height: radius * 2))
        context.saveGraphicsState()
        context.compositingOperation = .clear
        notch.fill()
        context.restoreGraphicsState()
    }

    private static func draw(paused: Bool) {
        NSColor.black.setStroke()
        NSColor.black.setFill()

        // 柜体
        let body = NSBezierPath(
            roundedRect: NSRect(x: 1.6, y: 1.6, width: 14.8, height: 10.6), xRadius: 2.6, yRadius: 2.6)
        body.lineWidth = 1.3
        body.stroke()

        // 2 × 2 储物格：右上格留给卡片
        let bins = [
            NSRect(x: 3.6, y: 3.5, width: 4.6, height: 2.9),
            NSRect(x: 9.8, y: 3.5, width: 4.6, height: 2.9),
            NSRect(x: 3.6, y: 7.4, width: 4.6, height: 2.9),
        ]
        for bin in bins {
            let path = NSBezierPath(roundedRect: bin, xRadius: 0.9, yRadius: 0.9)
            if paused {
                path.lineWidth = 0.9
                path.stroke()
            } else {
                path.fill()
            }
        }
        guard !paused else { return }
        drawCard()
    }

    /// 从右上格抽出、略微倾斜的卡片，四周擦出间隙以便与柜体分离
    private static func drawCard() {
        guard let context = NSGraphicsContext.current else { return }
        let transform = NSAffineTransform()
        transform.translateX(by: 12.1, yBy: 11.2)
        transform.rotate(byDegrees: -6)

        let card = NSBezierPath(
            roundedRect: NSRect(x: -2.2, y: -3.4, width: 4.4, height: 7.4), xRadius: 1.0, yRadius: 1.1)
        card.transform(using: transform as AffineTransform)

        // 擦除卡片周围 0.8pt，形成与柜体描边之间的留白
        context.saveGraphicsState()
        context.compositingOperation = .clear
        card.lineWidth = 1.6
        card.stroke()
        card.fill()
        context.restoreGraphicsState()

        card.fill()

        // 卡片上的「文字行」（镂空）
        context.saveGraphicsState()
        context.compositingOperation = .clear
        for y in [1.6, -0.2] {
            let line = NSBezierPath(
                roundedRect: NSRect(x: -1.3, y: y, width: 2.6, height: 0.8), xRadius: 0.4, yRadius: 0.4)
            line.transform(using: transform as AffineTransform)
            line.fill()
        }
        context.restoreGraphicsState()
    }
}
