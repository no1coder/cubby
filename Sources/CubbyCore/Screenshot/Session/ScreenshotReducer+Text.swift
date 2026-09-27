import CoreGraphics
import Foundation

/// 文字标注（§2.3 editingText / §2.7 文字）
///
/// 编辑器文本由覆盖层通过 `.textChanged` 同步进会话，因此任何结束编辑的时机（Esc、⌘↩、点击外部、右键、
/// 工具栏、切换工具）都由 reducer 直接提交，覆盖层只需在收到 `.endTextEditing` 时移除编辑器。
extension ScreenshotReducer {
    /// 编辑器最小宽度（§2.7）；覆盖层的文字编辑框按同一值限制最小宽度（契约扩展：公开）
    public static let minimumTextWidth: CGFloat = 40

    static func reduceEditingText(_ session: ScreenshotSession, event: ScreenshotEvent, topology: ScreenTopology)
        -> Result
    {
        switch event {
        case .mouseMoved(let point), .mouseDragged(let point), .mouseUp(let point):
            return (session.updating { $0.cursor = point }, [])
        case .modifiersChanged(let modifiers):
            return (
                session.updating {
                    $0.modifiers = modifiers
                    $0.colorFormat = modifiers.contains(.shift) ? .rgb : .hex
                }, []
            )
        case .textChanged(let text):
            return (session.updating { $0.textEditing = session.textEditing?.withText(text) }, [])
        case .textCommitted(let text):
            return committingText(session, text: text)
        case .styleChanged(let style):
            return styleChanged(session, to: style)
        case .scrolled:
            return (session, [])
        case .mouseDown(let point, _):
            // 点击文本框外：只提交，这次点击不再产生其他效果
            return committingText(session.updating { $0.cursor = point }, text: session.textEditing?.text)
        case .command(.escape), .command(.commitText):
            return committingText(session, text: session.textEditing?.text)
        case .translation(let translation) where translation.isPipelineReport:
            // 流水线回报与编辑无关：照常更新译文，不提交文字
            return reduceTranslation(session, translation, topology: topology)
        case .command(.translate) where !session.isTranslationAvailable:
            // 翻译不可用时 ⇧⌘T 什么都不做，也不因此提交文字
            return (session, [])
        case .rightMouseDown, .command, .toolbarAction, .translation:
            // 先提交，再按提交后的阶段照常处理（右键清选区、工具栏出口、切换工具等）
            let committed = committingText(session, text: session.textEditing?.text)
            let followUp = dispatch(committed.session, event: event, topology: topology)
            return (followUp.session, committed.effects + followUp.effects)
        }
    }

    /// annotating + 文字工具按下：点在已有文字上则重新编辑，否则在按下处新建
    static func beginningTextEditing(_ session: ScreenshotSession, at point: CGPoint, topology: ScreenTopology)
        -> Result
    {
        let existing = session.document.annotations.last {
            $0.tool == .text && $0.hitTest(point, tolerance: annotationHitTolerance)
        }
        let state: TextEditingState
        if let existing, case .text(let text, let origin, let maxWidth) = existing.shape {
            state = TextEditingState(origin: origin, existing: existing.id, text: text, maxWidth: maxWidth)
        } else {
            state = TextEditingState(
                origin: point, existing: nil, text: "", maxWidth: textWidth(session, at: point, topology: topology))
        }
        // 这次按下交给编辑器，不保留 press；上一次拖拽若因丢失 mouseUp 还没结束也一并结束，
        // 否则 drag 残留而 press 为 nil，之后永远等不到松开，工具栏与撤销等命令一直被屏蔽
        let editing = session.updating {
            $0.phase = .editingText
            $0.textEditing = state
            $0.selectedAnnotation = state.existing
            $0.press = nil
            $0.drag = .none
        }
        return (editing, [.beginTextEditing(state, initialText: state.text)])
    }

    /// 换行宽度：在选区内点击时到选区右缘，在选区外时到屏幕右缘；不小于最小宽度
    private static func textWidth(_ session: ScreenshotSession, at point: CGPoint, topology: ScreenTopology) -> CGFloat
    {
        let selectionRight = session.selection?.maxX ?? point.x
        let screenRight = selectionBounds(session, topology: topology)?.maxX ?? point.x
        let rightEdge = point.x < selectionRight ? selectionRight : screenRight
        return max(minimumTextWidth, rightEdge - point.x)
    }

    /// 提交：空白 → 丢弃（重新编辑时删除原标注）；已有 → 原位替换文本；新建 → 追加。末尾空白与换行去掉
    static func committingText(_ session: ScreenshotSession, text: String?) -> Result {
        let content = trimmingTrailingWhitespace(text ?? "")
        let isBlank = content.isEmpty
        let editing = session.textEditing
        let existing = editing?.existing.flatMap { session.document.annotation(id: $0) }

        let document: AnnotationDocument
        let serial: Int
        switch (editing, existing, isBlank) {
        case (_, .some(let annotation), true):
            (document, serial) = (session.document.removing(id: annotation.id), session.annotationSerial)
        case (_, .some(let annotation), false):
            (document, serial) = (session.document.replacing(annotation.withText(content)), session.annotationSerial)
        case (.some(let state), nil, false):
            let annotation = Annotation(
                id: AnnotationDrafting.annotationID(serial: session.annotationSerial),
                shape: .text(content, origin: state.origin, maxWidth: state.maxWidth),
                style: session.styles.style(for: .text)
            )
            (document, serial) = (session.document.adding(annotation), session.annotationSerial + 1)
        default:
            (document, serial) = (session.document, session.annotationSerial)
        }
        let committed = session.updating {
            $0.document = document
            $0.annotationSerial = serial
            $0.textEditing = nil
            $0.selectedAnnotation = nil
            $0.phase = session.selection == nil ? .hovering : session.selectionPhase
        }
        return (committed, [.endTextEditing])
    }

    /// 去掉末尾的空白与换行：从末尾线性回退（不用正则，`\s+$` 在长空白串上会 O(n²) 回溯）
    static func trimmingTrailingWhitespace(_ text: String) -> String {
        guard let last = text.lastIndex(where: { !$0.isWhitespace }) else { return "" }
        return String(text[...last])
    }
}
