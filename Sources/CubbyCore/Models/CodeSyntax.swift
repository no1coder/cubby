import Foundation

/// 代码卡片上的一个着色片段
public struct CodeToken: Equatable, Sendable {
    /// 设计稿只给这三类上色
    public enum Kind: Sendable {
        case keyword
        case string
        case type
    }

    public let kind: Kind
    /// 片段在传入 `CodeSyntax.tokens(in:language:)` 的那个字符串上的范围，落在字符（Character）边界上；
    /// 字符串片段包含两侧引号
    public let range: Range<String.Index>

    public init(kind: Kind, range: Range<String.Index>) {
        self.kind = kind
        self.range = range
    }
}

/// 代码卡片的轻量语法着色：从左到右单趟扫描，只标出关键字、字符串和类型
public enum CodeSyntax {
    /// 最多扫描开头这么多个字符（卡片最多显示 4 行），之后的文本不产生片段，保证任意输入下工作量有上限
    public static let scanLimit = 4_000

    /// 返回按位置排序、互不重叠的着色片段。
    /// - 字符串：按语言支持的引号识别，处理反斜杠转义，到闭合引号或行尾为止（不跨行）
    /// - 注释（`//`、`/* */`、`#`、SQL 的 `--`）整体跳过，不产生片段
    /// - 关键字：整词匹配各语言的关键字集；`language` 为 nil 时使用通用的小关键字集
    /// - 类型：大写 ASCII 字母开头且不是关键字的标识符（JSON、Shell、HTML、CSS、SQL 不标类型）
    public static func tokens(in text: String, language: CodeLanguage?) -> [CodeToken] {
        let end = text.index(text.startIndex, offsetBy: scanLimit, limitedBy: text.endIndex) ?? text.endIndex
        let scanner = CodeScanner(source: text[..<end], rules: .rules(for: language))
        return scanner.tokens()
    }
}

/// 单趟扫描器：每一步从当前位置读出一个注释、字符串、标识符、数字或单个字符
private struct CodeScanner {
    let source: Substring
    let rules: CodeSyntaxRules

    func tokens() -> [CodeToken] {
        var tokens: [CodeToken] = []
        var index = source.startIndex
        while index < source.endIndex {
            let (token, next) = step(at: index)
            if let token { tokens.append(token) }
            index = next
        }
        return tokens
    }

    private func step(at index: String.Index) -> (CodeToken?, String.Index) {
        let char = source[index]
        if let end = commentEnd(at: index) { return (nil, end) }
        if isStringStart(char, at: index) {
            let end = stringEnd(from: index)
            return (CodeToken(kind: .string, range: index..<end), end)
        }
        if isIdentifierStart(char) {
            let end = identifierEnd(from: index)
            return (classify(index..<end), end)
        }
        // 数字连同其中的字母一起跳过，避免 0xFF、1E5 里的字母被当成类型
        if char.isNumber { return (nil, identifierEnd(from: index)) }
        return (nil, source.index(after: index))
    }

    // MARK: 注释

    /// 当前位置是注释开头时返回注释结束位置（行注释不含换行符）
    private func commentEnd(at index: String.Index) -> String.Index? {
        let rest = source[index...]
        if rules.lineComments.contains(where: rest.hasPrefix) || isHashComment(at: index) {
            return lineEnd(from: index)
        }
        guard rules.blockComments, rest.hasPrefix("/*") else { return nil }
        let body = rest.dropFirst(2)
        return body.firstRange(of: "*/")?.upperBound ?? source.endIndex
    }

    private func isHashComment(at index: String.Index) -> Bool {
        guard source[index] == "#" else { return false }
        switch rules.hashComment {
        case .none: return false
        case .always: return true
        case .afterWhitespace: return previous(index)?.isWhitespace ?? true
        }
    }

    private func lineEnd(from index: String.Index) -> String.Index {
        source[index...].firstIndex(where: \.isNewline) ?? source.endIndex
    }

    // MARK: 字符串

    /// 单引号紧跟在标识符后面时是撇号（don't）或生命周期（&'a），不是字符串
    private func isStringStart(_ char: Character, at index: String.Index) -> Bool {
        guard rules.quotes.contains(char) else { return false }
        guard char == "'", let before = previous(index) else { return true }
        return !isIdentifierPart(before)
    }

    /// 字符串结束位置：闭合引号之后；未闭合时停在行尾（不含换行符）或扫描范围末尾
    private func stringEnd(from start: String.Index) -> String.Index {
        let quote = source[start]
        var index = source.index(after: start)
        while index < source.endIndex {
            let char = source[index]
            if char.isNewline { return index }
            index = source.index(after: index)
            if char == quote { return index }
            if char == "\\", index < source.endIndex, !source[index].isNewline {
                index = source.index(after: index)
            }
        }
        return source.endIndex
    }

    // MARK: 标识符

    private func isIdentifierStart(_ char: Character) -> Bool {
        char.isLetter || char == "_" || (char != "-" && rules.identifierExtras.contains(char))
    }

    private func isIdentifierPart(_ char: Character) -> Bool {
        char.isLetter || char.isNumber || char == "_" || rules.identifierExtras.contains(char)
    }

    private func identifierEnd(from start: String.Index) -> String.Index {
        source[start...].firstIndex { !isIdentifierPart($0) } ?? source.endIndex
    }

    private func classify(_ range: Range<String.Index>) -> CodeToken? {
        let word = source[range]
        if rules.tagNamesAreKeywords {
            return isTagName(at: range.lowerBound) ? CodeToken(kind: .keyword, range: range) : nil
        }
        if rules.isKeyword(word) { return CodeToken(kind: .keyword, range: range) }
        if rules.highlightsTypes, let first = word.first, first.isASCII, first.isUppercase {
            return CodeToken(kind: .type, range: range)
        }
        return nil
    }

    /// 标签名紧跟在 `<` 或 `</` 之后
    private func isTagName(at index: String.Index) -> Bool {
        guard let before = previous(index) else { return false }
        if before == "<" { return true }
        return before == "/" && previous(source.index(before: index)) == "<"
    }

    private func previous(_ index: String.Index) -> Character? {
        index > source.startIndex ? source[source.index(before: index)] : nil
    }
}
