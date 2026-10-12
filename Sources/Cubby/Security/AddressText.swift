import SwiftUI
import CubbyCore

/// 地址的等宽分组显示（AddressComparison.groups，4 个字符一组）：首尾两组加粗，可把不同的字符标红。
/// 用于警示卡、面板卡片、预览与粘贴核对 HUD
enum AddressText {
    struct Style {
        var size: CGFloat
        var weight: Font.Weight = .medium
        /// 首尾两组的颜色（nil 沿用前景色）
        var endsColor: Color?
        /// 不同字符的底色与文字色
        var highlightBackground = Color.red.opacity(0.35)
        var highlightForeground: Color?
    }

    /// 分组后的整串
    static func attributed(_ value: String, style: Style, highlights: [Range<Int>] = []) -> AttributedString {
        let groups = AddressComparison.groups(value)
        var result = AttributedString()
        var offset = 0
        for (index, group) in groups.enumerated() {
            let isEnd = groups.count > 1 && (index == 0 || index == groups.count - 1)
            if index > 0 {
                // 两侧都标红时，组间空格也标红，标红区段连成一片（设计稿）
                let joined = isHighlighted(offset - 1, highlights) && isHighlighted(offset, highlights)
                result += run(" ", bold: false, highlighted: joined, style: style)
            }
            for (charIndex, character) in group.enumerated() {
                result += run(
                    String(character), bold: isEnd, highlighted: isHighlighted(offset + charIndex, highlights),
                    style: style)
            }
            offset += group.count
        }
        return result
    }

    /// 缩写的分组（HUD）：前 3 组 … 后 2 组，组数不多时显示全部
    static func abbreviated(_ value: String, style: Style) -> AttributedString {
        let groups = AddressComparison.groups(value)
        guard groups.count > 6 else { return attributed(value, style: style) }
        let shown = Array(groups.prefix(3)) + ["…"] + Array(groups.suffix(2))
        var result = AttributedString()
        for (index, group) in shown.enumerated() {
            if index > 0 { result += run(" ", bold: false, highlighted: false, style: style) }
            result += run(group, bold: index == 0 || index == shown.count - 1, highlighted: false, style: style)
        }
        return result
    }

    private static func isHighlighted(_ offset: Int, _ ranges: [Range<Int>]) -> Bool {
        ranges.contains { $0.contains(offset) }
    }

    private static func run(_ text: String, bold: Bool, highlighted: Bool, style: Style) -> AttributedString {
        var run = AttributedString(text)
        run.font = .system(size: style.size, weight: bold ? .bold : style.weight, design: .monospaced)
        if bold, let endsColor = style.endsColor { run.foregroundColor = endsColor }
        if highlighted {
            run.backgroundColor = style.highlightBackground
            if let foreground = style.highlightForeground { run.foregroundColor = foreground }
        }
        return run
    }
}
