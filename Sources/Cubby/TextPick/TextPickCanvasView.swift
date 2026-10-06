import AppKit
import CoreText
import CubbyCore

/// 拆词卡的词块区（docs/TEXT-PICK-DESIGN.md §3、§4）：AppKit 自绘，上千块也流畅——
/// 排版由 TextPickLayout 给出（控制器按文档版本缓存），绘制只画脏区内的行，字形按块懒加载缓存；
/// 详情区窗口从不成为 key（docs/DESIGN.md「实现约束」），所以接受 first mouse，悬停用 activeAlways 的跟踪区域。
/// 点选 / 拖选 / ⇧单击 / 自动滚动见 +Interaction，读屏元素见 +Accessibility
@MainActor
final class TextPickCanvasView: NSView {
    /// 拖选：按下时的选取、起点与方向（起点未选中 = 加选）
    struct Drag {
        let base: TextPickSelection
        let start: Int
        let adding: Bool
    }

    weak var controller: TextPickController?
    private(set) var layout: TextPickLayout?
    private(set) var tokens: [TextPickToken] = []
    private(set) var selection = TextPickSelection()
    /// 已显示的文档版本；变化时重新排版并播放打开动画
    private var version = -1
    private var layoutWidth: CGFloat = 0
    private var lines: [CTLine?] = []
    private var opening: OpeningAnimation?
    private var animationTimer: Timer?
    /// 新文档等到第一次带尺寸的绘制再开始打开动画（创建时视图还没有大小，算不出可见的行）
    private var needsOpeningAnimation = false

    var hovered: Int?
    var drag: Drag?
    /// 拖选中最后的指针位置（窗口坐标）：自动滚动时内容移动了，用它重新算指针下的块
    var lastDragLocation: CGPoint?
    var autoScrollTimer: Timer?
    var accessibilityTokens: [TextPickTokenElement]?

    override var isFlipped: Bool { true }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    /// 内容区左上角（词块坐标的原点）
    var contentOrigin: CGPoint {
        CGPoint(x: TextPickMetrics.contentHorizontal, y: TextPickMetrics.contentVertical)
    }

    // MARK: - 与控制器同步

    /// SwiftUI 更新时调用：文档版本变化则重新载入，选取变化则重绘
    func update(controller: TextPickController, version newVersion: Int, selection newSelection: TextPickSelection) {
        self.controller = controller
        if newVersion != version {
            reload(version: newVersion)
        }
        setSelection(newSelection)
    }

    func setSelection(_ newSelection: TextPickSelection) {
        guard newSelection != selection else { return }
        selection = newSelection
        needsDisplay = true
    }

    private func reload(version newVersion: Int) {
        version = newVersion
        tokens = controller?.document?.tokens ?? []
        lines = Array(repeating: nil, count: tokens.count)
        hovered = nil
        drag = nil
        accessibilityTokens = nil
        layout = nil
        layoutWidth = 0
        fitToClipView()
        scroll(.zero)
        stopOpeningAnimation()
        needsOpeningAnimation = !Motion.prefersReducedMotion
        needsDisplay = true
    }

    /// 宽度跟随滚动视图；高度为内容高度（至少铺满可见区域，空白处也能收到指针事件）
    func fitToClipView() {
        let clip = enclosingScrollView?.contentView.bounds.size ?? bounds.size
        // 还没有尺寸时不排版（宽度为 0 会把每块排成一行）
        guard clip.width > TextPickMetrics.contentHorizontal * 2 else { return }
        let width = clip.width - TextPickMetrics.contentHorizontal * 2
        if width != layoutWidth || layout == nil {
            layoutWidth = width
            layout = controller?.layout(width: width)
        }
        let content = layout.map(TextPickTypesetter.contentHeight(of:)) ?? 0
        let size = CGSize(width: clip.width, height: max(content, clip.height))
        if frame.size != size {
            setFrameSize(size)
        }
    }

    // MARK: - 绘制

    override func draw(_ dirtyRect: NSRect) {
        guard let layout, let context = NSGraphicsContext.current?.cgContext else { return }
        if needsOpeningAnimation {
            startOpeningAnimation()
        }
        let origin = contentOrigin
        let local = dirtyRect.offsetBy(dx: -origin.x, dy: -origin.y)
        let palette = TextPickChipPalette.current
        let now = CACurrentMediaTime()
        context.textMatrix = CGAffineTransform(scaleX: 1, y: -1)
        for row in layout.rowRange(intersecting: local) {
            let appearance = opening?.appearance(ofRow: row, at: now) ?? .shown
            guard appearance.alpha > 0 else { continue }
            for index in layout.rows[row].tokens {
                let frame = layout.frames[index].offsetBy(dx: origin.x, dy: origin.y)
                guard frame.intersects(dirtyRect) else { continue }
                drawChip(index, in: frame, context: context, palette: palette, appearance: appearance)
            }
        }
    }

