import Foundation

/// RGBA 颜色分量，取值范围 0...1
public struct RGBAColor: Equatable, Sendable {
    public let red: Double
    public let green: Double
    public let blue: Double
    public let alpha: Double

    public init(red: Double, green: Double, blue: Double, alpha: Double = 1) {
        self.red = red
        self.green = green
        self.blue = blue
        self.alpha = alpha
    }
}

/// 解析 `#RGB`、`#RGBA`、`#RRGGBB`、`#RRGGBBAA` 格式的 HEX 颜色
public enum HexColor {
    public static func parse(_ string: String) -> RGBAColor? {
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("#") else { return nil }

        let hex = String(trimmed.dropFirst())
        guard [3, 4, 6, 8].contains(hex.count),
            hex.allSatisfy(\.isHexDigit),
            let value = UInt64(hex, radix: 16)
        else { return nil }

        switch hex.count {
        case 3, 4:
            return shortForm(value, hasAlpha: hex.count == 4)
        default:
            return longForm(value, hasAlpha: hex.count == 8)
        }
    }

    /// 每个分量 4 位，例如 #F80 → #FF8800
    private static func shortForm(_ value: UInt64, hasAlpha: Bool) -> RGBAColor {
        let shift: UInt64 = hasAlpha ? 4 : 0
        let component = { (offset: UInt64) -> Double in
            Double((value >> (offset + shift)) & 0xF) / 15
        }
        return RGBAColor(
            red: component(8),
            green: component(4),
            blue: component(0),
            alpha: hasAlpha ? Double(value & 0xF) / 15 : 1
        )
    }

    /// 每个分量 8 位
    private static func longForm(_ value: UInt64, hasAlpha: Bool) -> RGBAColor {
        let shift: UInt64 = hasAlpha ? 8 : 0
        let component = { (offset: UInt64) -> Double in
            Double((value >> (offset + shift)) & 0xFF) / 255
        }
        return RGBAColor(
            red: component(16),
            green: component(8),
            blue: component(0),
            alpha: hasAlpha ? Double(value & 0xFF) / 255 : 1
        )
    }
}
