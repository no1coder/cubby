import Foundation

/// 文本特征判断，用于卡片的展示样式
public enum TextHeuristics {
    /// 只检查开头部分，避免大文本拖慢渲染
    private static let sampleLength = 2_000
    /// 行首关键字（按前缀匹配，避免 "please let me know" 之类的散文误判）
    private static let leadingKeywords = [
        "func ", "def ", "class ", "struct ", "enum ", "interface ", "import ", "from ", "return ",
        "const ", "let ", "var ", "fn ", "public ", "private ", "package ", "#include", "#import",
        "SELECT ", "INSERT ", "UPDATE ", "if (", "for (", "while (", "} else",
    ]
    /// 行内代码符号
    private static let inlineTokens = ["=>", "->", "</", "/>", " = ", "();", "console."]
    private static let codeLineEndings: Set<Character> = [";", "{", "}", ")"]
    /// 缩进行里出现即可视为代码的符号
    private static let indentedCodeSymbols: Set<Character> = [";", "{", "}", "(", ")", "[", "]", "=", "<", ">", "$"]
    /// 句读结尾说明是一句话，而不是语句
    private static let sentenceEndings: Set<Character> = [".", ",", "!", "?", ":"]
    /// 缩进的短语句（如 pass、exit 0、puts item）最多包含的词数；缩进的散文通常更长
    private static let maxIndentedStatementWords = 3

    /// 粗略判断文本是否为代码：多行，且至少一半的行带有代码结构特征
    public static func looksLikeCode(_ text: String) -> Bool {
        let sample = String(text.prefix(sampleLength))
        let lines =
            sample
            .split(whereSeparator: \.isNewline)
            .map { String($0) }
            .filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        guard lines.count >= 2 else { return false }

        let codeLikeLines = lines.filter(isCodeLikeLine).count
        return Double(codeLikeLines) / Double(lines.count) >= 0.5
    }

    private static func isCodeLikeLine(_ line: String) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        // Markdown / 普通列表项即使有缩进也不算代码
        guard !isListItem(trimmed) else { return false }
        if let last = trimmed.last, codeLineEndings.contains(last) { return true }
        if line.hasPrefix("\t") || line.hasPrefix("    "), isIndentedStatement(trimmed) { return true }
        if trimmed.hasPrefix("<"), trimmed.hasSuffix(">") { return true }
        if leadingKeywords.contains(where: trimmed.hasPrefix) { return true }
        return inlineTokens.contains { trimmed.contains($0) }
    }

    /// 缩进本身不足以说明是代码（首行缩进的段落、引文、诗歌都很常见）：
    /// 缩进行还须带代码符号，或是不以句读结尾、不超过 3 个词的 ASCII 短语句
    private static func isIndentedStatement(_ trimmed: String) -> Bool {
        if trimmed.contains(where: indentedCodeSymbols.contains) { return true }
        guard trimmed.allSatisfy(\.isASCII), let last = trimmed.last, !sentenceEndings.contains(last) else {
            return false
        }
        return trimmed.split(whereSeparator: \.isWhitespace).count <= maxIndentedStatementWords
    }

    private static func isListItem(_ trimmed: String) -> Bool {
        if ["- ", "* ", "+ ", "• "].contains(where: trimmed.hasPrefix) { return true }
        let digits = trimmed.prefix { $0.isNumber }
        return !digits.isEmpty && trimmed.dropFirst(digits.count).hasPrefix(". ")
    }
}
