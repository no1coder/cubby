import CubbyCore
import SwiftUI

/// 代码卡的轻量语法着色：关键字粉、字符串橙、类型青（代码卡两种外观下都是深底，颜色固定）
enum CodeColoring {
    private static let keyword = Color(red: 1, green: 0.48, blue: 0.7)
    private static let string = Color(red: 1, green: 0.62, blue: 0.39)
    private static let type = Color(red: 0.4, green: 0.84, blue: 0.77)

    /// 逐行着色（卡片只显示前几行，跨行的字符串本来就在行尾截止），再标出搜索关键词
    static func attributed(_ line: String, language: CodeLanguage?, keywords: [String]) -> AttributedString {
        var attributed = AttributedString(line)
        for token in CodeSyntax.tokens(in: line, language: language) {
            guard let range = Range(token.range, in: attributed) else { continue }
            attributed[range].foregroundColor = color(for: token.kind)
        }
        TextHighlighter.highlight(&attributed, text: line, keywords: keywords, tint: .yellow)
        return attributed
    }

    private static func color(for kind: CodeToken.Kind) -> Color {
        switch kind {
        case .keyword: keyword
        case .string: string
        case .type: type
        }
    }
}
