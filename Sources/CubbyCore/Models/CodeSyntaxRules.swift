import Foundation

/// 单一语言的着色规则：关键字、字符串引号、注释写法，以及是否把大写开头的标识符当作类型
struct CodeSyntaxRules: Sendable {
    /// `#` 何时开始注释
    enum HashComment: Sendable {
        /// `#` 不是注释（Swift 的 `#if`、Rust 的 `#[derive]`、CSS 的颜色等）
        case none
        /// 任意位置的 `#` 都开始注释（Python）
        case always
        /// 只有行首或空白之后的 `#` 才开始注释（Shell 的 `${#arr}`、`a#b` 不是注释）
        case afterWhitespace
    }

    let keywords: Set<String>
    /// 为 true 时 `keywords` 存大写形式，按大写比较（SQL）
    var caseInsensitiveKeywords = false
    let quotes: Set<Character>
    var lineComments: [String] = ["//"]
    var blockComments = true
    var hashComment = HashComment.none
    /// 大写 ASCII 字母开头、又不是关键字的标识符是否算类型
    var highlightsTypes = true
    /// 除字母、数字、下划线外还能出现在标识符中的字符（CSS 的 `-`、JS 的 `$`）
    var identifierExtras: Set<Character> = []
    /// HTML：只有紧跟 `<` 或 `</` 的标签名是关键字
    var tagNamesAreKeywords = false

    func isKeyword(_ word: Substring) -> Bool {
        caseInsensitiveKeywords ? keywords.contains(word.uppercased()) : keywords.contains(String(word))
    }

    static func rules(for language: CodeLanguage?) -> CodeSyntaxRules {
        guard let language else { return generic }
        switch language {
        case .swift: return CodeSyntaxRules(keywords: Keywords.swift, quotes: ["\""])
        case .javascript:
            return CodeSyntaxRules(keywords: Keywords.javascript, quotes: ["\"", "'", "`"], identifierExtras: ["$"])
        case .python:
            return CodeSyntaxRules(
                keywords: Keywords.python, quotes: ["\"", "'"], lineComments: [], blockComments: false,
                hashComment: .always)
        case .go: return CodeSyntaxRules(keywords: Keywords.go, quotes: ["\"", "'", "`"])
        case .rust: return CodeSyntaxRules(keywords: Keywords.rust, quotes: ["\""])
        default: return dataRules(for: language)
        }
    }

    /// 不区分类型的语言：JSON、Shell、HTML、CSS、SQL
    private static func dataRules(for language: CodeLanguage) -> CodeSyntaxRules {
        switch language {
        case .json:
            return CodeSyntaxRules(
                keywords: Keywords.json, quotes: ["\""], lineComments: [], blockComments: false, highlightsTypes: false)
        case .shell:
            return CodeSyntaxRules(
                keywords: Keywords.shell, quotes: ["\"", "'"], lineComments: [], blockComments: false,
                hashComment: .afterWhitespace, highlightsTypes: false)
        case .html:
            return CodeSyntaxRules(
                keywords: [], quotes: ["\""], lineComments: [], blockComments: false, highlightsTypes: false,
                tagNamesAreKeywords: true)
        case .css:
            return CodeSyntaxRules(
                keywords: Keywords.css, quotes: ["\"", "'"], lineComments: [], highlightsTypes: false,
                identifierExtras: ["-"])
        default:
            return CodeSyntaxRules(
                keywords: Keywords.sql, caseInsensitiveKeywords: true, quotes: ["'", "\""], lineComments: ["--"],
                highlightsTypes: false)
        }
    }

    /// 语言未知时的通用规则：C 系注释、行首或空白后的 `#` 注释、各语言共有的少量关键字
    private static let generic = CodeSyntaxRules(
        keywords: Keywords.generic, quotes: ["\"", "'"], hashComment: .afterWhitespace)
}

