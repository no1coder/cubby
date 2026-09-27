import CoreGraphics
import Foundation

/// 截图覆盖层的工具；`pointer` 表示无工具（指针模式）
public enum ScreenshotTool: String, Codable, CaseIterable, Sendable {
    case pointer, rectangle, ellipse, arrow, pen, highlighter, mosaic, text, number

    /// 单键快捷字符（小写，按字符匹配以兼容 Dvorak）
    public var shortcutCharacter: Character? {
        switch self {
        case .pointer: "v"
        case .rectangle: "r"
        case .ellipse: "o"
        case .arrow: "a"
        case .pen: "p"
        case .highlighter: "h"
        case .mosaic: "m"
        case .text: "t"
        case .number: "n"
        }
    }

    /// 按快捷字符查找工具，大小写不敏感
    public static func tool(forShortcut character: Character) -> ScreenshotTool? {
        // 按字符串比较：个别字符的小写形式不止一个字符，不能直接构造 Character
        let lowered = character.lowercased()
        return allCases.first { $0.shortcutCharacter.map(String.init) == lowered }
    }

    /// 工具栏按钮的 SF Symbol
    public var symbolName: String {
        switch self {
        case .pointer: "cursorarrow"
        case .rectangle: "rectangle"
        case .ellipse: "oval"
        case .arrow: "arrow.up.right"
        case .pen: "pencil.line"
        case .highlighter: "highlighter"
        case .mosaic: "checkerboard.rectangle"
        case .text: "textformat"
        case .number: "1.circle"
        }
    }

    /// 工具名（tooltip 由调用方拼接快捷键）
    public var displayName: String {
        switch self {
        case .pointer: String(localized: "Pointer", comment: "Screenshot tool name")
        case .rectangle: String(localized: "Rectangle", comment: "Screenshot tool name")
        case .ellipse: String(localized: "Ellipse", comment: "Screenshot tool name")
        case .arrow: String(localized: "Arrow", comment: "Screenshot tool name")
        case .pen: String(localized: "Pen", comment: "Screenshot tool name")
        case .highlighter: String(localized: "Highlighter", comment: "Screenshot tool name")
        case .mosaic: String(localized: "Mosaic", comment: "Screenshot tool name")
        // 文字工具与面板分类「Text」英文相同、中文不同（文字 / 文本），因此用独立的键
        case .text: String(localized: "screenshot.tool.text", defaultValue: "Text", comment: "Screenshot tool name")
        case .number: String(localized: "Number", comment: "Screenshot tool name")
        }
    }

    /// 样式条是否显示颜色（指针与马赛克没有颜色）
    public var usesColor: Bool {
        self != .pointer && self != .mosaic
    }

    /// 首次使用时的样式：荧光笔黄色，其余红色；均为 regular
    public var defaultStyle: AnnotationStyle {
        AnnotationStyle(color: self == .highlighter ? .yellow : .red, weight: .regular)
    }

    /// 档位的显示名：文字工具为字号 S / M / L，其余为粗细
    public func weightDisplayName(_ weight: StrokeWeight) -> String {
        switch (self == .text, weight) {
        case (true, .light): String(localized: "Small", comment: "Screenshot text size option")
        case (true, .regular): String(localized: "Medium", comment: "Screenshot text size option")
        case (true, .heavy): String(localized: "Large", comment: "Screenshot text size option")
        case (false, .light): String(localized: "Thin", comment: "Screenshot stroke weight option")
        case (false, .regular): String(localized: "Regular", comment: "Screenshot stroke weight option")
        case (false, .heavy): String(localized: "Thick", comment: "Screenshot stroke weight option")
        }
    }

    /// 绘制路径时的线宽（点）：形状类 2 / 3 / 5，画笔 2 / 4 / 6，荧光笔与马赛克 = 笔刷宽；其余 0
    public func strokeWidth(for weight: StrokeWeight) -> CGFloat {
        switch self {
        case .rectangle, .ellipse, .arrow: Metrics.shapeStroke.value(for: weight)
        case .pen: Metrics.penStroke.value(for: weight)
        case .highlighter, .mosaic: brushWidth(for: weight)
        case .pointer, .text, .number: 0
        }
    }

    /// 字号（点）：文字 14 / 20 / 28；序号数字 = 直径 × 0.6；其余 0
    public func fontSize(for weight: StrokeWeight) -> CGFloat {
        switch self {
        case .text: Metrics.textSize.value(for: weight)
        case .number: badgeDiameter(for: weight) * Metrics.badgeFontRatio
        default: 0
        }
    }

    /// 笔刷宽（点）：马赛克 12 / 24 / 40，荧光笔 12 / 18 / 26；其余 0
    public func brushWidth(for weight: StrokeWeight) -> CGFloat {
        switch self {
        case .mosaic: Metrics.mosaicBrush.value(for: weight)
        case .highlighter: Metrics.highlighterBrush.value(for: weight)
        default: 0
        }
    }

    /// 序号徽标直径（点）：20 / 26 / 32；其余 0
    public func badgeDiameter(for weight: StrokeWeight) -> CGFloat {
        self == .number ? Metrics.badgeDiameter.value(for: weight) : 0
    }
}

/// §2.6 的档位数值表
private enum Metrics {
    /// 三档取值：light / regular / heavy
    struct Tiers {
        let light: CGFloat
        let regular: CGFloat
        let heavy: CGFloat

        func value(for weight: StrokeWeight) -> CGFloat {
            switch weight {
            case .light: light
            case .regular: regular
            case .heavy: heavy
            }
        }
    }

    static let shapeStroke = Tiers(light: 2, regular: 3, heavy: 5)
    static let penStroke = Tiers(light: 2, regular: 4, heavy: 6)
    static let highlighterBrush = Tiers(light: 12, regular: 18, heavy: 26)
    static let mosaicBrush = Tiers(light: 12, regular: 24, heavy: 40)
    static let textSize = Tiers(light: 14, regular: 20, heavy: 28)
    static let badgeDiameter = Tiers(light: 20, regular: 26, heavy: 32)
    /// 序号数字字号 = 直径 × 0.6（0.55 在 Ø20 的小档上数字偏小）
    static let badgeFontRatio: CGFloat = 0.6
}
