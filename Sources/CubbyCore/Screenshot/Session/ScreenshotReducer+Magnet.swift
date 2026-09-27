import CoreGraphics

/// 选区边缘磁吸与箭头端点拖动（评审 §7）
extension ScreenshotReducer {
    /// 选区所在屏的吸附线；按住 ⌘ 时为 nil（临时关闭吸附）。
    /// 选 ⌘：拖拽时 ⇧ 已是正方形、⌥ 是中心扩展、空格是平移，⌘ 是唯一空闲的修饰键；
    /// 与 Keynote / Pages 「按住 ⌘ 拖动暂时关闭对齐参考线」的惯例一致，⌘ 组合键只在键盘事件里生效，拖拽时不冲突
    static func magnetGuides(_ session: ScreenshotSession, topology: ScreenTopology) -> SelectionMagnet.Guides? {
        guard !session.modifiers.contains(.command),
            let screen = session.screenID.flatMap({ topology.screen(id: $0) })
        else { return nil }
        return SelectionMagnet.Guides(screen: screen, topology: topology)
    }

    /// 选中箭头端点手柄的命中容差（与选区手柄一致）
    public static let arrowHandleTolerance: CGFloat = 8

    /// 选中的箭头若有端点落在 point 的容差内，返回它（两端都命中时取更近的一端）
    static func arrowEndHit(_ session: ScreenshotSession, at point: CGPoint) -> (AnnotationID, ArrowEnd)? {
        guard let arrow = session.selectedAnnotationValue, case .arrow(let from, let to) = arrow.shape else {
            return nil
        }
        let distances = [
            (ArrowEnd.tail, hypot(point.x - from.x, point.y - from.y)), (.head, hypot(point.x - to.x, point.y - to.y)),
        ]
        guard let nearest = distances.min(by: { $0.1 < $1.1 }), nearest.1 <= arrowHandleTolerance else { return nil }
        return (arrow.id, nearest.0)
    }

    /// 端点拖动：以按下时的箭头为基准平移被拖的一端，按另一端做角度吸附（⇧ 强制 45°）；
    /// 每一帧都从按下时的文档替换，整个拖动只记一步撤销
    static func movingArrowEnd(
        _ session: ScreenshotSession,
        press: PointerPress,
        id: AnnotationID,
        end: ArrowEnd,
        delta: CGVector,
        constrained: Bool
    ) -> ScreenshotSession {
        guard let original = press.document.annotation(id: id), case .arrow(let from, let to) = original.shape else {
            return session
        }
        let shape: AnnotationShape
        switch end {
        case .head:
            let target = offset(to, by: delta)
            shape = .arrow(
                from: from, to: AnnotationDrafting.arrowHead(from: from, to: target, constrained: constrained))
        case .tail:
            let target = offset(from, by: delta)
            shape = .arrow(from: AnnotationDrafting.arrowHead(from: to, to: target, constrained: constrained), to: to)
        }
        return session.updating {
            $0.document = press.document.replacing(Annotation(id: id, shape: shape, style: original.style))
        }
    }
}
