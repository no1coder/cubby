// 调试场景只在 Debug 构建中编译（Release 不含预置会话与假窗口布局）
#if DEBUG
import CoreGraphics

/// `--scenario screenshot:<name>` 的预置会话（§5.2），坐标相对第一块屏幕的左上角
///
/// 覆盖层拿到 `phase == .editingText` 的预置会话时，应按 `textEditing` 直接打开编辑器
/// （预置会话不会再发 `.beginTextEditing`）。
public enum ScreenshotDebugScenario {
    /// 全部会话场景名（"pin" / "permission" 不是会话预置，由 ScreenshotCoordinator 直接处理）
    public static let names = [
        "hovering", "selecting", "adjusting", "annotating", "text", "tiny", "edge", "fullscreen",
        "hover-cycle", "window-mode", "arrow-guide", "magnet", "shift-line",
    ]

    private static let annotatingPrefix = "annotating:"
    /// 标准选区 (200, 150) → (760, 520)
    private static let standardSelection = CGRect(x: 200, y: 150, width: 560, height: 370)
    private static let tinySelection = CGRect(x: 400, y: 300, width: 12, height: 10)
    private static let edgeSelectionSize = CGSize(width: 300, height: 200)
    /// edge 场景中光标距屏幕右下角的距离
    private static let edgeCursorInset: CGFloat = 10
    private static let textOrigin = CGPoint(x: 240, y: 200)
    /// "Hello 你好"（用转义避免源码中出现汉字）
    private static let sampleText = "Hello \u{4F60}\u{597D}"

    /// "hovering" / "selecting" / "adjusting" / "annotating" / "annotating:<tool>" / "text" / "tiny" / "edge" /
    /// "fullscreen" / "hover-cycle" / "window-mode" / "arrow-guide" / "magnet" / "shift-line"；未知名称或没有屏幕时为 nil
    public static func session(named name: String, topology: ScreenTopology, styles: ToolStyles) -> ScreenshotSession? {
        guard let screen = topology.screens.first else { return nil }
        let context = Context(screen: screen, topology: topology, styles: styles)
        if name.hasPrefix(annotatingPrefix) {
            return ScreenshotTool(rawValue: String(name.dropFirst(annotatingPrefix.count))).map(context.annotating)
        }
        switch name {
        case "hovering": return context.hovering()
        case "selecting": return context.selecting()
        case "adjusting": return context.adjusting(standardSelection)
        case "annotating": return context.annotatingWithSelectedArrow()
        case "text": return context.editingText()
        case "tiny": return context.adjusting(tinySelection)
        case "edge": return context.edge()
        case "fullscreen": return context.fullscreen()
        case "hover-cycle": return context.hoverCycle()
        case "window-mode": return context.windowMode()
        case "arrow-guide": return context.drawing(.arrow, shift: false, to: CGSize(width: 240, height: 4))
        case "magnet": return context.magnet()
        case "shift-line": return context.drawing(.pen, shift: true, to: CGSize(width: 240, height: -60))
        default: return nil
        }
    }

    /// 生成预置会话所需的上下文
    private struct Context {
        let screen: CaptureScreen
        let topology: ScreenTopology
        let styles: ToolStyles

        /// 相对屏幕左上角的点 → 全局点
        func point(_ local: CGPoint) -> CGPoint {
            CGPoint(x: screen.frame.minX + local.x, y: screen.frame.minY + local.y)
        }

        func rect(_ local: CGRect) -> CGRect {
            CGRect(origin: point(local.origin), size: local.size)
        }

        func initial(cursor: CGPoint) -> ScreenshotSession {
            ScreenshotSession.initial(styles: styles, cursor: cursor, topology: topology)
        }

        func hovering() -> ScreenshotSession {
            initial(cursor: ScenarioWindows.hoverPoint(on: screen, topology: topology))
        }

        func hoverCycle() -> ScreenshotSession {
            let cursor =
                ScenarioWindows.overlapPoint(on: screen, topology: topology)
                ?? ScenarioWindows.hoverPoint(on: screen, topology: topology)
            return ScreenshotReducer.cyclingHover(initial(cursor: cursor), forward: true)
        }

        func windowMode() -> ScreenshotSession? {
            let session = hovering()
            guard session.hover?.windowID != nil else { return nil }
            return ScreenshotReducer.togglingWindowCapture(session)
        }

        func selecting() -> ScreenshotSession {
            let anchor = point(standardSelection.origin)
            let cursor = point(CGPoint(x: standardSelection.maxX, y: standardSelection.maxY))
            let pressed = ScreenshotReducer.pressing(initial(cursor: anchor), at: anchor, intent: .selectHover)
            return ScreenshotReducer.mouseDragged(pressed, to: cursor, topology: topology)
        }

