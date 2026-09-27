import AppKit
import CubbyCore

/// 黑色半透明胶囊里的小标签（卷帘两侧「原文」「译文」、按住空格时的「原文 · 松开空格回到译文」）
final class OverlayChipView: OverlayPassthroughView {
    private let label = NSTextField(labelWithString: "")

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = NSColor.black.withAlphaComponent(OverlayTokens.chipBackgroundAlpha).cgColor
        layer?.cornerCurve = .continuous
        label.font = NSFont.systemFont(ofSize: FontSize.caption, weight: .semibold)
        label.textColor = .white
        addSubview(label)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    var text: String {
        get { label.stringValue }
        set {
            label.stringValue = newValue
            // intrinsicContentSize 取的是小数宽度，按它原样设宽会被裁掉最后一个字形（实测「Original」显示成「Origina」）；
            // 向上取整并留 1 pt 余量
            let fitting = label.fittingSize
            let size = CGSize(width: fitting.width.rounded(.up) + 1, height: fitting.height.rounded(.up))
            label.frame = CGRect(
                x: OverlayTokens.chipHorizontalPadding, y: OverlayTokens.chipVerticalPadding, width: size.width,
                height: size.height)
            setFrameSize(
                CGSize(
                    width: (size.width + OverlayTokens.chipHorizontalPadding * 2).rounded(.up),
                    height: (size.height + OverlayTokens.chipVerticalPadding * 2).rounded(.up)))
            layer?.cornerRadius = frame.height / 2
        }
    }
}

/// 卷帘分隔线（原型 #divider）：2 pt 白线 + 阴影、28 pt 圆形拖柄（‹ ›）、顶部两侧「原文」「译文」。
/// 视图铺满选区，只有分隔线附近 18 pt 与拖柄 36 pt 见方接收鼠标（拖柄优先于其他指针操作）；
/// 拖动回报全局点 x；VoiceOver 下是可增减的滑块
final class OverlayWipeDivider: NSView {
    /// 拖动到全局点 x
    var onMove: ((CGFloat) -> Void)?
    /// VoiceOver 增减（true = 向右）
    var onStep: ((Bool) -> Void)?

    private let line = CALayer()
    private let knob = CALayer()
    private let chevrons = CAShapeLayer()
    private let originalChip = OverlayChipView(frame: .zero)
    private let translationChip = OverlayChipView(frame: .zero)
    /// 分隔线在本视图中的 x（视图坐标）
    private var lineX: CGFloat = 0
    /// 选区左边缘的全局 x（视图坐标 ↔ 全局点）
    private var globalMinX: CGFloat = 0
    private var fraction: CGFloat = 0.5

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        configureLayers()
        originalChip.text = TranslationBarText.original
        translationChip.text = TranslationBarText.translation
        addSubview(originalChip)
        addSubview(translationChip)
        isHidden = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    override var isFlipped: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    private func configureLayers() {
        line.backgroundColor = NSColor.white.cgColor
        line.shadowColor = NSColor.black.cgColor
        line.shadowOpacity = OverlayTokens.wipeLineShadowOpacity
        line.shadowRadius = OverlayTokens.wipeLineShadowRadius
        line.shadowOffset = .zero
        knob.backgroundColor = NSColor.white.cgColor
        knob.cornerRadius = OverlayTokens.wipeKnobDiameter / 2
        knob.shadowColor = NSColor.black.cgColor
        knob.shadowOpacity = OverlayTokens.wipeKnobShadowOpacity
        knob.shadowRadius = OverlayTokens.wipeKnobShadowRadius
        knob.shadowOffset = CGSize(width: 0, height: -1)
        chevrons.fillColor = nil
        chevrons.strokeColor = OverlayTokens.wipeKnobGlyph.cgColor
        chevrons.lineWidth = OverlayTokens.wipeKnobGlyphWidth
        chevrons.lineCap = .round
        chevrons.lineJoin = .round
        knob.addSublayer(chevrons)
        layer?.addSublayer(line)
        layer?.addSublayer(knob)
    }

