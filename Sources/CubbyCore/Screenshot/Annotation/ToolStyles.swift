import Foundation

/// 每个工具的样式记忆（跨会话持久化在 `AppSettings.annotationStyles`）
///
/// 编码为以工具 rawValue 为键的 JSON 对象；解码逐条容错：未知工具键、无效条目都被忽略，
/// 缺失的工具回退到 `ScreenshotTool.defaultStyle`。
public struct ToolStyles: Codable, Equatable, Sendable {
    /// 所有工具都取默认样式
    public static let `default` = ToolStyles(styles: [:])

    /// 总是包含全部工具，保证按值比较有意义
    private let styles: [ScreenshotTool: AnnotationStyle]

    private init(styles: [ScreenshotTool: AnnotationStyle]) {
        self.styles = Dictionary(
            uniqueKeysWithValues: ScreenshotTool.allCases.map { ($0, styles[$0] ?? $0.defaultStyle) }
        )
    }

    /// 某个工具当前的样式
    public func style(for tool: ScreenshotTool) -> AnnotationStyle {
        styles[tool] ?? tool.defaultStyle
    }

    /// 返回只改一个工具样式的新值
    public func setting(_ style: AnnotationStyle, for tool: ScreenshotTool) -> ToolStyles {
        ToolStyles(styles: styles.merging([tool: style]) { _, new in new })
    }

    /// 容错解码：nil / 损坏 / 非对象 → `default`；未知工具键与无效条目忽略
    public static func decode(_ data: Data?) -> ToolStyles {
        guard let data, let styles = try? JSONDecoder().decode(ToolStyles.self, from: data) else {
            return .default
        }
        return styles
    }

    /// 键有序的 JSON，便于比较与调试
    public func encoded() -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        // 只含字符串枚举的字典，编码不会失败
        return (try? encoder.encode(self)) ?? Data()
    }

    // MARK: - Codable

    /// 单个条目的宽松解码：值无效时记为 nil 而不是让整体失败
    private struct LenientStyle: Decodable {
        let style: AnnotationStyle?

        init(from decoder: any Decoder) throws {
            style = try? AnnotationStyle(from: decoder)
        }
    }

    public init(from decoder: any Decoder) throws {
        // 值为 Optional：显式的 null 条目也只跳过自身
        let raw = try decoder.singleValueContainer().decode([String: LenientStyle?].self)
        let pairs = raw.compactMap { key, value -> (ScreenshotTool, AnnotationStyle)? in
            guard let tool = ScreenshotTool(rawValue: key), let style = value?.style else { return nil }
            return (tool, style)
        }
        self.init(styles: Dictionary(uniqueKeysWithValues: pairs))
    }

    public func encode(to encoder: any Encoder) throws {
        let raw = Dictionary(uniqueKeysWithValues: ScreenshotTool.allCases.map { ($0.rawValue, style(for: $0)) })
        var container = encoder.singleValueContainer()
        try container.encode(raw)
    }
}