        func adjusting(_ local: CGRect, cursor: CGPoint? = nil) -> ScreenshotSession {
            let selection = rect(local)
            return initial(cursor: cursor ?? CGPoint(x: selection.midX, y: selection.midY)).updating {
                $0.phase = .adjusting
                $0.selection = selection
                $0.screenID = screen.id
                ScreenshotReducer.leavingHover(&$0)
            }
        }

        func edge() -> ScreenshotSession {
            let size = edgeSelectionSize
            let local = CGRect(
                x: screen.frame.width - size.width, y: screen.frame.height - size.height,
                width: size.width, height: size.height)
            let cursor = point(
                CGPoint(x: screen.frame.width - edgeCursorInset, y: screen.frame.height - edgeCursorInset))
            return adjusting(local, cursor: cursor)
        }

        func fullscreen() -> ScreenshotSession {
            adjusting(CGRect(origin: .zero, size: screen.frame.size))
        }

        /// 标准选区 + 每种工具的标注（序号 3 个）
        func annotated() -> ScreenshotSession {
            let base = adjusting(standardSelection)
            let annotations = ScenarioAnnotations.make(styles: styles, selection: rect(standardSelection))
            let document = annotations.reduce(AnnotationDocument.empty) { $0.adding($1) }
            return base.updating {
                $0.document = document
                $0.annotationSerial = annotations.count + 1
            }
        }

        func annotatingWithSelectedArrow() -> ScreenshotSession {
            let session = annotated()
            let arrow = session.document.annotations.first { $0.tool == .arrow }
            return session.updating {
                $0.phase = .annotating
                $0.tool = .arrow
                $0.selectedAnnotation = arrow?.id
            }
        }

        func annotating(_ tool: ScreenshotTool) -> ScreenshotSession {
            annotated().updating {
                $0.tool = tool
                $0.phase = tool == .pointer ? .adjusting : .annotating
            }
        }

        /// 标准选区 + 标注，正在用 tool 从选区内一点拖出 offset（按住鼠标未松开）：
        /// 箭头落在 ±3° 内时显示吸附辅助线；shift 为 true 时按住 ⇧（画笔只保留首尾两点）
        func drawing(_ tool: ScreenshotTool, shift: Bool, to offset: CGSize) -> ScreenshotSession {
            let start = point(CGPoint(x: standardSelection.minX + 60, y: standardSelection.minY + 330))
            let prepared = annotating(tool).updating {
                // 与 reducer 处理 .modifiersChanged 一致：⇧ 按住时颜色读数为 RGB
                $0.modifiers = shift ? .shift : []
                $0.colorFormat = shift ? .rgb : .hex
            }
            let pressed = ScreenshotReducer.pressing(prepared, at: start, intent: .draw)
            // 中途经过一个偏离直线的点：⇧ 直线场景里看得出只保留了首尾
            let middle = CGPoint(x: start.x + offset.width / 2, y: start.y + offset.height / 2 + 40)
            let end = CGPoint(x: start.x + offset.width, y: start.y + offset.height)
            return [middle, end].reduce(pressed) { ScreenshotReducer.mouseDragged($0, to: $1, topology: topology) }
        }

        /// 正在拖出选区：起点在最前面那个窗口右边外侧 3 pt，左边吸附到窗口边缘（没有窗口时贴屏幕左边）
        func magnet() -> ScreenshotSession {
            let window = WindowHitTester.eligibleWindows(in: topology)
                .map { $0.frame.standardized.intersection(screen.frame) }
                .first { !$0.isNull && $0.width > 0 && $0.maxX + 200 < screen.frame.maxX }
            let anchor =
                window.map { CGPoint(x: $0.maxX + 3, y: $0.midY) }
                ?? CGPoint(x: screen.frame.minX + 3, y: screen.frame.midY)
            let cursor = CGPoint(x: anchor.x + 170, y: min(anchor.y + 140, screen.frame.maxY - 10))
            let pressed = ScreenshotReducer.pressing(initial(cursor: anchor), at: anchor, intent: .selectHover)
            return ScreenshotReducer.mouseDragged(pressed, to: cursor, topology: topology)
        }

        func editingText() -> ScreenshotSession {
            let origin = point(textOrigin)
            let selection = rect(standardSelection)
            let state = TextEditingState(
                origin: origin, existing: nil, text: sampleText, maxWidth: selection.maxX - origin.x)
            return adjusting(standardSelection, cursor: origin).updating {
                $0.phase = .editingText
                $0.tool = .text
                $0.textEditing = state
            }
        }
    }
}
#endif
