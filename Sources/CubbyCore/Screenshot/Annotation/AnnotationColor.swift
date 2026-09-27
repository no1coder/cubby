import Foundation

/// 标注调色板：Apple 系统色中的 8 种（sRGB），rawValue 用于持久化
public enum AnnotationColor: String, Codable, CaseIterable, Sendable {
    case red, orange, yellow, green, blue, purple, black, white

    /// `#RRGGBB` 形式的 sRGB 值（大写）
    public var hex: String {
        switch self {
        case .red: "#FF3B30"
        case .orange: "#FF9500"
        case .yellow: "#FFCC00"
        case .green: "#34C759"
        case .blue: "#007AFF"
        case .purple: "#AF52DE"
        case .black: "#000000"
        case .white: "#FFFFFF"
        }
    }

    /// 0...1 的 sRGB 分量，不透明
    public var rgba: RGBAColor {
        // hex 是编译期常量，解析必然成功；兜底为黑色只是为了不使用强制解包
        HexColor.parse(hex) ?? RGBAColor(red: 0, green: 0, blue: 0)
    }

    /// 色块的无障碍名称
    public var displayName: String {
        switch self {
        case .red: String(localized: "Red", comment: "Screenshot annotation color")
        case .orange: String(localized: "Orange", comment: "Screenshot annotation color")
        case .yellow: String(localized: "Yellow", comment: "Screenshot annotation color")
        case .green: String(localized: "Green", comment: "Screenshot annotation color")
        case .blue: String(localized: "Blue", comment: "Screenshot annotation color")
        case .purple: String(localized: "Purple", comment: "Screenshot annotation color")
        case .black: String(localized: "Black", comment: "Screenshot annotation color")
        case .white: String(localized: "White", comment: "Screenshot annotation color")
        }
    }
}
