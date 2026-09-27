import Foundation

/// 文字的书写系统判定（拼接、字号估算、假名补识别共用）
enum TextScript {
    /// 行间直接相连、不加空格的字符：汉字、假名、CJK 标点与全角符号（韩文词间有空格，不算在内）
    static func isCJK(_ character: Character) -> Bool {
        character.unicodeScalars.contains { isCJK($0) }
    }

    /// 假名（平假名、片假名、片假名扩展、半角片假名）
    static func isKana(_ scalar: Unicode.Scalar) -> Bool {
        switch scalar.value {
        case 0x3040...0x30FF, 0x31F0...0x31FF, 0xFF66...0xFF9F: true
        default: false
        }
    }

    static func containsKana(_ text: String) -> Bool {
        text.unicodeScalars.contains(where: isKana)
    }

    /// 字面饱满的文字（汉字、假名、韩文）：行框高 ≈ 字号 × 1.22，与拉丁文字不同
    static func isIdeographic(_ scalar: Unicode.Scalar) -> Bool {
        isCJK(scalar) || (0xAC00...0xD7AF).contains(scalar.value) || (0x1100...0x11FF).contains(scalar.value)
    }

    /// 字母中过半是字面饱满的文字
    static func isMostlyIdeographic(_ text: String) -> Bool {
        let letters = text.unicodeScalars.filter { $0.properties.isAlphabetic }
        guard !letters.isEmpty else { return false }
        return letters.filter(isIdeographic).count * 2 > letters.count
    }

    private static func isCJK(_ scalar: Unicode.Scalar) -> Bool {
        switch scalar.value {
        case 0x3000...0x303F,  // CJK 标点
            0x3040...0x30FF,  // 假名
            0x31F0...0x31FF,
            0x3400...0x4DBF,  // 扩展 A
            0x4E00...0x9FFF,  // 基本汉字
            0xF900...0xFAFF,  // 兼容汉字
            0xFF00...0xFFEF,  // 全角与半角形式
            0x20000...0x2FA1F:  // 扩展 B 及以后
            true
        default: false
        }
    }
}
