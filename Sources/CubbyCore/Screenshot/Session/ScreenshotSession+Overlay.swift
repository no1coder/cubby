import CoreGraphics

/// 覆盖层的光标种类（映射到具体 NSCursor 由 App 层负责）
public enum ScreenshotCursorKind: Hashable, Sendable {
    /// 悬停、框选、绘制
    case crosshair
    /// 编辑文字时编辑框外（单击只提交文字）
    case arrow
    /// 文字工具
    case iBeam
    /// 选区内、可拖动的标注、箭头端点
    case move
    /// 纯净窗口模式
    case camera
    /// 选区手柄
    case resize(SelectionHandle)
}

/// 箭头吸附辅助线：箭头所在的轴（尾 → 头）。覆盖层沿它向两端延长到屏幕边缘
public struct AnnotationSnapGuide: Equatable, Sendable {
    public let from: CGPoint
    public let to: CGPoint

    public init(from: CGPoint, to: CGPoint) {
        self.from = from
        self.to = to
    }
}

/// 驱动覆盖层光标、手柄与辅助线的派生属性（纯逻辑，便于测试）
extension ScreenshotSession {
    /// 当前光标：窗口模式为相机；拖拽中按拖拽类型；其余按光标位置命中（与按下时的优先级一致）
    public var cursorKind: ScreenshotCursorKind {
        if isWindowCaptureMode {
            return .camera
        }
        switch drag {
        case .resizing(let handle): return .resize(handle)
        case .movingSelection, .movingAnnotation, .movingArrowEnd: return .move
        case .creatingSelection, .drawing: return .crosshair
        case .none: break
        }
        switch phase {
        case .hovering, .selecting: return .crosshair
        case .editingText: return .arrow
        case .adjusting, .annotating: return selectionCursorKind
        }
    }

    /// 悬停 / 拖动中的选区手柄（放大显示）；箭头端点优先于选区手柄
    public var activeHandle: SelectionHandle? {
        if case .resizing(let handle) = drag {
            return handle
        }
        guard drag == .none, let selection, phase == .adjusting || phase == .annotating,
            ScreenshotReducer.arrowEndHit(self, at: cursor) == nil,
            case .handle(let handle) = SelectionGeometry.hitRegion(at: cursor, in: selection)
        else { return nil }
        return handle
    }

    /// 正在画 / 正在改端点的箭头恰好落在 45° 的倍数上时的辅助线（松开后为 nil）
    public var arrowSnapGuide: AnnotationSnapGuide? {
        let arrow: Annotation?
        switch drag {
        case .drawing(let annotation): arrow = annotation
        case .movingArrowEnd(let id, _): arrow = document.annotation(id: id)
        default: return nil
        }
        guard case .arrow(let from, let to) = arrow?.shape, ArrowGeometry.isOnSnapAngle(from: from, to: to) else {
            return nil
        }
        return AnnotationSnapGuide(from: from, to: to)
    }

    /// 选中箭头的两个端点（尾、头），覆盖层在这里画端点手柄；没有选中箭头时为空
    public var selectedArrowEndpoints: [CGPoint] {
        guard phase == .adjusting || phase == .annotating, let selected = selectedAnnotationValue,
            case .arrow(let from, let to) = selected.shape
        else { return [] }
        return [from, to]
    }

    private var selectionCursorKind: ScreenshotCursorKind {
        guard let selection else { return .crosshair }
        if ScreenshotReducer.arrowEndHit(self, at: cursor) != nil {
            return .move
        }
        let region = SelectionGeometry.hitRegion(at: cursor, in: selection)
        if case .handle(let handle) = region {
            return .resize(handle)
        }
        if phase == .annotating {
            return tool == .text ? .iBeam : .crosshair
        }
        let onAnnotation = document.topmost(at: cursor, tolerance: ScreenshotReducer.annotationHitTolerance) != nil
        return region == .inside || onAnnotation ? .move : .crosshair
    }
}
