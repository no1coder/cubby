import AppKit
import CubbyCore
import SwiftUI

/// 一块屏幕的覆盖层根视图（翻转坐标）：画布 + 标签 + 工具栏 / 样式条 / 翻译条 + 放大镜 + 提示 + 文字编辑器，
/// 以及截图翻译的卷帘分隔线、按住空格提示与悬停气泡（见 +Translation）
///
/// 位置全部来自 Core 的摆放算法（全局点），这里只负责换算到视图坐标并对齐到像素。
@MainActor
final class OverlayScreenView: NSView {
    /// 一次渲染所需的输入
    struct Input {
        let session: ScreenshotSession
        let canvas: OverlayCanvasState
        let magnifier: MagnifierReading?
        let hoverInfo: HoverInfoModel?
        let toolbar: ScreenshotToolbarModel
        let styleBar: ScreenshotStyleBarModel?
        /// 截图翻译的翻译条；nil = 不显示
        let translationBar: TranslationBarModel?
        let translation: OverlayTranslationChrome
    }

    let canvas: OverlayCanvasView
    private let sizeLabel = SizeLabelView(frame: .zero)
    private let hoverInfo = OverlayPassthroughView(frame: .zero)
    private let hoverHosting: NSHostingView<HoverInfoLabel>
    private let toolbar: OverlayGlassPanel<ScreenshotToolbar>
    private let styleBar: OverlayGlassPanel<ScreenshotStyleBar>
    let translationBar: OverlayGlassPanel<TranslationBar>
    let wipeDivider = OverlayWipeDivider(frame: .zero)
    let peekChip = OverlayChipView(frame: .zero)
    let bubble = TranslationBubbleView(frame: .zero)
    var translationBarModel: TranslationBarModel?
    let onTranslation: (OverlayTranslationInput) -> Void
    private let magnifier = MagnifierView(frame: .zero)
    private let hint = OverlayHintView(frame: .zero)
    private var hoverModel: HoverInfoModel?
    private var hoverSize: CGSize = .zero
    private var toolbarModel: ScreenshotToolbarModel?
    private var styleBarModel: ScreenshotStyleBarModel?
    private let onToolbarAction: (ScreenshotToolbarAction) -> Void
    private let onStyleChange: (AnnotationStyle) -> Void

    var space: OverlaySpace { canvas.space }