    private func drawChip(
        _ index: Int, in frame: CGRect, context: CGContext, palette: TextPickChipPalette,
        appearance: OpeningAnimation.Appearance
    ) {
        let token = tokens[index]
        let isSelected = selection.contains(index)
        context.saveGState()
        defer { context.restoreGState() }
        appearance.apply(to: context, around: CGPoint(x: frame.midX, y: frame.midY))
        let radius = TextPickMetrics.chipRadius
        let path = CGPath(roundedRect: frame, cornerWidth: radius, cornerHeight: radius, transform: nil)
        context.addPath(path)
        context.setFillColor(palette.fill(isSelected: isSelected, isHovered: hovered == index))
        context.fillPath()
        if let stroke = palette.stroke, !isSelected {
            let inset = TextPickMetrics.contrastStrokeWidth / 2
            context.addPath(
                CGPath(
                    roundedRect: frame.insetBy(dx: inset, dy: inset), cornerWidth: radius - inset,
                    cornerHeight: radius - inset, transform: nil))
            context.setStrokeColor(stroke)
            context.setLineWidth(TextPickMetrics.contrastStrokeWidth)
            context.strokePath()
        }
        drawText(of: index, kind: token.kind, in: frame, context: context, color: palette.text(token.kind, isSelected))
    }

    private func drawText(of index: Int, kind: TextPickToken.Kind, in frame: CGRect, context: CGContext, color: CGColor)
    {
        let padding = TextPickTypesetter.horizontalPadding(for: kind)
        let available = frame.width - padding * 2
        let full = line(at: index)
        let width = CGFloat(CTLineGetTypographicBounds(full, nil, nil, nil))
        // 比一行还宽的块：截断并以省略号结尾（P5、§3）
        let line = width > available + 0.5 ? truncated(full, to: available, kind: kind) : full
        context.setFillColor(color)
        context.textPosition = CGPoint(
            x: frame.minX + padding, y: TextPickTypesetter.baseline(in: frame, kind: kind))
        CTLineDraw(line, context)
    }

    private func line(at index: Int) -> CTLine {
        if let cached = lines[index] { return cached }
        let created = TextPickTypesetter.line(for: tokens[index])
        lines[index] = created
        return created
    }

    private func truncated(_ line: CTLine, to width: CGFloat, kind: TextPickToken.Kind) -> CTLine {
        let ellipsis = TextPickTypesetter.line("\u{2026}", kind: kind)
        return CTLineCreateTruncatedLine(line, Double(max(width, 0)), .end, ellipsis) ?? line
    }

    /// 某块在视图坐标里的位置
    func chipFrame(_ index: Int) -> CGRect? {
        guard let layout, layout.frames.indices.contains(index) else { return nil }
        return layout.frames[index].offsetBy(dx: contentOrigin.x, dy: contentOrigin.y)
    }

    func redraw(_ index: Int?) {
        guard let index, let frame = chipFrame(index) else { return }
        setNeedsDisplay(frame.insetBy(dx: -1, dy: -1))
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        needsDisplay = true
    }

    // MARK: - 打开动画

    /// 词块按行依次淡入并从 0.92 放大到 1（只动可见的行），总时长不超过 0.3 秒；减弱动态效果时不做（§2）
    private func startOpeningAnimation() {
        needsOpeningAnimation = false
        guard let layout, !layout.rows.isEmpty, !visibleRect.isEmpty else { return }
        let local = visibleRect.offsetBy(dx: -contentOrigin.x, dy: -contentOrigin.y)
        let visible = layout.rowRange(intersecting: local)
        opening = OpeningAnimation(start: CACurrentMediaTime(), visibleRows: max(visible.count, 1))
        animationTimer = Self.repeatingTimer(interval: TextPickMetrics.animationInterval) { [weak self] in
            self?.animationTick()
        }
    }

    private func animationTick() {
        needsDisplay = true
        guard let opening, CACurrentMediaTime() - opening.start > TextPickMetrics.openingDuration else { return }
        stopOpeningAnimation()
    }

    private func stopOpeningAnimation() {
        opening = nil
        animationTimer?.invalidate()
        animationTimer = nil
    }

    /// 在 default 与 eventTracking 模式下运行的计时器（拖选时也要继续）
    static func repeatingTimer(interval: TimeInterval, _ tick: @escaping @MainActor () -> Void) -> Timer {
        let timer = Timer(timeInterval: interval, repeats: true) { _ in
            MainActor.assumeIsolated { tick() }
        }
        for mode in [RunLoop.Mode.default, .eventTracking] {
            RunLoop.main.add(timer, forMode: mode)
        }
        return timer
    }

    override func viewWillMove(toWindow newWindow: NSWindow?) {
        super.viewWillMove(toWindow: newWindow)
        guard newWindow == nil else { return }
        stopOpeningAnimation()
        stopAutoScroll()
    }
}
