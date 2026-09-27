import Foundation

/// 放大镜颜色读数格式（按住 ⇧ 时为 rgb）
public enum ColorFormat: Equatable, Sendable {
    case hex
    case rgb
}

/// 颜色文本格式化（§2.4）："#FF8800" / CSS "rgb(255, 136, 0)"；忽略 alpha。
/// 两种格式都能被 ColorText 解析，取色结果进入历史后是颜色条目
public enum ColorFormatter {
    private static let maxByte = 255.0

    public static func string(_ color: RGBAColor, format: ColorFormat) -> String {
        let bytes = [color.red, color.green, color.blue].map(byte)
        switch format {
        case .hex:
            return "#" + bytes.map { String(format: "%02X", $0) }.joined()
        case .rgb:
            return "rgb(" + bytes.map(String.init).joined(separator: ", ") + ")"
        }
    }

    /// 0...1 → 0...255，四舍五入并夹紧
    private static func byte(_ value: Double) -> Int {
        Int((min(max(value, 0), 1) * maxByte).rounded())
    }
}
