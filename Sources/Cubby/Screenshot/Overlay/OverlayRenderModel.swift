import CubbyCore
import CoreGraphics

/// 从会话派生各视图的输入（纯计算，不持有状态）
@MainActor
enum OverlayRenderModel {
    /// 某块屏幕的画布状态
    static func canvasState(
        for session: ScreenshotSession,
        screen: CaptureScreen,
        pixelated: CGImage?,
        index: AnnotationIndex
    ) -> OverlayCanvasState {
        var state = OverlayCanvasState()
        state.highlight = session.highlightedRect
        // 先决定（并计数）再看是否在本屏：多屏时只在光标所在屏显示
        state.showsOnboarding =
            OverlayOnboarding.isVisible(phase: session.phase) && screen.contains(session.cursor)
        state.pixelated = pixelated
        if session.phase == .hovering {
            state.hover = session.highlightedRect
            state.hoverStyle = session.isWindowCaptureMode ? .windowCapture : .target
            state.hoverIsWindow = session.hover?.windowID != nil
        } else if let selection = session.selection {
            state.selection = selection
            let showsHandles = session.phase == .adjusting || session.phase == .annotating
            state.handles = showsHandles ? SelectionGeometry.visibleHandles(for: selection) : []
            state.activeHandle = session.activeHandle
        }
        let live = liveItem(for: session)
        state.live = live
        let hidden = Set([live?.annotation.id, session.textEditing?.existing].compactMap { $0 })
        let visible = index.entries.filter { entry in
            !hidden.contains(entry.annotation.id) && intersects(entry.bounds, screen: screen)
        }.map { OverlayAnnotationItem(annotation: $0.annotation, numberLabel: $0.numberLabel) }
        state.highlighters = visible.filter { $0.annotation.tool == .highlighter }
        state.annotations = visible.filter { $0.annotation.tool != .highlighter }
        // 选中箭头显示两端手柄而不是虚线框（评审 P2-4）；其他形状仍是虚线框
        state.arrowEndpoints = session.selectedArrowEndpoints
        if session.phase != .editingText, state.arrowEndpoints.isEmpty, let selected = session.selectedAnnotation {
            state.selectedBounds =
                live?.annotation.id == selected ? live?.annotation.bounds : index.bounds(for: selected)
        }
        state.snapGuide = session.arrowSnapGuide
        return state
    }

    /// 实时层：正在画的标注，或正在拖动的标注（拖动期间从标注层移出，标注层不必每帧重绘）
    static func liveItem(for session: ScreenshotSession) -> OverlayAnnotationItem? {
        switch session.drag {
        case .drawing(let annotation):
            return OverlayAnnotationItem(annotation: annotation, numberLabel: nil)
        case .movingAnnotation(let id, _), .movingArrowEnd(let id, _):
            guard let annotation = session.document.annotation(id: id) else { return nil }
            return OverlayAnnotationItem(annotation: annotation, numberLabel: session.document.numberLabel(for: id))
        default:
            return nil
        }
    }

    /// 文档里是否有马赛克，或马赛克工具正激活（需要像素化副本）
    static func needsPixelation(_ session: ScreenshotSession) -> Bool {
        session.tool == .mosaic || session.document.annotations.contains { $0.tool == .mosaic }
            || session.drag.isDrawingMosaic
    }

    private static func intersects(_ bounds: CGRect, screen: CaptureScreen) -> Bool {
        !bounds.isNull && bounds.intersects(screen.frame)
    }

    // MARK: - 放大镜

    /// 放大镜读数与所在屏幕；不可见或光标不在任何屏幕时为 nil
    static func magnifier(
        for session: ScreenshotSession,
        capture: CaptureSession
    ) -> (screenID: UInt32, reading: MagnifierReading)? {
        guard session.isMagnifierVisible,
            let screen = capture.topology.screen(containing: session.cursor),
            let frame = capture.frame(for: screen.id)
        else { return nil }
        let grid = MagnifierSampler.sample(
            frame: frame.image,
            centerPixel: screen.pixelPoint(session.cursor),
            radius: OverlayTokens.magnifierRadius
        )
        let colorText = grid.center.map { ColorFormatter.string($0, format: session.colorFormat) } ?? ""
        let reading = MagnifierReading(grid: grid, point: screen.localPoint(session.cursor), colorText: colorText)
        return (screen.id, reading)
    }

    // MARK: - 工具栏

    static func toolbarModel(for session: ScreenshotSession) -> ScreenshotToolbarModel {
        ScreenshotToolbarModel(
            tool: session.tool,
            canUndo: session.canUndo,
            canRedo: session.canRedo,
            translate: translateButton(for: session)
        )
    }

    /// 翻译按钮：不可用时不显示；已有结果时 tooltip 说明再按切换原文 / 译文
    private static func translateButton(for session: ScreenshotSession) -> ScreenshotToolbarModel.Translate? {
        guard session.isTranslationAvailable else { return nil }
        guard let run = session.translation else { return .idle }
        return run.hasResult ? .showing(translation: session.showsTranslation) : .active
    }

    static func styleBarModel(for session: ScreenshotSession) -> ScreenshotStyleBarModel? {
        session.styleBarTool.map { ScreenshotStyleBarModel(tool: $0, style: session.activeStyle) }
    }
}

extension DragState {
    /// 正在画马赛克（尚未进入文档）
    var isDrawingMosaic: Bool {
        if case .drawing(let annotation) = self {
            return annotation.tool == .mosaic
        }
        return false
    }
}