/// 各语言的核心关键字（不求完整，只覆盖卡片上最常见的词）
private enum Keywords {
    static let swift: Set<String> = [
        "actor", "any", "as", "associatedtype", "async", "await", "break", "case", "catch", "class", "continue",
        "default", "defer", "deinit", "do", "else", "enum", "extension", "fallthrough", "false", "fileprivate",
        "final", "for", "func", "guard", "if", "import", "in", "init", "inout", "internal", "is", "lazy", "let",
        "mutating", "nil", "nonisolated", "open", "override", "private", "protocol", "public", "repeat", "rethrows",
        "return", "self", "Self", "some", "static", "struct", "subscript", "super", "switch", "throw", "throws",
        "true", "try", "typealias", "var", "weak", "where", "while",
    ]
    static let javascript: Set<String> = [
        "as", "async", "await", "break", "case", "catch", "class", "const", "continue", "declare", "default",
        "delete", "do", "else", "enum", "export", "extends", "false", "finally", "for", "from", "function", "if",
        "implements", "import", "in", "instanceof", "interface", "keyof", "let", "namespace", "new", "null", "of",
        "private", "protected", "public", "readonly", "return", "static", "super", "switch", "this", "throw", "true",
        "try", "type", "typeof", "undefined", "var", "void", "while", "yield",
    ]
    static let python: Set<String> = [
        "and", "as", "assert", "async", "await", "break", "case", "class", "continue", "def", "del", "elif", "else",
        "except", "False", "finally", "for", "from", "global", "if", "import", "in", "is", "lambda", "match", "None",
        "nonlocal", "not", "or", "pass", "raise", "return", "self", "True", "try", "while", "with", "yield",
    ]
    static let go: Set<String> = [
        "break", "case", "chan", "const", "continue", "default", "defer", "else", "fallthrough", "false", "for",
        "func", "go", "goto", "if", "import", "interface", "map", "nil", "package", "range", "return", "select",
        "struct", "switch", "true", "type", "var",
    ]
    static let rust: Set<String> = [
        "as", "async", "await", "break", "const", "continue", "crate", "dyn", "else", "enum", "extern", "false", "fn",
        "for", "if", "impl", "in", "let", "loop", "match", "mod", "move", "mut", "pub", "ref", "return", "self",
        "Self", "static", "struct", "super", "trait", "true", "type", "unsafe", "use", "where", "while",
    ]
    static let json: Set<String> = ["true", "false", "null"]
    static let shell: Set<String> = [
        "alias", "case", "cd", "do", "done", "echo", "elif", "else", "esac", "exit", "export", "fi", "for",
        "function", "if", "in", "local", "return", "set", "source", "then", "unset", "until", "while",
    ]
    static let css: Set<String> = [
        "auto", "font-face", "import", "important", "inherit", "initial", "keyframes", "media", "none", "supports",
        "unset",
    ]
    /// 以大写存放，比较时先把标识符转成大写
    static let sql: Set<String> = [
        "ADD", "ALL", "ALTER", "AND", "AS", "ASC", "BETWEEN", "BY", "CASE", "CREATE", "DEFAULT", "DELETE", "DESC",
        "DISTINCT", "DROP", "ELSE", "END", "EXISTS", "FALSE", "FOREIGN", "FROM", "FULL", "GROUP", "HAVING", "IN",
        "INDEX", "INNER", "INSERT", "INTO", "IS", "JOIN", "KEY", "LEFT", "LIKE", "LIMIT", "NOT", "NULL", "OFFSET",
        "ON", "OR", "ORDER", "OUTER", "PRIMARY", "REFERENCES", "RIGHT", "SELECT", "SET", "TABLE", "THEN", "TRUE",
        "UNION", "UNIQUE", "UPDATE", "VALUES", "WHEN", "WHERE", "WITH",
    ]
    static let generic: Set<String> = [
        "class", "const", "def", "else", "false", "for", "func", "function", "if", "import", "let", "new", "nil",
        "None", "null", "return", "self", "struct", "this", "true", "var", "while",
    ]
}
