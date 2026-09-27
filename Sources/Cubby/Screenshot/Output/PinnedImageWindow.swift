import AppKit
import Carbon.HIToolbox

/// 贴图窗口（设计文档 §2.9）：置顶、不激活应用、以 1:1 出现在截图原位。
/// 拖动移动；滚轮 / 捏合以光标为锚点缩放；⌘C 复制、⌘S 存储、⌘0 回到 1:1；双击、Esc、⌘W 关闭；右键菜单。
/// 动作（复制、存储、关闭）通过闭包交给 PinnedImageController，窗口本身只管呈现与交互
@MainActor
final class PinnedImageWindow: NSPanel {
    /// 缩放范围 10%–400%
    static let zoomRange: ClosedRange<CGFloat> = 0.1...4
    /// 右键菜单中的不透明度选项
    static let opacityOptions: [CGFloat] = [1, 0.8, 0.6, 0.4]
    /// 滚轮每格缩放倍数
    private static let wheelStep: CGFloat = 1.05
    /// 触控板等精确滚动：每累计这么多点相当于滚轮一格
    private static let preciseDeltaPerStep: CGFloat = 8
    /// 缩小后较短边至少保留的点数：再小就很难再悬停操作
    private static let minimumSide: CGFloat = 24

    let image: CGImage
    /// 1:1 时的点尺寸
    let naturalSize: CGSize
    private(set) var zoom: CGFloat = 1

    var onCopy: (() -> Void)?
    var onSave: (() -> Void)?
    var onClose: (() -> Void)?

    private let zoomIndicator = PinnedZoomIndicator()