    init(
        frame: FrozenFrame,
        onToolbarAction: @escaping (ScreenshotToolbarAction) -> Void,
        onStyleChange: @escaping (AnnotationStyle) -> Void,
        onTranslation: @escaping (OverlayTranslationInput) -> Void
    ) {
        canvas = OverlayCanvasView(frame: frame)
        let placeholder = ScreenshotToolbarModel(tool: .pointer, canUndo: false, canRedo: false)
        toolbar = OverlayGlassPanel(rootView: ScreenshotToolbar(model: placeholder, onAction: onToolbarAction))
        let style = ScreenshotStyleBarModel(tool: .rectangle, style: ScreenshotTool.rectangle.defaultStyle)
        styleBar = OverlayGlassPanel(rootView: ScreenshotStyleBar(model: style, onChange: onStyleChange))
        hoverHosting = NSHostingView(rootView: HoverInfoLabel(model: Self.emptyHoverModel))
        translationBar = OverlayGlassPanel(
            rootView: TranslationBar(model: Self.emptyTranslationBar) { onTranslation(.bar($0)) })
        self.onToolbarAction = onToolbarAction
        self.onStyleChange = onStyleChange
        self.onTranslation = onTranslation
        super.init(frame: CGRect(origin: .zero, size: frame.screen.frame.size))
        wantsLayer = true
        canvas.frame = bounds
        canvas.autoresizingMask = [.width, .height]
        hoverInfo.addSubview(hoverHosting)
        // 悬停气泡是临时的提示：放在工具栏与翻译条之上，压住它们时也能读全
        let views: [NSView] = [
            canvas, wipeDivider, peekChip, sizeLabel, hoverInfo, toolbar, styleBar, translationBar, bubble, magnifier,
            hint,
        ]
        for view in views {
            addSubview(view)
        }
        for view: NSView in [sizeLabel, hoverInfo, magnifier, peekChip] {
            view.isHidden = true
        }
        peekChip.text = TranslationBarText.peekChip
        wipeDivider.onMove = { onTranslation(.moveWipe($0)) }
        wipeDivider.onStep = { onTranslation(.stepWipe($0)) }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    override var isFlipped: Bool { true }

    /// 鼠标是否落在工具栏 / 样式条 / 翻译条上（此时光标用箭头）
    func isOverChrome(_ global: CGPoint) -> Bool {
        let point = space.viewPoint(global)
        let panels: [NSView] = [toolbar, styleBar, translationBar]
        return panels.contains { !$0.isHidden && $0.frame.contains(point) }
    }

    // MARK: - 渲染

    func render(_ input: Input) {
        canvas.apply(input.canvas)
        renderToolbar(input)
        renderTranslationChrome(input.translation)
        renderSizeLabel(input.session)
        renderHoverInfo(input.hoverInfo, anchor: input.canvas.hover)
        renderMagnifier(input.magnifier, cursor: input.session.cursor)
    }

    /// 标签、工具栏与屏幕边缘保持的距离（贴边的浮层看起来像被截断）
    private var layoutBounds: CGRect {
        space.screen.frame.insetBy(dx: OverlayTokens.screenMargin, dy: OverlayTokens.screenMargin)
    }

    /// 上方外侧 → 下方外侧 → 内侧左上（`SizeLabelPlacement`）；与工具栏 / 样式条重叠时改放内侧左上
    private func renderSizeLabel(_ session: ScreenshotSession) {
        guard session.phase != .hovering, let selection = session.selection, space.intersects(selection) else {
            sizeLabel.isHidden = true
            return
        }
        let text = SizeLabelPlacement.text(for: selection, scale: space.scale)
        let size = SizeLabelView.size(for: text)
        let aligned = space.pixelAligned(selection)
        let layout = SizeLabelPlacement.layout(
            labelSize: size,
            selection: aligned,
            screen: layoutBounds,
            gap: OverlayTokens.labelGap
        )
        var frame = alignedViewRect(layout.frame)
        if chromeFrames.contains(where: { $0.intersects(frame) }) {
            let inside = CGRect(
                origin: CGPoint(x: aligned.minX + OverlayTokens.labelGap, y: aligned.minY + OverlayTokens.labelGap),
                size: size
            )
            frame = alignedViewRect(SelectionGeometry.clamped(inside, to: layoutBounds))
        }
        sizeLabel.show(text: text, frame: frame)
    }

    /// 当前显示中的工具栏与样式条（视图坐标）
    private var chromeFrames: [CGRect] {
        [
            toolbar.isShown ? toolbar.frame : nil, styleBar.isShown ? styleBar.frame : nil,
            translationBar.isShown ? translationBar.frame : nil,
        ].compactMap { $0 }
    }

    private func renderHoverInfo(_ model: HoverInfoModel?, anchor: CGRect?) {
        guard let model, let anchor, space.intersects(anchor) else {
            hoverInfo.isHidden = true
            return
        }
        if model != hoverModel {
            hoverModel = model
            hoverHosting.rootView = HoverInfoLabel(model: model)
            let size = hoverHosting.fittingSize
            hoverSize = CGSize(width: size.width.rounded(.up), height: size.height.rounded(.up))
        }
        let frame = alignedViewRect(
            hoverLabelFrame(anchor: space.pixelAligned(anchor.intersection(space.screen.frame))))
        hoverInfo.frame = frame
        hoverHosting.frame = CGRect(origin: .zero, size: frame.size)
        hoverInfo.isHidden = false
    }

    /// 悬停标签：目标左上角外侧上方；放不下（例如最大化窗口贴着菜单栏）时放在目标内侧左上，
    /// 不像尺寸标签那样跳到目标下方——目标可能很高，标签会离光标很远
    private func hoverLabelFrame(anchor: CGRect) -> CGRect {
        let gap = OverlayTokens.labelGap
        let above = CGRect(
            x: anchor.minX,
            y: anchor.minY - gap - hoverSize.height,
            width: hoverSize.width,
            height: hoverSize.height
        )
        let bounds = layoutBounds
        let origin =
            above.minY >= bounds.minY ? above.origin : CGPoint(x: anchor.minX + gap, y: anchor.minY + gap)
        return SelectionGeometry.clamped(CGRect(origin: origin, size: hoverSize), to: bounds)
    }

    private func renderToolbar(_ input: Input) {
        let session = input.session
        guard session.isToolbarVisible, let selection = session.selection, isSelectionScreen(session) else {
            toolbar.setShown(false)
            styleBar.setShown(false)
            translationBar.setShown(false)
            return
        }
        if toolbarModel != input.toolbar {
            toolbarModel = input.toolbar
            toolbar.update(rootView: ScreenshotToolbar(model: input.toolbar, onAction: onToolbarAction))
        }
        if let model = input.styleBar, styleBarModel != model {
            styleBarModel = model
            styleBar.update(rootView: ScreenshotStyleBar(model: model, onChange: onStyleChange))
        }
        updateTranslationBar(input.translationBar)
        // 翻译条在工具栏远离选区的一侧，样式条排在翻译条之后
        let layout = TranslationBarPlacement.layout(
            toolbarSize: toolbar.fittingContentSize,
            translationBarSize: input.translationBar == nil ? nil : translationBar.fittingContentSize,
            styleBarSize: input.styleBar == nil ? nil : styleBar.fittingContentSize,
            selection: space.pixelAligned(selection),
            screen: layoutBounds,
            gap: OverlayTokens.toolbarGap,
            inset: OverlayTokens.toolbarGap
        )
        place(toolbar, at: layout.toolbar)
        if let frame = layout.styleBar {
            place(styleBar, at: frame)
        } else {
            styleBar.setShown(false)
        }
        if let frame = layout.translationBar {
            place(translationBar, at: frame)
        } else {
            translationBar.setShown(false)
        }
    }

    private func place<Content: View>(_ panel: OverlayGlassPanel<Content>, at global: CGRect) {
        let frame = alignedViewRect(global)
        if panel.frame != frame {
            panel.frame = frame
        }
        panel.setShown(true)
    }

    private func renderMagnifier(_ reading: MagnifierReading?, cursor: CGPoint) {
        guard let reading, space.screen.contains(cursor) else {
            magnifier.isHidden = true
            return
        }
        let frame = MagnifierPlacement.frame(
            size: OverlayTokens.magnifierSize,
            cursor: cursor,
            screen: space.screen.frame,
            offset: OverlayTokens.magnifierOffset
        )
        magnifier.show(reading, frame: alignedViewRect(frame))
    }

    // MARK: - 提示与编辑器

    func showHint(_ message: String, at global: CGPoint) {
        hint.show(message, centeredAt: space.viewPoint(global), within: bounds)
    }

    /// 编辑器放在画布之上、工具栏之下（候选窗与工具栏都不会被挡住）
    func addEditor(_ editor: TextAnnotationEditor) {
        addSubview(editor, positioned: .below, relativeTo: toolbar)
    }

    // MARK: - 工具

    private func isSelectionScreen(_ session: ScreenshotSession) -> Bool {
        if let id = session.screenID {
            return id == space.screen.id
        }
        return session.selection.map(space.intersects) ?? false
    }

    /// 全局矩形 → 视图矩形，原点对齐到设备像素
    func alignedViewRect(_ global: CGRect) -> CGRect {
        let rect = space.viewRect(global)
        return CGRect(
            x: space.pixelRounded(rect.minX),
            y: space.pixelRounded(rect.minY),
            width: rect.width,
            height: rect.height
        )
    }

    private static let emptyHoverModel = HoverInfoModel(
        icon: nil,
        iconIdentity: 0,
        symbolName: "macwindow",
        title: nil,
        sizeText: "",
        depth: nil,
        hint: nil,
        isWindowCapture: false
    )
}

#if DEBUG
/// 仅调试构建：端到端测试（--e2e）读取标签与提示的只读入口
extension OverlayScreenView {
    /// 尺寸标签可见时的文本
    var debugSizeLabelText: String? {
        sizeLabel.isHidden ? nil : sizeLabel.debugText
    }

    /// 提示 HUD 可见时的文本
    var debugHintText: String? {
        hint.debugMessage
    }

    /// 显示中的工具栏 / 样式条（全局点）
    var debugToolbarFrame: CGRect? {
        toolbar.isShown ? space.globalRect(fromView: toolbar.frame) : nil
    }

    var debugStyleBarFrame: CGRect? {
        styleBar.isShown ? space.globalRect(fromView: styleBar.frame) : nil
    }
}
#endif
