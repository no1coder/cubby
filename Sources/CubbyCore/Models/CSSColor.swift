import Foundation

/// 解析 CSS 的 `rgb()` / `rgba()` 颜色：
/// - 逗号语法 `rgb(255, 136, 0)`、`rgba(255, 136, 0, 0.5)`，或空格语法 `rgb(255 136 0)`、`rgb(255 136 0 / 50%)`；
/// - 函数名大小写不敏感，允许首尾与分隔符两侧的空白；`rgb` 与 `rgba` 都接受 3 或 4 个值；
/// - 通道为 0–255 的数字；alpha 为 0–1 的数字或 0%–100%；
/// - 整段文本必须恰好是一个颜色（句子里出现的 rgb 字样不算），越界、数量不对、混用分隔符一律拒绝
public enum CSSColor {
    private static let functionNames = ["rgba(", "rgb("]
    private static let maxChannel = 255.0
    private static let maxPercent = 100.0

    public static func parse(_ string: String) -> RGBAColor? {
        let text = string.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard let name = functionNames.first(where: text.hasPrefix), text.hasSuffix(")") else { return nil }
        let body = String(text.dropFirst(name.count).dropLast())
        guard let tokens = split(body) else { return nil }
        let channels = tokens.channels.compactMap(channel)
        let opacity = tokens.alpha.map(alpha) ?? 1
        guard channels.count == 3, let opacity else { return nil }
        return RGBAColor(red: channels[0], green: channels[1], blue: channels[2], alpha: opacity)
    }

    /// 拆成 3 个通道 + 可选 alpha；两种语法不可混用
    private static func split(_ body: String) -> (channels: [String], alpha: String?)? {
        if body.contains(",") {
            guard !body.contains("/") else { return nil }
            let parts = body.split(separator: ",", omittingEmptySubsequences: false).map(trimmed)
            guard (3...4).contains(parts.count), parts.allSatisfy(isSingleToken) else { return nil }
            return (Array(parts.prefix(3)), parts.count == 4 ? parts[3] : nil)
        }
        let halves = body.split(separator: "/", omittingEmptySubsequences: false).map(trimmed)
        guard (1...2).contains(halves.count) else { return nil }
        let channels = halves[0].split(whereSeparator: \.isWhitespace).map(String.init)
        guard channels.count == 3 else { return nil }
        guard halves.count == 2 else { return (channels, nil) }
        return isSingleToken(halves[1]) ? (channels, halves[1]) : nil
    }

    /// 0–255 的整数或小数（不接受百分比、指数、十六进制）
    private static func channel(_ token: String) -> Double? {
        guard isPlainNumber(token, allowsLeadingDot: false), let value = Double(token), value <= maxChannel else {
            return nil
        }
        return value / maxChannel
    }

    /// 0–1 的数字，或 0%–100%
    private static func alpha(_ token: String) -> Double? {
        let isPercent = token.hasSuffix("%")
        let number = isPercent ? String(token.dropLast()) : token
        guard isPlainNumber(number, allowsLeadingDot: true), let value = Double(number) else { return nil }
        let fraction = isPercent ? value / maxPercent : value
        return (0...1).contains(fraction) ? fraction : nil
    }

    /// 只由数字和至多一个小数点组成，且小数点后必须有数字
    private static func isPlainNumber(_ token: String, allowsLeadingDot: Bool) -> Bool {
        guard !token.isEmpty, token.allSatisfy({ $0.isASCII && ($0.isNumber || $0 == ".") }),
            token.filter({ $0 == "." }).count <= 1, !token.hasSuffix(".")
        else { return false }
        return allowsLeadingDot || !token.hasPrefix(".")
    }

    private static func trimmed(_ part: some StringProtocol) -> String {
        part.trimmingCharacters(in: .whitespaces)
    }

    private static func isSingleToken(_ part: String) -> Bool {
        !part.isEmpty && !part.contains(where: \.isWhitespace)
    }
}

/// 颜色文本：HEX（`#FF8800` 等）或 CSS `rgb()` / `rgba()`
public enum ColorText {
    public static func parse(_ string: String) -> RGBAColor? {
        HexColor.parse(string) ?? CSSColor.parse(string)
    }
}