    /// - Parameter frame: AppKit 屏幕坐标下的初始位置，尺寸即 1:1 的点尺寸
    init(image: CGImage, frame: CGRect) {
        self.image = image
        self.naturalSize = frame.size
        super.init(
            contentRect: frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        isFloatingPanel = true
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        isOpaque = false
        backgroundColor = .clear
        // 阴影按内容的透明度计算：内容视图做了圆角裁剪，阴影随之为圆角
        hasShadow = true
        animationBehavior = .none
        // 拖动由内容视图调用 performDrag 实现，才能同时识别双击
        isMovableByWindowBackground = false

        let content = PinnedImageView(image: image)
        content.pinWindow = self
        contentView = content
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    /// 显示在最前但不抢键盘焦点：用户通常还要在原来的应用里继续输入
    func present() {
        orderFrontRegardless()
        // 内容首次绘制后再计算阴影形状
        Task { @MainActor [weak self] in self?.invalidateShadow() }
    }

    // MARK: - 缩放

    /// 较短边不小于 minimumSide；原图本身很小时至少允许 1:1
    private var minimumZoom: CGFloat {
        let shortSide = max(min(naturalSize.width, naturalSize.height), 1)
        return min(1, max(Self.zoomRange.lowerBound, Self.minimumSide / shortSide))
    }

    /// 以 anchor（AppKit 屏幕坐标）为不动点缩放到 newZoom，并显示百分比
    func setZoom(_ newZoom: CGFloat, anchor: CGPoint) {
        let clamped = min(max(newZoom, minimumZoom), Self.zoomRange.upperBound)
        defer { zoomIndicator.show(percentText, over: self) }
        guard abs(clamped - zoom) > 0.0001 else { return }

        let old = frame
        let size = CGSize(width: naturalSize.width * clamped, height: naturalSize.height * clamped)
        // 锚点在窗口内的相对位置保持不变
        let relativeX = (anchor.x - old.minX) / old.width
        let relativeY = (anchor.y - old.minY) / old.height
        let origin = CGPoint(x: anchor.x - relativeX * size.width, y: anchor.y - relativeY * size.height)
        zoom = clamped
        setFrame(CGRect(origin: origin, size: size), display: true)
        invalidateShadow()
    }

    /// 滚轮 / 精确滚动：向上（远离用户）放大
    fileprivate func zoom(byScroll event: NSEvent) {
        let raw = event.isDirectionInvertedFromDevice ? -event.scrollingDeltaY : event.scrollingDeltaY
        guard raw != 0 else { return }
        let steps = event.hasPreciseScrollingDeltas ? raw / Self.preciseDeltaPerStep : raw
        setZoom(zoom * pow(Self.wheelStep, steps), anchor: NSEvent.mouseLocation)
    }

    fileprivate func zoom(byMagnification event: NSEvent) {
        setZoom(zoom * (1 + event.magnification), anchor: NSEvent.mouseLocation)
    }

    func resetZoom() {
        setZoom(1, anchor: CGPoint(x: frame.midX, y: frame.midY))
    }

    private var percentText: String {
        Self.percent(zoom)
    }

    /// 按系统地区格式化的整数百分比（如 "80%"）
    private static func percent(_ value: CGFloat) -> String {
        Double(value).formatted(.percent.precision(.fractionLength(0)))
    }

    // MARK: - 关闭

    override func close() {
        zoomIndicator.hide()
        super.close()
    }

    /// 无边框窗口没有关闭按钮，系统默认的 performClose 会提示音失败
    override func performClose(_ sender: Any?) {
        onClose?()
    }

    // MARK: - 键盘

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        let flags = event.modifierFlags.intersection([.command, .option, .control, .shift])
        // 字母按字符匹配（兼容 Dvorak 等布局）
        guard flags == .command, let key = event.charactersIgnoringModifiers?.lowercased() else {
            return super.performKeyEquivalent(with: event)
        }
        switch key {
        case "c": onCopy?()
        case "s": onSave?()
        case "w": onClose?()
        case "0": resetZoom()
        default: return super.performKeyEquivalent(with: event)
        }
        return true
    }

    override func cancelOperation(_ sender: Any?) {
        onClose?()
    }

    // MARK: - 右键菜单

    fileprivate func makeContextMenu() -> NSMenu {
        let menu = NSMenu()
        menu.addItem(
            menuItem(
                String(localized: "pin.copy", defaultValue: "Copy", comment: "Pinned screenshot context menu item"),
                key: "c"
            ) { [weak self] in self?.onCopy?() })
        menu.addItem(
            menuItem(String(localized: "Save…", comment: "Pinned screenshot context menu item"), key: "s") {
                [weak self] in self?.onSave?()
            })
        let opacity = NSMenuItem(
            title: String(localized: "Opacity", comment: "Pinned screenshot context menu item"),
            action: nil,
            keyEquivalent: ""
        )
        opacity.submenu = makeOpacityMenu()
        menu.addItem(opacity)
        menu.addItem(.separator())
        menu.addItem(
            menuItem(String(localized: "Close", comment: "Pinned screenshot context menu item"), key: "w") {
                [weak self] in self?.onClose?()
            })
        return menu
    }

    private func makeOpacityMenu() -> NSMenu {
        let menu = NSMenu()
        for value in Self.opacityOptions {
            let item = menuItem(Self.percent(value), key: "") { [weak self] in
                self?.alphaValue = value
            }
            item.state = abs(alphaValue - value) < 0.01 ? .on : .off
            menu.addItem(item)
        }
        return menu
    }

    private func menuItem(_ title: String, key: String, handler: @escaping () -> Void) -> NSMenuItem {
        ClosureMenuItem(title: title, keyEquivalent: key, handler: handler)
    }
}

/// 贴图内容：圆角裁剪的位图 + 1px 白色内描边；负责鼠标交互
@MainActor
private final class PinnedImageView: NSView {
    weak var pinWindow: PinnedImageWindow?

