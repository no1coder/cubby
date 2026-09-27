import Foundation

/// 整块看起来不是自然语言的文字：数字、URL、邮箱、路径、命令行、代码（docs/TRANSLATION-DESIGN.md §3.3）
enum NonTranslatableText {
    /// 没有字母；或只有一段 ≤ 3 个拉丁字母且含数字（12.4 GB、5 min、v2.3.1）
    static func isNumeric(_ text: String) -> Bool {
        let hasLetter = text.unicodeScalars.contains { $0.properties.isAlphabetic }
        return !hasLetter || matches(numberWithUnit, text)
    }

    /// URL、邮箱、路径、包名、命令行或代码（整块匹配）
    static func isCodeLike(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return [url, email, path].contains { matches($0, trimmed) } || isCommandLine(trimmed) || isCode(trimmed)
    }

    // MARK: - 规则

    private static let numberWithUnit = regex(#"^(?=.*\d)[^\p{L}]*[A-Za-z]{1,3}[^\p{L}]*$"#)
    private static let url = regex(#"^((https?|ftp)://|www\.)\S+$|^([\w-]+\.)+[A-Za-z][\w-]*(/\S*)?$"#)
    private static let email = regex(#"^[\w.+-]+@[\w-]+(\.[\w-]+)+$"#)
    private static let path = regex(#"^(~|\.{1,2})?/\S*$|^[A-Za-z]:\\\S*$"#)
    private static let prompt = regex(#"^[$%#>] \S"#)
    /// 单个标识符：含下划线、函数调用 foo(…)
    private static let identifier = regex(#"^\S*(\w_\w|[A-Za-z_]\w*\()\S*$"#)

    /// 行首出现时视为命令行的常见命令（需全小写、无句末标点）
    private static let commands: Set<String> = [
        "git", "npm", "npx", "yarn", "pnpm", "brew", "swift", "make", "cd", "ls", "sudo", "curl", "wget", "pip",
        "pip3", "python", "python3", "node", "xcrun", "xcodebuild", "docker", "kubectl", "cargo", "ssh", "rm",
        "mkdir", "chmod", "defaults", "killall",
    ]

    /// 出现两种以上即视为代码的记号
    private static let codeTokens = ["{", "}", ";", "=>", "==", "!=", "&&", "||", "->", "()", "::", "</", "/>"]

    private static func isCommandLine(_ text: String) -> Bool {
        if matches(prompt, text) { return true }
        guard let first = text.split(separator: " ").first, commands.contains(String(first)) else { return false }
        let endsLikeSentence = [".", "!", "?"].contains { text.hasSuffix($0) }
        return text == text.lowercased() && !endsLikeSentence
    }

    private static func isCode(_ text: String) -> Bool {
        codeTokens.filter { text.contains($0) }.count >= 2 || matches(identifier, text)
    }

    private static func regex(_ pattern: String) -> NSRegularExpression {
        // 模式是编译期常量，失败即编程错误
        try! NSRegularExpression(pattern: pattern)
    }

    private static func matches(_ expression: NSRegularExpression, _ text: String) -> Bool {
        expression.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) != nil
    }
}
