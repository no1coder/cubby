import Foundation

extension PixelColor {
    /// WCAG 相对亮度（sRGB 线性化后加权）
    var relativeLuminance: Double {
        func linear(_ value: Double) -> Double {
            value <= 0.040_45 ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * linear(red) + 0.7152 * linear(green) + 0.0722 * linear(blue)
    }

    /// WCAG 对比度 1…21
    func contrastRatio(with other: PixelColor) -> Double {
        let lighter = max(relativeLuminance, other.relativeLuminance)
        let darker = min(relativeLuminance, other.relativeLuminance)
        return (lighter + 0.05) / (darker + 0.05)
    }

    /// 按 fraction（0…1）混向 other
    func mixed(with other: PixelColor, fraction: Double) -> PixelColor {
        PixelColor(
            red: red + (other.red - red) * fraction, green: green + (other.green - green) * fraction,
            blue: blue + (other.blue - blue) * fraction, alpha: alpha + (other.alpha - alpha) * fraction)
    }

    /// 与 background 的对比度不足 minimum 时，沿原有明暗方向（比背景亮 → 白，暗 → 黑）混合到刚好达标；
    /// 该方向到头仍不达标时就用该端的纯白 / 纯黑，不翻转明暗（绿底白字按钮不会变成黑字）
    func ensuringContrast(_ minimum: Double, against background: PixelColor) -> PixelColor {
        guard contrastRatio(with: background) < minimum else { return self }
        let preferred: PixelColor = relativeLuminance > background.relativeLuminance ? .white : .black
        guard preferred.contrastRatio(with: background) >= minimum else { return preferred }
        var low = 0.0
        var high = 1.0
        // 同一方向上对比度随混合比例单调增加：二分到 1/256 精度
        for _ in 0..<8 {
            let middle = (low + high) / 2
            if mixed(with: preferred, fraction: middle).contrastRatio(with: background) >= minimum {
                high = middle
            } else {
                low = middle
            }
        }
        return mixed(with: preferred, fraction: high)
    }
}