    /// frame：选区（视图坐标）；x：分隔线的全局点 x；selectionMinX：选区左边缘的全局 x
    func show(frame: CGRect, lineX x: CGFloat, selectionMinX: CGFloat, isFocused: Bool) {
        self.frame = frame
        globalMinX = selectionMinX
        lineX = x - selectionMinX
        fraction = frame.width > 0 ? lineX / frame.width : 0.5
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        let width = OverlayTokens.wipeLineWidth
        line.frame = CGRect(x: lineX - width / 2, y: 0, width: width, height: frame.height)
        let diameter = OverlayTokens.wipeKnobDiameter
        knob.frame = CGRect(
            x: lineX - diameter / 2, y: (frame.height - diameter) / 2, width: diameter, height: diameter)
        knob.borderWidth = isFocused ? OverlayTokens.wipeFocusRingWidth : 0
        knob.borderColor = OverlayColors.accent.cgColor
        chevrons.frame = knob.bounds
        chevrons.path = Self.chevronPath(in: knob.bounds)
        CATransaction.commit()
        let inset = OverlayTokens.chipInset
        originalChip.setFrameOrigin(CGPoint(x: lineX - inset - originalChip.frame.width, y: inset))
        translationChip.setFrameOrigin(CGPoint(x: lineX + inset, y: inset))
        // 选区太矮时标签会压住拖柄：放不下就不显示
        let fits = inset + originalChip.frame.height + inset / 2 <= knob.frame.minY
        originalChip.isHidden = !fits
        translationChip.isHidden = !fits
        isHidden = false
    }

    /// ‹ ›：两个 V 形，拖柄中心左右各一
    private static func chevronPath(in bounds: CGRect) -> CGPath {
        let path = CGMutablePath()
        let center = CGPoint(x: bounds.midX, y: bounds.midY)
        for side: CGFloat in [-1, 1] {
            path.move(to: CGPoint(x: center.x + side * 2.5, y: center.y - 4.5))
            path.addLine(to: CGPoint(x: center.x + side * 7, y: center.y))
            path.addLine(to: CGPoint(x: center.x + side * 2.5, y: center.y + 4.5))
        }
        return path
    }

    /// 分隔线的命中带或拖柄的命中区（视图坐标）
    func isHandle(at point: CGPoint) -> Bool {
        guard !isHidden, bounds.contains(point) else { return false }
        let knobHalf = OverlayTokens.wipeKnobHitSize / 2
        let onKnob = abs(point.x - lineX) <= knobHalf && abs(point.y - bounds.midY) <= knobHalf
        return onKnob || abs(point.x - lineX) <= OverlayTokens.wipeLineHitWidth / 2
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        guard let superview else { return nil }
        return isHandle(at: convert(point, from: superview)) ? self : nil
    }

    override func mouseDown(with event: NSEvent) { move(with: event) }
    override func mouseDragged(with event: NSEvent) { move(with: event) }

    private func move(with event: NSEvent) {
        onMove?(globalMinX + convert(event.locationInWindow, from: nil).x)
    }

    // MARK: - 无障碍

    override func isAccessibilityElement() -> Bool { true }
    override func accessibilityRole() -> NSAccessibility.Role? { .slider }
    override func accessibilityLabel() -> String? { TranslationBarText.wipeLabel }
    override func accessibilityValue() -> Any? { NSNumber(value: Int((fraction * 100).rounded())) }
    override func accessibilityPerformIncrement() -> Bool {
        onStep?(true)
        return true
    }
    override func accessibilityPerformDecrement() -> Bool {
        onStep?(false)
        return true
    }
}

#if DEBUG
extension OverlayWipeDivider {
    /// 仅调试构建（e2e）：拖柄中心（本视图坐标）
    var debugKnobCenter: CGPoint {
        CGPoint(x: lineX, y: bounds.midY)
    }
}
#endif

