import CoreGraphics
import Foundation

/// 拖拽中的标注几何（§2.7）与确定性标注 id
enum AnnotationDrafting {
    /// 自由笔迹的抽稀距离，与 `StrokeSmoothing.thinned` 的默认值一致
    static let thinningDistance: CGFloat = 1.5

    /// 确定性 id 的固定前缀（UUID 前 8 字节），后 8 字节为会话内序号
    private static let idPrefix: [UInt8] = [0x43, 0x55, 0x42, 0x42, 0x59, 0x00, 0x40, 0x00]

    /// 由会话内序号生成标注 id：同样的事件序列得到同样的 id（reducer 不依赖随机数）
    static func annotationID(serial: Int) -> AnnotationID {
        let suffix = withUnsafeBytes(of: UInt64(truncatingIfNeeded: serial).bigEndian) { Array($0) }
        let bytes = idPrefix + suffix
        let uuid = UUID(
            uuid: (
                bytes[0], bytes[1], bytes[2], bytes[3], bytes[4], bytes[5], bytes[6], bytes[7],
                bytes[8], bytes[9], bytes[10], bytes[11], bytes[12], bytes[13], bytes[14], bytes[15]
            ))
        return AnnotationID(rawValue: uuid)
    }

    /// 从 anchor 拖到 point 时该工具的形状；constrained = ⇧；previous 用于自由笔迹追加点。
    /// - 箭头：⇧ 强制 45°；不按 ⇧ 时 ±3° 内自动磁吸到 0° / 45° / 90°；
    /// - 画笔 / 荧光笔 / 马赛克：按住 ⇧ 只保留首尾两点（直线）；
    /// - 指针 / 文字 / 序号不能拖拽绘制，返回 nil
    static func shape(
        for tool: ScreenshotTool,
        from anchor: CGPoint,
        to point: CGPoint,
        constrained: Bool,
        previous: AnnotationShape?
    ) -> AnnotationShape? {
        switch tool {
        case .rectangle:
            return .rectangle(rect(from: anchor, to: point, square: constrained))
        case .ellipse:
            return .ellipse(rect(from: anchor, to: point, square: constrained))
        case .arrow:
            return .arrow(from: anchor, to: arrowHead(from: anchor, to: point, constrained: constrained))
        case .pen:
            return .pen(stroke(from: anchor, to: point, constrained: constrained, previous: previous))
        case .highlighter:
            return .highlighter(stroke(from: anchor, to: point, constrained: constrained, previous: previous))
        case .mosaic:
            return .mosaic(stroke(from: anchor, to: point, constrained: constrained, previous: previous))
        case .pointer, .text, .number:
            return nil
        }
    }

    /// 用新的光标位置更新正在画的标注（id、样式不变）
    static func updated(_ annotation: Annotation, anchor: CGPoint, to point: CGPoint, constrained: Bool) -> Annotation {
        guard
            let shape = shape(
                for: annotation.tool, from: anchor, to: point, constrained: constrained, previous: annotation.shape)
        else { return annotation }
        return Annotation(id: annotation.id, shape: shape, style: annotation.style)
    }

    /// anchor 为一角的矩形；square 时边长取较小边、方向跟随光标象限
    static func rect(from anchor: CGPoint, to point: CGPoint, square: Bool) -> CGRect {
        let dx = point.x - anchor.x
        let dy = point.y - anchor.y
        let side = min(abs(dx), abs(dy))
        let width = square ? side : abs(dx)
        let height = square ? side : abs(dy)
        return CGRect(
            x: dx >= 0 ? anchor.x : anchor.x - width,
            y: dy >= 0 ? anchor.y : anchor.y - height,
            width: width,
            height: height
        )
    }

    /// 箭头头部：⇧ 强制 45°，否则 ±3° 磁吸（端点拖动也用它，以固定的另一端为基准）
    static func arrowHead(from anchor: CGPoint, to point: CGPoint, constrained: Bool) -> CGPoint {
        constrained
            ? ArrowGeometry.snapped45(from: anchor, to: point) : ArrowGeometry.magnetized(from: anchor, to: point)
    }

    /// 自由笔迹：⇧ 时只取首尾两点（直线），否则在已有点后追加
    private static func stroke(from anchor: CGPoint, to point: CGPoint, constrained: Bool, previous: AnnotationShape?)
        -> [CGPoint]
    {
        guard constrained else { return appending(point, to: points(of: previous) ?? [anchor]) }
        return appending(point, to: [anchor])
    }

    private static func points(of shape: AnnotationShape?) -> [CGPoint]? {
        switch shape {
        case .pen(let points), .highlighter(let points), .mosaic(let points): points
        default: nil
        }
    }

    /// 抽稀：与上一个保留点距离不足 thinningDistance 的点丢弃
    private static func appending(_ point: CGPoint, to points: [CGPoint]) -> [CGPoint] {
        guard let last = points.last else { return [point] }
        guard hypot(point.x - last.x, point.y - last.y) >= thinningDistance else { return points }
        return points + [point]
    }
}