    init(image: CGImage) {
        super.init(frame: .zero)
        wantsLayer = true
        guard let layer else { return }
        layer.contents = image
        layer.contentsGravity = .resize
        layer.minificationFilter = .trilinear
        layer.cornerRadius = Radius.control
        layer.cornerCurve = .continuous
        // 裁掉圆角外的像素：窗口阴影按透明度计算，因此也是圆角
        layer.masksToBounds = true
        layer.borderColor = NSColor(white: 1, alpha: 0.15).cgColor
        updateBorderWidth()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        updateBorderWidth()
    }

    /// 描边固定 1 物理像素
    private func updateBorderWidth() {
        let scale = window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 2
        layer?.borderWidth = 1 / scale
        layer?.contentsScale = scale
    }

    override func mouseDown(with event: NSEvent) {
        if event.clickCount >= 2 {
            pinWindow?.onClose?()
            return
        }
        window?.makeKey()
        window?.performDrag(with: event)
    }

    override func scrollWheel(with event: NSEvent) {
        pinWindow?.zoom(byScroll: event)
    }

    override func magnify(with event: NSEvent) {
        pinWindow?.zoom(byMagnification: event)
    }

    override func keyDown(with event: NSEvent) {
        if Int(event.keyCode) == kVK_Escape {
            pinWindow?.onClose?()
        } else {
            super.keyDown(with: event)
        }
    }

    override func menu(for event: NSEvent) -> NSMenu? {
        pinWindow?.makeContextMenu()
    }
}

/// 缩放百分比提示：贴图正中的深色胶囊（样式同截图尺寸标签），停止缩放后淡出。
/// 用子窗口而不是子视图：贴图缩得很小时标签不会被圆角裁掉，拖动贴图时也会跟随
@MainActor
private final class PinnedZoomIndicator {
    private static let visibleDuration: Duration = .milliseconds(800)
    private static let fadeDuration: TimeInterval = 0.2
    /// 内边距 3 × 7
    private static let inset = NSSize(width: 7, height: 3)

    private let panel: NSPanel
    private let label = NSTextField(labelWithString: "")
    private weak var parent: NSWindow?
    private var generation = 0

    init() {
        label.font = .monospacedDigitSystemFont(ofSize: FontSize.caption, weight: .semibold)
        label.textColor = .white
        let background = NSView()
        background.wantsLayer = true
        background.layer?.backgroundColor = NSColor(white: 0, alpha: 0.65).cgColor
        background.addSubview(label)

        panel = NSPanel(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: true
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.ignoresMouseEvents = true
        panel.isReleasedWhenClosed = false
        panel.animationBehavior = .none
        panel.contentView = background
    }

    func show(_ text: String, over window: NSWindow) {
        label.stringValue = text
        let textSize = label.fittingSize
        let size = NSSize(
            width: ceil(textSize.width) + Self.inset.width * 2,
            height: ceil(textSize.height) + Self.inset.height * 2
        )
        label.frame = NSRect(origin: NSPoint(x: Self.inset.width, y: Self.inset.height), size: textSize)
        panel.contentView?.layer?.cornerRadius = size.height / 2
        let anchor = window.frame
        let origin = NSPoint(x: anchor.midX - size.width / 2, y: anchor.midY - size.height / 2)
        panel.setFrame(NSRect(origin: origin, size: size), display: true)
        if parent !== window {
            parent?.removeChildWindow(panel)
            window.addChildWindow(panel, ordered: .above)
            parent = window
        }
        panel.alphaValue = 1
        scheduleHide()
    }

    func hide() {
        generation += 1
        parent?.removeChildWindow(panel)
        parent = nil
        panel.orderOut(nil)
    }

    private func scheduleHide() {
        generation += 1
        let current = generation
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: Self.visibleDuration)
            guard let self, self.generation == current else { return }
            NSAnimationContext.runAnimationGroup(
                { context in
                    context.duration = Self.fadeDuration
                    self.panel.animator().alphaValue = 0
                },
                completionHandler: { [weak self] in
                    Task { @MainActor in
                        guard let self, self.generation == current else { return }
                        self.hide()
                    }
                })
        }
    }
}
