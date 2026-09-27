import SwiftUI
import CubbyCore

/// 颜色预览：文本可以是 HEX 或 CSS rgb() / rgba()
struct ColorPreview: View {
    let hex: String

    var body: some View {
        if let color = ColorText.parse(hex) {
            VStack(spacing: 18) {
                RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
                    .fill(color.swiftUIColor)
                    .frame(width: 150, height: 150)
                    .overlay(
                        // 接近纯白的色块在浅色背景上会融进去，描边加深
                        RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
                            .strokeBorder(Color.primary.opacity(CardPalette.isNearWhite(color) ? 0.2 : 0.12))
                    )
                    .shadow(color: .black.opacity(0.15), radius: 10, y: 4)
                    .accessibilityHidden(true)
                VStack(spacing: 8) {
                    ForEach(ColorFormats.rows(for: color, hex: hex), id: \.label) { row in
                        HStack {
                            Text(row.label)
                                .font(.system(size: FontSize.caption, weight: .medium))
                                .foregroundStyle(.secondary)
                                .frame(width: 36, alignment: .leading)
                            Text(row.value)
                                .font(.system(size: FontSize.body, design: .monospaced))
                                .textSelection(.enabled)
                            Spacer()
                        }
                        .accessibilityElement(children: .combine)
                    }
                }
                .frame(width: 240)
            }
            .padding(24)
        }
    }
}

/// 颜色的多种表示
enum ColorFormats {
    struct Row {
        let label: String
        let value: String
    }

    static func rows(for color: RGBAColor, hex: String) -> [Row] {
        let rgb = [color.red, color.green, color.blue].map { String(Int(($0 * 255).rounded())) }
        let hasAlpha = color.alpha < 1
        let rgbValue =
            hasAlpha
            ? "rgba(\(rgb.joined(separator: ", ")), \(alphaText(color.alpha)))"
            : "rgb(\(rgb.joined(separator: ", ")))"
        let hsl = hslComponents(color)
        return [
            Row(label: "HEX", value: hexValue(hex, color: color)),
            Row(label: hasAlpha ? "RGBA" : "RGB", value: rgbValue),
            Row(label: "HSL", value: "hsl(\(hsl.h), \(hsl.s)%, \(hsl.l)%)"),
        ]
    }

    /// 预览页脚：不透明度（「不透明」或「不透明度 50%」），比重复类型名更有用
    static func opacityDescription(_ color: RGBAColor) -> String {
        guard color.alpha < 1 else {
            return String(localized: "Opaque", comment: "Color preview footer: the color has no transparency")
        }
        let percent = color.alpha.formatted(.percent.precision(.fractionLength(0)).locale(TimeFormatting.locale))
        return String(localized: "Opacity \(percent)", comment: "Color preview footer. %@ = opacity, e.g. “50%”")
    }

    /// CSS 的 alpha 最多保留 2 位有效数字（0.5、0.25、0.05），固定用小数点
    private static func alphaText(_ alpha: Double) -> String {
        String(format: "%.2g", alpha)
    }

    /// 原文是 HEX 时原样（大写）显示；原文是 rgb() 时换算为 #RRGGBB（有透明度时追加 AA）
    private static func hexValue(_ text: String, color: RGBAColor) -> String {
        guard !text.hasPrefix("#") else { return text.uppercased() }
        let base = ColorFormatter.string(color, format: .hex)
        guard color.alpha < 1 else { return base }
        return base + String(format: "%02X", Int((color.alpha * 255).rounded()))
    }

    private static func hslComponents(_ color: RGBAColor) -> (h: Int, s: Int, l: Int) {
        let maxValue = max(color.red, color.green, color.blue)
        let minValue = min(color.red, color.green, color.blue)
        let lightness = (maxValue + minValue) / 2
        let delta = maxValue - minValue
        guard delta > 0 else { return (0, 0, Int((lightness * 100).rounded())) }

        let saturation = delta / (1 - abs(2 * lightness - 1))
        let hue: Double =
            switch maxValue {
            case color.red: 60 * ((color.green - color.blue) / delta).truncatingRemainder(dividingBy: 6)
            case color.green: 60 * ((color.blue - color.red) / delta + 2)
            default: 60 * ((color.red - color.green) / delta + 4)
            }
        let normalizedHue = hue < 0 ? hue + 360 : hue
        return (Int(normalizedHue.rounded()), Int((saturation * 100).rounded()), Int((lightness * 100).rounded()))
    }
}
