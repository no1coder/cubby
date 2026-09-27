import Foundation

/// 粗细 / 字号 / 直径的三档；具体数值由 `ScreenshotTool` 按工具解释（§2.6）
public enum StrokeWeight: String, Codable, CaseIterable, Sendable {
    case light, regular, heavy
}

/// 一个标注（或一个工具的默认值）的样式：颜色 + 档位
public struct AnnotationStyle: Codable, Hashable, Sendable {
    public let color: AnnotationColor
    public let weight: StrokeWeight

    public init(color: AnnotationColor, weight: StrokeWeight) {
        self.color = color
        self.weight = weight
    }

    /// 返回只改颜色的新样式
    public func withColor(_ color: AnnotationColor) -> AnnotationStyle {
        AnnotationStyle(color: color, weight: weight)
    }

    /// 返回只改档位的新样式
    public func withWeight(_ weight: StrokeWeight) -> AnnotationStyle {
        AnnotationStyle(color: color, weight: weight)
    }
}