/// 悬停看原文的气泡（原型 #bubble）：标题「原文」+ 最多 6 行原文，跟随块而不是指针
final class TranslationBubbleView: OverlayPassthroughView {
    private let title = NSTextField(labelWithString: "")
    private let body = NSTextField(wrappingLabelWithString: "")

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = OverlayTokens.bubbleBackground.cgColor
        layer?.cornerRadius = OverlayTokens.bubbleCornerRadius
        layer?.cornerCurve = .continuous
        layer?.borderWidth = 0.5
        layer?.borderColor = NSColor.white.withAlphaComponent(0.14).cgColor
        layer?.shadowColor = NSColor.black.cgColor
        layer?.shadowOpacity = OverlayTokens.bubbleShadowOpacity
        layer?.shadowRadius = OverlayTokens.bubbleShadowRadius
        title.font = NSFont.systemFont(ofSize: FontSize.caption2, weight: .semibold)
        title.textColor = NSColor.white.withAlphaComponent(OverlayTokens.bubbleTitleAlpha)
        title.stringValue = TranslationBarText.bubbleTitle
        body.font = NSFont.systemFont(ofSize: FontSize.footnote)
        body.textColor = OverlayTokens.bubbleText
        body.maximumNumberOfLines = OverlayTokens.bubbleMaxLines
        body.lineBreakMode = .byTruncatingTail
        body.cell?.truncatesLastVisibleLine = true
        addSubview(title)
        addSubview(body)
        isHidden = true
        setAccessibilityElement(true)
        setAccessibilityRole(.staticText)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    /// block、selection、bounds（整屏）为视图坐标：放在块上方（可以伸出选区），屏幕上方放不下时放下方；
    /// 横向从块的左边开始，夹在选区与屏幕内
    func show(_ text: String, block: CGRect, selection: CGRect, within bounds: CGRect) {
        let padding = OverlayTokens.bubbleHorizontalPadding
        let maxText = OverlayTokens.bubbleMaxWidth - padding * 2
        body.stringValue = text
        let titleSize = title.intrinsicContentSize
        let bodySize = Self.textSize(text, font: body.font, maxWidth: maxText)
        let textWidth = min(max(bodySize.width, titleSize.width), maxText).rounded(.up)
        let top = OverlayTokens.bubbleTopPadding
        title.frame = CGRect(x: padding, y: top, width: textWidth, height: titleSize.height)
        let bodyTop = title.frame.maxY + OverlayTokens.bubbleTitleSpacing
        body.frame = CGRect(x: padding, y: bodyTop, width: textWidth, height: bodySize.height.rounded(.up))
        let size = CGSize(width: textWidth + padding * 2, height: body.frame.maxY + OverlayTokens.bubbleBottomPadding)
        let gap = OverlayTokens.bubbleGap
        let margin = OverlayTokens.bubbleMargin
        let above = block.minY - gap - size.height
        let y = above >= bounds.minY + margin ? above : block.maxY + gap
        let inSelection = min(max(block.minX, selection.minX + margin), selection.maxX - size.width - margin)
        let x = min(max(inSelection, bounds.minX + margin), bounds.maxX - size.width - margin)
        frame = CGRect(origin: CGPoint(x: x.rounded(), y: y.rounded()), size: size)
        setAccessibilityValue(text)
        isHidden = false
    }

    /// 原文排版后的尺寸：宽度不超过 maxWidth，高度最多 6 行（多出的由标签截断为省略号）
    private static func textSize(_ text: String, font: NSFont?, maxWidth: CGFloat) -> CGSize {
        let font = font ?? NSFont.systemFont(ofSize: FontSize.footnote)
        let bounds = (text as NSString).boundingRect(
            with: CGSize(width: maxWidth, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading], attributes: [.font: font])
        let lineHeight = NSLayoutManager().defaultLineHeight(for: font)
        let height = min(bounds.height, lineHeight * CGFloat(OverlayTokens.bubbleMaxLines))
        // 标签自身左右各有 2 pt 的内边距
        return CGSize(width: (bounds.width + 4).rounded(.up), height: height.rounded(.up))
    }

    #if DEBUG
    /// 仅调试构建（e2e）：显示中的原文
    var debugText: String? {
        isHidden ? nil : body.stringValue
    }
    #endif
}
