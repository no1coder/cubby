import AppKit

/// 菜单栏图标右上角的强调色蓝点（docs/UPDATE-REMINDER-DESIGN.md U5）。
///
/// 为什么叠一个视图而不是画进图标：图标是模板图，系统按菜单栏深浅（以及按下、壁纸着色）统一着色，
/// 画进去的颜色会被变成单色；改成非模板图又会失去这些适配。所以图标保持模板图，只在右上角擦出缺口
/// （StatusBarIcon.image(badged:)），蓝点是叠在按钮上的独立小视图：颜色取系统强调色并随之变化，
/// 不接收点击、对读屏器隐藏（读屏名称由图标的 accessibilityDescription 注明「有新版本」）。
/// 通知用 selector 方式登记，视图释放时系统自动移除
final class StatusItemUpdateBadge: NSView {
    init(button: NSButton) {
        super.init(frame: .zero)
        wantsLayer = true
        isHidden = true
        setAccessibilityElement(false)
        button.addSubview(self)
        // 菜单栏高度变化（外接屏、刘海屏）时按钮尺寸会变，重新定位
        button.postsFrameChangedNotifications = true
        NotificationCenter.default.addObserver(
            self, selector: #selector(buttonFrameChanged), name: NSView.frameDidChangeNotification, object: button)
        NotificationCenter.default.addObserver(
            self, selector: #selector(systemColorsChanged), name: NSColor.systemColorsDidChangeNotification,
            object: nil)
        reposition()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    var isVisible: Bool {
        get { !isHidden }
        set {
            isHidden = !newValue
            if newValue { reposition() }
        }
    }

    // MARK: - 位置

    /// 按图标在按钮中实际绘制的位置换算蓝点的圆心与直径，兼顾按钮是否翻转与图标缩小
    private func reposition() {
        guard let button = superview as? NSButton else { return }
        let icon = StatusBarIcon.size
        let area = Self.imageArea(in: button)
        // 图标只会等比缩小（scaleProportionallyDown），在区域内居中
        let scale = min(1, area.width / icon.width, area.height / icon.height)
        let origin = CGPoint(x: area.midX - icon.width * scale / 2, y: area.midY - icon.height * scale / 2)
        let badgeY = button.isFlipped ? icon.height - StatusBarIcon.badgeCenter.y : StatusBarIcon.badgeCenter.y
        let center = CGPoint(
            x: origin.x + StatusBarIcon.badgeCenter.x * scale,
            y: origin.y + badgeY * scale
        )
        let diameter = StatusBarIcon.badgeDiameter * scale
        let rect = CGRect(x: center.x - diameter / 2, y: center.y - diameter / 2, width: diameter, height: diameter)
        frame = button.backingAlignedRect(rect, options: .alignAllEdgesNearest)
        layer?.cornerRadius = frame.width / 2
    }

    /// 图标的绘制区域：优先问按钮的 cell；取不到时用整个按钮（图标在其中居中）
    private static func imageArea(in button: NSButton) -> CGRect {
        if let rect = button.cell?.imageRect(forBounds: button.bounds), rect.width > 0, rect.height > 0 {
            return rect
        }
        return button.bounds
    }

    @objc private func buttonFrameChanged(_ notification: Notification) {
        reposition()
    }

    // MARK: - 颜色

    override var wantsUpdateLayer: Bool {
        true
    }

    override func updateLayer() {
        effectiveAppearance.performAsCurrentDrawingAppearance {
            layer?.backgroundColor = NSColor.controlAccentColor.cgColor
        }
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        needsDisplay = true
    }

    @objc private func systemColorsChanged(_ notification: Notification) {
        needsDisplay = true
    }

    /// 点击穿透到下面的按钮
    override func hitTest(_ point: NSPoint) -> NSView? {
        nil
    }
}
