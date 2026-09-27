import AppKit
import CoreGraphics

/// 把标注画进 CGContext（覆盖层与导出共用）
///
/// 调用约定：context 为 CoreGraphics 默认坐标（左下原点、一个用户单位 = 一个目标像素）；
/// 渲染器内部 `saveGState` 后翻转 y 轴、按 `environment.scale` 缩放、按 `environment.origin` 平移，
/// 此后直接使用标注的全局点坐标绘制，结束时 `restoreGState`。线宽、字号均以点定义。
public enum AnnotationRenderer {
    /// 选中框相对标注 bounds 的外扩（点）
    public static let selectionOutlineInset: CGFloat = 4
    private static let selectionOutlineWidth: CGFloat = 1
    private static let selectionDash: [CGFloat] = [4, 2]

    /// 绘制全部标注；序号编号由文档顺序推导
    ///
    /// 荧光笔整层垫在最下面（冻结帧之上、其他标注之下），其余按文档顺序（先画的在下）。理由：
    /// - 荧光笔用来标记截图内容本身，垫在下面时箭头、文字、序号保持纯色，不会被 multiply 染暗；
    /// - 与覆盖层一致：屏幕上荧光笔是单独一层 multiply 图层、位于其他标注之下（导出与所见一致）。
    public static func draw(_ document: AnnotationDocument, in context: CGContext, environment: RenderEnvironment) {
        inGlobalSpace(context, environment) {
            var labels: [AnnotationID: Int] = [:]
            var nextNumber = 1
            for annotation in document.annotations where annotation.tool == .number {
                labels[annotation.id] = nextNumber
                nextNumber += 1
            }
            let highlighters = document.annotations.filter { $0.tool == .highlighter }
            let others = document.annotations.filter { $0.tool != .highlighter }
            let painter = ShapePainter(context: context, environment: environment)
            for annotation in highlighters + others {
                painter.paint(annotation, numberLabel: labels[annotation.id])
            }
        }
    }

    /// 绘制单个标注（覆盖层实时层等场景）；numberLabel 只对序号标注有意义，nil 时只画徽标底
    public static func draw(
        _ annotation: Annotation,
        numberLabel: Int?,
        in context: CGContext,
        environment: RenderEnvironment
    ) {
        inGlobalSpace(context, environment) {
            ShapePainter(context: context, environment: environment).paint(annotation, numberLabel: numberLabel)
        }
    }

    /// 选中框：沿 bounds 外扩 4 pt 的 1 pt 强调色虚线（4-2），供覆盖层复用
    public static func drawSelectionOutline(
        for annotation: Annotation,
        in context: CGContext,
        environment: RenderEnvironment
    ) {
        let bounds = annotation.bounds
        guard !bounds.isNull else { return }
        inGlobalSpace(context, environment) {
            context.setStrokeColor(accentColor)
            context.setLineWidth(selectionOutlineWidth)
            context.setLineDash(phase: 0, lengths: selectionDash)
            context.stroke(bounds.insetBy(dx: -selectionOutlineInset, dy: -selectionOutlineInset))
        }
    }

    // MARK: - 内部

    /// 系统强调色（sRGB）；取不到时用系统蓝
    private static var accentColor: CGColor {
        NSColor.controlAccentColor.usingColorSpace(.sRGB)?.cgColor ?? AnnotationColor.blue.rgba.srgbCGColor
    }

    /// 进入「左上原点、y 向下、单位为全局点」的坐标系执行 body，结束后恢复
    private static func inGlobalSpace(_ context: CGContext, _ environment: RenderEnvironment, _ body: () -> Void) {
        context.saveGState()
        context.translateBy(x: 0, y: environment.targetPixelSize.height)
        context.scaleBy(x: environment.scale, y: -environment.scale)
        context.translateBy(x: -environment.origin.x, y: -environment.origin.y)
        body()
        context.restoreGState()
    }
}
