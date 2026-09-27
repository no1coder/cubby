import AppKit

/// 正文可见区域对应的字符位置：顶部探测线处，以及是否已滚到底
struct GuideVisibleRegion: Equatable {
    let topLocation: Int
    let bottomLocation: Int
    let isAtBottom: Bool
}

/// 使用说明的正文：只读、可选择复制的 NSTextView（TextKit 1，以便用 GuideLayoutManager 画键帽）。
/// 负责滚动到指定位置、上报当前可见位置、搜索高亮与链接点击。
@MainActor
final class GuideTextController: NSObject, NSTextViewDelegate {
    /// 顶部探测线距可见区域顶边的距离：标题滚到这条线以上即视为进入该节
    private static let probeOffset: CGFloat = 36
    private static let bottomTolerance: CGFloat = 2

    let scrollView = NSScrollView()
    private let textView: GuideTextView
    private let layoutManager = GuideLayoutManager()
    private var boundsObserver: (any NSObjectProtocol)?
    /// 程序滚动（点目录跳转）期间不上报，由调用方直接设定当前节
    private var isScrollingProgrammatically = false

    var onVisibleRegionChange: ((GuideVisibleRegion) -> Void)?
    var onLinkClick: ((URL) -> Void)?

    override init() {
        let storage = NSTextStorage()
        storage.addLayoutManager(layoutManager)
        let container = NSTextContainer(size: NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude))
        container.widthTracksTextView = true
        layoutManager.addTextContainer(container)
        textView = GuideTextView(frame: .zero, textContainer: container)
        super.init()
        configureTextView()
        configureScrollView()
    }

    /// 键盘焦点默认放在正文上：空格、方向键直接滚动
    var focusView: NSView {
        textView
    }

    func display(_ text: NSAttributedString) {
        guard let container = textView.textContainer else { return }
        textView.textStorage?.setAttributedString(text)
        // 先排版一次让滚动条出现（正文宽度随之变窄，NSTextView 会把选区滚入视野），按最终宽度再排一次，最后回到顶部
        layoutManager.ensureLayout(for: container)
        scrollView.tile()
        layoutManager.ensureLayout(for: container)
        let clip = scrollView.contentView
        clip.scroll(to: .zero)
        scrollView.reflectScrolledClipView(clip)
    }

    /// 把指定字符所在的行滚到顶部（标题上方的段前距一并露出）
    func scroll(toCharacter location: Int) {
        guard let container = textView.textContainer, location < (textView.textStorage?.length ?? 0) else { return }
        layoutManager.ensureLayout(for: container)
        let glyph = layoutManager.glyphIndexForCharacter(at: location)
        let line = layoutManager.lineFragmentRect(forGlyphAt: glyph, effectiveRange: nil)
        let target = NSPoint(x: 0, y: line.minY + textView.textContainerOrigin.y)
        let clip = scrollView.contentView
        isScrollingProgrammatically = true
        clip.scroll(to: clip.constrainBoundsRect(NSRect(origin: target, size: clip.bounds.size)).origin)
        scrollView.reflectScrolledClipView(clip)
        isScrollingProgrammatically = false
    }

    /// 高亮搜索命中（临时属性，不改动正文）
    func highlight(_ ranges: [NSRange]) {
        let length = textView.textStorage?.length ?? 0
        let everything = NSRange(location: 0, length: length)
        layoutManager.removeTemporaryAttribute(.backgroundColor, forCharacterRange: everything)
        layoutManager.removeTemporaryAttribute(.foregroundColor, forCharacterRange: everything)
        let attributes: [NSAttributedString.Key: Any] = [
            .backgroundColor: NSColor.findHighlightColor,
            .foregroundColor: NSColor.black,
        ]
        for range in ranges where NSMaxRange(range) <= length {
            layoutManager.addTemporaryAttributes(attributes, forCharacterRange: range)
        }
    }

    /// 滚动到命中处并以系统查找指示器标出
    func reveal(_ range: NSRange) {
        guard NSMaxRange(range) <= (textView.textStorage?.length ?? 0) else { return }
        textView.scrollRangeToVisible(range)
        textView.showFindIndicator(for: range)
    }

    // MARK: - NSTextViewDelegate

    /// 链接交给调用方判断去向；一律返回 true，不让系统按默认方式打开
    func textView(_ textView: NSTextView, clickedOnLink link: Any, at charIndex: Int) -> Bool {
        let url = (link as? URL) ?? (link as? String).flatMap(URL.init(string:))
        if let url { onLinkClick?(url) }
        return true
    }

    // MARK: - 私有

    private func configureTextView() {
        textView.isEditable = false
        textView.isSelectable = true
        textView.isRichText = true
        textView.importsGraphics = false
        textView.allowsUndo = false
        textView.usesFindBar = false
        textView.isAutomaticLinkDetectionEnabled = false
        textView.displaysLinkToolTips = true
        textView.drawsBackground = true
        textView.backgroundColor = .textBackgroundColor
        textView.linkTextAttributes = [.foregroundColor: NSColor.linkColor, .cursor: NSCursor.pointingHand]
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.minSize = .zero
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.delegate = self
        textView.setAccessibilityLabel(String(localized: "User Guide", comment: "User guide window title"))
    }

    private func configureScrollView() {
        scrollView.documentView = textView
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.drawsBackground = true
        scrollView.backgroundColor = .textBackgroundColor
        let clip = scrollView.contentView
        clip.postsBoundsChangedNotifications = true
        boundsObserver = NotificationCenter.default.addObserver(
            forName: NSView.boundsDidChangeNotification, object: clip, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.visibleRegionDidChange() }
        }
    }

    private func visibleRegionDidChange() {
        guard !isScrollingProgrammatically, let region = visibleRegion() else { return }
        onVisibleRegionChange?(region)
    }

    private func visibleRegion() -> GuideVisibleRegion? {
        guard let container = textView.textContainer, (textView.textStorage?.length ?? 0) > 0 else { return nil }
        let visible = scrollView.contentView.bounds
        let origin = textView.textContainerOrigin
        let top = characterIndex(at: NSPoint(x: 0, y: visible.minY + Self.probeOffset - origin.y), in: container)
        let bottom = characterIndex(at: NSPoint(x: 0, y: visible.maxY - origin.y), in: container)
        let isAtBottom = visible.maxY >= textView.frame.height - Self.bottomTolerance
        return GuideVisibleRegion(topLocation: top, bottomLocation: bottom, isAtBottom: isAtBottom)
    }

    private func characterIndex(at point: NSPoint, in container: NSTextContainer) -> Int {
        let glyph = layoutManager.glyphIndex(for: point, in: container)
        return layoutManager.characterIndexForGlyph(at: glyph)
    }
}

/// 正文视图：窗口变宽时两侧留白随之增加，正文保持易读的栏宽并居中
final class GuideTextView: NSTextView {
    static let readableWidth: CGFloat = 680
    static let minHorizontalInset: CGFloat = 32
    static let verticalInset: CGFloat = 28

    override func setFrameSize(_ newSize: NSSize) {
        let horizontal = max(Self.minHorizontalInset, (newSize.width - Self.readableWidth) / 2)
        if textContainerInset.width != horizontal {
            textContainerInset = NSSize(width: horizontal, height: Self.verticalInset)
        }
        super.setFrameSize(newSize)
    }
}
