import CoreGraphics

/// 驱动覆盖层视图的派生属性
extension ScreenshotSession {
    /// hovering / selecting / 拖手柄时可见；窗口模式下隐藏
    public var isMagnifierVisible: Bool {
        guard !isWindowCaptureMode else { return false }
        if case .resizing = drag {
            return true
        }
        return phase == .hovering || phase == .selecting
    }

    /// 有选区且没有在拖拽选区 / 手柄时可见（画标注、拖标注时保留，避免工具栏每一笔都闪烁）
    public var isToolbarVisible: Bool {
        guard selection != nil else { return false }
        return phase != .hovering && phase != .selecting && !drag.isSelectionDrag
    }

    /// 去遮罩区域：选区，或 hovering 时的悬停目标；窗口模式下只有窗口目标才高亮
    public var highlightedRect: CGRect? {
        if let selection {
            return selection
        }
        guard phase == .hovering, let hover else { return nil }
        if isWindowCaptureMode && hover.windowID == nil {
            return nil
        }
        return hover.selectionRect
    }

    /// 文档是否有标注（ScreenshotOverlayPresenting.hasAnnotations 直接用它）
    public var hasAnnotations: Bool {
        !document.annotations.isEmpty
    }

    /// 选中的标注（id 已失效时为 nil）
    public var selectedAnnotationValue: Annotation? {
        selectedAnnotation.flatMap { document.annotation(id: $0) }
    }

    /// 样式条应展示的工具：选中标注的工具优先，其次当前工具；都没有（指针且未选中）时为 nil = 不显示样式条
    public var styleBarTool: ScreenshotTool? {
        guard phase == .adjusting || phase == .annotating || phase == .editingText else { return nil }
        if let selected = selectedAnnotationValue {
            return selected.tool
        }
        return tool == .pointer ? nil : tool
    }

    /// 样式条当前显示的样式：选中标注的样式，否则当前工具的默认样式
    public var activeStyle: AnnotationStyle {
        selectedAnnotationValue?.style ?? styles.style(for: tool)
    }

    /// 鼠标按下中（含尚未超过拖拽阈值）或正在拖拽。拖拽每一步都从按下时的快照重建选区与文档，
    /// 所以此时必须忽略会改动文档 / 选区的命令，否则命令会被下一次拖动回滚
    var isPointerBusy: Bool {
        press != nil || drag != .none
    }

    /// 可以编辑选区与标注：有选区的阶段且鼠标空闲
    var canEditSelection: Bool {
        (phase == .adjusting || phase == .annotating) && !isPointerBusy
    }

    /// 有选区的阶段：指针 → adjusting，否则 annotating
    var selectionPhase: ScreenshotPhase {
        tool == .pointer ? .adjusting : .annotating
    }
}
