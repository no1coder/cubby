import CoreGraphics
import Foundation

/// 标注的稳定标识（撤销 / 重做、选中、拖动都靠它对应同一个标注）
public struct AnnotationID: Hashable, Sendable, Codable {
    public let rawValue: UUID

    /// 生成新的随机标识
    public init() {
        rawValue = UUID()
    }

    /// 用已知 UUID 构造（调试场景与测试需要确定的 id）
    public init(rawValue: UUID) {
        self.rawValue = rawValue
    }
}

/// 标注的几何形状；全部坐标为全局点（§3.2）
public enum AnnotationShape: Equatable, Sendable {
    /// 矩形描边（可为反向拖出的负尺寸，使用时归一化）
    case rectangle(CGRect)
    /// 以外接矩形定义的椭圆描边
    case ellipse(CGRect)
    /// 锥形箭头：from = 尾，to = 头
    case arrow(from: CGPoint, to: CGPoint)
    /// 画笔：已抽稀的原始点，渲染时平滑
    case pen([CGPoint])
    /// 荧光笔：已抽稀的原始点
    case highlighter([CGPoint])
    /// 马赛克笔迹：已抽稀的原始点
    case mosaic([CGPoint])
    /// 文字：origin 为第一行行框左上角，maxWidth 为换行宽度
    case text(String, origin: CGPoint, maxWidth: CGFloat)
    /// 序号徽标：编号由文档顺序推导，不存储
    case number(center: CGPoint)

    /// 产生该形状的工具
    public var tool: ScreenshotTool {
        switch self {
        case .rectangle: .rectangle
        case .ellipse: .ellipse
        case .arrow: .arrow
        case .pen: .pen
        case .highlighter: .highlighter
        case .mosaic: .mosaic
        case .text: .text
        case .number: .number
        }
    }

    /// 整体平移后的新形状
    public func translated(by delta: CGVector) -> AnnotationShape {
        let move = { (point: CGPoint) in CGPoint(x: point.x + delta.dx, y: point.y + delta.dy) }
        switch self {
        case .rectangle(let rect): return .rectangle(rect.offsetBy(dx: delta.dx, dy: delta.dy))
        case .ellipse(let rect): return .ellipse(rect.offsetBy(dx: delta.dx, dy: delta.dy))
        case .arrow(let from, let to): return .arrow(from: move(from), to: move(to))
        case .pen(let points): return .pen(points.map(move))
        case .highlighter(let points): return .highlighter(points.map(move))
        case .mosaic(let points): return .mosaic(points.map(move))
        case .text(let text, let origin, let maxWidth): return .text(text, origin: move(origin), maxWidth: maxWidth)
        case .number(let center): return .number(center: move(center))
        }
    }
}

/// 一个不可变的标注：形状 + 样式 + 标识
public struct Annotation: Identifiable, Equatable, Sendable {
    public let id: AnnotationID
    public let shape: AnnotationShape
    public let style: AnnotationStyle

    public init(id: AnnotationID = AnnotationID(), shape: AnnotationShape, style: AnnotationStyle) {
        self.id = id
        self.shape = shape
        self.style = style
    }

    /// 产生该标注的工具
    public var tool: ScreenshotTool {
        shape.tool
    }

    /// 平移后的新标注（id、样式不变）
    public func translated(by delta: CGVector) -> Annotation {
        Annotation(id: id, shape: shape.translated(by: delta), style: style)
    }

    /// 换样式后的新标注（id、形状不变）
    public func withStyle(_ style: AnnotationStyle) -> Annotation {
        Annotation(id: id, shape: shape, style: style)
    }

    /// 替换文字内容；非文字标注返回自身
    public func withText(_ text: String) -> Annotation {
        guard case .text(_, let origin, let maxWidth) = shape else { return self }
        return Annotation(id: id, shape: .text(text, origin: origin, maxWidth: maxWidth), style: style)
    }
}
