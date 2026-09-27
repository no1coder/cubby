import AppKit
import CubbyCore

/// 文字标注编辑器（§2.7）：TextKit 2 的 `NSTextView` + 1 pt 强调色虚线框
///
/// 与 CoreText 渲染逐像素对齐的约定（见 `TextLayout`）：
/// - 字体 = 系统 semibold、颜色 = 样式色、段落样式默认；
/// - `lineFragmentPadding = 0`、`textContainerInset = 0`：文字首行行框左上角就是文本视图的 (0, 0)，
///   也就是 `TextEditingState.origin`；编辑框的 4 pt 内边距在 origin 之外；
/// - 换行宽度 = `maxWidth`（文本容器宽度），视图宽度随内容增长到它为止；
/// - 使用 TextKit 2，**不**访问 `layoutManager`（会回退 TextKit 1，纯中文行高会变）。
@MainActor
final class TextAnnotationEditor: NSView, NSTextViewDelegate {
    /// 文本变化（发 `.textChanged`）
    var onTextChange: ((String) -> Void)?

    let textView: NSTextView
    private let border = CAShapeLayer()
    private let space: OverlaySpace
    private(set) var state: TextEditingState
    private var style: AnnotationStyle

    init(state: TextEditingState, style: AnnotationStyle, space: OverlaySpace) {
        self.state = state
        self.style = style
        self.space = space
        textView = NSTextView(usingTextLayoutManager: true)
        super.init(frame: .zero)
        wantsLayer = true
        configureBorder()
        configureTextView()
        textView.string = state.text
        applyStyle()
        layoutEditor()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    override var isFlipped: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    /// 输入法组字中（拼音候选）：按键一律交给输入法
    var hasMarkedText: Bool {
        textView.hasMarkedText()
    }

    /// 样式条在编辑时改色 / 改字号：实时应用
    func update(style: AnnotationStyle) {
        guard style != self.style else { return }
        self.style = style
        applyStyle()
        layoutEditor()
    }

    func focus() {
        window?.makeFirstResponder(textView)
        textView.setSelectedRange(NSRange(location: (textView.string as NSString).length, length: 0))
    }

    // MARK: - NSTextViewDelegate

    func textDidChange(_ notification: Notification) {
        layoutEditor()
        onTextChange?(textView.string)
    }

    // MARK: - 配置

    private var fontSize: CGFloat {
        ScreenshotTool.text.fontSize(for: style.weight)
    }

    private var font: NSFont {
        // 与 TextLayout.font(size:) 相同
        NSFont.systemFont(ofSize: fontSize, weight: .semibold)
    }

    private func configureTextView() {
        textView.delegate = self
        textView.drawsBackground = false
        textView.isRichText = false
        textView.importsGraphics = false
        textView.allowsUndo = true
        textView.usesFindBar = false
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.isContinuousSpellCheckingEnabled = false
        textView.isGrammarCheckingEnabled = false
        textView.smartInsertDeleteEnabled = false
        textView.textContainerInset = .zero
        textView.isVerticallyResizable = false
        textView.isHorizontallyResizable = false
        textView.defaultParagraphStyle = .default
        if let container = textView.textContainer {
            container.lineFragmentPadding = 0
            container.widthTracksTextView = false
            container.heightTracksTextView = false
            container.size = CGSize(width: state.maxWidth, height: .greatestFiniteMagnitude)
        }
        addSubview(textView)
    }

    private func configureBorder() {
        border.fillColor = nil
        border.lineWidth = OverlayTokens.textEditorBorderWidth
        border.lineDashPattern = OverlayTokens.textEditorDash
        layer?.addSublayer(border)
    }

    private func applyStyle() {
        let color = OverlayColors.nsColor(style.color.rgba)
        textView.font = font
        textView.textColor = color
        textView.insertionPointColor = color
        textView.typingAttributes = [
            .font: font,
            .foregroundColor: color,
            .paragraphStyle: NSParagraphStyle.default,
        ]
        if let storage = textView.textStorage, storage.length > 0 {
            let range = NSRange(location: 0, length: storage.length)
            storage.addAttributes([.font: font, .foregroundColor: color], range: range)
        }
        border.strokeColor = OverlayColors.accent.cgColor
    }

    /// 视图宽度随内容增长到 maxWidth；高度 = 行数 × 行高（空文本也保留一行）
    private func layoutEditor() {
        let content = measuredTextSize()
        let inset = OverlayTokens.textEditorInset
        let origin = space.viewPoint(state.origin)
        textView.frame = CGRect(x: inset, y: inset, width: content.width, height: content.height)
        frame = CGRect(
            x: origin.x - inset,
            y: origin.y - inset,
            width: content.width + inset * 2,
            height: content.height + inset * 2
        )
        let half = OverlayTokens.textEditorBorderWidth / 2
        border.frame = bounds
        border.path = CGPath(rect: bounds.insetBy(dx: half, dy: half), transform: nil)
    }

    /// TextKit 2 的实际排版范围与 `TextLayout.size`（含行尾空白、末尾换行，与导出同口径）取大者；
    /// 最小宽度 = 最小编辑宽度与 maxWidth 的较小者
    private func measuredTextSize() -> CGSize {
        let lineHeight = Self.lineHeight(for: font)
        let layout = TextLayout.size(of: textView.string, fontSize: fontSize, maxWidth: state.maxWidth)
        var used = CGSize(width: layout.width, height: max(layout.height, lineHeight))
        if let layoutManager = textView.textLayoutManager {
            layoutManager.ensureLayout(for: layoutManager.documentRange)
            let bounds = layoutManager.usageBoundsForTextContainer
            used = CGSize(width: max(used.width, bounds.maxX), height: max(used.height, bounds.maxY))
        }
        let minimum = min(ScreenshotReducer.minimumTextWidth, state.maxWidth)
        let width = min(max(used.width + OverlayTokens.textEditorCaretAllowance, minimum), state.maxWidth)
        return CGSize(width: width.rounded(.up), height: used.height.rounded(.up))
    }

    /// 与 TextLayout 相同的行高口径：round(ascent) + round(descent) + round(leading)
    private static func lineHeight(for font: NSFont) -> CGFloat {
        font.ascender.rounded() + (-font.descender).rounded() + font.leading.rounded()
    }

}
